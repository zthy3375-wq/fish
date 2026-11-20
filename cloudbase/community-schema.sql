-- Community owns separate tables; academic data and analytics are never joined.
CREATE TABLE IF NOT EXISTS public.hyt_members (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), username text UNIQUE NOT NULL,
 nickname text NOT NULL, password_hash text NOT NULL, recovery_hash text NOT NULL,
 role text NOT NULL DEFAULT 'member' CHECK (role IN ('member','moderator')),
 banned_until timestamptz, deleted_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.hyt_sessions (
 hash text PRIMARY KEY, member_id uuid NOT NULL REFERENCES public.hyt_members(id),
 expires_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS hyt_sessions_member ON public.hyt_sessions(member_id);
CREATE TABLE IF NOT EXISTS public.hyt_posts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), author_id uuid NOT NULL REFERENCES public.hyt_members(id),
 body text NOT NULL CHECK(length(body) BETWEEN 1 AND 3000), anonymous boolean NOT NULL,
 request_id uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz,
 locked boolean NOT NULL DEFAULT false, UNIQUE(author_id,request_id)
);
CREATE INDEX IF NOT EXISTS hyt_posts_feed ON public.hyt_posts(created_at DESC,id DESC) WHERE deleted_at IS NULL;
CREATE TABLE IF NOT EXISTS public.hyt_comments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), post_id uuid NOT NULL REFERENCES public.hyt_posts(id),
 author_id uuid NOT NULL REFERENCES public.hyt_members(id), body text NOT NULL CHECK(length(body) BETWEEN 1 AND 1000),
 anonymous boolean NOT NULL, reply_to uuid REFERENCES public.hyt_comments(id), request_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz, UNIQUE(author_id,request_id)
);
CREATE INDEX IF NOT EXISTS hyt_comments_post ON public.hyt_comments(post_id,created_at,id);
CREATE TABLE IF NOT EXISTS public.hyt_thread_aliases (
 post_id uuid REFERENCES public.hyt_posts(id), member_id uuid REFERENCES public.hyt_members(id),
 label text NOT NULL DEFAULT substr(replace(gen_random_uuid()::text,'-',''),1,8), PRIMARY KEY(post_id,member_id), UNIQUE(post_id,label)
);
CREATE TABLE IF NOT EXISTS public.hyt_reactions (
 post_id uuid REFERENCES public.hyt_posts(id), member_id uuid REFERENCES public.hyt_members(id),
 kind text CHECK(kind IN ('like','save')), PRIMARY KEY(post_id,member_id,kind)
);
CREATE TABLE IF NOT EXISTS public.hyt_blocks (
 member_id uuid REFERENCES public.hyt_members(id), blocked_id uuid REFERENCES public.hyt_members(id),
 PRIMARY KEY(member_id,blocked_id), CHECK(member_id<>blocked_id)
);
CREATE TABLE IF NOT EXISTS public.hyt_hidden_threads (
 member_id uuid REFERENCES public.hyt_members(id), post_id uuid REFERENCES public.hyt_posts(id), PRIMARY KEY(member_id,post_id)
);
CREATE TABLE IF NOT EXISTS public.hyt_reports (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), reporter_id uuid REFERENCES public.hyt_members(id),
 post_id uuid NOT NULL REFERENCES public.hyt_posts(id), comment_id uuid REFERENCES public.hyt_comments(id),
 reason text NOT NULL, status text NOT NULL DEFAULT 'open', resolution text,
 created_at timestamptz NOT NULL DEFAULT now(), resolved_at timestamptz
);
CREATE INDEX IF NOT EXISTS hyt_reports_open ON public.hyt_reports(created_at) WHERE status='open';
CREATE TABLE IF NOT EXISTS public.hyt_moderation (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), moderator_id uuid REFERENCES public.hyt_members(id),
 report_id uuid REFERENCES public.hyt_reports(id), action text NOT NULL, reason text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.hyt_moderation ADD COLUMN IF NOT EXISTS post_id uuid REFERENCES public.hyt_posts(id);
ALTER TABLE public.hyt_moderation ADD COLUMN IF NOT EXISTS comment_id uuid REFERENCES public.hyt_comments(id);
CREATE INDEX IF NOT EXISTS hyt_moderation_time ON public.hyt_moderation(created_at,id);

CREATE TABLE IF NOT EXISTS public.hyt_community_rate (
 key text PRIMARY KEY, count int NOT NULL, until_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS hyt_rate_expiration ON public.hyt_community_rate(until_at);

-- v6: viewer-owned follow edges; no public follower graph or anonymous projections.
CREATE TABLE IF NOT EXISTS public.hyt_follows (
 member_id uuid NOT NULL REFERENCES public.hyt_members(id),
 followed_id uuid NOT NULL REFERENCES public.hyt_members(id),
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(member_id,followed_id), CHECK(member_id<>followed_id)
);
CREATE INDEX IF NOT EXISTS hyt_follows_page ON public.hyt_follows(member_id,created_at DESC,followed_id DESC);
CREATE INDEX IF NOT EXISTS hyt_follows_target ON public.hyt_follows(followed_id);

-- v9: private one-to-one text conversations, independent of posts and anonymous aliases.
CREATE TABLE IF NOT EXISTS public.hyt_dm_threads (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), low_id uuid NOT NULL REFERENCES public.hyt_members(id),
 high_id uuid NOT NULL REFERENCES public.hyt_members(id), last_seq bigint NOT NULL DEFAULT 0,
 updated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(low_id,high_id), CHECK(low_id<high_id)
);
CREATE TABLE IF NOT EXISTS public.hyt_dm_messages (
 seq bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, id uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
 thread_id uuid NOT NULL REFERENCES public.hyt_dm_threads(id), sender_id uuid NOT NULL REFERENCES public.hyt_members(id),
 body text NOT NULL CHECK(length(body) BETWEEN 1 AND 1000), request_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(sender_id,request_id)
);
CREATE INDEX IF NOT EXISTS hyt_dm_messages_page ON public.hyt_dm_messages(thread_id,seq DESC);
CREATE INDEX IF NOT EXISTS hyt_dm_messages_rate ON public.hyt_dm_messages(sender_id,created_at DESC);
CREATE INDEX IF NOT EXISTS hyt_dm_threads_low ON public.hyt_dm_threads(low_id,last_seq DESC);
CREATE INDEX IF NOT EXISTS hyt_dm_threads_high ON public.hyt_dm_threads(high_id,last_seq DESC);
CREATE TABLE IF NOT EXISTS public.hyt_dm_reads (
 thread_id uuid NOT NULL REFERENCES public.hyt_dm_threads(id), member_id uuid NOT NULL REFERENCES public.hyt_members(id),
 last_seq bigint NOT NULL DEFAULT 0, PRIMARY KEY(thread_id,member_id)
);

