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
CREATE OR REPLACE FUNCTION public.hyt_badges(m public.hyt_members) RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('official',CASE WHEN m.developer_since IS NOT NULL THEN jsonb_build_object('code','developer','at',m.developer_since)
 WHEN m.role='moderator' THEN jsonb_build_object('code','moderator','at',coalesce(m.moderator_since,
 (SELECT min(created_at) FROM public.hyt_moderation WHERE moderator_id=m.id AND action='grant_moderator'))) END,
 'worn',(SELECT jsonb_build_object('code',kind,'at',granted_at) FROM public.hyt_honors WHERE member_id=m.id AND kind=m.worn_honor));
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
ALTER TABLE public.hyt_media ADD COLUMN IF NOT EXISTS contest_entry_id uuid;
CREATE OR REPLACE FUNCTION public.hyt_community(a text,b jsonb,th text) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog,public AS $fn$
#variable_conflict use_column
DECLARE subject public.hyt_members%ROWTYPE; metric text; m public.hyt_members%ROWTYPE; p public.hyt_posts%ROWTYPE; c public.hyt_comments%ROWTYPE;
 report public.hyt_reports%ROWTYPE; target uuid; result jsonb; n int; k text; stamp timestamptz; limit_n int; anon boolean; img public.hyt_media%ROWTYPE; root uuid; snapshot timestamptz; dm public.hyt_dm_threads%ROWTYPE; msg public.hyt_dm_messages%ROWTYPE;
BEGIN
 IF a LIKE 'contests.%' THEN RETURN public.hyt_contests(a,b,th); END IF;
 IF a='rate' THEN
  DELETE FROM public.hyt_community_rate WHERE key IN (SELECT key FROM public.hyt_community_rate WHERE until_at<now()-interval '1 day' LIMIT 100);
  INSERT INTO public.hyt_community_rate(key,count,until_at) VALUES(b->>'key',1,now()+make_interval(secs=>(b->>'seconds')::int))
  ON CONFLICT(key) DO UPDATE SET count=CASE WHEN hyt_community_rate.until_at<=now() THEN 1 ELSE hyt_community_rate.count+1 END,
  until_at=CASE WHEN hyt_community_rate.until_at<=now() THEN excluded.until_at ELSE hyt_community_rate.until_at END RETURNING count INTO n;
  IF n>(b->>'limit')::int THEN RETURN jsonb_build_object('status',429,'error','too_many_requests'); END IF;
  RETURN '{"status":200}'::jsonb;
 END IF;
 IF a='media.cleanup' THEN
  WITH stale AS (UPDATE public.hyt_media SET deleted_at=coalesce(deleted_at,now()) WHERE id IN (SELECT i.id FROM public.hyt_media i WHERE (i.deleted_at IS NOT NULL OR (i.post_id IS NULL AND i.contest_entry_id IS NULL AND i.created_at<now()-interval '7 days')) AND NOT EXISTS(SELECT 1 FROM public.hyt_members u WHERE u.avatar_id=i.id AND u.deleted_at IS NULL) LIMIT 20 FOR UPDATE SKIP LOCKED) RETURNING *) SELECT coalesce(jsonb_agg(public.hyt_media_json(stale)),'[]'::jsonb) INTO result FROM stale;
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
   UPDATE public.hyt_members SET worn_honor=b->>'honor',showcase=ARRAY(SELECT jsonb_array_elements_text(b->'showcase')) WHERE id=m.id RETURNING * INTO m;
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
     UPDATE public.hyt_members SET worn_honor=b->>'kind' WHERE id=target AND worn_honor IS NULL;
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
  UPDATE public.hyt_media SET deleted_at=now() WHERE id=(b->>'imageId')::uuid AND member_id=m.id AND post_id IS NULL AND contest_entry_id IS NULL AND id IS DISTINCT FROM m.avatar_id;
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
   UPDATE public.hyt_members SET deleted_at=now(),username='deleted_'||id::text,nickname='已注销',password_hash='',recovery_hash='',avatar_id=NULL WHERE id=m.id;
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
 FOR obj IN SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename IN
 ('hyt_honors','hyt_awards','hyt_honor_history','hyt_recommendations','hyt_dm_threads','hyt_dm_messages','hyt_dm_reads','hyt_members','hyt_sessions','hyt_posts','hyt_comments','hyt_thread_aliases','hyt_reactions','hyt_blocks','hyt_hidden_threads','hyt_reports','hyt_moderation','hyt_community_rate','hyt_media','hyt_comment_likes','hyt_thread_watches','hyt_thread_visits','hyt_notifications','hyt_responses','hyt_follows','hyt_polls','hyt_poll_votes','hyt_buddies','hyt_buddy_members') LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',obj.tablename);
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC',obj.tablename);
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=role_name) THEN EXECUTE format('REVOKE ALL ON public.%I FROM %I',obj.tablename,role_name); END IF;
  END LOOP;
 END LOOP;
 FOR obj IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN ('hyt_credit','hyt_badges','hyt_progress','hyt_award_check','hyt_award_pending','hyt_hall','hyt_dm_visible','hyt_dm_json','hyt_dm_message_json','hyt_community','hyt_member_json','hyt_author_json','hyt_post_json','hyt_comment_json','hyt_media_json','hyt_visible_notifications','hyt_notification_json','hyt_notify_comment','hyt_avatar_json','hyt_profile_json','hyt_poll_json','hyt_comment_image_visible','hyt_buddy_json') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',obj.signature);
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=role_name) THEN EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I',obj.signature,role_name); END IF;
  END LOOP;
 END LOOP;
END $$;

