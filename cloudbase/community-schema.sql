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

-- Additive v2 migration. Old clients/posts retain their original identity and content.
ALTER TABLE public.hyt_posts ADD COLUMN IF NOT EXISTS title text NOT NULL DEFAULT '';
ALTER TABLE public.hyt_posts ADD COLUMN IF NOT EXISTS category text NOT NULL DEFAULT 'daily';
-- v5 adds discovery metadata without rewriting any existing category or identity.
ALTER TABLE public.hyt_posts ADD COLUMN IF NOT EXISTS interest text NOT NULL DEFAULT '';
ALTER TABLE public.hyt_posts DROP CONSTRAINT IF EXISTS hyt_posts_interest_check;
ALTER TABLE public.hyt_posts ADD CONSTRAINT hyt_posts_interest_check CHECK(interest='' OR (category='entertainment' AND interest IN ('games','anime','film','music','photo','sports')));
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
 kind text NOT NULL CHECK(kind IN ('same','hug','useful')), PRIMARY KEY(post_id,member_id)
);
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
CREATE OR REPLACE FUNCTION public.hyt_member_json(m public.hyt_members) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('id',m.id,'username',m.username,'nickname',m.nickname,'role',m.role,'bannedUntil',m.banned_until,'bio',m.bio,'avatar',public.hyt_avatar_json(m.id));
$$;
CREATE OR REPLACE FUNCTION public.hyt_author_json(uid uuid, pid uuid, anon boolean, viewer uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('name',CASE WHEN anon THEN '匿名同学 · '||coalesce(a.label,'隐藏') ELSE m.nickname END,
 'anonymous',anon,'mine',uid=viewer)||CASE WHEN anon THEN '{}'::jsonb ELSE jsonb_build_object('id',uid,'avatar',public.hyt_avatar_json(uid)) END
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
 'postTitle',left(CASE WHEN p.title<>'' THEN p.title ELSE p.body END,100),'excerpt',CASE WHEN n.kind='buddy' THEN '报名或招募状态有更新，点开查看当前情况' WHEN n.kind='post_response' THEN (SELECT CASE kind WHEN 'same' THEN '我也一样' WHEN 'hug' THEN '抱抱' ELSE '有用' END FROM public.hyt_responses WHERE post_id=p.id AND member_id=n.actor_id) ELSE left(coalesce(nullif(c.body,''),CASE WHEN c.id IS NOT NULL THEN '[图片]' ELSE coalesce(nullif(p.body,''),(SELECT definition->>'question' FROM public.hyt_polls WHERE post_id=p.id)) END),180) END,
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
 SELECT jsonb_build_object('id',u.id,'nickname',u.nickname,'bio',u.bio,'avatar',public.hyt_avatar_json(u.id),
 'following',EXISTS(SELECT 1 FROM public.hyt_follows f WHERE f.member_id=viewer AND f.followed_id=u.id),
 'postCount',(SELECT count(*) FROM public.hyt_posts p WHERE p.author_id=u.id AND NOT p.anonymous AND p.deleted_at IS NULL
 AND NOT EXISTS(SELECT 1 FROM public.hyt_hidden_threads h WHERE h.member_id=viewer AND h.post_id=p.id)));
$$;

-- Each call is a PostgreSQL transaction. The HTTP server is the only caller.
CREATE OR REPLACE FUNCTION public.hyt_community(a text,b jsonb,th text) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog,public AS $fn$
#variable_conflict use_column
DECLARE m public.hyt_members%ROWTYPE; p public.hyt_posts%ROWTYPE; c public.hyt_comments%ROWTYPE;
 report public.hyt_reports%ROWTYPE; target uuid; result jsonb; n int; k text; stamp timestamptz; limit_n int; anon boolean; img public.hyt_media%ROWTYPE; root uuid; snapshot timestamptz;
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
  INSERT INTO public.hyt_members(username,nickname,password_hash,recovery_hash)
  VALUES(b->>'username',b->>'nickname',b->>'passwordHash',b->>'recoveryHash') ON CONFLICT(username) DO NOTHING RETURNING * INTO m;
  IF NOT FOUND THEN RETURN '{"status":409,"error":"username_unavailable"}'::jsonb; END IF;
  INSERT INTO public.hyt_sessions(hash,member_id,expires_at) VALUES(th,m.id,now()+interval '30 days');
  RETURN jsonb_build_object('status',201,'user',public.hyt_member_json(m));
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
 -- Serialize follow/block changes for the same pair before locking either caller.
 IF a IN ('follows.set','blocks.set') THEN
  SELECT s.member_id INTO target FROM public.hyt_sessions s JOIN public.hyt_members u ON u.id=s.member_id
   WHERE s.hash=th AND s.expires_at>now() AND u.deleted_at IS NULL;
  IF target IS NOT NULL THEN
   IF a='follows.set' THEN k=b->>'memberId';
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
 IF a='notifications.read' THEN
  UPDATE public.hyt_notifications SET read_at=coalesce(read_at,now()) WHERE recipient_id=m.id AND id IN (SELECT value::uuid FROM jsonb_array_elements_text(b->'ids'));
  RETURN jsonb_build_object('status',200,'unreadCount',(SELECT count(*) FROM public.hyt_visible_notifications(m.id) WHERE read_at IS NULL));
 END IF;
 IF a IN ('notifications.list','notifications.unread') THEN
  SELECT count(*) INTO n FROM public.hyt_visible_notifications(m.id) WHERE read_at IS NULL;
  IF a='notifications.unread' THEN RETURN jsonb_build_object('status',200,'unreadCount',n); END IF;
  SELECT coalesce(jsonb_agg(public.hyt_notification_json(q,m.id) ORDER BY q.created_at DESC,q.id DESC),'[]'::jsonb) INTO result
  FROM (SELECT * FROM public.hyt_visible_notifications(m.id) WHERE
   (coalesce(b->>'filter','all')='all' OR (b->>'filter'='likes' AND kind IN ('post_like','comment_like','post_response')) OR (b->>'filter'='replies' AND kind IN ('reply','post_reply','thread_reply','buddy')))
   AND (b->>'beforeTime' IS NULL OR (created_at,id)<((b->>'beforeTime')::timestamptz,(b->>'beforeId')::uuid))
   ORDER BY created_at DESC,id DESC LIMIT 31) q;
  RETURN jsonb_build_object('status',200,'notifications',result,'unreadCount',n);
 END IF;
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
  RETURN jsonb_build_object('status',200,'posts',result,'snapshotTime',snapshot);
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
  RETURN jsonb_build_object('status',201,'post',public.hyt_post_json(p,m.id));
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
    IF EXISTS(SELECT 1 FROM public.hyt_blocks WHERE (member_id=m.id AND blocked_id=p.author_id) OR (member_id=p.author_id AND blocked_id=m.id)) THEN RETURN '{"status":403,"error":"forbidden"}'::jsonb; END IF;
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
    AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=c.author_id AND NOT c.anonymous)
    AND (b->>'afterTime' IS NULL OR (c.created_at,c.id)>((b->>'afterTime')::timestamptz,(b->>'afterId')::uuid)) ORDER BY c.created_at,c.id LIMIT 21) q;
  RETURN jsonb_build_object('status',200,'post',public.hyt_post_json(p,m.id),'comments',result);
 END IF;
 IF a IN ('posts.get','comments.replies') THEN
  IF a='comments.replies' AND NOT EXISTS(SELECT 1 FROM public.hyt_comments rc WHERE rc.id=(b->>'rootId')::uuid AND rc.post_id=p.id AND rc.reply_to IS NULL AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=rc.author_id AND NOT rc.anonymous)) THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
  SELECT coalesce(jsonb_agg(public.hyt_comment_json(q,m.id) ORDER BY q.created_at,q.id),'[]'::jsonb) INTO result FROM
   (SELECT c.* FROM public.hyt_comments c WHERE c.post_id=p.id
    AND (a='posts.get' OR c.root_id=(b->>'rootId')::uuid)
    AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=c.author_id AND NOT c.anonymous)
    AND (b->>'afterTime' IS NULL OR (c.created_at,c.id)>((b->>'afterTime')::timestamptz,(b->>'afterId')::uuid)) ORDER BY c.created_at,c.id LIMIT 51) q;
  RETURN jsonb_build_object('status',200,'post',public.hyt_post_json(p,m.id),'comments',result);
 END IF;
 IF a='comments.like' THEN
  SELECT * INTO c FROM public.hyt_comments c WHERE c.id=(b->>'commentId')::uuid AND c.post_id=p.id AND c.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=c.author_id AND NOT c.anonymous);
  IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
  IF (b->>'enabled')::boolean THEN
   INSERT INTO public.hyt_comment_likes VALUES(c.id,m.id) ON CONFLICT DO NOTHING;
   IF c.author_id<>m.id THEN INSERT INTO public.hyt_notifications(recipient_id,actor_id,post_id,comment_id,kind,event_key)
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
  RETURN jsonb_build_object('status',201,'comment',public.hyt_comment_json(c,m.id));
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
   IF b->>'kind'='like' AND p.author_id<>m.id THEN INSERT INTO public.hyt_notifications(recipient_id,actor_id,post_id,kind,event_key)
    VALUES(p.author_id,m.id,p.id,'post_like','post-like:'||p.id||':'||m.id) ON CONFLICT DO NOTHING; END IF;
  ELSE DELETE FROM public.hyt_reactions WHERE post_id=p.id AND member_id=m.id AND kind=b->>'kind'; END IF;
  RETURN jsonb_build_object('status',200,'post',public.hyt_post_json(p,m.id));
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
    UPDATE public.hyt_buddies SET revision=revision+1 WHERE post_id IN (SELECT j.post_id FROM public.hyt_buddy_members j JOIN public.hyt_posts bp ON bp.id=j.post_id WHERE (j.member_id=m.id AND bp.author_id=target) OR (j.member_id=target AND bp.author_id=m.id));
    DELETE FROM public.hyt_buddy_members j USING public.hyt_posts bp WHERE bp.id=j.post_id AND ((j.member_id=m.id AND bp.author_id=target) OR (j.member_id=target AND bp.author_id=m.id));
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
 ('hyt_members','hyt_sessions','hyt_posts','hyt_comments','hyt_thread_aliases','hyt_reactions','hyt_blocks','hyt_hidden_threads','hyt_reports','hyt_moderation','hyt_community_rate','hyt_media','hyt_comment_likes','hyt_thread_watches','hyt_thread_visits','hyt_notifications','hyt_responses','hyt_follows','hyt_polls','hyt_poll_votes','hyt_buddies','hyt_buddy_members') LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',obj.tablename);
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC',obj.tablename);
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=role_name) THEN EXECUTE format('REVOKE ALL ON public.%I FROM %I',obj.tablename,role_name); END IF;
  END LOOP;
 END LOOP;
 FOR obj IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN ('hyt_community','hyt_member_json','hyt_author_json','hyt_post_json','hyt_comment_json','hyt_media_json','hyt_visible_notifications','hyt_notification_json','hyt_notify_comment','hyt_avatar_json','hyt_profile_json','hyt_poll_json','hyt_comment_image_visible','hyt_buddy_json') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',obj.signature);
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=role_name) THEN EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I',obj.signature,role_name); END IF;
  END LOOP;
 END LOOP;
END $$;