-- Additive v2 migration. Old clients/posts retain their original identity and content.
ALTER TABLE public.hyt_posts ADD COLUMN IF NOT EXISTS title text NOT NULL DEFAULT '';
ALTER TABLE public.hyt_posts ADD COLUMN IF NOT EXISTS category text NOT NULL DEFAULT 'daily';
-- v5 adds discovery metadata without rewriting any existing category or identity.
ALTER TABLE public.hyt_posts ADD COLUMN IF NOT EXISTS interest text NOT NULL DEFAULT '';
ALTER TABLE public.hyt_posts DROP CONSTRAINT IF EXISTS hyt_posts_interest_check;
ALTER TABLE public.hyt_posts ADD CONSTRAINT hyt_posts_interest_check CHECK(
 interest='' OR (category='study' AND interest='graduate')
 OR (category='entertainment' AND interest IN ('reading','fitness','games','anime','film','music','photo','sports'))
);
ALTER TABLE public.hyt_posts DROP CONSTRAINT IF EXISTS hyt_posts_treehole_anonymous_check;
ALTER TABLE public.hyt_posts ADD CONSTRAINT hyt_posts_treehole_anonymous_check CHECK(category<>'treehole' OR anonymous);
CREATE INDEX IF NOT EXISTS hyt_posts_interest ON public.hyt_posts(interest,created_at DESC,id DESC) WHERE deleted_at IS NULL AND interest<>'';
ALTER TABLE public.hyt_posts DROP CONSTRAINT IF EXISTS hyt_posts_body_check;
ALTER TABLE public.hyt_posts ADD CONSTRAINT hyt_posts_body_check CHECK(length(body)<=3000);
ALTER TABLE public.hyt_comments ADD COLUMN IF NOT EXISTS root_id uuid REFERENCES public.hyt_comments(id);
WITH RECURSIVE threads AS (
 SELECT id,id AS root FROM public.hyt_comments WHERE reply_to IS NULL
 UNION ALL SELECT c.id,t.root FROM public.hyt_comments c JOIN threads t ON c.reply_to=t.id
) UPDATE public.hyt_comments c SET root_id=t.root FROM threads t WHERE c.id=t.id AND c.reply_to IS NOT NULL AND c.root_id IS NULL;
ALTER TABLE public.hyt_reactions ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
CREATE TABLE IF NOT EXISTS public.hyt_comment_likes (
 comment_id uuid REFERENCES public.hyt_comments(id),member_id uuid REFERENCES public.hyt_members(id),PRIMARY KEY(comment_id,member_id)
);
CREATE TABLE IF NOT EXISTS public.hyt_media (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), member_id uuid NOT NULL REFERENCES public.hyt_members(id),
 request_id uuid NOT NULL, digest text NOT NULL, object_key text NOT NULL UNIQUE,
 post_id uuid REFERENCES public.hyt_posts(id), position int NOT NULL DEFAULT 0,
 width int NOT NULL DEFAULT 0,height int NOT NULL DEFAULT 0,bytes int NOT NULL DEFAULT 0,
 ready boolean NOT NULL DEFAULT false,created_at timestamptz NOT NULL DEFAULT now(),deleted_at timestamptz,
 UNIQUE(member_id,request_id)
);
CREATE INDEX IF NOT EXISTS hyt_media_post ON public.hyt_media(post_id,position);
CREATE INDEX IF NOT EXISTS hyt_comments_root ON public.hyt_comments(post_id,root_id,created_at,id);
CREATE INDEX IF NOT EXISTS hyt_posts_category ON public.hyt_posts(category,created_at DESC,id DESC) WHERE deleted_at IS NULL;
-- Additive v3 migration: existing posts, accounts and aliases keep their identity.
ALTER TABLE public.hyt_members ADD COLUMN IF NOT EXISTS bio text NOT NULL DEFAULT '';
CREATE TABLE IF NOT EXISTS public.hyt_thread_watches (
 member_id uuid REFERENCES public.hyt_members(id), post_id uuid REFERENCES public.hyt_posts(id),
 enabled boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(member_id,post_id)
);
CREATE INDEX IF NOT EXISTS hyt_watches_post ON public.hyt_thread_watches(post_id) WHERE enabled;
CREATE TABLE IF NOT EXISTS public.hyt_thread_visits (
 member_id uuid REFERENCES public.hyt_members(id), post_id uuid REFERENCES public.hyt_posts(id),
 seen_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(member_id,post_id)
);
CREATE INDEX IF NOT EXISTS hyt_comments_participant ON public.hyt_comments(author_id,post_id) WHERE deleted_at IS NULL;
CREATE TABLE IF NOT EXISTS public.hyt_notifications (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), recipient_id uuid NOT NULL REFERENCES public.hyt_members(id),
 actor_id uuid NOT NULL REFERENCES public.hyt_members(id), post_id uuid NOT NULL REFERENCES public.hyt_posts(id),
 comment_id uuid REFERENCES public.hyt_comments(id), kind text NOT NULL CHECK(kind IN ('reply','post_reply','thread_reply','post_like','comment_like')),
 event_key text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), read_at timestamptz,
 UNIQUE(recipient_id,event_key)
);
CREATE INDEX IF NOT EXISTS hyt_notifications_inbox ON public.hyt_notifications(recipient_id,created_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS hyt_notifications_unread ON public.hyt_notifications(recipient_id) WHERE read_at IS NULL;
-- Additive v4: avatars remain private media, reactions expose counts and only the viewer's choice.
ALTER TABLE public.hyt_media ADD COLUMN IF NOT EXISTS purpose text NOT NULL DEFAULT 'post' CHECK(purpose IN ('post','avatar'));
ALTER TABLE public.hyt_members ADD COLUMN IF NOT EXISTS avatar_id uuid;
CREATE TABLE IF NOT EXISTS public.hyt_responses (
 post_id uuid REFERENCES public.hyt_posts(id), member_id uuid REFERENCES public.hyt_members(id),
 kind text NOT NULL CHECK(kind IN ('same','hug','useful','joy')), PRIMARY KEY(post_id,member_id)
);
ALTER TABLE public.hyt_responses DROP CONSTRAINT IF EXISTS hyt_responses_kind_check;
ALTER TABLE public.hyt_responses ADD CONSTRAINT hyt_responses_kind_check CHECK(kind IN ('same','hug','useful','joy'));
ALTER TABLE public.hyt_notifications DROP CONSTRAINT IF EXISTS hyt_notifications_kind_check;
ALTER TABLE public.hyt_notifications ADD CONSTRAINT hyt_notifications_kind_check CHECK(kind IN ('reply','post_reply','thread_reply','post_like','comment_like','post_response','buddy'));
-- v7: immutable poll definitions, private votes, and comment-owned images.
ALTER TABLE public.hyt_comments DROP CONSTRAINT IF EXISTS hyt_comments_body_check;
ALTER TABLE public.hyt_comments ADD CONSTRAINT hyt_comments_body_check CHECK(length(body)<=1000);
ALTER TABLE public.hyt_media ADD COLUMN IF NOT EXISTS comment_id uuid REFERENCES public.hyt_comments(id);
ALTER TABLE public.hyt_media DROP CONSTRAINT IF EXISTS hyt_media_purpose_check;
ALTER TABLE public.hyt_media ADD CONSTRAINT hyt_media_purpose_check CHECK(purpose IN ('post','avatar','comment'));
CREATE INDEX IF NOT EXISTS hyt_media_comment ON public.hyt_media(comment_id,position);
CREATE TABLE IF NOT EXISTS public.hyt_polls (
 post_id uuid PRIMARY KEY REFERENCES public.hyt_posts(id), definition jsonb NOT NULL,
 closes_at timestamptz NOT NULL, CHECK(jsonb_array_length(definition->'options') BETWEEN 2 AND 6)
);
CREATE TABLE IF NOT EXISTS public.hyt_poll_votes (
 post_id uuid REFERENCES public.hyt_polls(post_id), member_id uuid REFERENCES public.hyt_members(id),
 option_index int NOT NULL CHECK(option_index BETWEEN 0 AND 5), PRIMARY KEY(post_id,member_id)
);
ALTER TABLE public.hyt_polls ADD COLUMN IF NOT EXISTS revision bigint NOT NULL DEFAULT 0;
CREATE OR REPLACE FUNCTION public.hyt_poll_json(pid uuid,viewer uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('version',revision,'question',definition->>'question','closesAt',closes_at,'closed',closes_at<=now(),
 'total',(SELECT count(*) FROM public.hyt_poll_votes WHERE post_id=pid),
 'myOptionId',(SELECT option_index::text FROM public.hyt_poll_votes WHERE post_id=pid AND member_id=viewer),
 'options',(SELECT jsonb_agg(jsonb_build_object('id',(ord-1)::text,'text',label,'count',
 (SELECT count(*) FROM public.hyt_poll_votes WHERE post_id=pid AND option_index=ord-1)) ORDER BY ord)
 FROM jsonb_array_elements_text(definition->'options') WITH ORDINALITY x(label,ord)))
 FROM public.hyt_polls WHERE post_id=pid;
$$;
-- v8: small meetups; capacity counts additional members, excluding the host.
CREATE TABLE IF NOT EXISTS public.hyt_buddies (
 post_id uuid PRIMARY KEY REFERENCES public.hyt_posts(id), definition jsonb NOT NULL,
 starts_at timestamptz NOT NULL, capacity int NOT NULL CHECK(capacity BETWEEN 1 AND 20),
 closed boolean NOT NULL DEFAULT false, revision bigint NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS public.hyt_buddy_members (
 post_id uuid REFERENCES public.hyt_buddies(post_id), member_id uuid REFERENCES public.hyt_members(id),
 joined_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(post_id,member_id)
);
CREATE INDEX IF NOT EXISTS hyt_buddy_member_posts ON public.hyt_buddy_members(member_id,post_id);
CREATE OR REPLACE FUNCTION public.hyt_buddy_json(pid uuid,viewer uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('version',revision,'location',definition->>'location','startsAt',starts_at,'capacity',capacity,
 'closed',closed,'expired',starts_at<=now(),'count',(SELECT count(*) FROM public.hyt_buddy_members WHERE post_id=pid),
 'joined',EXISTS(SELECT 1 FROM public.hyt_buddy_members WHERE post_id=pid AND member_id=viewer))
 FROM public.hyt_buddies WHERE post_id=pid;
$$;
CREATE OR REPLACE FUNCTION public.hyt_comment_image_visible(cid uuid,viewer uuid) RETURNS boolean
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT EXISTS(SELECT 1 FROM public.hyt_comments c LEFT JOIN public.hyt_comments root ON root.id=c.root_id
 WHERE c.id=cid AND c.deleted_at IS NULL
 AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks b WHERE b.member_id=viewer AND ((b.blocked_id=c.author_id AND NOT c.anonymous) OR (b.blocked_id=root.author_id AND NOT root.anonymous))));
$$;
CREATE OR REPLACE FUNCTION public.hyt_media_json(img public.hyt_media) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('id',img.id,'key',img.object_key,'width',img.width,'height',img.height);
$$;

CREATE OR REPLACE FUNCTION public.hyt_avatar_json(uid uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT public.hyt_media_json(i) FROM public.hyt_members m JOIN public.hyt_media i ON i.id=m.avatar_id
 WHERE m.id=uid AND m.deleted_at IS NULL AND i.ready AND i.deleted_at IS NULL AND i.purpose='avatar';
$$;
-- Identity and honor records are attached to stable member IDs. The developer bootstrap
-- has no HTTP route. Existing moderators retain their current capabilities on migration.
ALTER TABLE public.hyt_members ADD COLUMN IF NOT EXISTS developer_since timestamptz;
ALTER TABLE public.hyt_members ADD COLUMN IF NOT EXISTS moderator_since timestamptz;
ALTER TABLE public.hyt_members ADD COLUMN IF NOT EXISTS mod_caps text[] NOT NULL DEFAULT ARRAY['content','reports','users','recommend'];
ALTER TABLE public.hyt_members ADD COLUMN IF NOT EXISTS worn_honor text;
ALTER TABLE public.hyt_members ADD COLUMN IF NOT EXISTS showcase text[] NOT NULL DEFAULT '{}';
ALTER TABLE public.hyt_members ADD COLUMN IF NOT EXISTS awards_initialized boolean NOT NULL DEFAULT false;
CREATE UNIQUE INDEX IF NOT EXISTS hyt_one_developer ON public.hyt_members ((true)) WHERE developer_since IS NOT NULL;
CREATE TABLE IF NOT EXISTS public.hyt_honors (
 member_id uuid REFERENCES public.hyt_members(id), kind text CHECK(kind IN ('seed','creator','contributor')),
 granted_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(member_id,kind)
);
CREATE TABLE IF NOT EXISTS public.hyt_honor_history (
 id uuid PRIMARY KEY, actor uuid NOT NULL REFERENCES public.hyt_members(id), target uuid NOT NULL REFERENCES public.hyt_members(id),
 change jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS hyt_honor_history_target ON public.hyt_honor_history(target,created_at DESC);
CREATE TABLE IF NOT EXISTS public.hyt_recommendations (
 member_id uuid PRIMARY KEY REFERENCES public.hyt_members(id), actor uuid NOT NULL REFERENCES public.hyt_members(id),
 reason text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.hyt_awards (
 member_id uuid REFERENCES public.hyt_members(id), code text NOT NULL, earned_at timestamptz NOT NULL DEFAULT now(),
 seen boolean NOT NULL DEFAULT false, PRIMARY KEY(member_id,code)
);
ALTER TABLE public.hyt_awards ADD COLUMN IF NOT EXISTS backfilled boolean NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS hyt_honor_posts ON public.hyt_posts(author_id,id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS hyt_honor_saves ON public.hyt_reactions(member_id,post_id) WHERE kind='save';
CREATE INDEX IF NOT EXISTS hyt_honor_comments ON public.hyt_comments(author_id,id) WHERE deleted_at IS NULL;
-- New reactions share one newcomer credit per recipient per UTC day, irrespective of how
-- many fresh accounts supply them. Older edges require existing server notification evidence.
ALTER TABLE public.hyt_reactions ADD COLUMN IF NOT EXISTS credit text;
ALTER TABLE public.hyt_comment_likes ADD COLUMN IF NOT EXISTS credit text;
CREATE OR REPLACE FUNCTION public.hyt_credit() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
DECLARE object_id uuid;
BEGIN
 IF TG_TABLE_NAME='hyt_reactions' THEN
  IF NEW.kind<>'like' THEN RETURN NEW; END IF;
  object_id=NEW.post_id;
 ELSE object_id=NEW.comment_id; END IF;
 IF EXISTS (SELECT 1 FROM public.hyt_members WHERE id=NEW.member_id AND created_at <= now()-interval '24 hours') THEN
  NEW.credit=object_id::text||':'||NEW.member_id;
 ELSE NEW.credit='new:'||(now() AT TIME ZONE 'UTC')::date; END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS hyt_credit_like ON public.hyt_reactions;
CREATE TRIGGER hyt_credit_like BEFORE INSERT ON public.hyt_reactions FOR EACH ROW EXECUTE FUNCTION public.hyt_credit();
DROP TRIGGER IF EXISTS hyt_credit_like ON public.hyt_comment_likes;
CREATE TRIGGER hyt_credit_like BEFORE INSERT ON public.hyt_comment_likes FOR EACH ROW EXECUTE FUNCTION public.hyt_credit();
-- Community collection extends existing identities/achievements without copying their rows.
CREATE TABLE IF NOT EXISTS public.hyt_collection_definitions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 code text NOT NULL UNIQUE CHECK(code ~ '^[a-z][a-z0-9-]{1,47}$'),
 name text NOT NULL CHECK(length(name) BETWEEN 2 AND 24),
 category text NOT NULL CHECK(category IN ('identity','contribution','legend','limited','hidden')),
 rarity text NOT NULL CHECK(rarity IN ('common','fine','rare','epic','legendary')),
 criteria text NOT NULL CHECK(length(criteria) BETWEEN 2 AND 240),
 story text NOT NULL CHECK(length(story) BETWEEN 2 AND 240),
 edition_year int CHECK(edition_year BETWEEN 2020 AND 2100),
 capacity int CHECK(capacity BETWEEN 1 AND 10000),
 mode text NOT NULL CHECK(mode IN ('review','automatic','template')),
 archived_at timestamptz,
 CHECK(edition_year IS NULL OR category='limited'),
 CHECK(mode<>'template' OR (category='limited' AND edition_year IS NULL))
);
CREATE TABLE IF NOT EXISTS public.hyt_collection_grants (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), member_id uuid NOT NULL REFERENCES public.hyt_members(id),
 definition_id uuid NOT NULL REFERENCES public.hyt_collection_definitions(id),
 actor_id uuid REFERENCES public.hyt_members(id), earned_at timestamptz NOT NULL DEFAULT now(),
 story text NOT NULL CHECK(length(story) BETWEEN 2 AND 240),
 evidence text, seen_at timestamptz, revoked_at timestamptz, public_hidden boolean NOT NULL DEFAULT false,
 UNIQUE(member_id,definition_id)
);
CREATE INDEX IF NOT EXISTS hyt_collection_active ON public.hyt_collection_grants(definition_id,earned_at DESC,id DESC) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS hyt_collection_registration ON public.hyt_members(created_at,id);
CREATE TABLE IF NOT EXISTS public.hyt_collection_audit (
 request_id uuid PRIMARY KEY, actor_id uuid NOT NULL REFERENCES public.hyt_members(id),
 member_id uuid REFERENCES public.hyt_members(id), operation text NOT NULL, payload jsonb NOT NULL,
 outcome text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS hyt_collection_audit_order ON public.hyt_collection_audit(created_at DESC,request_id DESC);
ALTER TABLE public.hyt_members ADD COLUMN IF NOT EXISTS worn_collection uuid REFERENCES public.hyt_collection_grants(id);
ALTER TABLE public.hyt_members ADD COLUMN IF NOT EXISTS collection_title text;
ALTER TABLE public.hyt_members ADD COLUMN IF NOT EXISTS collection_use_title boolean NOT NULL DEFAULT false;
ALTER TABLE public.hyt_members ADD COLUMN IF NOT EXISTS collection_checked_at timestamptz;

INSERT INTO public.hyt_collection_definitions(code,name,category,rarity,criteria,story,mode) VALUES
 ('handan-light','邯院之光','legend','legendary','审核重大贡献的具体影响与佐证。','这份贡献让更多同学受益。','review'),
 ('that-person','传说中的那个人','legend','legendary','审核具有代表性的社区故事及当事人授权。','一个被同学们长久记住的名字。','review'),
 ('community-classic','镇站之宝','legend','legendary','审核经典原创内容、原帖及长期影响。','这件作品成为社区记忆的一部分。','review'),
 ('campus-legend','校园传奇','legend','legendary','审核跨学期的持续贡献和独立认可记录。','你用时间留下了自己的校园印记。','review'),
 ('first-hundred','开天辟地','legend','legendary','按原始注册时间排序的前 100 个账号。','社区刚开门时，你已经在这里。','automatic'),
 ('architect','社区建筑师','contribution','epic','提交被采纳的建议及落地版本记录，由开发者审核。','你的建议成为了同学们真的能用到的功能。','review'),
 ('landmark-post','神帖制造机','contribution','epic','一篇公开原创帖获得至少 10 位符合条件的不同同学点赞。','有一篇你写的故事，被很多同学认真读过。','automatic'),
 ('gold-creator','黄金创作者','contribution','epic','审核至少三篇官方精选作品及其记录。','被收藏的好作品不止一件。','review'),
 ('bug-hunter','捉虫大师','contribution','epic','审核严重问题的反馈、复现证据与修复记录。','一处难找的故障，被你沿着线索查清。','review'),
 ('early-resident','初代居民','identity','rare','社区首条注册记录起 30 天内加入。','在最早的一个月，你来到社区。','automatic'),
 ('answer-guide','百事通','contribution','rare','审核跨时段的有效互助记录与求助者反馈。','有人找到答案，是因为你愿意多解释一步。','review'),
 ('campus-photographer','金牌摄影师','contribution','rare','审核至少三件校园摄影精选及原创证明。','你把邯院的光影留了下来。','review'),
 ('campus-observer','校园观察家','contribution','rare','审核持续分享的原创校园见闻与实际价值。','那些容易被略过的校园细节，被你记录了下来。','review'),
 ('good-company','气氛组组长','contribution','rare','审核跨主题的积极互动与具体社区反馈。','你让讨论变得更有意思，也让新人更愿意开口。','review'),
 ('person-of-year','年度人物','limited','legendary','按年份建档，审核评选结果和公开事迹。','这一年，你成为同学们记得的人。','template'),
 ('creator-of-year','年度最佳创作者','limited','epic','按年份建档，审核年度作品与评选记录。','你的作品为这一年留下了注脚。','template'),
 ('photo-of-year','年度摄影师','limited','epic','按年份建档，审核年度摄影作品和评选记录。','这一年的校园，有了你留下的影像。','template'),
 ('warmth-of-year','年度最温暖的人','limited','epic','按年份建档，审核年度互助事迹与评选记录。','这一年的许多小事，因为你而更温暖。','template'),
 ('graduation-keepsake','毕业季青春纪念章','limited','rare','按实际活动年份建档，核实毕业季参与记录。','离开校园之前，你给这一段青春留了一张书签。','template'),
 ('welcome-guide','迎新季引路人','limited','rare','按实际迎新年份建档，审核有效引导与互助记录。','有同学因为你的指路，更快熟悉了校园。','template'),
 ('before-dawn','凌晨四点的邯院','hidden','rare','凌晨公开分享并收到同学认可的回应。','邯院还没醒，你的故事已经有人读到了。','automatic'),
 ('developer-noticed','被开发者看见了','hidden','epic','有开发者核实的贡献授予记录。','你留下的贡献，被开发者认真记下来了。','automatic'),
 ('world-lines','世界线收束','hidden','legendary','首批注册账号的第一周年。','从开门第一天一路走来，两段时间终于接上。','automatic'),
 ('archivist','考古学家','hidden','rare','在两条半年前的公开帖子里留下受认可的回复。','你把两段旧故事带回了今天。','automatic'),
 ('crossed-paths','命运的相遇','hidden','fine','互相关注的同学曾在彼此的公开帖子下认真交流。','你们在各自的故事里，相遇了两次。','automatic'),
 ('no-island','没有人是一座孤岛','hidden','epic','多位长期同学在不同的公开帖里送来拥抱。','隔着不同的日子和屏幕，总有人向你伸手。','automatic')
ON CONFLICT(code) DO NOTHING;

CREATE OR REPLACE FUNCTION public.hyt_collection_item(
 d public.hyt_collection_definitions,g public.hyt_collection_grants
) RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('id',d.id,'code',d.code,'name',d.name,'category',d.category,'rarity',d.rarity,
 'year',d.edition_year,'archived',d.archived_at IS NOT NULL OR coalesce(d.edition_year<extract(year FROM now() AT TIME ZONE 'Asia/Shanghai'),false),'capacity',d.capacity,
 'criteria',CASE WHEN d.category<>'hidden' THEN d.criteria END,
 'awardId',g.id,'at',g.earned_at,'story',CASE WHEN g.id IS NOT NULL THEN g.story END,
 'publicHidden',coalesce(g.public_hidden,false));
$$;

CREATE OR REPLACE FUNCTION public.hyt_collection_refresh(m public.hyt_members) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
DECLARE first_day timestamptz; pioneer boolean;
BEGIN
 IF m.collection_checked_at>now()-interval '20 minutes' THEN RETURN; END IF;
 UPDATE public.hyt_members SET collection_checked_at=now() WHERE id=m.id AND deleted_at IS NULL
 AND (collection_checked_at IS NULL OR collection_checked_at<=now()-interval '20 minutes');
 IF NOT FOUND THEN RETURN; END IF;
 SELECT created_at INTO first_day FROM public.hyt_members ORDER BY created_at,id LIMIT 1;
 SELECT EXISTS(SELECT 1 FROM (SELECT id FROM public.hyt_members ORDER BY created_at,id LIMIT 100) original WHERE id=m.id) INTO pioneer;
 WITH missing AS (
   SELECT d.* FROM public.hyt_collection_definitions d
   WHERE d.mode='automatic' AND d.archived_at IS NULL AND NOT EXISTS
    (SELECT 1 FROM public.hyt_collection_grants g WHERE g.member_id=m.id AND g.definition_id=d.id)
 ), qualifying AS (
   SELECT d.* FROM missing d WHERE CASE d.code
   WHEN 'early-resident' THEN m.created_at<first_day+interval '30 days'
   WHEN 'first-hundred' THEN pioneer
   WHEN 'world-lines' THEN pioneer AND m.created_at+interval '1 year'<=now()
   WHEN 'developer-noticed' THEN EXISTS (
     SELECT 1 FROM public.hyt_collection_grants g JOIN public.hyt_collection_definitions reviewed ON reviewed.id=g.definition_id
     WHERE g.member_id=m.id AND g.revoked_at IS NULL AND g.actor_id IS NOT NULL AND reviewed.category IN ('legend','contribution')
   ) OR EXISTS (
     SELECT 1 FROM public.hyt_honor_history h JOIN public.hyt_honors old ON old.member_id=h.target AND old.kind=h.change->>'kind'
     JOIN public.hyt_members actor ON actor.id=h.actor WHERE h.target=m.id AND actor.developer_since IS NOT NULL AND h.change->>'operation'='grant'
   )
   WHEN 'landmark-post' THEN EXISTS (
     SELECT 1 FROM public.hyt_posts p JOIN public.hyt_reactions r ON r.post_id=p.id AND r.kind='like'
     JOIN public.hyt_members peer ON peer.id=r.member_id AND peer.id<>m.id AND peer.deleted_at IS NULL
     WHERE p.author_id=m.id AND NOT p.anonymous AND p.deleted_at IS NULL
       AND p.created_at>=m.created_at AND peer.created_at<least(now()-interval '30 days',p.created_at)
     GROUP BY p.id HAVING count(DISTINCT peer.id)>=10
   )
   WHEN 'before-dawn' THEN EXISTS (
     SELECT 1 FROM public.hyt_posts p JOIN public.hyt_responses r ON r.post_id=p.id
     JOIN public.hyt_members peer ON peer.id=r.member_id AND peer.id<>m.id AND peer.deleted_at IS NULL
     WHERE p.author_id=m.id AND NOT p.anonymous AND p.deleted_at IS NULL
       AND extract(hour FROM p.created_at AT TIME ZONE 'Asia/Shanghai')=4
       AND peer.created_at<=p.created_at-interval '30 days'
   )
   WHEN 'archivist' THEN 2<=(SELECT count(DISTINCT c.post_id) FROM public.hyt_comments c
     JOIN public.hyt_posts p ON p.id=c.post_id AND p.deleted_at IS NULL AND NOT p.anonymous AND p.author_id<>m.id
     JOIN public.hyt_comment_likes l ON l.comment_id=c.id
     JOIN public.hyt_members peer ON peer.id=l.member_id AND peer.id<>m.id AND peer.deleted_at IS NULL
     WHERE c.author_id=m.id AND c.deleted_at IS NULL AND NOT c.anonymous AND c.created_at>=p.created_at+interval '180 days'
       AND peer.created_at<=c.created_at-interval '30 days')
   WHEN 'crossed-paths' THEN EXISTS (
     SELECT 1 FROM public.hyt_follows f JOIN public.hyt_follows other ON (other.member_id,other.followed_id)=(f.followed_id,m.id)
     JOIN public.hyt_members peer ON peer.id=f.followed_id AND peer.deleted_at IS NULL AND peer.created_at<=now()-interval '30 days'
     WHERE f.member_id=m.id AND m.created_at<=now()-interval '30 days'
       AND EXISTS(SELECT 1 FROM public.hyt_comments c JOIN public.hyt_posts p ON p.id=c.post_id
         WHERE c.author_id=m.id AND NOT c.anonymous AND c.deleted_at IS NULL AND p.author_id=peer.id AND NOT p.anonymous AND p.deleted_at IS NULL)
       AND EXISTS(SELECT 1 FROM public.hyt_comments c JOIN public.hyt_posts p ON p.id=c.post_id
         WHERE c.author_id=peer.id AND NOT c.anonymous AND c.deleted_at IS NULL AND p.author_id=m.id AND NOT p.anonymous AND p.deleted_at IS NULL)
   )
   WHEN 'no-island' THEN EXISTS (
     SELECT 1 FROM public.hyt_posts p JOIN public.hyt_responses r ON r.post_id=p.id AND r.kind='hug'
     JOIN public.hyt_members peer ON peer.id=r.member_id AND peer.id<>m.id AND peer.deleted_at IS NULL
     WHERE p.author_id=m.id AND NOT p.anonymous AND p.deleted_at IS NULL
       AND peer.created_at<=p.created_at-interval '30 days'
     HAVING count(DISTINCT peer.id)>=3 AND count(DISTINCT (p.created_at AT TIME ZONE 'Asia/Shanghai')::date)>=2
   ) ELSE false END
 )
 INSERT INTO public.hyt_collection_grants(member_id,definition_id,story,earned_at,seen_at)
 SELECT m.id,id,story,CASE WHEN code IN ('early-resident','first-hundred') THEN m.created_at
   WHEN code='world-lines' THEN m.created_at+interval '1 year' ELSE now() END,
 CASE WHEN rarity NOT IN ('epic','legendary') AND category<>'hidden' THEN now() END
 FROM qualifying ON CONFLICT(member_id,definition_id) DO NOTHING;
END $$;

CREATE OR REPLACE FUNCTION public.hyt_collection_badge(m public.hyt_members) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('id',g.id,'code',d.code,'name',d.name,'rarity',d.rarity,
 'title',CASE WHEN m.collection_use_title THEN coalesce(m.collection_title,d.name) END)
 FROM public.hyt_collection_grants g JOIN public.hyt_collection_definitions d ON d.id=g.definition_id
 WHERE g.id=m.worn_collection AND g.member_id=m.id AND g.revoked_at IS NULL
   AND (d.category<>'hidden' OR g.public_hidden);
$$;

CREATE OR REPLACE FUNCTION public.hyt_badges(m public.hyt_members) RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('official',CASE WHEN m.developer_since IS NOT NULL THEN jsonb_build_object('code','developer','at',m.developer_since)
 WHEN m.role='moderator' THEN jsonb_build_object('code','moderator','at',coalesce(m.moderator_since,
 (SELECT min(created_at) FROM public.hyt_moderation WHERE moderator_id=m.id AND action='grant_moderator'))) END,
 'worn',(SELECT jsonb_build_object('code',kind,'at',granted_at) FROM public.hyt_honors WHERE member_id=m.id AND kind=m.worn_honor))
 || coalesce((SELECT jsonb_build_object('collection',badge) FROM public.hyt_collection_badge(m) badge WHERE badge IS NOT NULL),'{}');
$$;
CREATE OR REPLACE FUNCTION public.hyt_progress(uid uuid,metric text) RETURNS int LANGUAGE plpgsql STABLE AS $$
DECLARE total int;
BEGIN
 IF metric='registered' THEN RETURN 1;
 ELSIF metric='posts' THEN
  SELECT count(*) INTO total FROM (SELECT 1 FROM (
   SELECT DISTINCT CASE WHEN p.body<>'' OR p.title<>'' THEN regexp_replace(lower(p.title||' '||p.body),'[[:space:][:punct:]]','','g')
    ELSE coalesce((SELECT string_agg(i.digest,',' ORDER BY i.position) FROM public.hyt_media i WHERE i.post_id=p.id AND i.comment_id IS NULL AND i.ready AND i.deleted_at IS NULL),
    (SELECT definition::text FROM public.hyt_polls WHERE post_id=p.id),(SELECT definition::text FROM public.hyt_buddies WHERE post_id=p.id)) END AS signature
   FROM public.hyt_posts p WHERE p.author_id=uid AND p.deleted_at IS NULL
  ) p WHERE nullif(signature,'') IS NOT NULL LIMIT 5) counted;
 ELSIF metric='threads' OR metric='comment' THEN
  -- An identical normalized reply pasted into many discussions gives credit once.
  -- One post can earn at most one discussion credit; use a deterministic canonical occurrence.
  SELECT count(*) INTO total FROM (SELECT DISTINCT post_id FROM (
   SELECT DISTINCT ON (norm) post_id FROM (
    SELECT c.post_id,c.created_at,c.id,CASE WHEN c.body='' AND EXISTS(SELECT 1 FROM public.hyt_media i WHERE i.comment_id=c.id AND i.ready AND i.deleted_at IS NULL) THEN (SELECT string_agg(i.digest,',' ORDER BY i.position) FROM public.hyt_media i WHERE i.comment_id=c.id AND i.ready AND i.deleted_at IS NULL) ELSE regexp_replace(lower(c.body),'[[:space:][:punct:]]','','g') END norm
    FROM public.hyt_comments c JOIN public.hyt_posts p ON p.id=c.post_id
    WHERE c.author_id=uid AND c.deleted_at IS NULL AND p.deleted_at IS NULL
   ) comments WHERE length(norm)>=2 AND norm !~ '^(.)\1+$' ORDER BY norm,created_at,id
  ) eligible LIMIT 10) counted;
 ELSIF metric='saves' THEN
  SELECT count(*) INTO total FROM (SELECT 1 FROM public.hyt_reactions r JOIN public.hyt_posts p ON p.id=r.post_id
   WHERE r.member_id=uid AND r.kind='save' AND p.deleted_at IS NULL LIMIT 20) s;
 ELSIF metric='likes' THEN
  SELECT count(*) INTO total FROM (SELECT DISTINCT credit FROM (
   SELECT coalesce(r.credit,CASE WHEN n.created_at>=u.created_at+interval '24 hours' THEN p.id::text||':'||u.id ELSE 'new:'||(n.created_at AT TIME ZONE 'UTC')::date END) credit
   FROM public.hyt_posts p JOIN public.hyt_reactions r ON r.post_id=p.id AND r.kind='like'
   JOIN public.hyt_members u ON u.id=r.member_id AND u.deleted_at IS NULL
   LEFT JOIN public.hyt_notifications n ON r.credit IS NULL AND n.recipient_id=uid AND n.event_key='post-like:'||p.id||':'||u.id
   WHERE p.author_id=uid AND u.id<>uid AND p.deleted_at IS NULL
   UNION ALL
   SELECT coalesce(l.credit,CASE WHEN n.created_at>=u.created_at+interval '24 hours' THEN c.id::text||':'||u.id ELSE 'new:'||(n.created_at AT TIME ZONE 'UTC')::date END)
   FROM public.hyt_comments c JOIN public.hyt_posts p ON p.id=c.post_id AND p.deleted_at IS NULL
   JOIN public.hyt_comment_likes l ON l.comment_id=c.id JOIN public.hyt_members u ON u.id=l.member_id AND u.deleted_at IS NULL
   LEFT JOIN public.hyt_notifications n ON l.credit IS NULL AND n.recipient_id=uid AND n.event_key='comment-like:'||c.id||':'||u.id
   WHERE c.author_id=uid AND u.id<>uid AND c.deleted_at IS NULL
  ) credits WHERE credit IS NOT NULL LIMIT 30) s;
 END IF;
 RETURN coalesce(total,0);
END $$;
CREATE OR REPLACE FUNCTION public.hyt_award_check(uid uuid,metric text,historical boolean DEFAULT false) RETURNS void LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
 -- Serialize grants for the same recipient, without taking their member row on another user's like.
 PERFORM pg_advisory_xact_lock(hashtextextended(uid::text||':awards',0));
 IF NOT EXISTS (SELECT 1 FROM (VALUES ('registered','arrival'),('posts','firstpost'),('posts','sprout'),('threads','hello'),('threads','neighbor'),('likes','liked'),('likes','popular'),('saves','collector')) codes(m,k)
  WHERE m=metric AND NOT EXISTS(SELECT 1 FROM public.hyt_awards WHERE member_id=uid AND code=k)) THEN RETURN; END IF;
 n=public.hyt_progress(uid,metric);
 INSERT INTO public.hyt_awards(member_id,code,earned_at,seen,backfilled)
 SELECT uid,k,CASE WHEN k='arrival' THEN (SELECT created_at FROM public.hyt_members WHERE id=uid) ELSE now() END,historical,historical AND k<>'arrival'
 FROM (VALUES ('registered','arrival',1),('posts','firstpost',1),('posts','sprout',5),('threads','hello',1),('threads','neighbor',10),
 ('likes','liked',1),('likes','popular',30),('saves','collector',20)) v(m,k,threshold)
 WHERE m=metric AND n>=threshold ON CONFLICT DO NOTHING;
END $$;
CREATE OR REPLACE FUNCTION public.hyt_award_pending(uid uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('awardOwner',uid,'unlocks',coalesce(jsonb_agg(code ORDER BY earned_at,code),'[]')) FROM public.hyt_awards WHERE member_id=uid AND NOT seen;
$$;
CREATE OR REPLACE FUNCTION public.hyt_hall(u public.hyt_members,viewer uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('id',u.id,'nickname',u.nickname,'badges',public.hyt_badges(u),'showcase',u.showcase,
 'honors',coalesce((SELECT jsonb_agg(jsonb_build_object('code',kind,'at',granted_at) ORDER BY granted_at) FROM public.hyt_honors WHERE member_id=u.id),'[]'),
 'total',(SELECT count(*) FROM public.hyt_awards WHERE member_id=u.id),
 'backfilled',ARRAY(SELECT code FROM public.hyt_awards WHERE member_id=u.id AND backfilled AND (viewer=u.id OR code=ANY(u.showcase))),
 'awards',coalesce((SELECT jsonb_object_agg(code,earned_at) FROM public.hyt_awards WHERE member_id=u.id AND (viewer=u.id OR code=ANY(u.showcase))),'{}'))
 || CASE WHEN viewer=u.id THEN jsonb_build_object('progress',jsonb_build_object('posts',public.hyt_progress(u.id,'posts'),'threads',public.hyt_progress(u.id,'threads'),'likes',public.hyt_progress(u.id,'likes'),'saves',public.hyt_progress(u.id,'saves'),'registered',1,'days',greatest(0,floor(extract(epoch FROM (now()-u.created_at))/86400)::int))) ELSE '{}' END;
$$;

CREATE OR REPLACE FUNCTION public.hyt_member_json(m public.hyt_members) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('id',m.id,'badges',public.hyt_badges(m),'caps',CASE WHEN m.role='moderator' THEN m.mod_caps ELSE '{}'::text[] END,'showcase',m.showcase,'username',m.username,'nickname',m.nickname,'role',m.role,'bannedUntil',m.banned_until,'bio',m.bio,'avatar',public.hyt_avatar_json(m.id));
$$;
CREATE OR REPLACE FUNCTION public.hyt_author_json(uid uuid, pid uuid, anon boolean, viewer uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('name',CASE WHEN anon THEN '匿名同学 · '||coalesce(a.label,'隐藏') ELSE m.nickname END,
 'anonymous',anon,'mine',uid=viewer)||CASE WHEN anon THEN '{}'::jsonb ELSE jsonb_build_object('badges',public.hyt_badges(m),'id',uid,'avatar',public.hyt_avatar_json(uid)) END
 FROM public.hyt_members m LEFT JOIN public.hyt_thread_aliases a ON a.member_id=m.id AND a.post_id=pid WHERE m.id=uid;
$$;
CREATE OR REPLACE FUNCTION public.hyt_post_json(p public.hyt_posts, viewer uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('id',p.id,'body',CASE WHEN p.body='' THEN coalesce((SELECT '[投票] '||(definition->>'question') FROM public.hyt_polls WHERE post_id=p.id),'') ELSE p.body END,'buddy',public.hyt_buddy_json(p.id,viewer),'poll',public.hyt_poll_json(p.id,viewer),'anonymous',p.anonymous,'author',public.hyt_author_json(p.author_id,p.id,p.anonymous,viewer),
 'createdAt',p.created_at,'locked',p.locked,'title',p.title,'category',p.category,'interest',p.interest,
 'responseCounts',(SELECT coalesce(jsonb_object_agg(kind,total),'{}'::jsonb) FROM (SELECT kind,count(*) AS total FROM public.hyt_responses WHERE post_id=p.id GROUP BY kind) responses),
 'myResponse',(SELECT kind FROM public.hyt_responses WHERE post_id=p.id AND member_id=viewer),
 'images',(SELECT coalesce(jsonb_agg(public.hyt_media_json(img) ORDER BY position),'[]'::jsonb) FROM public.hyt_media img WHERE img.post_id=p.id AND img.comment_id IS NULL AND img.ready AND img.deleted_at IS NULL),
 'commentCount',(SELECT count(*) FROM public.hyt_comments c WHERE c.post_id=p.id AND c.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks b WHERE b.member_id=viewer AND b.blocked_id=c.author_id AND NOT c.anonymous)),
 'likeCount',(SELECT count(*) FROM public.hyt_reactions r WHERE r.post_id=p.id AND r.kind='like'),
 'liked',EXISTS(SELECT 1 FROM public.hyt_reactions r WHERE r.post_id=p.id AND r.member_id=viewer AND r.kind='like'),
 'saved',EXISTS(SELECT 1 FROM public.hyt_reactions r WHERE r.post_id=p.id AND r.member_id=viewer AND r.kind='save'),
 'watching',EXISTS(SELECT 1 FROM public.hyt_thread_watches w WHERE w.post_id=p.id AND w.member_id=viewer AND w.enabled),
 'newReplyCount',(SELECT count(*) FROM public.hyt_comments c JOIN public.hyt_thread_visits v ON v.post_id=c.post_id AND v.member_id=viewer
 WHERE c.post_id=p.id AND c.created_at>v.seen_at AND c.author_id<>viewer AND c.deleted_at IS NULL
 AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=viewer AND bl.blocked_id=c.author_id AND NOT c.anonymous)));
$$;
CREATE OR REPLACE FUNCTION public.hyt_comment_json(c public.hyt_comments, viewer uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('id',c.id,'postId',c.post_id,'body',CASE WHEN c.deleted_at IS NULL THEN CASE WHEN c.body='' THEN '[图片]' ELSE c.body END ELSE '这条评论已删除' END,
 'author',CASE WHEN c.deleted_at IS NULL THEN public.hyt_author_json(c.author_id,c.post_id,c.anonymous,viewer) ELSE jsonb_build_object('name','已删除','anonymous',true,'mine',false) END,
 'images',CASE WHEN c.deleted_at IS NULL THEN (SELECT coalesce(jsonb_agg(public.hyt_media_json(img) ORDER BY position),'[]'::jsonb) FROM public.hyt_media img WHERE img.comment_id=c.id AND img.ready AND img.deleted_at IS NULL) ELSE '[]'::jsonb END,
 'createdAt',c.created_at,'replyTo',c.reply_to,'rootId',c.root_id,'deleted',c.deleted_at IS NOT NULL,
 'likeCount',CASE WHEN c.deleted_at IS NULL THEN (SELECT count(*) FROM public.hyt_comment_likes l WHERE l.comment_id=c.id) ELSE 0 END,
 'liked',c.deleted_at IS NULL AND EXISTS(SELECT 1 FROM public.hyt_comment_likes l WHERE l.comment_id=c.id AND l.member_id=viewer),
 'replyCount',(SELECT count(*) FROM public.hyt_comments rc WHERE rc.root_id=c.id AND rc.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=viewer AND bl.blocked_id=rc.author_id AND NOT rc.anonymous)),
 'isOriginalPoster',c.deleted_at IS NULL AND c.author_id=p.author_id AND (p.anonymous OR NOT c.anonymous)) FROM public.hyt_posts p WHERE p.id=c.post_id;
$$;

-- Visibility is checked at read time, so removed/blocked content cannot survive in previews or counts.
CREATE OR REPLACE FUNCTION public.hyt_visible_notifications(viewer uuid) RETURNS SETOF public.hyt_notifications
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT n.* FROM public.hyt_notifications n JOIN public.hyt_posts p ON p.id=n.post_id
 JOIN public.hyt_members actor ON actor.id=n.actor_id
 LEFT JOIN public.hyt_comments c ON c.id=n.comment_id
 LEFT JOIN public.hyt_comments root ON root.id=c.root_id
 WHERE n.recipient_id=viewer AND p.deleted_at IS NULL AND actor.deleted_at IS NULL
 AND (n.comment_id IS NULL OR c.deleted_at IS NULL)
 AND NOT EXISTS(SELECT 1 FROM public.hyt_hidden_threads h WHERE h.member_id=viewer AND h.post_id=p.id)
 AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks b WHERE b.member_id=viewer AND b.blocked_id=p.author_id AND NOT p.anonymous)
 AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks b WHERE b.member_id=viewer AND b.blocked_id=root.author_id AND NOT root.anonymous)
 AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks b WHERE b.member_id=viewer AND b.blocked_id=n.actor_id AND (n.kind IN ('post_like','comment_like','post_response','buddy') OR NOT coalesce(c.anonymous,true)))
 AND (n.kind<>'thread_reply' OR EXISTS(SELECT 1 FROM public.hyt_thread_watches w WHERE w.member_id=viewer AND w.post_id=p.id AND w.enabled))
 AND (n.kind<>'post_response' OR EXISTS(SELECT 1 FROM public.hyt_responses r WHERE r.post_id=p.id AND r.member_id=n.actor_id))
 AND (n.kind<>'post_like' OR EXISTS(SELECT 1 FROM public.hyt_reactions r WHERE r.post_id=p.id AND r.member_id=n.actor_id AND r.kind='like'))
 AND (n.kind<>'comment_like' OR EXISTS(SELECT 1 FROM public.hyt_comment_likes l WHERE l.comment_id=c.id AND l.member_id=n.actor_id));
$$;
CREATE OR REPLACE FUNCTION public.hyt_notification_json(n public.hyt_notifications, viewer uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('id',n.id,'kind',n.kind,'postId',n.post_id,'commentId',n.comment_id,
 'rootId',coalesce(c.root_id,c.id),'createdAt',n.created_at,'readAt',n.read_at,
 'postTitle',left(CASE WHEN p.title<>'' THEN p.title ELSE p.body END,100),'excerpt',CASE WHEN n.kind='buddy' THEN '报名或招募状态有更新，点开查看当前情况' WHEN n.kind='post_response' THEN (SELECT CASE kind WHEN 'same' THEN '我也一样' WHEN 'hug' THEN '抱抱' WHEN 'joy' THEN '欢乐' ELSE '有用' END FROM public.hyt_responses WHERE post_id=p.id AND member_id=n.actor_id) ELSE left(coalesce(nullif(c.body,''),CASE WHEN c.id IS NOT NULL THEN '[图片]' ELSE coalesce(nullif(p.body,''),(SELECT definition->>'question' FROM public.hyt_polls WHERE post_id=p.id)) END),180) END,
 -- A like carries no public identity: it must not link an anonymous participant back to an account.
 'actor',CASE WHEN n.kind IN ('post_like','comment_like','post_response','buddy') THEN jsonb_build_object('name','一位同学','anonymous',true,'mine',false)
 ELSE public.hyt_author_json(n.actor_id,n.post_id,c.anonymous,viewer) END)
 FROM public.hyt_posts p LEFT JOIN public.hyt_comments c ON c.id=n.comment_id WHERE p.id=n.post_id;
$$;
CREATE OR REPLACE FUNCTION public.hyt_notify_comment(c public.hyt_comments) RETURNS void
LANGUAGE sql SET search_path=pg_catalog,public AS $$
 INSERT INTO public.hyt_notifications(recipient_id,actor_id,post_id,comment_id,kind,event_key)
 SELECT recipient,c.author_id,c.post_id,c.id,CASE min(priority) WHEN 1 THEN 'reply' WHEN 2 THEN 'post_reply' ELSE 'thread_reply' END,'comment:'||c.id
 FROM (
  SELECT author_id AS recipient,1 AS priority FROM public.hyt_comments WHERE id=c.reply_to AND deleted_at IS NULL
  UNION ALL SELECT author_id,2 FROM public.hyt_posts WHERE id=c.post_id
  UNION ALL SELECT member_id,3 FROM public.hyt_thread_watches WHERE post_id=c.post_id AND enabled
 ) recipients JOIN public.hyt_members member ON member.id=recipient AND member.deleted_at IS NULL
 WHERE recipient<>c.author_id GROUP BY recipient ON CONFLICT(recipient_id,event_key) DO NOTHING;
$$;

CREATE OR REPLACE FUNCTION public.hyt_profile_json(u public.hyt_members,viewer uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('showcase',u.showcase,'badges',public.hyt_badges(u),'id',u.id,'nickname',u.nickname,'bio',u.bio,'avatar',public.hyt_avatar_json(u.id),
 'following',EXISTS(SELECT 1 FROM public.hyt_follows f WHERE f.member_id=viewer AND f.followed_id=u.id),
 'postCount',(SELECT count(*) FROM public.hyt_posts p WHERE p.author_id=u.id AND NOT p.anonymous AND p.deleted_at IS NULL
 AND NOT EXISTS(SELECT 1 FROM public.hyt_hidden_threads h WHERE h.member_id=viewer AND h.post_id=p.id)));
$$;

CREATE OR REPLACE FUNCTION public.hyt_dm_visible(viewer uuid) RETURNS SETOF public.hyt_dm_threads
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT t.* FROM public.hyt_dm_threads t JOIN public.hyt_members u ON u.id=CASE WHEN t.low_id=viewer THEN t.high_id ELSE t.low_id END
 WHERE viewer IN (t.low_id,t.high_id) AND u.deleted_at IS NULL
 AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks b WHERE (b.member_id=viewer AND b.blocked_id=u.id) OR (b.member_id=u.id AND b.blocked_id=viewer));
$$;
CREATE OR REPLACE FUNCTION public.hyt_dm_json(t public.hyt_dm_threads,viewer uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('id',t.id,'member',jsonb_build_object('id',u.id,'nickname',u.nickname,'avatar',public.hyt_avatar_json(u.id)),
 'lastSeq',t.last_seq::text,'updatedAt',t.updated_at,
 'lastMessage',(SELECT left(body,100) FROM public.hyt_dm_messages WHERE thread_id=t.id ORDER BY seq DESC LIMIT 1),
 'unreadCount',(SELECT count(*) FROM public.hyt_dm_messages d WHERE d.thread_id=t.id AND d.sender_id<>viewer
 AND d.seq>coalesce((SELECT last_seq FROM public.hyt_dm_reads WHERE thread_id=t.id AND member_id=viewer),0)))
 FROM public.hyt_members u WHERE u.id=CASE WHEN t.low_id=viewer THEN t.high_id ELSE t.low_id END;
$$;
CREATE OR REPLACE FUNCTION public.hyt_dm_message_json(d public.hyt_dm_messages,viewer uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('id',d.id,'seq',d.seq::text,'body',d.body,'mine',d.sender_id=viewer,'createdAt',d.created_at,'requestId',CASE WHEN d.sender_id=viewer THEN d.request_id ELSE NULL END);
$$;

-- Each call is a PostgreSQL transaction. The HTTP server is the only caller.
CREATE OR REPLACE FUNCTION public.hyt_collection_api(a text,b jsonb,m public.hyt_members) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
#variable_conflict use_column
DECLARE target public.hyt_members; d public.hyt_collection_definitions;
 g public.hyt_collection_grants; previous public.hyt_collection_audit;
 operation text:=b->>'operation'; outcome text:='ok'; rows jsonb; own boolean;
 wanted uuid:=(b->>'memberId')::uuid; award uuid:=(b->>'awardId')::uuid;
 definition uuid:=(b->>'definitionId')::uuid; request uuid:=(b->>'requestId')::uuid;
 page int:=coalesce((b->>'offset')::int,0); edition int:=(b->>'year')::int;
BEGIN
 IF a='collection.profile' THEN
  wanted:=coalesce(wanted,m.id); own:=wanted=m.id;
  SELECT * INTO target FROM public.hyt_members u WHERE id=wanted AND deleted_at IS NULL
    AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks WHERE (member_id,blocked_id) IN ((wanted,m.id),(m.id,wanted)));
  IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'; END IF;
  IF own THEN PERFORM public.hyt_collection_refresh(target); END IF;
  SELECT coalesce(jsonb_agg(s.item),'[]') INTO rows FROM (
   SELECT public.hyt_collection_item(d,g) AS item
   FROM public.hyt_collection_definitions d LEFT JOIN public.hyt_collection_grants g
     ON g.definition_id=d.id AND g.member_id=wanted AND g.revoked_at IS NULL
   WHERE (d.mode<>'template' AND d.category<>'hidden' AND own AND d.archived_at IS NULL
          AND (d.edition_year IS NULL OR d.edition_year>=extract(year FROM now() AT TIME ZONE 'Asia/Shanghai')))
     OR (g.id IS NOT NULL AND (own OR d.category<>'hidden' OR g.public_hidden))
   ORDER BY (g.id IS NULL),g.earned_at DESC,d.category,d.name LIMIT 41 OFFSET page
  ) s;
  RETURN jsonb_build_object('status',200,'collection',jsonb_build_object('id',wanted,'nickname',target.nickname,
    'items',rows,'badges',public.hyt_badges(target),
    'identities',coalesce((SELECT jsonb_agg(kind ORDER BY granted_at) FROM public.hyt_honors WHERE member_id=wanted),'[]'),
    'customTitle',CASE WHEN own THEN target.collection_title END,
    'useTitle',own AND target.collection_use_title,
    'total',(SELECT count(*) FROM public.hyt_collection_grants g JOIN public.hyt_collection_definitions d ON d.id=g.definition_id
      WHERE g.member_id=wanted AND g.revoked_at IS NULL AND (own OR d.category<>'hidden' OR g.public_hidden)),
    'rarities',(SELECT coalesce(jsonb_object_agg(rarity,n),'{}') FROM (
      SELECT d.rarity,count(*) n FROM public.hyt_collection_grants g JOIN public.hyt_collection_definitions d ON d.id=g.definition_id
      WHERE g.member_id=wanted AND g.revoked_at IS NULL AND (own OR d.category<>'hidden' OR g.public_hidden) GROUP BY d.rarity
    ) counts),'unseen',CASE WHEN own AND page=0 THEN (SELECT coalesce(jsonb_agg(g.id ORDER BY g.earned_at),'[]') FROM public.hyt_collection_grants g
      WHERE g.member_id=m.id AND g.revoked_at IS NULL AND g.seen_at IS NULL) ELSE '[]'::jsonb END));
 END IF;
 IF a='collection.archive' THEN
  SELECT coalesce(jsonb_agg(s.item),'[]') INTO rows FROM (
   SELECT public.hyt_collection_item(d,g)||jsonb_build_object('memberId',u.id,'nickname',u.nickname) AS item
   FROM public.hyt_collection_grants g JOIN public.hyt_collection_definitions d ON d.id=g.definition_id
   JOIN public.hyt_members u ON u.id=g.member_id AND u.deleted_at IS NULL
   WHERE g.revoked_at IS NULL AND d.category<>'hidden'
    AND CASE b->>'section' WHEN 'legend' THEN d.category='legend'
     WHEN 'annual' THEN d.category='limited' AND d.edition_year IS NOT NULL
     WHEN 'retired' THEN d.archived_at IS NOT NULL OR d.edition_year<extract(year FROM now() AT TIME ZONE 'Asia/Shanghai')
     ELSE d.category='contribution' END
    AND (edition IS NULL OR d.edition_year=edition)
    AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks WHERE (member_id,blocked_id) IN ((u.id,m.id),(m.id,u.id)))
   ORDER BY d.edition_year DESC NULLS LAST,g.earned_at DESC,g.id DESC LIMIT 21 OFFSET page
  ) s;
  RETURN jsonb_build_object('status',200,'honorArchive',rows,
   'honorYears',(SELECT coalesce(jsonb_agg(year ORDER BY year DESC),'[]') FROM (SELECT DISTINCT edition_year AS year
    FROM public.hyt_collection_definitions WHERE edition_year IS NOT NULL) y));
 END IF;
 IF a='collection.wear' OR a='collection.visibility' THEN
  IF award IS NOT NULL THEN
   SELECT * INTO g FROM public.hyt_collection_grants WHERE id=award AND member_id=m.id AND revoked_at IS NULL FOR UPDATE;
   IF NOT FOUND THEN RETURN '{"status":400,"error":"invalid_showcase"}'; END IF;
   SELECT * INTO d FROM public.hyt_collection_definitions WHERE id=g.definition_id;
  END IF;
  IF a='collection.wear' THEN
   IF award IS NOT NULL AND d.category='hidden' AND NOT g.public_hidden THEN RETURN '{"status":409,"error":"honor_visibility_required"}'; END IF;
   UPDATE public.hyt_members SET worn_collection=award,collection_use_title=coalesce((b->>'useTitle')::boolean,false),
    worn_honor=CASE WHEN award IS NOT NULL THEN NULL ELSE worn_honor END WHERE id=m.id RETURNING * INTO target;
  ELSE
   IF award IS NULL OR d.category<>'hidden' THEN RETURN '{"status":400,"error":"invalid_request"}'; END IF;
   UPDATE public.hyt_collection_grants SET public_hidden=(b->>'public')::boolean WHERE id=award;
   UPDATE public.hyt_members SET worn_collection=CASE WHEN worn_collection=award AND NOT(b->>'public')::boolean
     THEN NULL ELSE worn_collection END WHERE id=m.id RETURNING * INTO target;
  END IF;
  RETURN jsonb_build_object('status',200,'updatedIdentity',jsonb_build_object('id',target.id,'badges',public.hyt_badges(target),'showcase',target.showcase));
 END IF;
 IF a='collection.ack' THEN
  UPDATE public.hyt_collection_grants SET seen_at=now()
    WHERE member_id=m.id AND id IN (SELECT jsonb_array_elements_text(b->'awardIds')::uuid) AND revoked_at IS NULL AND seen_at IS NULL;
  RETURN '{"status":200}';
 END IF;
 IF m.developer_since IS NULL OR m.banned_until>now() THEN RETURN '{"status":403,"error":"forbidden"}'; END IF;

 IF a='collection.admin' THEN
  RETURN jsonb_build_object('status',200,
   'honorDefinitions',(SELECT coalesce(jsonb_agg(public.hyt_collection_item(c,NULL)||jsonb_build_object(
    'mode',c.mode,'defaultStory',c.story,'issued',(SELECT count(*) FROM public.hyt_collection_grants WHERE definition_id=c.id))
    ORDER BY c.archived_at NULLS FIRST,c.category,c.edition_year DESC,c.name),'[]') FROM (SELECT * FROM public.hyt_collection_definitions
    ORDER BY archived_at NULLS FIRST,category,edition_year DESC,name LIMIT 101 OFFSET coalesce((b->>'definitionOffset')::int,0)) c),
   'honorMembers',(SELECT coalesce(jsonb_agg(to_jsonb(u)),'[]') FROM (
     SELECT id,nickname,collection_title AS "customTitle" FROM public.hyt_members
     WHERE deleted_at IS NULL AND b->>'query'<>'' AND (id::text=b->>'query' OR nickname=b->>'query')
     ORDER BY id LIMIT 20) u),
   'honorGrants',CASE WHEN wanted IS NULL THEN '[]'::jsonb ELSE
    (SELECT coalesce(jsonb_agg(to_jsonb(s)),'[]') FROM (
      SELECT g.id,d.name,d.edition_year AS year,g.earned_at AS at,g.revoked_at AS revoked,g.evidence
      FROM public.hyt_collection_grants g JOIN public.hyt_collection_definitions d ON d.id=g.definition_id
      WHERE g.member_id=wanted ORDER BY g.earned_at DESC,g.id LIMIT 51 OFFSET coalesce((b->>'grantOffset')::int,0)) s) END,
   'honorAudit',(SELECT coalesce(jsonb_agg(to_jsonb(k)),'[]') FROM (
    SELECT h.*,u.nickname FROM (
     SELECT operation,outcome,created_at AS at,member_id,payload->>'reason' AS reason,payload->>'evidence' AS evidence,request_id AS id
     FROM public.hyt_collection_audit
     WHERE NOT coalesce((b->>'exceptions')::boolean,false) OR outcome<>'ok'
     UNION ALL
     SELECT 'auto_grant','ok',g.earned_at,g.member_id,d.name,g.evidence,g.id
     FROM public.hyt_collection_grants g JOIN public.hyt_collection_definitions d ON d.id=g.definition_id
     WHERE d.mode='automatic' AND NOT coalesce((b->>'exceptions')::boolean,false)
    ) h LEFT JOIN public.hyt_members u ON u.id=h.member_id
    ORDER BY h.at DESC,h.id DESC LIMIT 21 OFFSET page) k));
 END IF;

 IF a<>'collection.change' OR request IS NULL THEN RETURN '{"status":400,"error":"invalid_request"}'; END IF;
 -- Serialize retries of one request before it can mutate any record.
 PERFORM pg_advisory_xact_lock(hashtextextended('hyt-collection:'||request::text,0));
 SELECT * INTO previous FROM public.hyt_collection_audit WHERE request_id=request;
 IF FOUND THEN
  IF previous.actor_id<>m.id OR previous.payload<>b THEN RETURN '{"status":409,"error":"request_conflict"}'; END IF;
  RETURN jsonb_build_object('status',CASE WHEN previous.outcome='ok' THEN 200 ELSE 409 END,'error',nullif(previous.outcome,'ok'));
 END IF;
 IF operation='save' THEN
  IF definition IS NULL THEN
   INSERT INTO public.hyt_collection_definitions(code,name,category,rarity,criteria,story,edition_year,capacity,mode)
    VALUES(b->>'code',b->>'name',b->>'category',b->>'rarity',b->>'criteria',b->>'story',edition,(b->>'capacity')::int,'review')
    ON CONFLICT(code) DO NOTHING;
   IF NOT FOUND THEN outcome:='honor_duplicate'; END IF;
  ELSE
   SELECT * INTO d FROM public.hyt_collection_definitions WHERE id=definition FOR UPDATE;
   IF NOT FOUND OR d.archived_at IS NOT NULL OR d.mode<>'review'
      OR d.edition_year<extract(year FROM now() AT TIME ZONE 'Asia/Shanghai') THEN outcome:='honor_locked';
   ELSIF (b->>'capacity')::int < (SELECT count(*) FROM public.hyt_collection_grants WHERE definition_id=d.id) THEN outcome:='honor_capacity';
   ELSE
    UPDATE public.hyt_collection_definitions SET name=b->>'name',criteria=b->>'criteria',story=b->>'story',capacity=(b->>'capacity')::int
      WHERE id=d.id;
   END IF;
  END IF;
 ELSIF operation='archive' THEN
  UPDATE public.hyt_collection_definitions SET archived_at=now()
   WHERE id=definition AND category='limited' AND edition_year IS NOT NULL AND archived_at IS NULL;
  IF NOT FOUND THEN outcome:='honor_locked'; END IF;
 ELSIF operation='title' THEN
  UPDATE public.hyt_members SET collection_title=nullif(b->>'title','') WHERE id=wanted AND deleted_at IS NULL;
  IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'; END IF;
 ELSIF operation='grant' THEN
  PERFORM 1 FROM public.hyt_members WHERE id=wanted AND deleted_at IS NULL FOR NO KEY UPDATE;
  IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'; END IF;
  SELECT * INTO d FROM public.hyt_collection_definitions WHERE id=definition FOR UPDATE;
  IF NOT FOUND OR d.mode<>'review' OR d.archived_at IS NOT NULL
      OR (d.edition_year IS NOT NULL AND d.edition_year<>extract(year FROM now() AT TIME ZONE 'Asia/Shanghai')) THEN outcome:='honor_locked';
  ELSIF EXISTS(SELECT 1 FROM public.hyt_collection_grants WHERE member_id=wanted AND definition_id=d.id AND revoked_at IS NULL) THEN
   outcome:='honor_duplicate';
  ELSIF d.capacity IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.hyt_collection_grants WHERE member_id=wanted AND definition_id=d.id)
   AND d.capacity<=(SELECT count(*) FROM public.hyt_collection_grants WHERE definition_id=d.id) THEN outcome:='honor_capacity';
  ELSE
   INSERT INTO public.hyt_collection_grants(member_id,definition_id,actor_id,evidence,story,seen_at)
    VALUES(wanted,d.id,m.id,b->>'evidence',b->>'story',CASE WHEN d.rarity NOT IN ('epic','legendary') AND d.category<>'hidden' THEN now() END)
    ON CONFLICT(member_id,definition_id) DO UPDATE SET revoked_at=NULL,actor_id=excluded.actor_id,evidence=excluded.evidence,
     story=excluded.story,public_hidden=false;
  END IF;
 ELSIF operation='revoke' THEN
  SELECT member_id INTO wanted FROM public.hyt_collection_grants WHERE id=award;
  PERFORM 1 FROM public.hyt_members WHERE id=wanted FOR NO KEY UPDATE;
  SELECT g.* INTO g FROM public.hyt_collection_grants g JOIN public.hyt_collection_definitions d ON d.id=g.definition_id
   WHERE g.id=award AND g.revoked_at IS NULL AND d.code NOT IN ('first-hundred','early-resident') FOR UPDATE OF g;
  IF NOT FOUND THEN outcome:='honor_locked';
  ELSE
   wanted:=g.member_id;
   UPDATE public.hyt_collection_grants SET revoked_at=now(),public_hidden=false WHERE id=award;
   UPDATE public.hyt_members SET worn_collection=NULL WHERE id=wanted AND worn_collection=award;
  END IF;
 ELSE RETURN '{"status":400,"error":"invalid_request"}'; END IF;
 INSERT INTO public.hyt_collection_audit(request_id,actor_id,member_id,operation,payload,outcome)
  VALUES(request,m.id,wanted,operation,b,outcome);
 RETURN jsonb_build_object('status',CASE WHEN outcome='ok' THEN 200 ELSE 409 END,'error',nullif(outcome,'ok'));
END $$;

CREATE OR REPLACE FUNCTION public.hyt_community(a text,b jsonb,th text) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog,public AS $fn$
#variable_conflict use_column
DECLARE subject public.hyt_members%ROWTYPE; metric text; m public.hyt_members%ROWTYPE; p public.hyt_posts%ROWTYPE; c public.hyt_comments%ROWTYPE;
 report public.hyt_reports%ROWTYPE; target uuid; result jsonb; n int; k text; stamp timestamptz; limit_n int; anon boolean; img public.hyt_media%ROWTYPE; root uuid; snapshot timestamptz; dm public.hyt_dm_threads%ROWTYPE; msg public.hyt_dm_messages%ROWTYPE;
BEGIN
 IF a='rate' THEN
  DELETE FROM public.hyt_community_rate WHERE key IN (SELECT key FROM public.hyt_community_rate WHERE until_at<now()-interval '1 day' LIMIT 100);
  INSERT INTO public.hyt_community_rate(key,count,until_at) VALUES(b->>'key',1,now()+make_interval(secs=>(b->>'seconds')::int))
  ON CONFLICT(key) DO UPDATE SET count=CASE WHEN hyt_community_rate.until_at<=now() THEN 1 ELSE hyt_community_rate.count+1 END,
  until_at=CASE WHEN hyt_community_rate.until_at<=now() THEN excluded.until_at ELSE hyt_community_rate.until_at END RETURNING count INTO n;
  IF n>(b->>'limit')::int THEN RETURN jsonb_build_object('status',429,'error','too_many_requests'); END IF;
  RETURN '{"status":200}'::jsonb;
 END IF;
 IF a='media.cleanup' THEN
  WITH stale AS (UPDATE public.hyt_media SET deleted_at=coalesce(deleted_at,now()) WHERE id IN (SELECT i.id FROM public.hyt_media i WHERE (i.deleted_at IS NOT NULL OR (i.post_id IS NULL AND i.created_at<now()-interval '7 days')) AND NOT EXISTS(SELECT 1 FROM public.hyt_members u WHERE u.avatar_id=i.id AND u.deleted_at IS NULL) LIMIT 20 FOR UPDATE SKIP LOCKED) RETURNING *) SELECT coalesce(jsonb_agg(public.hyt_media_json(stale)),'[]'::jsonb) INTO result FROM stale;
  RETURN jsonb_build_object('status',200,'images',result);
 END IF;
 IF a='media.purge' THEN
  DELETE FROM public.hyt_media WHERE id=(b->>'imageId')::uuid AND deleted_at IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.hyt_members u WHERE u.avatar_id=hyt_media.id AND u.deleted_at IS NULL);
  RETURN '{"status":200}'::jsonb;
 END IF;
 IF a='credentials' THEN
  SELECT * INTO m FROM public.hyt_members WHERE username=b->>'username' AND deleted_at IS NULL;
  IF NOT FOUND THEN RETURN '{"status":404}'::jsonb; END IF;
  RETURN jsonb_build_object('status',200,'id',m.id,'passwordHash',m.password_hash,'recoveryHash',m.recovery_hash);
 END IF;
 IF a='register' THEN
  INSERT INTO public.hyt_members(username,nickname,password_hash,recovery_hash,awards_initialized)
  VALUES(b->>'username',b->>'nickname',b->>'passwordHash',b->>'recoveryHash',true) ON CONFLICT(username) DO NOTHING RETURNING * INTO m;
  IF NOT FOUND THEN RETURN '{"status":409,"error":"username_unavailable"}'::jsonb; END IF;
  INSERT INTO public.hyt_sessions(hash,member_id,expires_at) VALUES(th,m.id,now()+interval '30 days');
  PERFORM public.hyt_award_check(m.id,'registered');
  RETURN jsonb_build_object('status',201,'user',public.hyt_member_json(m))||public.hyt_award_pending(m.id);
 END IF;
 IF a IN ('login','recover') THEN
  SELECT * INTO m FROM public.hyt_members WHERE id=(b->>'id')::uuid AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND OR (a='login' AND m.password_hash<>b->>'proof') OR (a='recover' AND m.recovery_hash<>b->>'proof') THEN RETURN '{"status":401,"error":"invalid_credentials"}'::jsonb; END IF;
  IF a='recover' THEN
   UPDATE public.hyt_members SET password_hash=b->>'passwordHash',recovery_hash=b->>'recoveryHash' WHERE id=m.id;
   DELETE FROM public.hyt_sessions WHERE member_id=m.id;
  END IF;
  DELETE FROM public.hyt_sessions WHERE member_id=m.id AND (expires_at<=now() OR created_at<now()-interval '30 days');
  DELETE FROM public.hyt_sessions WHERE hash IN (SELECT hash FROM public.hyt_sessions WHERE member_id=m.id ORDER BY created_at DESC OFFSET 9);
  INSERT INTO public.hyt_sessions(hash,member_id,expires_at) VALUES(th,m.id,now()+interval '30 days');
  RETURN jsonb_build_object('status',200,'user',public.hyt_member_json(m));
 END IF;
 -- Role changes and moderation are rare. Order their locks before acquiring a caller
 -- or target row, so a concurrent dismissal cannot race with an administrative mutation.
 IF a IN ('honors.change','admin.action','admin.resolve') THEN PERFORM pg_advisory_xact_lock(hashtext('hyt-administration')); END IF;
 -- Serialize follow/block changes for the same pair before locking either caller.
 IF a IN ('follows.set','blocks.set','members.block','messages.open','messages.send') THEN
  SELECT s.member_id INTO target FROM public.hyt_sessions s JOIN public.hyt_members u ON u.id=s.member_id
   WHERE s.hash=th AND s.expires_at>now() AND u.deleted_at IS NULL;
  IF target IS NOT NULL THEN
   IF a IN ('follows.set','members.block','messages.open') THEN k=b->>'memberId';
   ELSIF a='messages.send' THEN SELECT CASE WHEN low_id=target THEN high_id::text ELSE low_id::text END INTO k FROM public.hyt_dm_threads WHERE id=(b->>'conversationId')::uuid AND target IN (low_id,high_id);
   ELSIF b->>'commentId' IS NOT NULL THEN SELECT author_id::text INTO k FROM public.hyt_comments WHERE id=(b->>'commentId')::uuid AND post_id=(b->>'postId')::uuid AND NOT anonymous;
   ELSE SELECT author_id::text INTO k FROM public.hyt_posts WHERE id=(b->>'postId')::uuid AND NOT anonymous; END IF;
   IF k IS NOT NULL THEN PERFORM pg_advisory_xact_lock(hashtextextended(least(target::text,k)||greatest(target::text,k),0)); END IF;
  END IF;
 END IF;
 SELECT u.* INTO m FROM public.hyt_sessions s JOIN public.hyt_members u ON u.id=s.member_id
 WHERE s.hash=th AND s.expires_at>now() AND u.deleted_at IS NULL FOR UPDATE OF u;
 IF NOT FOUND THEN RETURN '{"status":401,"error":"session_expired"}'::jsonb; END IF;
 -- Persistent limits are allocated only after a real account is authenticated.
 INSERT INTO public.hyt_community_rate(key,count,until_at) VALUES('member:'||m.id,1,now()+interval '1 minute')
 ON CONFLICT(key) DO UPDATE SET count=CASE WHEN hyt_community_rate.until_at<=now() THEN 1 ELSE hyt_community_rate.count+1 END,
 until_at=CASE WHEN hyt_community_rate.until_at<=now() THEN excluded.until_at ELSE hyt_community_rate.until_at END RETURNING count INTO n;
 IF n>180 THEN RETURN '{"status":429,"error":"too_many_requests"}'::jsonb; END IF;
 IF a LIKE 'collection.%' THEN RETURN public.hyt_collection_api(a,b,m); END IF;
 IF NOT m.awards_initialized AND (a IN ('me','honors.hall') OR (a='posts.list' AND b->>'entry'='true')) THEN
  FOREACH metric IN ARRAY ARRAY['registered','posts','threads','likes','saves'] LOOP PERFORM public.hyt_award_check(m.id,metric,true); END LOOP;
  UPDATE public.hyt_members SET awards_initialized=true WHERE id=m.id;
 END IF;
 -- Time awards are derived only from the authenticated member's original registration.
 IF a IN ('me','honors.hall') OR (a='posts.list' AND b->>'entry'='true') THEN
  INSERT INTO public.hyt_awards(member_id,code,earned_at)
   SELECT m.id,v.code,m.created_at+v.age FROM (VALUES ('month',interval '720 hours'),('year',interval '8760 hours')) v(code,age)
   WHERE m.created_at+v.age<=now() AND NOT EXISTS(SELECT 1 FROM public.hyt_awards x WHERE x.member_id=m.id AND x.code=v.code)
   ON CONFLICT DO NOTHING;
 END IF;
 IF a LIKE 'honors.%' THEN
  IF a='honors.hall' THEN
   target=coalesce((b->>'memberId')::uuid,m.id);
   IF EXISTS(SELECT 1 FROM public.hyt_blocks WHERE (member_id,blocked_id) IN ((target,m.id),(m.id,target))) THEN RETURN '{"status":404,"error":"not_found"}'; END IF;
   SELECT public.hyt_hall(u,m.id) INTO result FROM public.hyt_members u WHERE id=target AND deleted_at IS NULL;
   IF result IS NULL THEN RETURN '{"status":404,"error":"not_found"}'; END IF;
   RETURN jsonb_build_object('status',200,'hall',result) || CASE WHEN target=m.id THEN public.hyt_award_pending(m.id) ELSE '{}'::jsonb END;
  END IF;
  IF a='honors.ack' THEN
   UPDATE public.hyt_awards SET seen=true WHERE member_id=m.id AND NOT seen AND code IN (SELECT jsonb_array_elements_text(b->'codes'));
   RETURN '{"status":200}';
  END IF;
  IF a='honors.wear' THEN
   IF (b->>'honor' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.hyt_honors WHERE member_id=m.id AND kind=b->>'honor'))
    OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(b->'showcase') item WHERE NOT EXISTS(SELECT 1 FROM public.hyt_awards WHERE member_id=m.id AND code=item))
    OR jsonb_array_length(b->'showcase')>3 THEN RETURN '{"status":400,"error":"invalid_showcase"}'; END IF;
   UPDATE public.hyt_members SET worn_honor=b->>'honor',worn_collection=CASE WHEN b->>'honor' IS NOT NULL THEN NULL ELSE worn_collection END,showcase=ARRAY(SELECT jsonb_array_elements_text(b->'showcase')) WHERE id=m.id RETURNING * INTO m;
   RETURN jsonb_build_object('status',200,'hall',public.hyt_hall(m,m.id),'user',public.hyt_member_json(m));
  END IF;
  IF m.role<>'moderator' OR m.banned_until>now() THEN RETURN '{"status":403,"error":"forbidden"}'; END IF;
  IF a='honors.manage' THEN
   IF m.developer_since IS NULL AND NOT ('recommend'=ANY(m.mod_caps) OR 'users'=ANY(m.mod_caps)) THEN RETURN '{"status":403,"error":"forbidden"}'; END IF;
   SELECT coalesce(jsonb_agg(x),'[]') INTO result FROM (
    SELECT jsonb_build_object('id',u.id,'nickname',u.nickname,'official',(public.hyt_badges(u)->'official'),'caps',CASE WHEN u.role='moderator' THEN u.mod_caps ELSE '{}'::text[] END,
     'honors',ARRAY(SELECT kind FROM public.hyt_honors WHERE member_id=u.id),'bannedUntil',u.banned_until,
     'recommendation',r.reason) x
    FROM public.hyt_members u LEFT JOIN public.hyt_recommendations r ON r.member_id=u.id
    WHERE u.deleted_at IS NULL AND (CASE WHEN coalesce(b->>'query','')='' THEN (r.member_id IS NOT NULL OR u.role='moderator')
      ELSE u.id::text=b->>'query' OR u.nickname=b->>'query' END)
    ORDER BY (r.member_id IS NOT NULL) DESC,u.nickname,u.id LIMIT 30) options;
   RETURN jsonb_build_object('status',200,'members',result,'audit',CASE WHEN m.developer_since IS NOT NULL THEN
    (SELECT coalesce(jsonb_agg(x),'[]') FROM (SELECT jsonb_build_object('at',h.created_at,'actor',au.nickname,'target',tu.nickname,'change',h.change) x
      FROM public.hyt_honor_history h JOIN public.hyt_members au ON au.id=h.actor JOIN public.hyt_members tu ON tu.id=h.target ORDER BY h.created_at DESC LIMIT 30) history) ELSE '[]'::jsonb END);
  END IF;
  IF a='honors.change' THEN
   k=b->>'operation';
   IF m.developer_since IS NULL AND NOT ((k='recommend' AND 'recommend'=ANY(m.mod_caps)) OR (k IN ('mute','unmute') AND 'users'=ANY(m.mod_caps))) THEN RETURN '{"status":403,"error":"forbidden"}'; END IF;
   target=(b->>'memberId')::uuid;
   SELECT * INTO subject FROM public.hyt_members WHERE id=target AND deleted_at IS NULL FOR UPDATE;
   IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'; END IF;
   IF EXISTS(SELECT 1 FROM public.hyt_honor_history WHERE id=(b->>'requestId')::uuid) THEN
    IF EXISTS(SELECT 1 FROM public.hyt_honor_history WHERE id=(b->>'requestId')::uuid AND actor=m.id AND hyt_honor_history.target=subject.id AND change=(b-'requestId'-'memberId')) THEN RETURN '{"status":200}'; END IF;
    RETURN '{"status":409,"error":"request_conflict"}';
   END IF;
   IF k IN ('appoint','dismiss','mute','unmute') AND (subject.developer_since IS NOT NULL OR subject.id=m.id OR (subject.role='moderator' AND m.developer_since IS NULL)) THEN RETURN '{"status":403,"error":"forbidden"}'; END IF;
   CASE k
    WHEN 'appoint' THEN UPDATE public.hyt_members SET role='moderator',mod_caps=ARRAY(SELECT jsonb_array_elements_text(b->'caps')),moderator_since=coalesce(moderator_since,now()) WHERE id=target;
    WHEN 'dismiss' THEN UPDATE public.hyt_members SET role='member',moderator_since=NULL,mod_caps='{}' WHERE id=target;
    WHEN 'mute' THEN UPDATE public.hyt_members SET banned_until=now()+interval '7 days' WHERE id=target;
    WHEN 'unmute' THEN UPDATE public.hyt_members SET banned_until=NULL WHERE id=target;
    WHEN 'recommend' THEN INSERT INTO public.hyt_recommendations(member_id,actor,reason) VALUES(target,m.id,b->>'reason') ON CONFLICT(member_id) DO UPDATE SET actor=excluded.actor,reason=excluded.reason,created_at=now();
    WHEN 'decline' THEN DELETE FROM public.hyt_recommendations WHERE member_id=target;
    WHEN 'grant' THEN
     IF b->>'kind'='creator' AND NOT EXISTS(SELECT 1 FROM public.hyt_recommendations WHERE member_id=target) THEN RETURN '{"status":409,"error":"recommendation_required"}'; END IF;
     INSERT INTO public.hyt_honors(member_id,kind) VALUES(target,b->>'kind') ON CONFLICT DO NOTHING;
     UPDATE public.hyt_members SET worn_honor=b->>'kind' WHERE id=target AND worn_honor IS NULL AND worn_collection IS NULL;
     IF b->>'kind'='creator' THEN DELETE FROM public.hyt_recommendations WHERE member_id=target; END IF;
    WHEN 'revoke' THEN
     IF b->>'kind'='seed' THEN RETURN '{"status":409,"error":"permanent_honor"}'; END IF;
     DELETE FROM public.hyt_honors WHERE member_id=target AND kind=b->>'kind';
     UPDATE public.hyt_members SET worn_honor=NULL WHERE id=target AND worn_honor=b->>'kind';
    ELSE RETURN '{"status":400,"error":"invalid_request"}';
   END CASE;
   INSERT INTO public.hyt_honor_history(id,actor,target,change) VALUES((b->>'requestId')::uuid,m.id,target,b-'requestId'-'memberId');
   SELECT jsonb_build_object('id',u.id,'badges',public.hyt_badges(u),'showcase',u.showcase) INTO result FROM public.hyt_members u WHERE id=target;
   RETURN jsonb_build_object('status',200,'updatedIdentity',result);
  END IF;
 END IF;
 -- Applies equally to legacy report-resolution and the newer direct moderation routes.
 IF a LIKE 'admin.%' AND (m.role<>'moderator' OR m.banned_until>now() OR (m.developer_since IS NULL AND (
  (a IN ('admin.reports','admin.resolve') AND NOT 'reports'=ANY(m.mod_caps)) OR
  (a IN ('admin.content','admin.context') AND NOT ('content'=ANY(m.mod_caps) OR 'reports'=ANY(m.mod_caps))) OR
  (a='admin.history' AND NOT ('content'=ANY(m.mod_caps) OR 'reports'=ANY(m.mod_caps))) OR
  (a='admin.action' AND (CASE WHEN b->>'reportId' IS NULL THEN NOT 'content'=ANY(m.mod_caps) ELSE NOT 'reports'=ANY(m.mod_caps) END)) OR
  (a IN ('admin.action','admin.resolve') AND b->>'decision'='ban' AND NOT 'users'=ANY(m.mod_caps)) OR
  (a IN ('admin.action','admin.resolve') AND b->>'decision' IN ('lock','unlock','remove') AND NOT 'content'=ANY(m.mod_caps))
 ))) THEN RETURN '{"status":403,"error":"forbidden"}'; END IF;

 IF a='media.reserve' THEN
  IF m.banned_until>now() THEN RETURN '{"status":403,"error":"account_muted"}'::jsonb; END IF;
  SELECT * INTO img FROM public.hyt_media WHERE member_id=m.id AND request_id=(b->>'requestId')::uuid;
  IF FOUND THEN
   IF img.deleted_at IS NOT NULL OR img.digest<>b->>'digest' OR img.purpose<>coalesce(b->>'purpose','post') THEN RETURN '{"status":409,"error":"request_conflict"}'::jsonb; END IF;
  ELSE
   IF (SELECT count(*) FROM public.hyt_media WHERE member_id=m.id AND created_at>now()-interval '1 day')>=90 THEN RETURN '{"status":429,"error":"upload_limit"}'::jsonb; END IF;
   target=gen_random_uuid();
   INSERT INTO public.hyt_media(id,member_id,request_id,digest,object_key,purpose) VALUES(target,m.id,(b->>'requestId')::uuid,b->>'digest',target::text||'.jpg',coalesce(b->>'purpose','post')) RETURNING * INTO img;
  END IF;
  RETURN jsonb_build_object('status',200,'image',public.hyt_media_json(img),'ready',img.ready);
 END IF;
 IF a='media.commit' THEN
  UPDATE public.hyt_media SET ready=true,width=(b->>'width')::int,height=(b->>'height')::int,bytes=(b->>'bytes')::int
   WHERE id=(b->>'imageId')::uuid AND member_id=m.id AND deleted_at IS NULL AND post_id IS NULL RETURNING * INTO img;
  IF NOT FOUND THEN RETURN '{"status":409,"error":"request_conflict"}'::jsonb; END IF;
  RETURN jsonb_build_object('status',200,'image',public.hyt_media_json(img));
 END IF;
 IF a='media.discard' THEN
  UPDATE public.hyt_media SET deleted_at=now() WHERE id=(b->>'imageId')::uuid AND member_id=m.id AND post_id IS NULL AND id IS DISTINCT FROM m.avatar_id;
  RETURN '{"status":200}'::jsonb;
 END IF;
 IF a='session' THEN RETURN jsonb_build_object('status',200,'user',public.hyt_member_json(m),'passwordHash',m.password_hash); END IF;
 IF a='blocks.clear' THEN DELETE FROM public.hyt_blocks WHERE member_id=m.id; DELETE FROM public.hyt_hidden_threads WHERE member_id=m.id; RETURN '{"status":200}'::jsonb; END IF;
 IF a='me' THEN RETURN jsonb_build_object('status',200,'user',public.hyt_member_json(m)); END IF;
 IF a='logout' THEN DELETE FROM public.hyt_sessions WHERE hash=th; RETURN '{"status":200}'::jsonb; END IF;
 IF a='avatar.set' THEN
  IF m.banned_until>now() THEN RETURN '{"status":403,"error":"account_muted"}'::jsonb; END IF;
  target=(b->>'imageId')::uuid;
  IF target IS NOT NULL THEN
   SELECT * INTO img FROM public.hyt_media WHERE id=target AND member_id=m.id AND purpose='avatar' AND ready AND deleted_at IS NULL AND post_id IS NULL FOR UPDATE;
   IF NOT FOUND THEN RETURN '{"status":400,"error":"image_unavailable"}'::jsonb; END IF;
  END IF;
  UPDATE public.hyt_media SET deleted_at=now() WHERE id=m.avatar_id AND id IS DISTINCT FROM target;
  UPDATE public.hyt_members SET avatar_id=target WHERE id=m.id RETURNING * INTO m;
  RETURN jsonb_build_object('status',200,'user',public.hyt_member_json(m));
 END IF;
 IF a='profile.update'  THEN UPDATE public.hyt_members SET nickname=b->>'nickname',bio=coalesce(b->>'bio',bio) WHERE id=m.id RETURNING * INTO m; RETURN jsonb_build_object('status',200,'user',public.hyt_member_json(m)); END IF;
 IF a='profile.get' THEN
  SELECT public.hyt_profile_json(u,m.id) INTO result FROM public.hyt_members u WHERE u.id=(b->>'memberId')::uuid AND u.deleted_at IS NULL
  AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=u.id);
  IF result IS NULL THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
  RETURN jsonb_build_object('status',200,'profile',result);
 END IF;
 IF a='follows.set' THEN
  target=(b->>'memberId')::uuid;
  IF target=m.id THEN RETURN '{"status":400,"error":"invalid_request"}'::jsonb; END IF;
  IF (b->>'enabled')::boolean THEN
   PERFORM id FROM public.hyt_members WHERE id=target AND deleted_at IS NULL FOR KEY SHARE;
   IF NOT FOUND OR EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE (bl.member_id=m.id AND bl.blocked_id=target) OR (bl.member_id=target AND bl.blocked_id=m.id)) THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.hyt_follows WHERE member_id=m.id AND followed_id=target) AND (SELECT count(*) FROM public.hyt_follows WHERE member_id=m.id)>=1000 THEN RETURN '{"status":400,"error":"following_limit"}'::jsonb; END IF;
   INSERT INTO public.hyt_follows(member_id,followed_id) VALUES(m.id,target) ON CONFLICT DO NOTHING;
  ELSE DELETE FROM public.hyt_follows WHERE member_id=m.id AND followed_id=target; END IF;
  SELECT public.hyt_profile_json(u,m.id) INTO result FROM public.hyt_members u WHERE id=target AND deleted_at IS NULL
   AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE (bl.member_id=m.id AND bl.blocked_id=u.id) OR (bl.member_id=u.id AND bl.blocked_id=m.id));
  RETURN jsonb_build_object('status',200,'profile',result);
 END IF;
 IF a='follows.list' THEN
  SELECT coalesce(jsonb_agg(q.person ORDER BY q.created_at DESC,q.followed_id DESC),'[]'::jsonb) INTO result FROM (
   SELECT f.created_at,f.followed_id,jsonb_build_object('id',u.id,'nickname',u.nickname,'bio',u.bio,'avatar',public.hyt_avatar_json(u.id),'followedAt',f.created_at) AS person
   FROM public.hyt_follows f JOIN public.hyt_members u ON u.id=f.followed_id AND u.deleted_at IS NULL
   WHERE f.member_id=m.id AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE (bl.member_id=m.id AND bl.blocked_id=u.id) OR (bl.member_id=u.id AND bl.blocked_id=m.id))
   AND (b->>'beforeTime' IS NULL OR (f.created_at,f.followed_id)<((b->>'beforeTime')::timestamptz,(b->>'beforeId')::uuid))
   ORDER BY f.created_at DESC,f.followed_id DESC LIMIT 21) q;
  RETURN jsonb_build_object('status',200,'following',result);
 END IF;
 IF a='follows.stats' THEN
  RETURN jsonb_build_object('status',200,'social',jsonb_build_object(
   'followingCount',(SELECT count(*) FROM public.hyt_follows f JOIN public.hyt_members u ON u.id=f.followed_id AND u.deleted_at IS NULL WHERE f.member_id=m.id AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE (bl.member_id=m.id AND bl.blocked_id=u.id) OR (bl.member_id=u.id AND bl.blocked_id=m.id))),
   'followerCount',(SELECT count(*) FROM public.hyt_follows f JOIN public.hyt_members u ON u.id=f.member_id AND u.deleted_at IS NULL WHERE f.followed_id=m.id AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE (bl.member_id=m.id AND bl.blocked_id=u.id) OR (bl.member_id=u.id AND bl.blocked_id=m.id)))));
 END IF;
 IF a='followers.list' THEN
  SELECT coalesce(jsonb_agg(q.person ORDER BY q.created_at DESC,q.member_id DESC),'[]'::jsonb) INTO result FROM (
   SELECT f.created_at,f.member_id,jsonb_build_object('id',u.id,'nickname',u.nickname,'bio',u.bio,'avatar',public.hyt_avatar_json(u.id),'followedAt',f.created_at,
   'following',EXISTS(SELECT 1 FROM public.hyt_follows me WHERE me.member_id=m.id AND me.followed_id=u.id)) AS person
   FROM public.hyt_follows f JOIN public.hyt_members u ON u.id=f.member_id AND u.deleted_at IS NULL
   WHERE f.followed_id=m.id AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE (bl.member_id=m.id AND bl.blocked_id=u.id) OR (bl.member_id=u.id AND bl.blocked_id=m.id))
   AND (b->>'beforeTime' IS NULL OR (f.created_at,f.member_id)<((b->>'beforeTime')::timestamptz,(b->>'beforeId')::uuid))
   ORDER BY f.created_at DESC,f.member_id DESC LIMIT 21) q;
  RETURN jsonb_build_object('status',200,'followers',result);
 END IF;
 IF a='members.block' THEN
  target=(b->>'memberId')::uuid;
  IF target=m.id THEN RETURN '{"status":400,"error":"invalid_request"}'::jsonb; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.hyt_members WHERE id=target AND deleted_at IS NULL) THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
  INSERT INTO public.hyt_blocks VALUES(m.id,target) ON CONFLICT DO NOTHING;
  DELETE FROM public.hyt_follows WHERE (member_id=m.id AND followed_id=target) OR (member_id=target AND followed_id=m.id);
  UPDATE public.hyt_buddies SET revision=revision+1 WHERE post_id IN (SELECT j.post_id FROM public.hyt_buddy_members j JOIN public.hyt_posts bp ON bp.id=j.post_id WHERE NOT bp.anonymous AND ((j.member_id=m.id AND bp.author_id=target) OR (j.member_id=target AND bp.author_id=m.id)));
  DELETE FROM public.hyt_buddy_members j USING public.hyt_posts bp WHERE bp.id=j.post_id AND NOT bp.anonymous AND ((j.member_id=m.id AND bp.author_id=target) OR (j.member_id=target AND bp.author_id=m.id));
  RETURN '{"status":200}'::jsonb;
 END IF;
 IF a='messages.open' THEN
  target=(b->>'memberId')::uuid;
  IF target=m.id THEN RETURN '{"status":400,"error":"invalid_request"}'::jsonb; END IF;
  PERFORM id FROM public.hyt_members WHERE id=target AND deleted_at IS NULL FOR KEY SHARE;
  IF NOT FOUND OR EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE (bl.member_id=m.id AND bl.blocked_id=target) OR (bl.member_id=target AND bl.blocked_id=m.id)) THEN RETURN '{"status":404,"error":"conversation_unavailable"}'::jsonb; END IF;
  INSERT INTO public.hyt_dm_threads(low_id,high_id) VALUES(least(m.id,target),greatest(m.id,target)) ON CONFLICT DO NOTHING;
  SELECT * INTO dm FROM public.hyt_dm_threads WHERE low_id=least(m.id,target) AND high_id=greatest(m.id,target);
  RETURN jsonb_build_object('status',200,'conversation',public.hyt_dm_json(dm,m.id));
 END IF;
 IF a IN ('messages.inbox','messages.unread') THEN
  SELECT count(*) INTO n FROM public.hyt_dm_messages d JOIN public.hyt_dm_visible(m.id) t ON t.id=d.thread_id
  WHERE d.sender_id<>m.id AND d.seq>coalesce((SELECT last_seq FROM public.hyt_dm_reads WHERE thread_id=t.id AND member_id=m.id),0);
  IF a='messages.unread' THEN RETURN jsonb_build_object('status',200,'messageUnreadCount',n); END IF;
  SELECT coalesce(jsonb_agg(public.hyt_dm_json(q,m.id) ORDER BY q.last_seq DESC,q.id DESC),'[]'::jsonb) INTO result
   FROM (SELECT * FROM public.hyt_dm_visible(m.id) t WHERE t.last_seq>0 AND (b->>'beforeSeq' IS NULL OR (t.last_seq,t.id)<((b->>'beforeSeq')::bigint,(b->>'beforeId')::uuid)) ORDER BY t.last_seq DESC,t.id DESC LIMIT 21) q;
  RETURN jsonb_build_object('status',200,'conversations',result,'messageUnreadCount',n);
 END IF;
 IF a IN ('messages.list','messages.send','messages.read') THEN
  SELECT * INTO dm FROM public.hyt_dm_visible(m.id) WHERE id=(b->>'conversationId')::uuid;
  IF NOT FOUND THEN RETURN '{"status":404,"error":"conversation_unavailable"}'::jsonb; END IF;
  IF a='messages.read' THEN
   -- Acknowledgement is bounded to messages already delivered on this thread; newer messages remain unread.
   IF NOT EXISTS(SELECT 1 FROM public.hyt_dm_messages WHERE thread_id=dm.id AND seq=(b->>'throughSeq')::bigint) THEN RETURN '{"status":400,"error":"invalid_request"}'::jsonb; END IF;
   INSERT INTO public.hyt_dm_reads VALUES(dm.id,m.id,(b->>'throughSeq')::bigint) ON CONFLICT(thread_id,member_id) DO UPDATE SET last_seq=greatest(hyt_dm_reads.last_seq,excluded.last_seq);
   IF coalesce((b->>'withUnread')::boolean,false) THEN
   SELECT count(*) INTO n FROM public.hyt_dm_messages d JOIN public.hyt_dm_visible(m.id) t ON t.id=d.thread_id
    WHERE d.sender_id<>m.id AND d.seq>coalesce((SELECT last_seq FROM public.hyt_dm_reads WHERE thread_id=t.id AND member_id=m.id),0);
   RETURN jsonb_build_object('status',200,'messageUnreadCount',n);
   END IF;
   RETURN '{"status":200}'::jsonb;
  END IF;
  IF a='messages.list' THEN
   SELECT coalesce(jsonb_agg(public.hyt_dm_message_json(q,m.id) ORDER BY CASE WHEN b->>'afterSeq' IS NOT NULL THEN q.seq END ASC, q.seq DESC),'[]'::jsonb) INTO result FROM (
    SELECT * FROM public.hyt_dm_messages WHERE thread_id=dm.id AND (b->>'beforeSeq' IS NULL OR seq<(b->>'beforeSeq')::bigint) AND (b->>'afterSeq' IS NULL OR seq>(b->>'afterSeq')::bigint) ORDER BY CASE WHEN b->>'afterSeq' IS NOT NULL THEN seq END ASC,seq DESC LIMIT 31) q;
   RETURN jsonb_build_object('status',200,'conversation',public.hyt_dm_json(dm,m.id),'messages',result);
  END IF;
  IF m.banned_until>now() THEN RETURN '{"status":403,"error":"account_muted"}'::jsonb; END IF;
  target=CASE WHEN dm.low_id=m.id THEN dm.high_id ELSE dm.low_id END;
  PERFORM id FROM public.hyt_members WHERE id=target AND deleted_at IS NULL FOR KEY SHARE;
  IF NOT FOUND THEN RETURN '{"status":404,"error":"conversation_unavailable"}'::jsonb; END IF;
  SELECT * INTO msg FROM public.hyt_dm_messages WHERE sender_id=m.id AND request_id=(b->>'requestId')::uuid;
  IF FOUND THEN
   IF msg.thread_id<>dm.id OR msg.body<>b->>'body' THEN RETURN '{"status":409,"error":"request_conflict"}'::jsonb; END IF;
  ELSE
   IF (SELECT count(*) FROM public.hyt_dm_messages WHERE sender_id=m.id AND created_at>now()-interval '1 minute')>=20 OR (SELECT count(*) FROM public.hyt_dm_messages WHERE sender_id=m.id AND created_at>now()-interval '1 day')>=500 THEN RETURN '{"status":429,"error":"posting_too_fast"}'::jsonb; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.hyt_dm_messages WHERE thread_id=dm.id) AND (SELECT count(DISTINCT d.thread_id) FROM public.hyt_dm_messages d WHERE d.sender_id=m.id AND d.created_at>now()-interval '1 day')>=30 THEN RETURN '{"status":429,"error":"posting_too_fast"}'::jsonb; END IF;
   INSERT INTO public.hyt_dm_messages(thread_id,sender_id,body,request_id) VALUES(dm.id,m.id,b->>'body',(b->>'requestId')::uuid) RETURNING * INTO msg;
   UPDATE public.hyt_dm_threads SET last_seq=msg.seq,updated_at=msg.created_at WHERE id=dm.id RETURNING * INTO dm;
  END IF;
  RETURN jsonb_build_object('status',200,'message',public.hyt_dm_message_json(msg,m.id),'conversation',public.hyt_dm_json(dm,m.id));
 END IF;
 IF a='notifications.read' THEN
  UPDATE public.hyt_notifications SET read_at=coalesce(read_at,now()) WHERE recipient_id=m.id AND id IN (SELECT value::uuid FROM jsonb_array_elements_text(b->'ids'));
  RETURN jsonb_build_object('status',200,'unreadCount',(SELECT count(*) FROM public.hyt_visible_notifications(m.id) WHERE read_at IS NULL));
 END IF;
 IF a IN ('notifications.list','notifications.unread') THEN
  SELECT count(*) INTO n FROM public.hyt_visible_notifications(m.id) WHERE read_at IS NULL;
  IF b->>'withMessages'='true' THEN
   -- Reuse the authenticated caller instead of recursively repeating auth and rate writes.
   SELECT count(*)::text INTO k FROM public.hyt_dm_messages d JOIN public.hyt_dm_visible(m.id) t ON t.id=d.thread_id
    WHERE d.sender_id<>m.id AND d.seq>coalesce((SELECT last_seq FROM public.hyt_dm_reads WHERE thread_id=t.id AND member_id=m.id),0);
  END IF;
  IF a='notifications.unread' THEN RETURN public.hyt_award_pending(m.id)||jsonb_strip_nulls(jsonb_build_object('status',200,'unreadCount',n,'messageUnreadCount',k::int)); END IF;
  SELECT coalesce(jsonb_agg(public.hyt_notification_json(q,m.id) ORDER BY q.created_at DESC,q.id DESC),'[]'::jsonb) INTO result
  FROM (SELECT * FROM public.hyt_visible_notifications(m.id) WHERE
   (coalesce(b->>'filter','all')='all' OR (b->>'filter'='likes' AND kind IN ('post_like','comment_like','post_response')) OR (b->>'filter'='replies' AND kind IN ('reply','post_reply','thread_reply','buddy')))
   AND (b->>'beforeTime' IS NULL OR (created_at,id)<((b->>'beforeTime')::timestamptz,(b->>'beforeId')::uuid))
   ORDER BY created_at DESC,id DESC LIMIT 31) q;
  RETURN jsonb_build_object('status',200,'notifications',result,'unreadCount',n) || CASE WHEN k IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('messageUnreadCount',k::int) END;
 END IF;
 IF a='account.delete' AND m.developer_since IS NOT NULL THEN RETURN '{"status":409,"error":"owner_transfer_required"}'; END IF;
 IF a IN ('password.change','account.delete') THEN
  IF m.password_hash<>b->>'proof' THEN RETURN '{"status":401,"error":"invalid_credentials"}'::jsonb; END IF;
  IF a='password.change' THEN
   UPDATE public.hyt_members SET password_hash=b->>'passwordHash',recovery_hash=b->>'recoveryHash' WHERE id=m.id;
   DELETE FROM public.hyt_sessions WHERE member_id=m.id AND hash<>th;
  ELSE
   UPDATE public.hyt_members SET deleted_at=now(),username='deleted_'||id::text,nickname='已注销',password_hash='',recovery_hash='',avatar_id=NULL,
    worn_collection=NULL,collection_title=NULL,collection_use_title=false WHERE id=m.id;
   UPDATE public.hyt_posts SET body='已删除',title='',deleted_at=now() WHERE author_id=m.id;
   UPDATE public.hyt_media SET deleted_at=now() WHERE member_id=m.id;
   DELETE FROM public.hyt_comment_likes WHERE member_id=m.id;
   UPDATE public.hyt_comments SET body='已删除',deleted_at=now() WHERE author_id=m.id;
   DELETE FROM public.hyt_sessions WHERE member_id=m.id;
   DELETE FROM public.hyt_reactions WHERE member_id=m.id;
   DELETE FROM public.hyt_responses WHERE member_id=m.id;
   UPDATE public.hyt_polls SET revision=revision+1 WHERE post_id IN (SELECT post_id FROM public.hyt_poll_votes WHERE member_id=m.id);
   UPDATE public.hyt_buddies SET revision=revision+1 WHERE post_id IN (SELECT post_id FROM public.hyt_buddy_members WHERE member_id=m.id);
   DELETE FROM public.hyt_buddy_members WHERE member_id=m.id OR post_id IN (SELECT id FROM public.hyt_posts WHERE author_id=m.id);
   DELETE FROM public.hyt_poll_votes WHERE member_id=m.id OR post_id IN (SELECT id FROM public.hyt_posts WHERE author_id=m.id);
   DELETE FROM public.hyt_dm_reads WHERE thread_id IN (SELECT id FROM public.hyt_dm_threads WHERE m.id IN (low_id,high_id));
   DELETE FROM public.hyt_dm_messages WHERE thread_id IN (SELECT id FROM public.hyt_dm_threads WHERE m.id IN (low_id,high_id));
   DELETE FROM public.hyt_dm_threads WHERE m.id IN (low_id,high_id);
   DELETE FROM public.hyt_follows WHERE member_id=m.id OR followed_id=m.id;
   DELETE FROM public.hyt_blocks WHERE member_id=m.id OR blocked_id=m.id;
   DELETE FROM public.hyt_hidden_threads WHERE member_id=m.id;
   DELETE FROM public.hyt_notifications WHERE recipient_id=m.id OR actor_id=m.id;
   DELETE FROM public.hyt_thread_watches WHERE member_id=m.id;
   DELETE FROM public.hyt_thread_visits WHERE member_id=m.id;
  END IF;
  RETURN '{"status":200}'::jsonb;
 END IF;
 IF a='posts.list' THEN
  snapshot=coalesce((b->>'snapshotTime')::timestamptz,now());
  SELECT coalesce(jsonb_agg(public.hyt_post_json(jsonb_populate_record(NULL::public.hyt_posts,to_jsonb(q)),m.id)||jsonb_build_object('rank',q.rank::text) ORDER BY q.rank DESC,q.created_at DESC,q.id DESC),'[]'::jsonb) INTO result FROM
   (SELECT ranked.* FROM (SELECT p.*,
    CASE WHEN b->>'scope' IN ('participated','watching') THEN round(extract(epoch FROM greatest(p.created_at,(SELECT max(c.created_at) FROM public.hyt_comments c WHERE c.post_id=p.id AND c.deleted_at IS NULL AND c.created_at<=snapshot AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=c.author_id AND NOT c.anonymous)))),6)
    WHEN b->>'sort'='hot' THEN round(((SELECT count(*)*2 FROM public.hyt_reactions r WHERE r.post_id=p.id AND r.kind='like' AND r.created_at<=snapshot)+(SELECT count(*)*3 FROM public.hyt_comments c WHERE c.post_id=p.id AND c.deleted_at IS NULL AND c.created_at<=snapshot)) / power(greatest(extract(epoch FROM snapshot-p.created_at)/3600,0)+2,1.2),8) ELSE 0 END AS rank
    FROM public.hyt_posts p WHERE p.deleted_at IS NULL AND p.created_at<=snapshot
    AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=p.author_id AND NOT p.anonymous)
    AND NOT EXISTS(SELECT 1 FROM public.hyt_hidden_threads h WHERE h.member_id=m.id AND h.post_id=p.id)
    AND (coalesce(b->>'category','all')='all' OR p.category=b->>'category')
    AND (coalesce(b->>'section','all')='all' OR CASE WHEN p.category IN ('help','study') THEN 'daily' ELSE p.category END=b->>'section')
    AND (coalesce(b->>'interest','')='' OR p.interest=b->>'interest')
    AND (coalesce(b->>'scope','all')<>'mine' OR p.author_id=m.id)
    AND (coalesce(b->>'scope','all')<>'saved' OR EXISTS(SELECT 1 FROM public.hyt_reactions r WHERE r.post_id=p.id AND r.member_id=m.id AND r.kind='save'))
    AND (coalesce(b->>'scope','all')<>'joined' OR EXISTS(SELECT 1 FROM public.hyt_buddy_members j WHERE j.post_id=p.id AND j.member_id=m.id))
    AND (coalesce(b->>'scope','all')<>'participated' OR EXISTS(SELECT 1 FROM public.hyt_buddy_members j WHERE j.post_id=p.id AND j.member_id=m.id) OR p.author_id=m.id OR EXISTS(SELECT 1 FROM public.hyt_comments c WHERE c.post_id=p.id AND c.author_id=m.id AND c.deleted_at IS NULL))
    AND (coalesce(b->>'scope','all')<>'watching' OR EXISTS(SELECT 1 FROM public.hyt_thread_watches w WHERE w.post_id=p.id AND w.member_id=m.id AND w.enabled))
    AND (coalesce(b->>'scope','all')<>'following' OR (NOT p.anonymous AND EXISTS(SELECT 1 FROM public.hyt_follows f JOIN public.hyt_members u ON u.id=f.followed_id AND u.deleted_at IS NULL WHERE f.member_id=m.id AND f.followed_id=p.author_id) AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=p.author_id AND bl.blocked_id=m.id)))
    AND (coalesce(b->>'scope','all')<>'author' OR (p.author_id=(b->>'memberId')::uuid AND NOT p.anonymous))
    AND (coalesce(b->>'query','')='' OR strpos(lower(p.title||' '||p.body||' '||coalesce((SELECT definition->>'question' FROM public.hyt_polls WHERE post_id=p.id),'')||' '||coalesce((SELECT definition->>'location' FROM public.hyt_buddies WHERE post_id=p.id),'')),lower(b->>'query'))>0)) ranked
    WHERE b->>'beforeTime' IS NULL OR (ranked.rank,ranked.created_at,ranked.id)<(coalesce((b->>'beforeRank')::numeric,0),(b->>'beforeTime')::timestamptz,(b->>'beforeId')::uuid)
    ORDER BY ranked.rank DESC,ranked.created_at DESC,ranked.id DESC LIMIT 21) q;
  RETURN jsonb_build_object('status',200,'posts',result,'snapshotTime',snapshot) || CASE WHEN b->>'entry'='true' THEN public.hyt_award_pending(m.id)||jsonb_build_object('user',public.hyt_member_json(m)) ELSE '{}'::jsonb END;
 END IF;

 IF a IN ('admin.context','admin.content','admin.history','admin.action') THEN
  IF m.role<>'moderator' THEN RETURN '{"status":403,"error":"forbidden"}'::jsonb; END IF;
  IF a='admin.history' THEN
   SELECT coalesce(jsonb_agg(x ORDER BY x->>'createdAt' DESC,x->>'id' DESC),'[]'::jsonb) INTO result FROM
    (SELECT jsonb_build_object('id',h.id,'action',h.action,'reason',h.reason,'createdAt',h.created_at,'operator',u.nickname,'postId',coalesce(h.post_id,r.post_id),'commentId',coalesce(h.comment_id,r.comment_id)) x
     FROM public.hyt_moderation h LEFT JOIN public.hyt_members u ON u.id=h.moderator_id LEFT JOIN public.hyt_reports r ON r.id=h.report_id
     WHERE b->>'beforeTime' IS NULL OR (h.created_at,h.id)<((b->>'beforeTime')::timestamptz,(b->>'beforeId')::uuid)
     ORDER BY h.created_at DESC,h.id DESC LIMIT 30) q;
   RETURN jsonb_build_object('status',200,'history',result);
  END IF;
  IF a='admin.content' THEN
   SELECT coalesce(jsonb_agg(x ORDER BY x->>'createdAt' DESC,x->>'id' DESC),'[]'::jsonb) INTO result FROM
    (SELECT public.hyt_post_json(v,m.id) x FROM public.hyt_posts v WHERE v.deleted_at IS NULL
     AND (coalesce(b->>'query','')='' OR position(lower(b->>'query') in lower(v.title||' '||v.body))>0)
     AND (b->>'beforeTime' IS NULL OR (v.created_at,v.id)<((b->>'beforeTime')::timestamptz,(b->>'beforeId')::uuid))
     ORDER BY v.created_at DESC,v.id DESC LIMIT 20) q;
   RETURN jsonb_build_object('status',200,'posts',result);
  END IF;
  IF a='admin.action' THEN
   -- Repeated network retries cannot create duplicate actions or extend punishments.
   SELECT jsonb_build_object('actor',moderator_id,'postId',post_id,'commentId',comment_id,'action',action,'reason',reason,'reportId',report_id) INTO result FROM public.hyt_moderation WHERE id=(b->>'requestId')::uuid;
   IF FOUND THEN
    IF result=jsonb_build_object('actor',m.id,'postId',(b->>'postId')::uuid,'commentId',(b->>'commentId')::uuid,'action',b->>'decision','reason',b->>'reason','reportId',(b->>'reportId')::uuid) THEN RETURN '{"status":200}'::jsonb; END IF;
    RETURN '{"status":409,"error":"request_conflict"}'::jsonb;
   END IF;
   IF b->>'reportId' IS NOT NULL THEN
    SELECT * INTO report FROM public.hyt_reports WHERE id=(b->>'reportId')::uuid FOR UPDATE;
    IF NOT FOUND OR report.post_id<>(b->>'postId')::uuid OR report.comment_id IS DISTINCT FROM (b->>'commentId')::uuid THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
    IF report.status<>'open' THEN RETURN '{"status":409,"error":"report_resolved"}'::jsonb; END IF;
   ELSIF b->>'decision' IN ('ban','dismiss') THEN RETURN '{"status":400,"error":"invalid_request"}'::jsonb;
   END IF;
  END IF;
  SELECT * INTO p FROM public.hyt_posts WHERE id=(b->>'postId')::uuid FOR UPDATE;
  IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
  target=p.author_id;
  IF b->>'commentId' IS NOT NULL THEN
   SELECT * INTO c FROM public.hyt_comments WHERE id=(b->>'commentId')::uuid AND post_id=p.id FOR UPDATE;
   IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
   target=c.author_id;
  END IF;
  IF a='admin.context' THEN
   RETURN jsonb_build_object('status',200,'post',CASE WHEN p.deleted_at IS NULL THEN public.hyt_post_json(p,m.id) ELSE NULL END,'removed',p.deleted_at IS NOT NULL,'context',(SELECT public.hyt_comment_json(v,m.id) FROM public.hyt_comments v WHERE v.id=c.reply_to AND v.post_id=p.id),'comment',CASE WHEN c.id IS NOT NULL THEN public.hyt_comment_json(c,m.id) ELSE NULL END,
    'comments',(SELECT coalesce(jsonb_agg(public.hyt_comment_json(v,m.id) ORDER BY v.created_at),'[]'::jsonb) FROM (SELECT * FROM public.hyt_comments WHERE post_id=p.id ORDER BY created_at LIMIT 20) v));
  END IF;
  IF b->>'decision'<>'dismiss' AND (p.deleted_at IS NOT NULL OR (c.id IS NOT NULL AND c.deleted_at IS NOT NULL)) THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
  IF b->>'decision'='remove' THEN
   IF c.id IS NULL THEN UPDATE public.hyt_posts SET deleted_at=now() WHERE id=p.id;UPDATE public.hyt_media SET deleted_at=now() WHERE post_id=p.id;
   ELSE UPDATE public.hyt_comments SET deleted_at=now() WHERE id=c.id;UPDATE public.hyt_media SET deleted_at=now() WHERE comment_id=c.id; END IF;
  ELSIF b->>'decision' IN ('lock','unlock') THEN UPDATE public.hyt_posts SET locked=(b->>'decision'='lock') WHERE id=p.id;
  ELSIF b->>'decision'='ban' THEN
   IF EXISTS(SELECT 1 FROM public.hyt_members WHERE id=target AND role='moderator') THEN RETURN '{"status":403,"error":"forbidden"}'::jsonb; END IF;
   UPDATE public.hyt_members SET banned_until=now()+interval '7 days' WHERE id=target;
  ELSIF b->>'decision'<>'dismiss' THEN RETURN '{"status":400,"error":"invalid_request"}'::jsonb;
  END IF;
  IF b->>'reportId' IS NOT NULL THEN UPDATE public.hyt_reports SET status='resolved',resolution=b->>'reason',resolved_at=now() WHERE id=report.id; END IF;
  INSERT INTO public.hyt_moderation(id,moderator_id,report_id,post_id,comment_id,action,reason) VALUES((b->>'requestId')::uuid,m.id,(b->>'reportId')::uuid,p.id,c.id,b->>'decision',b->>'reason');
  RETURN '{"status":200}'::jsonb;
 END IF;
 IF a='admin.reports' THEN
  IF m.role<>'moderator' THEN RETURN '{"status":403,"error":"forbidden"}'::jsonb; END IF;
  SELECT coalesce(jsonb_agg(x ORDER BY x->>'createdAt'),'[]'::jsonb) INTO result FROM
   (SELECT jsonb_build_object('id',r.id,'postId',r.post_id,'commentId',r.comment_id,'reason',r.reason,'createdAt',r.created_at,
    'body',coalesce(c.body,p.body),'status',r.status) x FROM public.hyt_reports r JOIN public.hyt_posts p ON p.id=r.post_id
    LEFT JOIN public.hyt_comments c ON c.id=r.comment_id WHERE r.status='open' ORDER BY r.created_at LIMIT 50) q;
  RETURN jsonb_build_object('status',200,'reports',result);
 END IF;
 IF a='admin.resolve' THEN
  IF m.role<>'moderator' THEN RETURN '{"status":403,"error":"forbidden"}'::jsonb; END IF;
  SELECT * INTO report FROM public.hyt_reports WHERE id=(b->>'reportId')::uuid FOR UPDATE;
  IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
  IF report.status<>'open' THEN RETURN '{"status":200}'::jsonb; END IF;
  SELECT * INTO p FROM public.hyt_posts WHERE id=report.post_id FOR UPDATE;
  target=p.author_id;
  IF report.comment_id IS NOT NULL THEN SELECT author_id INTO target FROM public.hyt_comments WHERE id=report.comment_id; END IF;
  IF b->>'decision'='remove' THEN
   IF report.comment_id IS NULL THEN UPDATE public.hyt_posts SET deleted_at=now() WHERE id=p.id; UPDATE public.hyt_media SET deleted_at=now() WHERE post_id=p.id;
   ELSE UPDATE public.hyt_comments SET deleted_at=now() WHERE id=report.comment_id; UPDATE public.hyt_media SET deleted_at=now() WHERE comment_id=report.comment_id; END IF;
  ELSIF b->>'decision'='lock' THEN UPDATE public.hyt_posts SET locked=true WHERE id=p.id;
  ELSIF b->>'decision'='ban' THEN UPDATE public.hyt_members SET banned_until=now()+interval '7 days' WHERE id=target AND role<>'moderator';
  ELSIF b->>'decision'<>'dismiss' THEN RETURN '{"status":400,"error":"invalid_request"}'::jsonb;
  END IF;
  UPDATE public.hyt_reports SET status='resolved',resolution=b->>'reason',resolved_at=now() WHERE id=report.id;
  INSERT INTO public.hyt_moderation(moderator_id,report_id,action,reason) VALUES(m.id,report.id,b->>'decision',b->>'reason');
  RETURN '{"status":200}'::jsonb;
 END IF;
 IF a IN ('posts.create','comments.create','reactions.set','comments.like','responses.set','polls.vote') AND m.banned_until>now() THEN RETURN '{"status":403,"error":"account_muted"}'::jsonb; END IF;
 IF a='posts.create' THEN
  SELECT * INTO p FROM public.hyt_posts WHERE author_id=m.id AND request_id=(b->>'requestId')::uuid;
  IF FOUND THEN
   IF p.deleted_at IS NOT NULL OR p.body<>b->>'body' OR p.anonymous<>(b->>'anonymous')::boolean OR p.title<>coalesce(b->>'title','') OR p.category<>coalesce(b->>'category','daily') OR p.interest<>coalesce(b->>'interest','') OR coalesce((SELECT jsonb_agg(id::text ORDER BY position) FROM public.hyt_media WHERE post_id=p.id AND comment_id IS NULL AND deleted_at IS NULL),'[]'::jsonb)<>coalesce(b->'images','[]'::jsonb) OR coalesce((SELECT definition FROM public.hyt_polls WHERE post_id=p.id),'null'::jsonb)<>coalesce(b->'poll','null'::jsonb) OR (SELECT definition FROM public.hyt_buddies WHERE post_id=p.id) IS DISTINCT FROM nullif(b->'buddy','null'::jsonb) THEN RETURN '{"status":409,"error":"request_conflict"}'::jsonb; END IF;
   RETURN jsonb_build_object('status',200,'post',public.hyt_post_json(p,m.id));
  END IF;
  IF (SELECT count(*) FROM public.hyt_posts WHERE author_id=m.id AND created_at>now()-interval '1 hour')>=10 THEN RETURN '{"status":429,"error":"posting_too_fast"}'::jsonb; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(coalesce(b->'images','[]'::jsonb)) ref WHERE NOT EXISTS(SELECT 1 FROM public.hyt_media im WHERE im.id=ref::uuid AND im.member_id=m.id AND im.purpose='post' AND im.ready AND im.deleted_at IS NULL AND im.post_id IS NULL)) THEN RETURN '{"status":400,"error":"image_unavailable"}'::jsonb; END IF;
  IF b->'buddy' IS NOT NULL AND b->'buddy'<>'null'::jsonb AND ((b->'buddy'->>'startsAt')::timestamptz<=now() OR (b->'buddy'->>'startsAt')::timestamptz>now()+interval '90 days') THEN RETURN '{"status":400,"error":"buddy_time"}'::jsonb; END IF;
  INSERT INTO public.hyt_posts(author_id,body,anonymous,request_id,title,category,interest) VALUES(m.id,b->>'body',(b->>'anonymous')::boolean,(b->>'requestId')::uuid,coalesce(b->>'title',''),coalesce(b->>'category','daily'),coalesce(b->>'interest','')) RETURNING * INTO p;
  UPDATE public.hyt_media im SET post_id=p.id,position=refs.ord FROM jsonb_array_elements_text(coalesce(b->'images','[]'::jsonb)) WITH ORDINALITY refs(ref,ord) WHERE im.id=refs.ref::uuid;
  IF b->'poll' IS NOT NULL AND b->'poll'<>'null'::jsonb THEN INSERT INTO public.hyt_polls(post_id,definition,closes_at) VALUES(p.id,b->'poll',now()+make_interval(hours=>(b->'poll'->>'durationHours')::int)); END IF;
  IF b->'buddy' IS NOT NULL AND b->'buddy'<>'null'::jsonb THEN INSERT INTO public.hyt_buddies(post_id,definition,starts_at,capacity) VALUES(p.id,b->'buddy',(b->'buddy'->>'startsAt')::timestamptz,(b->'buddy'->>'capacity')::int); END IF;
  INSERT INTO public.hyt_thread_aliases(post_id,member_id) VALUES(p.id,m.id);
  INSERT INTO public.hyt_thread_watches(member_id,post_id) VALUES(m.id,p.id) ON CONFLICT DO NOTHING;
  INSERT INTO public.hyt_thread_visits(member_id,post_id) VALUES(m.id,p.id) ON CONFLICT DO NOTHING;
  PERFORM public.hyt_award_check(m.id,'posts');
  RETURN jsonb_build_object('status',201,'post',public.hyt_post_json(p,m.id))||public.hyt_award_pending(m.id);
 END IF;
 SELECT * INTO p FROM public.hyt_posts WHERE id=(b->>'postId')::uuid AND deleted_at IS NULL FOR UPDATE;
 IF NOT FOUND OR EXISTS(SELECT 1 FROM public.hyt_hidden_threads h WHERE h.member_id=m.id AND h.post_id=p.id) OR EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=p.author_id AND NOT p.anonymous) THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
 IF a IN ('buddies.join','buddies.close','buddies.members') THEN
  IF NOT EXISTS(SELECT 1 FROM public.hyt_buddies WHERE post_id=p.id) THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
  IF a='buddies.members' THEN
   IF p.author_id<>m.id THEN RETURN '{"status":403,"error":"forbidden"}'::jsonb; END IF;
   SELECT coalesce(jsonb_agg(jsonb_build_object('id',u.id,'nickname',u.nickname,'avatar',public.hyt_avatar_json(u.id),'joinedAt',j.joined_at) ORDER BY j.joined_at,u.id),'[]'::jsonb) INTO result
   FROM public.hyt_buddy_members j JOIN public.hyt_members u ON u.id=j.member_id AND u.deleted_at IS NULL WHERE j.post_id=p.id;
   RETURN jsonb_build_object('status',200,'participants',result,'post',public.hyt_post_json(p,m.id));
  END IF;
  IF a='buddies.close' THEN
   IF p.author_id<>m.id THEN RETURN '{"status":403,"error":"forbidden"}'::jsonb; END IF;
   IF (SELECT closed=(b->>'closed')::boolean FROM public.hyt_buddies WHERE post_id=p.id) THEN RETURN jsonb_build_object('status',200,'post',public.hyt_post_json(p,m.id)); END IF;
   IF NOT (b->>'closed')::boolean THEN
    IF p.locked THEN RETURN '{"status":403,"error":"post_locked"}'::jsonb; END IF;
    IF m.banned_until>now() THEN RETURN '{"status":403,"error":"account_muted"}'::jsonb; END IF;
    IF (SELECT starts_at<=now() FROM public.hyt_buddies WHERE post_id=p.id) THEN RETURN '{"status":409,"error":"buddy_closed"}'::jsonb; END IF;
   END IF;
   UPDATE public.hyt_buddies SET closed=(b->>'closed')::boolean,revision=revision+1 WHERE post_id=p.id;
   INSERT INTO public.hyt_notifications(recipient_id,actor_id,post_id,kind,event_key)
   SELECT member_id,m.id,p.id,'buddy','buddy:'||p.id FROM public.hyt_buddy_members WHERE post_id=p.id
   ON CONFLICT(recipient_id,event_key) DO UPDATE SET actor_id=excluded.actor_id,created_at=now(),read_at=NULL;
  ELSE
   IF p.author_id=m.id THEN RETURN '{"status":400,"error":"buddy_host"}'::jsonb; END IF;
   IF EXISTS(SELECT 1 FROM public.hyt_buddy_members WHERE post_id=p.id AND member_id=m.id)=(b->>'enabled')::boolean THEN RETURN jsonb_build_object('status',200,'post',public.hyt_post_json(p,m.id)); END IF;
   IF (b->>'enabled')::boolean THEN
    IF p.locked THEN RETURN '{"status":403,"error":"post_locked"}'::jsonb; END IF;
    IF m.banned_until>now() THEN RETURN '{"status":403,"error":"account_muted"}'::jsonb; END IF;
    IF NOT p.anonymous AND EXISTS(SELECT 1 FROM public.hyt_blocks WHERE (member_id=m.id AND blocked_id=p.author_id) OR (member_id=p.author_id AND blocked_id=m.id)) THEN RETURN '{"status":403,"error":"forbidden"}'::jsonb; END IF;
    IF (SELECT closed OR starts_at<=now() FROM public.hyt_buddies WHERE post_id=p.id) THEN RETURN '{"status":409,"error":"buddy_closed"}'::jsonb; END IF;
    IF (SELECT count(*) FROM public.hyt_buddy_members WHERE post_id=p.id)>=(SELECT capacity FROM public.hyt_buddies WHERE post_id=p.id) THEN RETURN '{"status":409,"error":"buddy_full"}'::jsonb; END IF;
    INSERT INTO public.hyt_buddy_members(post_id,member_id) VALUES(p.id,m.id);
    INSERT INTO public.hyt_thread_watches(member_id,post_id) VALUES(m.id,p.id) ON CONFLICT DO NOTHING;
   ELSE DELETE FROM public.hyt_buddy_members WHERE post_id=p.id AND member_id=m.id;
   END IF;
   UPDATE public.hyt_buddies SET revision=revision+1 WHERE post_id=p.id;
   INSERT INTO public.hyt_notifications(recipient_id,actor_id,post_id,kind,event_key) VALUES(p.author_id,m.id,p.id,'buddy','buddy:'||p.id)
   ON CONFLICT(recipient_id,event_key) DO UPDATE SET actor_id=excluded.actor_id,created_at=now(),read_at=NULL;
  END IF;
  RETURN jsonb_build_object('status',200,'post',public.hyt_post_json(p,m.id));
 END IF;
 IF a='polls.vote' THEN
  IF p.locked THEN RETURN '{"status":409,"error":"post_locked"}'::jsonb; END IF;
  SELECT definition INTO result FROM public.hyt_polls WHERE post_id=p.id;
  IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
  IF (SELECT closes_at<=now() FROM public.hyt_polls WHERE post_id=p.id) THEN RETURN '{"status":409,"error":"poll_closed"}'::jsonb; END IF;
  IF b->>'optionId' IS NULL THEN DELETE FROM public.hyt_poll_votes WHERE post_id=p.id AND member_id=m.id;
  ELSE
   n=(b->>'optionId')::int;
   IF n<0 OR n>=jsonb_array_length(result->'options') THEN RETURN '{"status":400,"error":"invalid_request"}'::jsonb; END IF;
   INSERT INTO public.hyt_poll_votes(post_id,member_id,option_index) VALUES(p.id,m.id,n) ON CONFLICT(post_id,member_id) DO UPDATE SET option_index=excluded.option_index;
  END IF;
  UPDATE public.hyt_polls SET revision=revision+1 WHERE post_id=p.id;
  RETURN jsonb_build_object('status',200,'post',public.hyt_post_json(p,m.id));
 END IF;
 IF a='threads.watch' THEN
  INSERT INTO public.hyt_thread_watches(member_id,post_id,enabled) VALUES(m.id,p.id,(b->>'enabled')::boolean)
  ON CONFLICT(member_id,post_id) DO UPDATE SET enabled=excluded.enabled;
  INSERT INTO public.hyt_thread_visits(member_id,post_id) VALUES(m.id,p.id) ON CONFLICT DO NOTHING;
  RETURN jsonb_build_object('status',200,'post',public.hyt_post_json(p,m.id));
 END IF;
 IF a='posts.get' THEN
  INSERT INTO public.hyt_thread_visits(member_id,post_id) VALUES(m.id,p.id)
  ON CONFLICT(member_id,post_id) DO UPDATE SET seen_at=greatest(hyt_thread_visits.seen_at,excluded.seen_at);
 END IF;
 IF a='comments.context' THEN
  SELECT * INTO c FROM public.hyt_comments c WHERE c.id=(b->>'commentId')::uuid AND c.post_id=p.id AND c.deleted_at IS NULL
   AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=c.author_id AND NOT c.anonymous);
  IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
  SELECT public.hyt_comment_json(rc,m.id)||jsonb_build_object('replies',CASE WHEN c.root_id IS NULL THEN '[]'::jsonb ELSE jsonb_build_array(public.hyt_comment_json(c,m.id)) END) INTO result
   FROM public.hyt_comments rc WHERE rc.id=coalesce(c.root_id,c.id)
   AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=rc.author_id AND NOT rc.anonymous);
  IF result IS NULL THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
  RETURN jsonb_build_object('status',200,'context',result,'focusCommentId',c.id);
 END IF;
 IF a='media.url' THEN
  SELECT * INTO img FROM public.hyt_media WHERE id=(b->>'imageId')::uuid AND post_id=p.id AND ready AND deleted_at IS NULL AND (comment_id IS NULL OR public.hyt_comment_image_visible(comment_id,m.id));
  IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
  RETURN jsonb_build_object('status',200,'image',public.hyt_media_json(img));
 END IF;
 IF a='posts.get' AND coalesce((b->>'threaded')::boolean,false) THEN
  SELECT coalesce(jsonb_agg(public.hyt_comment_json(q,m.id)||jsonb_build_object('replies',
   (SELECT coalesce(jsonb_agg(public.hyt_comment_json(rc,m.id) ORDER BY rc.created_at,rc.id),'[]'::jsonb) FROM
    (SELECT * FROM public.hyt_comments rc WHERE rc.root_id=q.id AND rc.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=rc.author_id AND NOT rc.anonymous) ORDER BY rc.created_at,rc.id LIMIT 2) rc)) ORDER BY q.created_at,q.id),'[]'::jsonb) INTO result FROM
   (SELECT c.* FROM public.hyt_comments c WHERE c.post_id=p.id AND c.reply_to IS NULL
    AND (c.deleted_at IS NULL OR EXISTS(
      SELECT 1 FROM public.hyt_comments child WHERE child.root_id=c.id AND child.deleted_at IS NULL
       AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=child.author_id AND NOT child.anonymous)))
    AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=c.author_id AND NOT c.anonymous)
    AND (b->>'afterTime' IS NULL OR (c.created_at,c.id)>((b->>'afterTime')::timestamptz,(b->>'afterId')::uuid)) ORDER BY c.created_at,c.id LIMIT 21) q;
  RETURN jsonb_build_object('status',200,'post',public.hyt_post_json(p,m.id),'comments',result);
 END IF;
 IF a IN ('posts.get','comments.replies') THEN
  IF a='comments.replies' AND NOT EXISTS(SELECT 1 FROM public.hyt_comments rc WHERE rc.id=(b->>'rootId')::uuid AND rc.post_id=p.id AND rc.reply_to IS NULL AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=rc.author_id AND NOT rc.anonymous)) THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
  SELECT coalesce(jsonb_agg(public.hyt_comment_json(q,m.id) ORDER BY q.created_at,q.id),'[]'::jsonb) INTO result FROM
   (SELECT c.* FROM public.hyt_comments c WHERE c.post_id=p.id
    AND (a='posts.get' OR (c.root_id=(b->>'rootId')::uuid AND c.deleted_at IS NULL))
    AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=c.author_id AND NOT c.anonymous)
    AND (b->>'afterTime' IS NULL OR (c.created_at,c.id)>((b->>'afterTime')::timestamptz,(b->>'afterId')::uuid)) ORDER BY c.created_at,c.id LIMIT 51) q;
  RETURN jsonb_build_object('status',200,'post',public.hyt_post_json(p,m.id),'comments',result);
 END IF;
 IF a='comments.like' THEN
  SELECT * INTO c FROM public.hyt_comments c WHERE c.id=(b->>'commentId')::uuid AND c.post_id=p.id AND c.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=c.author_id AND NOT c.anonymous);
  IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
  IF (b->>'enabled')::boolean THEN
   INSERT INTO public.hyt_comment_likes VALUES(c.id,m.id) ON CONFLICT DO NOTHING;
   IF c.author_id<>m.id THEN PERFORM public.hyt_award_check(c.author_id,'likes'); INSERT INTO public.hyt_notifications(recipient_id,actor_id,post_id,comment_id,kind,event_key)
    VALUES(c.author_id,m.id,p.id,c.id,'comment_like','comment-like:'||c.id||':'||m.id) ON CONFLICT DO NOTHING; END IF;
  ELSE DELETE FROM public.hyt_comment_likes WHERE comment_id=c.id AND member_id=m.id; END IF;
  RETURN jsonb_build_object('status',200,'comment',public.hyt_comment_json(c,m.id));
 END IF;
 IF a='comments.create' THEN
  IF p.locked THEN RETURN '{"status":409,"error":"post_locked"}'::jsonb; END IF;
  anon=(b->>'anonymous')::boolean OR p.category='treehole' OR (p.author_id=m.id AND p.anonymous);
  SELECT * INTO c FROM public.hyt_comments WHERE author_id=m.id AND request_id=(b->>'requestId')::uuid;
  IF FOUND THEN
   IF c.deleted_at IS NOT NULL OR c.post_id<>p.id OR c.body<>b->>'body' OR c.anonymous<>anon OR c.reply_to IS DISTINCT FROM (b->>'replyTo')::uuid OR coalesce((SELECT jsonb_agg(id::text ORDER BY position) FROM public.hyt_media WHERE comment_id=c.id AND deleted_at IS NULL),'[]'::jsonb)<>coalesce(b->'images','[]'::jsonb) THEN RETURN '{"status":409,"error":"request_conflict"}'::jsonb; END IF;
   RETURN jsonb_build_object('status',200,'comment',public.hyt_comment_json(c,m.id));
  END IF;
  IF (SELECT count(*) FROM public.hyt_comments WHERE author_id=m.id AND created_at>now()-interval '1 hour')>=60 THEN RETURN '{"status":429,"error":"posting_too_fast"}'::jsonb; END IF;
  IF b->>'replyTo' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.hyt_comments c WHERE c.id=(b->>'replyTo')::uuid AND c.post_id=p.id AND c.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=c.author_id AND NOT c.anonymous)) THEN RETURN '{"status":404,"error":"reply_unavailable"}'::jsonb; END IF;
  root=NULL;
  IF b->>'replyTo' IS NOT NULL THEN SELECT coalesce(root_id,id) INTO root FROM public.hyt_comments WHERE id=(b->>'replyTo')::uuid; END IF;
  IF root IS NOT NULL AND EXISTS(SELECT 1 FROM public.hyt_comments rc JOIN public.hyt_blocks bl ON bl.member_id=m.id AND bl.blocked_id=rc.author_id AND NOT rc.anonymous WHERE rc.id=root) THEN RETURN '{"status":404,"error":"reply_unavailable"}'::jsonb; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(coalesce(b->'images','[]'::jsonb)) ref WHERE NOT EXISTS(SELECT 1 FROM public.hyt_media im WHERE im.id=ref::uuid AND im.member_id=m.id AND im.purpose='comment' AND im.ready AND im.deleted_at IS NULL AND im.post_id IS NULL AND im.comment_id IS NULL)) THEN RETURN '{"status":400,"error":"image_unavailable"}'::jsonb; END IF;
  INSERT INTO public.hyt_comments(post_id,author_id,body,anonymous,reply_to,request_id,root_id) VALUES(p.id,m.id,b->>'body',anon,(b->>'replyTo')::uuid,(b->>'requestId')::uuid,root) RETURNING * INTO c;
  UPDATE public.hyt_media im SET post_id=p.id,comment_id=c.id,position=refs.ord FROM jsonb_array_elements_text(coalesce(b->'images','[]'::jsonb)) WITH ORDINALITY refs(ref,ord) WHERE im.id=refs.ref::uuid;
  INSERT INTO public.hyt_thread_aliases(post_id,member_id) VALUES(p.id,m.id) ON CONFLICT DO NOTHING;
  INSERT INTO public.hyt_thread_watches(member_id,post_id) VALUES(m.id,p.id) ON CONFLICT DO NOTHING;
  INSERT INTO public.hyt_thread_visits(member_id,post_id) VALUES(m.id,p.id) ON CONFLICT DO NOTHING;
  PERFORM public.hyt_notify_comment(c);
  PERFORM public.hyt_award_check(m.id,'threads');
  RETURN jsonb_build_object('status',201,'comment',public.hyt_comment_json(c,m.id))||public.hyt_award_pending(m.id);
 END IF;
 IF a='posts.delete' THEN
  IF p.author_id<>m.id THEN RETURN '{"status":403,"error":"forbidden"}'::jsonb; END IF;
  UPDATE public.hyt_posts SET body='已删除',title='',deleted_at=now() WHERE id=p.id; UPDATE public.hyt_media SET deleted_at=now() WHERE post_id=p.id; RETURN '{"status":200}'::jsonb;
 END IF;
 IF a='comments.delete' THEN
  UPDATE public.hyt_comments SET body='已删除',deleted_at=now() WHERE id=(b->>'commentId')::uuid AND post_id=p.id AND author_id=m.id;
  IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
  UPDATE public.hyt_media SET deleted_at=now() WHERE comment_id=(b->>'commentId')::uuid;
  RETURN '{"status":200}'::jsonb;
 END IF;
 IF a='responses.set' THEN
  IF b->>'kind' IS NULL THEN DELETE FROM public.hyt_responses WHERE post_id=p.id AND member_id=m.id;
  ELSE
   INSERT INTO public.hyt_responses(post_id,member_id,kind) VALUES(p.id,m.id,b->>'kind') ON CONFLICT(post_id,member_id) DO UPDATE SET kind=excluded.kind;
   IF p.author_id<>m.id THEN INSERT INTO public.hyt_notifications(recipient_id,actor_id,post_id,kind,event_key)
    VALUES(p.author_id,m.id,p.id,'post_response','post-response:'||p.id||':'||m.id) ON CONFLICT DO NOTHING; END IF;
  END IF;
  RETURN jsonb_build_object('status',200,'post',public.hyt_post_json(p,m.id));
 END IF;
 IF a='reactions.set' THEN
  IF (b->>'enabled')::boolean THEN
   INSERT INTO public.hyt_reactions VALUES(p.id,m.id,b->>'kind') ON CONFLICT DO NOTHING;
   IF b->>'kind'='save' THEN PERFORM public.hyt_award_check(m.id,'saves'); END IF;
   IF b->>'kind'='like' AND p.author_id<>m.id THEN PERFORM public.hyt_award_check(p.author_id,'likes'); INSERT INTO public.hyt_notifications(recipient_id,actor_id,post_id,kind,event_key)
    VALUES(p.author_id,m.id,p.id,'post_like','post-like:'||p.id||':'||m.id) ON CONFLICT DO NOTHING; END IF;
  ELSE DELETE FROM public.hyt_reactions WHERE post_id=p.id AND member_id=m.id AND kind=b->>'kind'; END IF;
  RETURN jsonb_build_object('status',200,'post',public.hyt_post_json(p,m.id))||public.hyt_award_pending(m.id);
 END IF;
 IF a IN ('reports.create','blocks.set') THEN
  target=p.author_id; anon=p.anonymous;
  IF b->>'commentId' IS NOT NULL THEN
   SELECT author_id,anonymous INTO target,anon FROM public.hyt_comments WHERE id=(b->>'commentId')::uuid AND post_id=p.id AND deleted_at IS NULL;
   IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
  END IF;
  IF a='blocks.set' THEN
   IF target=m.id THEN RETURN '{"status":400,"error":"cannot_block_self"}'::jsonb; END IF;
   IF anon THEN INSERT INTO public.hyt_hidden_threads VALUES(m.id,p.id) ON CONFLICT DO NOTHING;
    UPDATE public.hyt_buddies SET revision=revision+1 WHERE post_id=p.id AND EXISTS(SELECT 1 FROM public.hyt_buddy_members WHERE post_id=p.id AND member_id=m.id);
    DELETE FROM public.hyt_buddy_members WHERE post_id=p.id AND member_id=m.id;
   ELSE
    INSERT INTO public.hyt_blocks VALUES(m.id,target) ON CONFLICT DO NOTHING;
    UPDATE public.hyt_buddies SET revision=revision+1 WHERE post_id IN (SELECT j.post_id FROM public.hyt_buddy_members j JOIN public.hyt_posts bp ON bp.id=j.post_id WHERE NOT bp.anonymous AND ((j.member_id=m.id AND bp.author_id=target) OR (j.member_id=target AND bp.author_id=m.id)));
    DELETE FROM public.hyt_buddy_members j USING public.hyt_posts bp WHERE bp.id=j.post_id AND NOT bp.anonymous AND ((j.member_id=m.id AND bp.author_id=target) OR (j.member_id=target AND bp.author_id=m.id));
    DELETE FROM public.hyt_follows WHERE (member_id=m.id AND followed_id=target) OR (member_id=target AND followed_id=m.id);
   END IF;
  ELSE
   IF (SELECT count(*) FROM public.hyt_reports WHERE reporter_id=m.id AND created_at>now()-interval '1 hour')>=20 THEN RETURN '{"status":429,"error":"too_many_requests"}'::jsonb; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.hyt_reports WHERE reporter_id=m.id AND post_id=p.id AND comment_id IS NOT DISTINCT FROM (b->>'commentId')::uuid AND status='open') THEN
    INSERT INTO public.hyt_reports(reporter_id,post_id,comment_id,reason) VALUES(m.id,p.id,(b->>'commentId')::uuid,b->>'reason');
   END IF;
  END IF;
  RETURN '{"status":200}'::jsonb;
 END IF;
 RETURN '{"status":404,"error":"not_found"}'::jsonb;