-- Theme competitions, additive migration 13. Existing account and honor keys stay intact.
CREATE TABLE IF NOT EXISTS public.hyt_contests (
 id uuid PRIMARY KEY, title text NOT NULL, type text NOT NULL, edition text NOT NULL DEFAULT '',
 description text NOT NULL, rules text NOT NULL, cover_post_id uuid REFERENCES public.hyt_posts(id),
 starts_at timestamptz NOT NULL, submission_ends timestamptz NOT NULL, voting_starts timestamptz NOT NULL,
 voting_ends timestamptz NOT NULL, award_at timestamptz NOT NULL,
 formats text[] NOT NULL, max_entries int NOT NULL DEFAULT 1, votes_per_user int NOT NULL DEFAULT 3,
 min_entries int NOT NULL DEFAULT 5, min_account_hours int NOT NULL DEFAULT 24, excellence int NOT NULL DEFAULT 3,
 published boolean NOT NULL DEFAULT false, paused boolean NOT NULL DEFAULT false, cancelled boolean NOT NULL DEFAULT false,
 auto_publish boolean NOT NULL DEFAULT false, settled_at timestamptz, announced_at timestamptz,
 version int NOT NULL DEFAULT 1, created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(starts_at<submission_ends AND submission_ends<=voting_starts AND voting_starts<voting_ends AND voting_ends<=award_at),
 CHECK(max_entries BETWEEN 1 AND 10 AND votes_per_user BETWEEN 1 AND 10 AND min_entries>0 AND min_account_hours>=0)
);
-- v14 additive: retain existing ballots and flags; administrative retry ledger.
ALTER TABLE public.hyt_contests ADD COLUMN IF NOT EXISTS risk_review boolean NOT NULL DEFAULT true;
CREATE TABLE IF NOT EXISTS public.hyt_contest_operations (
 member_id uuid NOT NULL REFERENCES public.hyt_members(id), request_id uuid NOT NULL, action text NOT NULL,
 payload jsonb NOT NULL, result jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(member_id,request_id)
);
CREATE INDEX IF NOT EXISTS hyt_contest_schedule ON public.hyt_contests(award_at,id) WHERE published AND NOT cancelled;
CREATE TABLE IF NOT EXISTS public.hyt_contest_entries (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), contest_id uuid NOT NULL REFERENCES public.hyt_contests(id),
 member_id uuid NOT NULL REFERENCES public.hyt_members(id), request_id uuid NOT NULL,
 title text NOT NULL, body text NOT NULL, post_id uuid REFERENCES public.hyt_posts(id),
 linked boolean NOT NULL DEFAULT false,
 status text NOT NULL DEFAULT 'approved' CHECK(status IN ('approved','removed','withdrawn')),
 votes int NOT NULL DEFAULT 0 CHECK(votes>=0), version int NOT NULL DEFAULT 1,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(member_id,request_id)
);
ALTER TABLE public.hyt_contest_entries ADD COLUMN IF NOT EXISTS linked boolean NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS hyt_contest_entry_order ON public.hyt_contest_entries(contest_id,status,id);
CREATE INDEX IF NOT EXISTS hyt_contest_entry_member ON public.hyt_contest_entries(member_id,contest_id);
CREATE INDEX IF NOT EXISTS hyt_contest_media ON public.hyt_media(contest_entry_id) WHERE contest_entry_id IS NOT NULL;
CREATE TABLE IF NOT EXISTS public.hyt_contest_requests (member_id uuid REFERENCES public.hyt_members(id),request_id uuid,entry_id uuid REFERENCES public.hyt_contest_entries(id),payload jsonb NOT NULL,PRIMARY KEY(member_id,request_id));
CREATE TABLE IF NOT EXISTS public.hyt_contest_votes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), contest_id uuid NOT NULL REFERENCES public.hyt_contests(id),
 entry_id uuid NOT NULL REFERENCES public.hyt_contest_entries(id), member_id uuid NOT NULL REFERENCES public.hyt_members(id),
 enabled boolean NOT NULL DEFAULT true, excluded boolean NOT NULL DEFAULT false, risk text,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), UNIQUE(entry_id,member_id)
);
ALTER TABLE public.hyt_contest_votes ADD COLUMN IF NOT EXISTS window_started_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.hyt_contest_votes ADD COLUMN IF NOT EXISTS window_changes int NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS hyt_contest_vote_review ON public.hyt_contest_votes(contest_id,risk,created_at DESC,id);
CREATE INDEX IF NOT EXISTS hyt_contest_voter ON public.hyt_contest_votes(contest_id,member_id) WHERE enabled;
CREATE TABLE IF NOT EXISTS public.hyt_contest_awards (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), contest_id uuid NOT NULL REFERENCES public.hyt_contests(id),
 entry_id uuid NOT NULL REFERENCES public.hyt_contest_entries(id), member_id uuid NOT NULL REFERENCES public.hyt_members(id),
 kind text NOT NULL, rank int, votes int NOT NULL, title text NOT NULL, edition text NOT NULL,
 awarded_at timestamptz NOT NULL DEFAULT now(), revoked_at timestamptz, UNIQUE(entry_id,kind)
);
CREATE INDEX IF NOT EXISTS hyt_contest_award_event ON public.hyt_contest_awards(contest_id,awarded_at DESC,id);
CREATE INDEX IF NOT EXISTS hyt_contest_award_year ON public.hyt_contest_awards((extract(year FROM awarded_at AT TIME ZONE 'Asia/Shanghai')),member_id) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS hyt_contest_award_member ON public.hyt_contest_awards(member_id,awarded_at DESC);
CREATE TABLE IF NOT EXISTS public.hyt_contest_reports (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), entry_id uuid NOT NULL REFERENCES public.hyt_contest_entries(id),
 member_id uuid NOT NULL REFERENCES public.hyt_members(id), reason text NOT NULL, resolved_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(entry_id,member_id)
);
CREATE TABLE IF NOT EXISTS public.hyt_contest_audit (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), contest_id uuid REFERENCES public.hyt_contests(id), actor_id uuid REFERENCES public.hyt_members(id),
 action text NOT NULL, target_id uuid, reason text NOT NULL, snapshot jsonb, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.hyt_contest_settings (id boolean PRIMARY KEY DEFAULT true CHECK(id), solicitation boolean NOT NULL DEFAULT false);
INSERT INTO public.hyt_contest_settings(id) VALUES(true) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS public.hyt_contest_themes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), member_id uuid NOT NULL REFERENCES public.hyt_members(id),
 title text NOT NULL, request_id uuid NOT NULL, status text NOT NULL DEFAULT 'pending', merged_into uuid REFERENCES public.hyt_contest_themes(id),
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(member_id,request_id)
);
CREATE TABLE IF NOT EXISTS public.hyt_contest_theme_votes (theme_id uuid REFERENCES public.hyt_contest_themes(id),member_id uuid REFERENCES public.hyt_members(id),PRIMARY KEY(theme_id,member_id));
CREATE TABLE IF NOT EXISTS public.hyt_contest_worn (member_id uuid PRIMARY KEY REFERENCES public.hyt_members(id),award_id uuid REFERENCES public.hyt_contest_awards(id));
CREATE TABLE IF NOT EXISTS public.hyt_contest_year_awards (year int NOT NULL,member_id uuid REFERENCES public.hyt_members(id),score int NOT NULL,awarded_at timestamptz NOT NULL DEFAULT now(),revoked_at timestamptz,PRIMARY KEY(year,member_id));

CREATE OR REPLACE FUNCTION public.hyt_contest_state(c public.hyt_contests) RETURNS text LANGUAGE sql VOLATILE AS $$
 SELECT CASE WHEN c.cancelled THEN 'cancelled' WHEN c.announced_at IS NOT NULL THEN 'ended'
 WHEN NOT c.published THEN 'draft' WHEN clock_timestamp()<c.starts_at THEN 'upcoming'
 WHEN clock_timestamp()<c.submission_ends THEN 'submitting' WHEN clock_timestamp()<c.voting_starts THEN 'waiting'
 WHEN clock_timestamp()<c.voting_ends THEN 'voting' ELSE 'reviewing' END;
$$;
CREATE OR REPLACE FUNCTION public.hyt_contest_json(c public.hyt_contests) RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('id',c.id,'title',c.title,'type',c.type,'edition',c.edition,'description',c.description,'rules',c.rules,
 'state',public.hyt_contest_state(c),'paused',c.paused,'startsAt',c.starts_at,'submissionEnds',c.submission_ends,'votingStarts',c.voting_starts,'votingEnds',c.voting_ends,'awardAt',c.award_at,
 'formats',c.formats,'maxEntries',c.max_entries,'votesPerUser',c.votes_per_user,'minEntries',c.min_entries,'minAccountHours',c.min_account_hours,'excellence',c.excellence,'autoPublish',c.auto_publish,'reviewRisk',c.risk_review,'version',c.version,
 'entryCount',(SELECT count(*) FROM public.hyt_contest_entries WHERE contest_id=c.id AND status='approved'),
 'participantCount',(SELECT count(DISTINCT member_id) FROM public.hyt_contest_entries WHERE contest_id=c.id AND status='approved'),
 'coverPostId',c.cover_post_id,'cover',(SELECT public.hyt_media_json(i) FROM public.hyt_media i JOIN public.hyt_posts p ON p.id=i.post_id WHERE p.id=c.cover_post_id AND p.deleted_at IS NULL AND i.ready AND i.deleted_at IS NULL ORDER BY i.position LIMIT 1));
$$;
CREATE OR REPLACE FUNCTION public.hyt_contest_entry_json(e public.hyt_contest_entries, viewer uuid, admin boolean DEFAULT false) RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('id',e.id,'contestId',e.contest_id,'memberId',e.member_id,'title',e.title,'body',e.body,'postId',e.post_id,'linked',e.linked,'status',e.status,'version',e.version,
 'author',CASE WHEN m.deleted_at IS NULL THEN m.nickname ELSE '已注销同学' END,'mine',e.member_id=viewer,'createdAt',e.created_at,
 'voted',EXISTS(SELECT 1 FROM public.hyt_contest_votes v WHERE v.entry_id=e.id AND v.member_id=viewer AND v.enabled),
 'votes',CASE WHEN admin OR c.announced_at IS NOT NULL THEN e.votes ELSE NULL END,
 'images',(SELECT coalesce(jsonb_agg(public.hyt_media_json(i) ORDER BY position),'[]'::jsonb) FROM public.hyt_media i WHERE (i.contest_entry_id=e.id OR (e.linked AND i.post_id=e.post_id AND i.comment_id IS NULL AND i.contest_entry_id IS NULL)) AND i.ready AND i.deleted_at IS NULL),
 'awards',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'kind',a.kind,'rank',a.rank,'at',a.awarded_at)),'[]'::jsonb) FROM public.hyt_contest_awards a WHERE a.entry_id=e.id AND a.revoked_at IS NULL AND c.announced_at IS NOT NULL))
 FROM public.hyt_members m, public.hyt_contests c WHERE m.id=e.member_id AND c.id=e.contest_id;