END $fn$;

-- No direct client role may query author mappings, credentials, or bypass server validation.
DO $$ DECLARE obj record; role_name text; BEGIN
 FOR obj IN SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename LIKE 'hyt_collection_%' OR tablename IN
 ('hyt_honors','hyt_awards','hyt_honor_history','hyt_recommendations','hyt_dm_threads','hyt_dm_messages','hyt_dm_reads','hyt_members','hyt_sessions','hyt_posts','hyt_comments','hyt_thread_aliases','hyt_reactions','hyt_blocks','hyt_hidden_threads','hyt_reports','hyt_moderation','hyt_community_rate','hyt_media','hyt_comment_likes','hyt_thread_watches','hyt_thread_visits','hyt_notifications','hyt_responses','hyt_follows','hyt_polls','hyt_poll_votes','hyt_buddies','hyt_buddy_members')) LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',obj.tablename);
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC',obj.tablename);
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=role_name) THEN EXECUTE format('REVOKE ALL ON public.%I FROM %I',obj.tablename,role_name); END IF;
  END LOOP;
 END LOOP;
 FOR obj IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND (proname LIKE 'hyt_collection_%' OR proname IN ('hyt_credit','hyt_badges','hyt_progress','hyt_award_check','hyt_award_pending','hyt_hall','hyt_dm_visible','hyt_dm_json','hyt_dm_message_json','hyt_community','hyt_member_json','hyt_author_json','hyt_post_json','hyt_comment_json','hyt_media_json','hyt_visible_notifications','hyt_notification_json','hyt_notify_comment','hyt_avatar_json','hyt_profile_json','hyt_poll_json','hyt_comment_image_visible','hyt_buddy_json')) LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',obj.signature);
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=role_name) THEN EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I',obj.signature,role_name); END IF;
  END LOOP;
 END LOOP;
END $$;