$$;

-- One event lock serializes votes, moderation and settlement. Unique award keys make retries safe.
CREATE OR REPLACE FUNCTION public.hyt_contest_settle(cid uuid) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
DECLARE c public.hyt_contests; valid_count int;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtext('contest:'||cid::text));
 SELECT * INTO c FROM public.hyt_contests WHERE id=cid FOR UPDATE;
 IF NOT FOUND OR c.cancelled OR c.paused OR NOT c.published OR clock_timestamp()<c.voting_ends THEN RETURN; END IF;
 SELECT count(*) INTO valid_count FROM public.hyt_contest_entries WHERE contest_id=cid AND status='approved';
 -- Revoke outdated snapshots, preserving the first award date and audit trail on corrections.
 UPDATE public.hyt_contest_awards SET revoked_at=now() WHERE contest_id=cid AND revoked_at IS NULL;
 INSERT INTO public.hyt_contest_awards(contest_id,entry_id,member_id,kind,rank,votes,title,edition,awarded_at)
 SELECT cid,e.id,e.member_id,'participation',NULL,e.votes,c.title,c.edition,coalesce(c.announced_at,now()) FROM public.hyt_contest_entries e WHERE contest_id=cid AND status='approved'
 ON CONFLICT(entry_id,kind) DO UPDATE SET revoked_at=NULL,votes=excluded.votes;
 IF valid_count>=c.min_entries THEN
  INSERT INTO public.hyt_contest_awards(contest_id,entry_id,member_id,kind,rank,votes,title,edition,awarded_at)
  SELECT cid,id,member_id,CASE rank WHEN 1 THEN 'champion' WHEN 2 THEN 'silver' WHEN 3 THEN 'bronze' ELSE 'excellent' END,rank,votes,c.title,c.edition,coalesce(c.announced_at,now())
  FROM (SELECT e.*,dense_rank() OVER(ORDER BY votes DESC)::int AS rank FROM public.hyt_contest_entries e WHERE contest_id=cid AND status='approved' AND votes>0) ranked
  WHERE rank<=3+c.excellence
  ON CONFLICT(entry_id,kind) DO UPDATE SET revoked_at=NULL,rank=excluded.rank,votes=excluded.votes;
 END IF;
 UPDATE public.hyt_contests SET settled_at=now() WHERE id=cid;
END;
$$;
CREATE TABLE IF NOT EXISTS public.hyt_contest_year_dirty (year int PRIMARY KEY);
CREATE TABLE IF NOT EXISTS public.hyt_contest_achievements (
 member_id uuid REFERENCES public.hyt_members(id), code text NOT NULL, unlocked_at timestamptz NOT NULL DEFAULT now(), revoked_at timestamptz, PRIMARY KEY(member_id,code)
);
CREATE OR REPLACE FUNCTION public.hyt_contest_achievements_refresh(cid uuid) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
BEGIN
 UPDATE public.hyt_contest_achievements SET revoked_at=now() WHERE member_id IN (SELECT member_id FROM public.hyt_contest_entries WHERE contest_id=cid) AND revoked_at IS NULL;
 WITH stats AS (
  SELECT e.member_id,count(DISTINCT aw.contest_id) FILTER(WHERE aw.kind='participation') AS participations,
   count(*) FILTER(WHERE aw.kind='champion') AS champions,count(*) FILTER(WHERE aw.kind IN ('champion','silver','bronze')) AS podiums
  FROM (SELECT DISTINCT member_id FROM public.hyt_contest_entries WHERE contest_id=cid) e
  LEFT JOIN public.hyt_contest_awards aw ON aw.member_id=e.member_id AND aw.revoked_at IS NULL
  LEFT JOIN public.hyt_contests c ON c.id=aw.contest_id
  WHERE aw.id IS NULL OR (c.announced_at IS NOT NULL AND NOT c.cancelled) GROUP BY e.member_id
 )
 INSERT INTO public.hyt_contest_achievements(member_id,code)
 SELECT member_id,code FROM stats CROSS JOIN LATERAL (VALUES
 ('first_champion',champions>=1),('five_champions',champions>=5),('twenty_champions',champions>=20),('hundred_events',participations>=100),('ten_podiums',podiums>=10)) awards(code,earned) WHERE earned
 ON CONFLICT(member_id,code) DO UPDATE SET revoked_at=NULL;
 INSERT INTO public.hyt_contest_year_dirty SELECT DISTINCT extract(year FROM awarded_at AT TIME ZONE 'Asia/Shanghai')::int FROM public.hyt_contest_awards WHERE contest_id=cid ON CONFLICT DO NOTHING;
 PERFORM public.hyt_contest_year_refresh(year) FROM public.hyt_contest_year_dirty WHERE year<extract(year FROM now() AT TIME ZONE 'Asia/Shanghai') ORDER BY year;
END;
$$;
CREATE OR REPLACE FUNCTION public.hyt_contest_year_refresh(y int) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
BEGIN
 IF y>=extract(year FROM now() AT TIME ZONE 'Asia/Shanghai') THEN RETURN; END IF;
 PERFORM pg_advisory_xact_lock(hashtext('contest-year:'||y::text));
 UPDATE public.hyt_contest_year_awards SET revoked_at=now() WHERE year=y AND revoked_at IS NULL;
 WITH scores AS (SELECT a.member_id,sum(CASE a.kind WHEN 'champion' THEN 5 WHEN 'silver' THEN 3 WHEN 'bronze' THEN 2 WHEN 'excellent' THEN 1 ELSE 0 END)::int AS score
  FROM public.hyt_contest_awards a JOIN public.hyt_contests c ON c.id=a.contest_id WHERE a.revoked_at IS NULL AND c.announced_at IS NOT NULL AND NOT c.cancelled AND extract(year FROM a.awarded_at AT TIME ZONE 'Asia/Shanghai')=y GROUP BY a.member_id),
 leaders AS (SELECT *,dense_rank() OVER(ORDER BY score DESC) AS place FROM scores WHERE score>0)
 INSERT INTO public.hyt_contest_year_awards(year,member_id,score) SELECT y,member_id,score FROM leaders WHERE place=1
 ON CONFLICT(year,member_id) DO UPDATE SET score=excluded.score,revoked_at=NULL;
 DELETE FROM public.hyt_contest_year_dirty WHERE year=y;
END;
$$;
CREATE OR REPLACE FUNCTION public.hyt_contest_tick() RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
DECLARE c public.hyt_contests; n int:=0; y int; highest int;
BEGIN
 FOR c IN SELECT * FROM public.hyt_contests WHERE published AND NOT cancelled AND NOT paused AND award_at<=now() AND announced_at IS NULL AND auto_publish ORDER BY award_at LIMIT 20 LOOP
  -- Recheck after the same event lock used by moderation and settlement.
  PERFORM pg_advisory_xact_lock(hashtext('contest:'||c.id::text));
  SELECT current_event.* INTO c FROM public.hyt_contests current_event WHERE current_event.id=c.id;
  IF NOT c.published OR c.cancelled OR c.paused OR NOT c.auto_publish OR c.announced_at IS NOT NULL OR c.award_at>clock_timestamp() THEN CONTINUE; END IF;
  IF EXISTS(SELECT 1 FROM public.hyt_contest_reports r JOIN public.hyt_contest_entries e ON e.id=r.entry_id WHERE e.contest_id=c.id AND r.resolved_at IS NULL) THEN CONTINUE; END IF;
  IF EXISTS(SELECT 1 FROM public.hyt_contest_votes WHERE contest_id=c.id AND enabled AND risk IS NOT NULL AND risk NOT IN ('young_account','rapid_votes') AND NOT excluded) THEN CONTINUE; END IF;
  PERFORM public.hyt_contest_settle(c.id);
  UPDATE public.hyt_contests SET announced_at=now() WHERE id=c.id AND announced_at IS NULL;
  PERFORM public.hyt_contest_achievements_refresh(c.id);
  INSERT INTO public.hyt_contest_audit(contest_id,action,reason) VALUES(c.id,'auto_announce','定时结算，无待复核风险票'); n:=n+1;
 END LOOP;
 FOR y IN SELECT year FROM public.hyt_contest_year_dirty WHERE year<extract(year FROM now() AT TIME ZONE 'Asia/Shanghai') ORDER BY year LOOP
  PERFORM public.hyt_contest_year_refresh(y);
 END LOOP;
 RETURN jsonb_build_object('announced',n,'serverTime',now());
END;
$$;

CREATE OR REPLACE FUNCTION public.hyt_contests(a text,b jsonb,th text) RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,public AS $contest$
#variable_conflict use_column
DECLARE previous_operation public.hyt_contest_operations; m public.hyt_members; c public.hyt_contests; e public.hyt_contest_entries; old public.hyt_contest_entries;
 p public.hyt_posts; t public.hyt_contest_themes; v public.hyt_contest_votes;
 cid uuid:=(b->>'contestId')::uuid; target uuid; result jsonb; rows jsonb; n int; delta int; off_n int:=coalesce((b->>'offset')::int,0); op text; stamp timestamptz:=clock_timestamp();
 admin boolean; mutation boolean:=a NOT IN ('contests.list','contests.get','contests.entries','contests.profile','contests.year','contests.themes','contests.admin','contests.image','contests.schedule');
BEGIN
 IF (a='contests.review' AND b->>'kind' IN ('theme','merge')) OR (a='contests.manage' AND b->>'operation'='solicitation') THEN cid:=NULL; END IF;
 SELECT u.* INTO m FROM public.hyt_sessions s JOIN public.hyt_members u ON u.id=s.member_id WHERE s.hash=th AND s.expires_at>now() AND u.deleted_at IS NULL;
 IF NOT FOUND THEN RETURN '{"status":401,"error":"session_expired"}'::jsonb; END IF;
 admin:=m.developer_since IS NOT NULL AND NOT coalesce(m.banned_until>now(),false);
 IF mutation AND m.banned_until>now() THEN RETURN '{"status":403,"error":"account_muted"}'::jsonb; END IF;
 IF a IN ('contests.save','contests.manage','contests.review','contests.admin','contests.schedule') AND NOT admin THEN RETURN '{"status":403,"error":"forbidden"}'::jsonb; END IF;
 IF mutation THEN
  PERFORM pg_advisory_xact_lock(hashtext('contest-member:'||m.id::text));
  IF a IN ('contests.suggest','contests.themevote') OR (a='contests.review' AND b->>'kind' IN ('theme','merge')) OR (a='contests.manage' AND b->>'operation'='solicitation') THEN PERFORM pg_advisory_xact_lock(hashtext('contest:global')); END IF;
  PERFORM pg_advisory_xact_lock(hashtext('contest:'||coalesce(cid::text,'global')));
  -- Recheck role and mute state inside the transaction after acquiring the serialization lock.
  SELECT * INTO m FROM public.hyt_members WHERE id=m.id;
  IF m.deleted_at IS NOT NULL OR m.banned_until>now() THEN RETURN '{"status":403,"error":"forbidden"}'::jsonb; END IF;
  IF a IN ('contests.save','contests.manage','contests.review') AND m.developer_since IS NULL THEN RETURN '{"status":403,"error":"forbidden"}'::jsonb; END IF;
 END IF;
 IF a IN ('contests.save','contests.manage','contests.review') AND b->>'requestId' IS NOT NULL THEN
  SELECT * INTO previous_operation FROM public.hyt_contest_operations WHERE member_id=m.id AND request_id=(b->>'requestId')::uuid;
  IF FOUND THEN
   IF previous_operation.action<>a OR previous_operation.payload<>b THEN RETURN '{"status":409,"error":"request_conflict"}'; END IF;
   RETURN previous_operation.result;
  END IF;
 END IF;
 IF a='contests.schedule' THEN
  SELECT * INTO c FROM public.hyt_contests WHERE id=cid;
  RETURN jsonb_build_object('status',200,'contest',CASE WHEN c.id IS NULL THEN NULL ELSE public.hyt_contest_json(c)||jsonb_build_object('published',c.published,'cancelled',c.cancelled) END);
 END IF;
 IF a='contests.list' THEN
  SELECT coalesce(jsonb_agg(public.hyt_contest_json(q) ORDER BY CASE WHEN q.cancelled THEN 4 WHEN q.announced_at IS NOT NULL THEN 3 WHEN NOT q.published THEN 5 WHEN q.starts_at>now() THEN 2 ELSE 1 END,CASE WHEN q.starts_at>now() THEN q.starts_at END ASC,q.starts_at DESC),'[]') INTO rows FROM
   (SELECT * FROM public.hyt_contests WHERE (published OR admin) AND (coalesce(b->>'type','')='' OR type=b->>'type') AND (coalesce((b->>'year')::int,0)=0 OR extract(year FROM starts_at AT TIME ZONE 'Asia/Shanghai')=(b->>'year')::int)
    ORDER BY CASE WHEN cancelled THEN 4 WHEN announced_at IS NOT NULL THEN 3 WHEN NOT published THEN 5 WHEN starts_at>now() THEN 2 ELSE 1 END, CASE WHEN starts_at>now() THEN starts_at END ASC,starts_at DESC,id LIMIT 21 OFFSET off_n) q;
  RETURN jsonb_build_object('status',200,'contests',rows,'serverTime',now());
 END IF;
 IF a='contests.profile' OR a='contests.year' THEN
  target:=coalesce((b->>'memberId')::uuid,m.id);
  IF a='contests.year' THEN
   SELECT coalesce(jsonb_agg(to_jsonb(q)),'[]') INTO rows FROM (SELECT u.id,u.nickname,sum(CASE aw.kind WHEN 'champion' THEN 5 WHEN 'silver' THEN 3 WHEN 'bronze' THEN 2 WHEN 'excellent' THEN 1 ELSE 0 END)::int AS score
    FROM public.hyt_contest_awards aw JOIN public.hyt_contests cc ON cc.id=aw.contest_id JOIN public.hyt_members u ON u.id=aw.member_id
    WHERE aw.revoked_at IS NULL AND cc.announced_at IS NOT NULL AND NOT cc.cancelled AND u.deleted_at IS NULL AND extract(year FROM aw.awarded_at AT TIME ZONE 'Asia/Shanghai')=(b->>'year')::int
    GROUP BY u.id,u.nickname HAVING sum(CASE aw.kind WHEN 'champion' THEN 5 WHEN 'silver' THEN 3 WHEN 'bronze' THEN 2 WHEN 'excellent' THEN 1 ELSE 0 END)>0 ORDER BY score DESC,u.id LIMIT 21 OFFSET off_n) q;
   RETURN jsonb_build_object('status',200,'leaders',rows);
  END IF;
  SELECT jsonb_build_object('participations',count(DISTINCT contest_id) FILTER(WHERE kind='participation'),'champions',count(*) FILTER(WHERE kind='champion'),'podiums',count(*) FILTER(WHERE kind IN ('champion','silver','bronze'))) INTO result
   FROM public.hyt_contest_awards aw JOIN public.hyt_contests cc ON cc.id=aw.contest_id WHERE aw.member_id=target AND aw.revoked_at IS NULL AND cc.announced_at IS NOT NULL AND NOT cc.cancelled;
  SELECT coalesce(jsonb_agg(to_jsonb(q)),'[]') INTO rows FROM (SELECT aw.* FROM public.hyt_contest_awards aw JOIN public.hyt_contests cc ON cc.id=aw.contest_id WHERE aw.member_id=target AND aw.revoked_at IS NULL AND cc.announced_at IS NOT NULL AND NOT cc.cancelled ORDER BY awarded_at DESC,aw.id LIMIT 21 OFFSET off_n) q;
  RETURN jsonb_build_object('status',200,'stats',result,'awards',rows,'worn',(SELECT award_id FROM public.hyt_contest_worn w JOIN public.hyt_contest_awards aw ON aw.id=w.award_id JOIN public.hyt_contests cc ON cc.id=aw.contest_id WHERE w.member_id=target AND aw.revoked_at IS NULL AND cc.announced_at IS NOT NULL AND NOT cc.cancelled),
   'achievements',(SELECT coalesce(jsonb_agg(jsonb_build_object('code',code,'at',unlocked_at)),'[]') FROM public.hyt_contest_achievements WHERE member_id=target AND revoked_at IS NULL),
   'annual',(SELECT coalesce(jsonb_agg(year),'[]') FROM public.hyt_contest_year_awards WHERE member_id=target AND revoked_at IS NULL));
 END IF;
 IF a='contests.wear' THEN
  IF b->>'awardId' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.hyt_contest_awards aw JOIN public.hyt_contests cc ON cc.id=aw.contest_id WHERE aw.id=(b->>'awardId')::uuid AND aw.member_id=m.id AND aw.revoked_at IS NULL AND cc.announced_at IS NOT NULL AND NOT cc.cancelled) THEN RETURN '{"status":403,"error":"forbidden"}'; END IF;
  INSERT INTO public.hyt_contest_worn VALUES(m.id,(b->>'awardId')::uuid) ON CONFLICT(member_id) DO UPDATE SET award_id=excluded.award_id;
  RETURN '{"status":200}';
 END IF;
 IF a IN ('contests.themes','contests.suggest','contests.themevote') THEN
  IF a='contests.suggest' THEN
   IF NOT (SELECT solicitation FROM public.hyt_contest_settings WHERE id) THEN RETURN '{"status":409,"error":"contest_closed"}'; END IF;
   SELECT * INTO t FROM public.hyt_contest_themes WHERE member_id=m.id AND request_id=(b->>'requestId')::uuid;
   IF FOUND AND t.title<>b->>'title' THEN RETURN '{"status":409,"error":"request_conflict"}'; END IF;
   IF t.id IS NULL AND (SELECT count(*) FROM public.hyt_contest_themes WHERE member_id=m.id AND created_at>now()-interval '1 day')>=3 THEN RETURN '{"status":429,"error":"too_many_requests"}'; END IF;
   INSERT INTO public.hyt_contest_themes(member_id,title,request_id) VALUES(m.id,b->>'title',(b->>'requestId')::uuid) ON CONFLICT(member_id,request_id) DO NOTHING;
  ELSIF a='contests.themevote' THEN
   IF NOT (SELECT solicitation FROM public.hyt_contest_settings WHERE id) OR NOT EXISTS(SELECT 1 FROM public.hyt_contest_themes WHERE id=(b->>'themeId')::uuid AND status='approved') THEN RETURN '{"status":409,"error":"contest_closed"}'; END IF;
   IF (b->>'enabled')::boolean THEN INSERT INTO public.hyt_contest_theme_votes VALUES((b->>'themeId')::uuid,m.id) ON CONFLICT DO NOTHING;
   ELSE DELETE FROM public.hyt_contest_theme_votes WHERE theme_id=(b->>'themeId')::uuid AND member_id=m.id; END IF;
  END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(q)),'[]') INTO rows FROM (SELECT t.id,t.title,t.status,t.merged_into,(SELECT count(*) FROM public.hyt_contest_theme_votes WHERE theme_id=t.id) AS votes,EXISTS(SELECT 1 FROM public.hyt_contest_theme_votes WHERE theme_id=t.id AND member_id=m.id) AS voted FROM public.hyt_contest_themes t WHERE status='approved' OR admin OR member_id=m.id ORDER BY created_at DESC,id LIMIT 21 OFFSET off_n) q;
  RETURN jsonb_build_object('status',200,'themes',rows,'solicitation',(SELECT solicitation FROM public.hyt_contest_settings WHERE id));
 END IF;
 IF a='contests.save' THEN
  SELECT * INTO c FROM public.hyt_contests WHERE id=cid;
  IF FOUND AND (c.cancelled OR c.announced_at IS NOT NULL) THEN RETURN '{"status":409,"error":"contest_closed"}'; END IF;
  IF c.id IS NOT NULL AND b->>'expectedVersion' IS NOT NULL AND c.version<>(b->>'expectedVersion')::int THEN RETURN '{"status":409,"error":"contest_conflict"}'; END IF;
  -- Rules and eligibility become immutable at opening. Extensions only move future deadlines forward.
  IF c.published AND now()>=c.starts_at AND (c.title<>b->>'title' OR c.type<>b->>'type' OR c.rules<>b->>'rules' OR c.formats<>ARRAY(SELECT jsonb_array_elements_text(b->'formats')) OR c.votes_per_user<>(b->>'votesPerUser')::int OR c.min_entries<>(b->>'minEntries')::int OR c.max_entries<>(b->>'maxEntries')::int OR c.min_account_hours<>(b->>'minAccountHours')::int OR c.excellence<>(b->>'excellence')::int OR c.risk_review<>coalesce((b->>'reviewRisk')::boolean,true) OR c.starts_at<>(b->>'startsAt')::timestamptz OR c.submission_ends>(b->>'submissionEnds')::timestamptz OR c.voting_starts>(b->>'votingStarts')::timestamptz OR c.voting_ends>(b->>'votingEnds')::timestamptz OR c.award_at>(b->>'awardAt')::timestamptz OR (now()>=c.submission_ends AND c.submission_ends<>(b->>'submissionEnds')::timestamptz) OR (now()>=c.voting_starts AND c.voting_starts<>(b->>'votingStarts')::timestamptz) OR (now()>=c.voting_ends AND c.voting_ends<>(b->>'votingEnds')::timestamptz)) THEN RETURN '{"status":409,"error":"contest_rules_locked"}'; END IF;
  IF NOT ((b->>'startsAt')::timestamptz<(b->>'submissionEnds')::timestamptz AND (b->>'submissionEnds')::timestamptz<=(b->>'votingStarts')::timestamptz AND (b->>'votingStarts')::timestamptz<(b->>'votingEnds')::timestamptz AND (b->>'votingEnds')::timestamptz<=(b->>'awardAt')::timestamptz) THEN RETURN '{"status":400,"error":"invalid_request"}'; END IF;
  INSERT INTO public.hyt_contests(id,title,type,edition,description,rules,cover_post_id,starts_at,submission_ends,voting_starts,voting_ends,award_at,formats,max_entries,votes_per_user,min_entries,min_account_hours,excellence,auto_publish,risk_review,published)
  VALUES(cid,b->>'title',b->>'type',b->>'edition',b->>'description',b->>'rules',(b->>'coverPostId')::uuid,(b->>'startsAt')::timestamptz,(b->>'submissionEnds')::timestamptz,(b->>'votingStarts')::timestamptz,(b->>'votingEnds')::timestamptz,(b->>'awardAt')::timestamptz,ARRAY(SELECT jsonb_array_elements_text(b->'formats')),(b->>'maxEntries')::int,(b->>'votesPerUser')::int,(b->>'minEntries')::int,(b->>'minAccountHours')::int,(b->>'excellence')::int,(b->>'autoPublish')::boolean,coalesce((b->>'reviewRisk')::boolean,true),coalesce((b->>'publish')::boolean,false))
  ON CONFLICT(id) DO UPDATE SET title=excluded.title,type=excluded.type,edition=excluded.edition,description=excluded.description,rules=excluded.rules,cover_post_id=excluded.cover_post_id,starts_at=excluded.starts_at,submission_ends=excluded.submission_ends,voting_starts=excluded.voting_starts,voting_ends=excluded.voting_ends,award_at=excluded.award_at,formats=excluded.formats,max_entries=excluded.max_entries,votes_per_user=excluded.votes_per_user,min_entries=excluded.min_entries,min_account_hours=excluded.min_account_hours,excellence=excluded.excellence,auto_publish=excluded.auto_publish,risk_review=excluded.risk_review,published=hyt_contests.published OR excluded.published,version=hyt_contests.version+1;
  INSERT INTO public.hyt_contest_audit(contest_id,actor_id,action,reason,snapshot) VALUES(cid,m.id,a,'保存赛事',to_jsonb(c));
 END IF;
 IF cid IS NOT NULL THEN
  SELECT * INTO c FROM public.hyt_contests WHERE id=cid;
  IF NOT FOUND OR (NOT c.published AND NOT admin) THEN RETURN '{"status":404,"error":"not_found"}'; END IF;
 END IF;
 IF a='contests.manage' THEN
  op:=b->>'operation';
  IF b->>'expectedVersion' IS NOT NULL AND c.id IS NOT NULL AND c.version<>(b->>'expectedVersion')::int THEN RETURN '{"status":409,"error":"contest_conflict"}'; END IF;
  IF c.cancelled AND op<>'solicitation' THEN RETURN '{"status":409,"error":"contest_closed"}'; END IF;
  IF op='publish' THEN UPDATE public.hyt_contests SET published=true WHERE id=cid;
  ELSIF op='pause' THEN UPDATE public.hyt_contests SET paused=true WHERE id=cid AND announced_at IS NULL;
  ELSIF op='resume' THEN UPDATE public.hyt_contests SET paused=false WHERE id=cid;
  ELSIF op='cancel' THEN
   UPDATE public.hyt_contests SET cancelled=true WHERE id=cid;
   UPDATE public.hyt_contest_awards SET revoked_at=coalesce(revoked_at,now()) WHERE contest_id=cid;
  ELSIF op='solicitation' THEN UPDATE public.hyt_contest_settings SET solicitation=(b->>'enabled')::boolean WHERE id;
  ELSIF op='announce' THEN
   IF c.paused OR clock_timestamp()<c.award_at THEN RETURN '{"status":409,"error":"contest_closed"}'; END IF;
   IF EXISTS(SELECT 1 FROM public.hyt_contest_votes WHERE contest_id=cid AND enabled AND risk IS NOT NULL AND risk NOT IN ('young_account','rapid_votes') AND NOT excluded) THEN RETURN '{"status":409,"error":"contest_review_pending"}'; END IF;
   IF EXISTS(SELECT 1 FROM public.hyt_contest_reports r JOIN public.hyt_contest_entries e ON e.id=r.entry_id WHERE e.contest_id=cid AND r.resolved_at IS NULL) THEN RETURN '{"status":409,"error":"contest_review_pending"}'; END IF;
   IF c.announced_at IS NULL THEN PERFORM public.hyt_contest_settle(cid); UPDATE public.hyt_contests SET announced_at=now() WHERE id=cid; END IF;
  END IF;
  INSERT INTO public.hyt_contest_audit(contest_id,actor_id,action,reason,snapshot) VALUES(cid,m.id,op,b->>'reason',to_jsonb(c));
  IF cid IS NOT NULL THEN UPDATE public.hyt_contests SET version=version+1 WHERE id=cid; PERFORM public.hyt_contest_achievements_refresh(cid); END IF;
 END IF;
 IF a='contests.submit' THEN
  SELECT entry_id,payload INTO target,result FROM public.hyt_contest_requests WHERE member_id=m.id AND request_id=(b->>'requestId')::uuid;
  IF FOUND THEN
   IF (result||jsonb_build_object('expectedVersion',result->'expectedVersion'))<>(b||jsonb_build_object('expectedVersion',b->'expectedVersion')) THEN RETURN '{"status":409,"error":"request_conflict"}'; END IF;
   SELECT * INTO e FROM public.hyt_contest_entries WHERE id=target;
   RETURN jsonb_build_object('status',200,'entry',public.hyt_contest_entry_json(e,m.id));
  END IF;
  IF c.cancelled OR c.paused OR public.hyt_contest_state(c)<>'submitting' THEN RETURN '{"status":409,"error":"contest_closed"}'; END IF;
  IF b->>'agreed'<>'true' THEN RETURN '{"status":400,"error":"agreement_required"}'; END IF;
  IF b->>'entryId' IS NOT NULL THEN
   SELECT * INTO old FROM public.hyt_contest_entries WHERE id=(b->>'entryId')::uuid AND contest_id=cid AND member_id=m.id AND status='approved';
   IF NOT FOUND THEN RETURN '{"status":403,"error":"forbidden"}'; END IF;
  ELSE
   IF (SELECT count(*) FROM public.hyt_contest_entries WHERE contest_id=cid AND member_id=m.id AND status='approved')>=c.max_entries THEN RETURN '{"status":409,"error":"contest_entry_limit"}'; END IF;
  END IF;
  IF old.id IS NOT NULL AND b->>'expectedVersion' IS NOT NULL AND old.version<>(b->>'expectedVersion')::int THEN RETURN '{"status":409,"error":"contest_conflict"}'; END IF;
  IF b->>'postId' IS NOT NULL AND (old.id IS NULL OR old.linked OR (b->>'linkPost')::boolean OR old.post_id IS DISTINCT FROM (b->>'postId')::uuid) THEN
   SELECT * INTO p FROM public.hyt_posts WHERE id=(b->>'postId')::uuid AND author_id=m.id AND deleted_at IS NULL AND NOT anonymous;
   IF NOT FOUND THEN RETURN '{"status":403,"error":"forbidden"}'; END IF;
   -- A single original post can participate once per event; edits keep a stable snapshot.
   IF EXISTS(SELECT 1 FROM public.hyt_contest_entries WHERE contest_id=cid AND post_id=p.id AND status='approved' AND id IS DISTINCT FROM old.id) THEN RETURN '{"status":409,"error":"request_conflict"}'; END IF;
  END IF;
  n:=jsonb_array_length(b->'images');
  IF p.id IS NOT NULL THEN SELECT count(*) INTO n FROM public.hyt_media WHERE post_id=p.id AND comment_id IS NULL AND ready AND deleted_at IS NULL; END IF;
  op:=CASE WHEN n=0 THEN 'text' WHEN coalesce(nullif(p.body,''),b->>'body','')='' THEN 'image' ELSE 'mixed' END;
  IF NOT op=ANY(c.formats) OR (n=0 AND coalesce(p.body,b->>'body','')='') THEN RETURN '{"status":400,"error":"contest_format"}'; END IF;
  IF p.id IS NULL AND EXISTS(SELECT 1 FROM jsonb_array_elements_text(b->'images') ref WHERE NOT EXISTS(SELECT 1 FROM public.hyt_media i WHERE i.id=ref::uuid AND i.member_id=m.id AND i.ready AND i.deleted_at IS NULL AND i.purpose='post' AND (i.post_id IS NULL OR (old.id IS NOT NULL AND i.contest_entry_id=old.id AND i.post_id=old.post_id)) AND (i.contest_entry_id IS NULL OR i.contest_entry_id=old.id))) THEN RETURN '{"status":409,"error":"image_unavailable"}'; END IF;
  IF old.id IS NOT NULL THEN
   UPDATE public.hyt_contest_entries SET title=b->>'title',body=coalesce(p.body,b->>'body'),post_id=CASE WHEN old.linked THEN p.id ELSE coalesce(p.id,old.post_id) END,linked=p.id IS NOT NULL,version=version+1,updated_at=now() WHERE id=old.id RETURNING * INTO e;
   UPDATE public.hyt_media SET contest_entry_id=NULL WHERE contest_entry_id=e.id;
  ELSE
   INSERT INTO public.hyt_contest_entries(contest_id,member_id,request_id,title,body,post_id,linked) VALUES(cid,m.id,(b->>'requestId')::uuid,b->>'title',coalesce(p.body,b->>'body'),p.id,p.id IS NOT NULL) RETURNING * INTO e;
  END IF;
  IF p.id IS NULL THEN
   UPDATE public.hyt_media i SET contest_entry_id=e.id,position=r.ord FROM jsonb_array_elements_text(b->'images') WITH ORDINALITY r(ref,ord) WHERE i.id=r.ref::uuid;
  ELSE
   -- Linked posts are owned originals. Their images remain governed by ordinary deletion permissions.
   NULL;
  END IF;
  IF (b->>'share')::boolean AND p.id IS NULL AND old.id IS NULL THEN
   result:=public.hyt_community('posts.create',jsonb_build_object('body',left(e.body,2700)||E'\n参赛作品 · '||c.title||E'\n'||e.title,'title',e.title,'category','daily','anonymous',false,'requestId',b->>'requestId','images',coalesce(b->'images','[]'::jsonb)),th);
   IF (result->>'status')::int>=400 THEN RAISE EXCEPTION 'community_share_failed'; END IF;
   UPDATE public.hyt_contest_entries SET post_id=(result->'post'->>'id')::uuid WHERE id=e.id RETURNING * INTO e;
  END IF;
  INSERT INTO public.hyt_contest_audit(contest_id,actor_id,action,target_id,reason,snapshot) VALUES(cid,m.id,'submit',e.id,'投稿或修订',to_jsonb(old));
  INSERT INTO public.hyt_contest_requests(member_id,request_id,entry_id,payload) VALUES(m.id,(b->>'requestId')::uuid,e.id,b);
  RETURN jsonb_build_object('status',200,'entry',public.hyt_contest_entry_json(e,m.id));
 END IF;
 IF a='contests.image' THEN
  SELECT * INTO e FROM public.hyt_contest_entries WHERE id=(b->>'entryId')::uuid AND contest_id=cid AND (status='approved' OR member_id=m.id OR admin);
  IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'; END IF;
  SELECT public.hyt_media_json(i) INTO result FROM public.hyt_media i WHERE i.id=(b->>'imageId')::uuid AND (i.contest_entry_id=e.id OR (e.linked AND i.post_id=e.post_id AND i.comment_id IS NULL)) AND i.ready AND i.deleted_at IS NULL;
  IF result IS NULL THEN RETURN '{"status":404,"error":"not_found"}'; END IF;
  RETURN jsonb_build_object('status',200,'image',result);
 END IF;
 IF a='contests.withdraw' THEN
  IF c.cancelled OR c.paused OR public.hyt_contest_state(c)<>'submitting' THEN RETURN '{"status":409,"error":"contest_closed"}'; END IF;
  SELECT * INTO e FROM public.hyt_contest_entries WHERE id=(b->>'entryId')::uuid AND contest_id=cid AND member_id=m.id;
  IF NOT FOUND OR e.status='removed' THEN RETURN '{"status":404,"error":"not_found"}'; END IF;
  IF e.status='withdrawn' THEN RETURN jsonb_build_object('status',200,'contest',public.hyt_contest_json(c)); END IF;
  UPDATE public.hyt_contest_entries SET status='withdrawn',updated_at=now() WHERE id=e.id RETURNING * INTO e;
  INSERT INTO public.hyt_contest_audit(contest_id,actor_id,action,target_id,reason,snapshot) VALUES(cid,m.id,'withdraw',e.id,'截止前撤稿',to_jsonb(e));
 END IF;
 IF a='contests.vote' THEN
  IF c.cancelled OR c.paused THEN RETURN '{"status":409,"error":"contest_closed"}'; END IF;
  SELECT * INTO e FROM public.hyt_contest_entries WHERE id=(b->>'entryId')::uuid AND contest_id=cid AND status='approved';
  IF NOT FOUND OR e.member_id=m.id THEN RETURN '{"status":403,"error":"contest_self_vote"}'; END IF;
  SELECT * INTO v FROM public.hyt_contest_votes WHERE entry_id=e.id AND member_id=m.id;
  IF (v.id IS NULL OR v.enabled IS DISTINCT FROM (b->>'enabled')::boolean) THEN
   IF public.hyt_contest_state(c)<>'voting' THEN RETURN '{"status":409,"error":"contest_closed"}'; END IF;
   IF c.min_account_hours>0 AND m.created_at>c.voting_starts-make_interval(hours=>c.min_account_hours) THEN RETURN '{"status":403,"error":"contest_ineligible"}'; END IF;
   IF coalesce(v.enabled,false) IS DISTINCT FROM (b->>'enabled')::boolean THEN
    IF (b->>'enabled')::boolean AND (SELECT count(*) FROM public.hyt_contest_votes WHERE contest_id=cid AND member_id=m.id AND enabled)>=c.votes_per_user THEN RETURN '{"status":409,"error":"contest_vote_limit"}'; END IF;
    n:=CASE WHEN v.window_started_at>stamp-interval '1 minute' THEN v.window_changes+1 ELSE 1 END;
    op:=CASE WHEN c.risk_review AND n>=CASE WHEN m.created_at>c.voting_starts-interval '7 days' THEN 12 ELSE 30 END THEN 'vote_burst' ELSE NULL END;
    delta:=CASE WHEN (b->>'enabled')::boolean THEN 1 ELSE -1 END;
    INSERT INTO public.hyt_contest_votes(contest_id,entry_id,member_id,enabled,risk,window_started_at,window_changes)
     VALUES(cid,e.id,m.id,(b->>'enabled')::boolean,op,stamp,1)
     ON CONFLICT(entry_id,member_id) DO UPDATE SET enabled=excluded.enabled,risk=coalesce(op,hyt_contest_votes.risk),window_started_at=CASE WHEN hyt_contest_votes.window_started_at>stamp-interval '1 minute' THEN hyt_contest_votes.window_started_at ELSE stamp END,window_changes=n;
    IF NOT coalesce(v.excluded,false) THEN UPDATE public.hyt_contest_entries SET votes=votes+delta WHERE id=e.id RETURNING * INTO e; END IF;
   END IF;
  END IF;
  RETURN jsonb_build_object('status',200,'entry',public.hyt_contest_entry_json(e,m.id,admin),'serverTime',now(),'votesUsed',(SELECT count(*) FROM public.hyt_contest_votes WHERE contest_id=cid AND member_id=m.id AND enabled));
 END IF;
 IF a='contests.report' THEN
  IF NOT EXISTS(SELECT 1 FROM public.hyt_contest_entries WHERE id=(b->>'entryId')::uuid AND contest_id=cid AND status='approved') THEN RETURN '{"status":404,"error":"not_found"}'; END IF;
  INSERT INTO public.hyt_contest_reports(entry_id,member_id,reason) VALUES((b->>'entryId')::uuid,m.id,b->>'reason') ON CONFLICT DO NOTHING;
  RETURN '{"status":200}';
 END IF;
 IF a='contests.review' THEN
  target:=(b->>'targetId')::uuid;op:=b->>'kind';
  IF (op='vote' AND b->>'decision' NOT IN ('valid','exclude')) OR (op<>'vote' AND b->>'decision' NOT IN ('approve','remove')) THEN RETURN '{"status":400,"error":"invalid_request"}'; END IF;
  IF op='entry' THEN
   SELECT * INTO e FROM public.hyt_contest_entries WHERE id=target AND contest_id=cid;
   IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'; END IF;
   IF b->>'decision'='approve' AND EXISTS(SELECT 1 FROM public.hyt_members WHERE id=e.member_id AND deleted_at IS NOT NULL) THEN RETURN '{"status":404,"error":"not_found"}'; END IF;
   IF b->>'decision'='remove' THEN
    UPDATE public.hyt_contest_votes SET enabled=false WHERE entry_id=target AND enabled;
    UPDATE public.hyt_contest_entries SET votes=0 WHERE id=target;
   END IF;
   UPDATE public.hyt_contest_entries SET status=CASE WHEN b->>'decision'='approve' THEN 'approved' ELSE 'removed' END WHERE id=target;
   UPDATE public.hyt_contest_reports SET resolved_at=now() WHERE entry_id=target;
  ELSIF op='vote' THEN
   SELECT * INTO v FROM public.hyt_contest_votes WHERE id=target AND contest_id=cid;
   IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'; END IF;
   IF v.enabled AND v.excluded IS DISTINCT FROM (b->>'decision'='exclude') THEN UPDATE public.hyt_contest_entries SET votes=votes+CASE WHEN b->>'decision'='exclude' THEN -1 ELSE 1 END WHERE id=v.entry_id; END IF;
   UPDATE public.hyt_contest_votes SET excluded=(b->>'decision'='exclude'),risk=NULL WHERE id=target;
  ELSE
   IF op='merge' AND (target=(b->>'mergeId')::uuid OR NOT EXISTS(SELECT 1 FROM public.hyt_contest_themes WHERE id=(b->>'mergeId')::uuid AND status='approved')) THEN RETURN '{"status":400,"error":"invalid_request"}'; END IF;
   SELECT * INTO t FROM public.hyt_contest_themes WHERE id=target;
   IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'; END IF;
   IF op='merge' THEN
    INSERT INTO public.hyt_contest_theme_votes(theme_id,member_id) SELECT (b->>'mergeId')::uuid,member_id FROM public.hyt_contest_theme_votes WHERE theme_id=target ON CONFLICT DO NOTHING;
    DELETE FROM public.hyt_contest_theme_votes WHERE theme_id=target;
   END IF;
   UPDATE public.hyt_contest_themes SET status=CASE WHEN op='merge' THEN 'merged' WHEN b->>'decision'='approve' THEN 'approved' ELSE 'removed' END,merged_into=CASE WHEN op='merge' THEN (b->>'mergeId')::uuid END WHERE id=target;
  END IF;
  INSERT INTO public.hyt_contest_audit(contest_id,actor_id,action,target_id,reason,snapshot) VALUES(cid,m.id,op||':'||(b->>'decision'),target,b->>'reason',CASE op WHEN 'entry' THEN to_jsonb(e) WHEN 'vote' THEN to_jsonb(v) ELSE to_jsonb(t) END);
  IF op IN ('entry','vote') AND c.announced_at IS NOT NULL THEN PERFORM public.hyt_contest_settle(cid); PERFORM public.hyt_contest_achievements_refresh(cid); END IF;
 END IF;
 IF a='contests.admin' THEN
  RETURN jsonb_build_object('status',200,'votes',(SELECT coalesce(jsonb_agg(to_jsonb(q)),'[]') FROM (SELECT id,entry_id,member_id,enabled,excluded,risk,created_at FROM public.hyt_contest_votes WHERE contest_id=cid ORDER BY risk NULLS LAST,created_at DESC LIMIT 21 OFFSET off_n) q),
   'contestReports',(SELECT coalesce(jsonb_agg(to_jsonb(q)),'[]') FROM (SELECT r.*,public.hyt_contest_entry_json(e,m.id,true) AS entry FROM public.hyt_contest_reports r JOIN public.hyt_contest_entries e ON e.id=r.entry_id WHERE e.contest_id=cid AND r.resolved_at IS NULL ORDER BY r.created_at LIMIT 50) q),
   'audit',(SELECT coalesce(jsonb_agg(to_jsonb(q)),'[]') FROM (SELECT * FROM public.hyt_contest_audit WHERE contest_id=cid ORDER BY created_at DESC,id LIMIT 21 OFFSET off_n) q),
   'awards',(SELECT coalesce(jsonb_agg(to_jsonb(q)),'[]') FROM (SELECT * FROM public.hyt_contest_awards WHERE contest_id=cid ORDER BY awarded_at DESC,id LIMIT 21 OFFSET off_n) q),
   'metrics',jsonb_build_object('validVotes',(SELECT count(*) FROM public.hyt_contest_votes WHERE contest_id=cid AND enabled AND NOT excluded),'pendingReports',(SELECT count(*) FROM public.hyt_contest_reports r JOIN public.hyt_contest_entries e ON e.id=r.entry_id WHERE e.contest_id=cid AND r.resolved_at IS NULL),'votes',(SELECT count(*) FROM public.hyt_contest_votes WHERE contest_id=cid),'entries',(SELECT count(*) FROM public.hyt_contest_entries WHERE contest_id=cid),'images',(SELECT count(*) FROM public.hyt_media i JOIN public.hyt_contest_entries e ON e.id=i.contest_entry_id WHERE e.contest_id=cid),'pendingRisk',(SELECT count(*) FROM public.hyt_contest_votes WHERE contest_id=cid AND enabled AND risk IS NOT NULL AND risk NOT IN ('young_account','rapid_votes') AND NOT excluded)));
 END IF;
 IF a='contests.entries' THEN
  SELECT coalesce(jsonb_agg(public.hyt_contest_entry_json(q.entry,m.id,admin) ORDER BY q.sort_key),'[]') INTO rows FROM
   (SELECT e AS entry,md5(e.id::text||m.id::text||(b->>'seed')) AS sort_key FROM public.hyt_contest_entries e WHERE contest_id=cid AND (status='approved' OR admin OR e.member_id=m.id) AND (b->>'afterId' IS NULL OR md5(e.id::text||m.id::text||(b->>'seed'))>md5((b->>'afterId')::uuid::text||m.id::text||(b->>'seed'))) AND (NOT coalesce((b->>'mine')::boolean,false) OR member_id=m.id) AND (NOT coalesce((b->>'winnersOnly')::boolean,false) OR (c.announced_at IS NOT NULL AND EXISTS(SELECT 1 FROM public.hyt_contest_awards aw WHERE aw.entry_id=e.id AND aw.revoked_at IS NULL AND aw.kind<>'participation')))
    ORDER BY sort_key LIMIT 21 OFFSET off_n) q;
  RETURN jsonb_build_object('status',200,'entries',rows);
 END IF;
 SELECT * INTO c FROM public.hyt_contests WHERE id=cid;
 result:=CASE WHEN cid IS NULL THEN jsonb_build_object('status',200,'solicitation',(SELECT solicitation FROM public.hyt_contest_settings WHERE id)) ELSE jsonb_build_object('status',200,'contest',public.hyt_contest_json(c),'serverTime',now(),'votesUsed',(SELECT count(*) FROM public.hyt_contest_votes WHERE contest_id=cid AND member_id=m.id AND enabled),
 'myEntries',(SELECT coalesce(jsonb_agg(public.hyt_contest_entry_json(me,m.id,admin) ORDER BY me.created_at DESC),'[]') FROM public.hyt_contest_entries me WHERE me.contest_id=cid AND me.member_id=m.id AND me.status='approved')) END;
 IF a IN ('contests.save','contests.manage','contests.review') AND b->>'requestId' IS NOT NULL THEN INSERT INTO public.hyt_contest_operations(member_id,request_id,action,payload,result) VALUES(m.id,(b->>'requestId')::uuid,a,b,result); END IF;
 RETURN result;
END;
$contest$;
-- RPC functions are server-only, matching the existing service boundary.
DO $permissions$ DECLARE r text; f record; BEGIN
 FOR r IN SELECT rolname FROM pg_roles WHERE rolname IN ('anon','authenticated') LOOP
  FOR f IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'hyt_contest%' LOOP
   EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I',f.signature,r);
  END LOOP;
  FOR f IN SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename LIKE 'hyt_contest%' LOOP
   EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',f.tablename);
   EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC',f.tablename);
   EXECUTE format('REVOKE ALL ON TABLE public.%I FROM %I',f.tablename,r);
  END LOOP;
 END LOOP;
 FOR f IN SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename LIKE 'hyt_contest%' LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',f.tablename);
  EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC',f.tablename);
 END LOOP;
 FOR f IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'hyt_contest%' LOOP EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f.signature); END LOOP;
END $permissions$;

-- Community account deletion also removes submitted content and retracts its votes.
CREATE INDEX IF NOT EXISTS hyt_contest_vote_member ON public.hyt_contest_votes(member_id,contest_id);
CREATE OR REPLACE FUNCTION public.hyt_contest_member_deleted() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
DECLARE cid uuid;
BEGIN
 FOR cid IN SELECT contest_id FROM public.hyt_contest_entries WHERE member_id=NEW.id UNION SELECT contest_id FROM public.hyt_contest_votes WHERE member_id=NEW.id ORDER BY contest_id LOOP
  PERFORM pg_advisory_xact_lock(hashtext('contest:'||cid::text));
  UPDATE public.hyt_contest_entries SET status='removed',title='作品已删除',body='' WHERE contest_id=cid AND member_id=NEW.id;
  UPDATE public.hyt_contest_votes SET enabled=false WHERE entry_id IN (SELECT id FROM public.hyt_contest_entries WHERE contest_id=cid AND member_id=NEW.id);
  UPDATE public.hyt_contest_entries SET votes=0 WHERE contest_id=cid AND member_id=NEW.id;
  UPDATE public.hyt_contest_entries e SET votes=e.votes-q.total FROM
   (SELECT entry_id,count(*)::int AS total FROM public.hyt_contest_votes WHERE contest_id=cid AND member_id=NEW.id AND enabled AND NOT excluded GROUP BY entry_id) q WHERE e.id=q.entry_id;
  UPDATE public.hyt_contest_votes SET enabled=false WHERE contest_id=cid AND member_id=NEW.id;
  INSERT INTO public.hyt_contest_audit(contest_id,actor_id,action,reason) VALUES(cid,NEW.id,'account_deleted','账号注销，移除作品并撤回投票');
  IF EXISTS(SELECT 1 FROM public.hyt_contests WHERE id=cid AND announced_at IS NOT NULL) THEN PERFORM public.hyt_contest_settle(cid); END IF;
  PERFORM public.hyt_contest_achievements_refresh(cid);
 END LOOP;
 RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS hyt_contest_member_delete ON public.hyt_members;
CREATE TRIGGER hyt_contest_member_delete AFTER UPDATE OF deleted_at ON public.hyt_members FOR EACH ROW WHEN(OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL) EXECUTE FUNCTION public.hyt_contest_member_deleted();
REVOKE ALL ON FUNCTION public.hyt_contest_member_deleted() FROM PUBLIC;
