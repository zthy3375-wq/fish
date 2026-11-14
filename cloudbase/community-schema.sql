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

CREATE OR REPLACE FUNCTION public.hyt_member_json(m public.hyt_members) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('id',m.id,'username',m.username,'nickname',m.nickname,'role',m.role,'bannedUntil',m.banned_until);
$$;
CREATE OR REPLACE FUNCTION public.hyt_author_json(uid uuid, pid uuid, anon boolean, viewer uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('name',CASE WHEN anon THEN '匿名同学 · '||coalesce(a.label,'隐藏') ELSE m.nickname END,
 'anonymous',anon,'mine',uid=viewer)
 FROM public.hyt_members m LEFT JOIN public.hyt_thread_aliases a ON a.member_id=m.id AND a.post_id=pid WHERE m.id=uid;
$$;
CREATE OR REPLACE FUNCTION public.hyt_post_json(p public.hyt_posts, viewer uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('id',p.id,'body',p.body,'anonymous',p.anonymous,'author',public.hyt_author_json(p.author_id,p.id,p.anonymous,viewer),
 'createdAt',p.created_at,'locked',p.locked,
 'commentCount',(SELECT count(*) FROM public.hyt_comments c WHERE c.post_id=p.id AND c.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks b WHERE b.member_id=viewer AND b.blocked_id=c.author_id AND NOT c.anonymous)),
 'likeCount',(SELECT count(*) FROM public.hyt_reactions r WHERE r.post_id=p.id AND r.kind='like'),
 'liked',EXISTS(SELECT 1 FROM public.hyt_reactions r WHERE r.post_id=p.id AND r.member_id=viewer AND r.kind='like'),
 'saved',EXISTS(SELECT 1 FROM public.hyt_reactions r WHERE r.post_id=p.id AND r.member_id=viewer AND r.kind='save'));
$$;
CREATE OR REPLACE FUNCTION public.hyt_comment_json(c public.hyt_comments, viewer uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('id',c.id,'postId',c.post_id,'body',CASE WHEN c.deleted_at IS NULL THEN c.body ELSE '这条评论已删除' END,
 'author',CASE WHEN c.deleted_at IS NULL THEN public.hyt_author_json(c.author_id,c.post_id,c.anonymous,viewer) ELSE jsonb_build_object('name','已删除','anonymous',true,'mine',false) END,
 'createdAt',c.created_at,'replyTo',c.reply_to,'deleted',c.deleted_at IS NOT NULL,
 'isOriginalPoster',c.deleted_at IS NULL AND c.author_id=p.author_id AND (p.anonymous OR NOT c.anonymous)) FROM public.hyt_posts p WHERE p.id=c.post_id;
$$;

-- Each call is a PostgreSQL transaction. The HTTP server is the only caller.
CREATE OR REPLACE FUNCTION public.hyt_community(a text,b jsonb,th text) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog,public AS $fn$
#variable_conflict use_column
DECLARE m public.hyt_members%ROWTYPE; p public.hyt_posts%ROWTYPE; c public.hyt_comments%ROWTYPE;
 report public.hyt_reports%ROWTYPE; target uuid; result jsonb; n int; k text; stamp timestamptz; limit_n int; anon boolean;
BEGIN
 IF a='rate' THEN
  DELETE FROM public.hyt_community_rate WHERE key IN (SELECT key FROM public.hyt_community_rate WHERE until_at<now()-interval '1 day' LIMIT 100);
  INSERT INTO public.hyt_community_rate(key,count,until_at) VALUES(b->>'key',1,now()+make_interval(secs=>(b->>'seconds')::int))
  ON CONFLICT(key) DO UPDATE SET count=CASE WHEN hyt_community_rate.until_at<=now() THEN 1 ELSE hyt_community_rate.count+1 END,
  until_at=CASE WHEN hyt_community_rate.until_at<=now() THEN excluded.until_at ELSE hyt_community_rate.until_at END RETURNING count INTO n;
  IF n>(b->>'limit')::int THEN RETURN jsonb_build_object('status',429,'error','too_many_requests'); END IF;
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
 SELECT u.* INTO m FROM public.hyt_sessions s JOIN public.hyt_members u ON u.id=s.member_id
 WHERE s.hash=th AND s.expires_at>now() AND u.deleted_at IS NULL FOR UPDATE OF u;
 IF NOT FOUND THEN RETURN '{"status":401,"error":"session_expired"}'::jsonb; END IF;
 -- Persistent limits are allocated only after a real account is authenticated.
 INSERT INTO public.hyt_community_rate(key,count,until_at) VALUES('member:'||m.id,1,now()+interval '1 minute')
 ON CONFLICT(key) DO UPDATE SET count=CASE WHEN hyt_community_rate.until_at<=now() THEN 1 ELSE hyt_community_rate.count+1 END,
 until_at=CASE WHEN hyt_community_rate.until_at<=now() THEN excluded.until_at ELSE hyt_community_rate.until_at END RETURNING count INTO n;
 IF n>180 THEN RETURN '{"status":429,"error":"too_many_requests"}'::jsonb; END IF;
 IF a='session' THEN RETURN jsonb_build_object('status',200,'user',public.hyt_member_json(m),'passwordHash',m.password_hash); END IF;
 IF a='blocks.clear' THEN DELETE FROM public.hyt_blocks WHERE member_id=m.id; DELETE FROM public.hyt_hidden_threads WHERE member_id=m.id; RETURN '{"status":200}'::jsonb; END IF;
 IF a='me' THEN RETURN jsonb_build_object('status',200,'user',public.hyt_member_json(m)); END IF;
 IF a='logout' THEN DELETE FROM public.hyt_sessions WHERE hash=th; RETURN '{"status":200}'::jsonb; END IF;
 IF a='profile.update' THEN UPDATE public.hyt_members SET nickname=b->>'nickname' WHERE id=m.id RETURNING * INTO m; RETURN jsonb_build_object('status',200,'user',public.hyt_member_json(m)); END IF;
 IF a IN ('password.change','account.delete') THEN
  IF m.password_hash<>b->>'proof' THEN RETURN '{"status":401,"error":"invalid_credentials"}'::jsonb; END IF;
  IF a='password.change' THEN
   UPDATE public.hyt_members SET password_hash=b->>'passwordHash',recovery_hash=b->>'recoveryHash' WHERE id=m.id;
   DELETE FROM public.hyt_sessions WHERE member_id=m.id AND hash<>th;
  ELSE
   UPDATE public.hyt_members SET deleted_at=now(),username='deleted_'||id::text,nickname='已注销',password_hash='',recovery_hash='' WHERE id=m.id;
   UPDATE public.hyt_posts SET body='已删除',deleted_at=now() WHERE author_id=m.id;
   UPDATE public.hyt_comments SET body='已删除',deleted_at=now() WHERE author_id=m.id;
   DELETE FROM public.hyt_sessions WHERE member_id=m.id;
   DELETE FROM public.hyt_reactions WHERE member_id=m.id;
   DELETE FROM public.hyt_blocks WHERE member_id=m.id OR blocked_id=m.id;
   DELETE FROM public.hyt_hidden_threads WHERE member_id=m.id;
  END IF;
  RETURN '{"status":200}'::jsonb;
 END IF;
 IF a='posts.list' THEN
  SELECT coalesce(jsonb_agg(public.hyt_post_json(q,m.id) ORDER BY q.created_at DESC,q.id DESC),'[]'::jsonb) INTO result FROM
   (SELECT p.* FROM public.hyt_posts p WHERE p.deleted_at IS NULL
    AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=p.author_id AND NOT p.anonymous)
    AND NOT EXISTS(SELECT 1 FROM public.hyt_hidden_threads h WHERE h.member_id=m.id AND h.post_id=p.id)
    AND (coalesce(b->>'scope','all')<>'mine' OR p.author_id=m.id)
    AND (coalesce(b->>'scope','all')<>'saved' OR EXISTS(SELECT 1 FROM public.hyt_reactions r WHERE r.post_id=p.id AND r.member_id=m.id AND r.kind='save'))
    AND (coalesce(b->>'query','')='' OR strpos(lower(p.body),lower(b->>'query'))>0)
    AND (b->>'beforeTime' IS NULL OR (p.created_at,p.id)<((b->>'beforeTime')::timestamptz,(b->>'beforeId')::uuid))
    ORDER BY p.created_at DESC,p.id DESC LIMIT 21) q;
  RETURN jsonb_build_object('status',200,'posts',result);
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
   IF report.comment_id IS NULL THEN UPDATE public.hyt_posts SET deleted_at=now() WHERE id=p.id;
   ELSE UPDATE public.hyt_comments SET deleted_at=now() WHERE id=report.comment_id; END IF;
  ELSIF b->>'decision'='lock' THEN UPDATE public.hyt_posts SET locked=true WHERE id=p.id;
  ELSIF b->>'decision'='ban' THEN UPDATE public.hyt_members SET banned_until=now()+interval '7 days' WHERE id=target AND role<>'moderator';
  ELSIF b->>'decision'<>'dismiss' THEN RETURN '{"status":400,"error":"invalid_request"}'::jsonb;
  END IF;
  UPDATE public.hyt_reports SET status='resolved',resolution=b->>'reason',resolved_at=now() WHERE id=report.id;
  INSERT INTO public.hyt_moderation(moderator_id,report_id,action,reason) VALUES(m.id,report.id,b->>'decision',b->>'reason');
  RETURN '{"status":200}'::jsonb;
 END IF;
 IF a IN ('posts.create','comments.create','reactions.set') AND m.banned_until>now() THEN RETURN '{"status":403,"error":"account_muted"}'::jsonb; END IF;
 IF a='posts.create' THEN
  SELECT * INTO p FROM public.hyt_posts WHERE author_id=m.id AND request_id=(b->>'requestId')::uuid;
  IF FOUND THEN
   IF p.deleted_at IS NOT NULL OR p.body<>b->>'body' OR p.anonymous<>(b->>'anonymous')::boolean THEN RETURN '{"status":409,"error":"request_conflict"}'::jsonb; END IF;
   RETURN jsonb_build_object('status',200,'post',public.hyt_post_json(p,m.id));
  END IF;
  IF (SELECT count(*) FROM public.hyt_posts WHERE author_id=m.id AND created_at>now()-interval '1 hour')>=10 THEN RETURN '{"status":429,"error":"posting_too_fast"}'::jsonb; END IF;
  INSERT INTO public.hyt_posts(author_id,body,anonymous,request_id) VALUES(m.id,b->>'body',(b->>'anonymous')::boolean,(b->>'requestId')::uuid) RETURNING * INTO p;
  INSERT INTO public.hyt_thread_aliases(post_id,member_id) VALUES(p.id,m.id);
  RETURN jsonb_build_object('status',201,'post',public.hyt_post_json(p,m.id));
 END IF;
 SELECT * INTO p FROM public.hyt_posts WHERE id=(b->>'postId')::uuid AND deleted_at IS NULL FOR UPDATE;
 IF NOT FOUND OR EXISTS(SELECT 1 FROM public.hyt_hidden_threads h WHERE h.member_id=m.id AND h.post_id=p.id) OR EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=p.author_id AND NOT p.anonymous) THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
 IF a='posts.get' THEN
  SELECT coalesce(jsonb_agg(public.hyt_comment_json(q,m.id) ORDER BY q.created_at,q.id),'[]'::jsonb) INTO result FROM
   (SELECT c.* FROM public.hyt_comments c WHERE c.post_id=p.id
    AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=c.author_id AND NOT c.anonymous)
    AND (b->>'afterTime' IS NULL OR (c.created_at,c.id)>((b->>'afterTime')::timestamptz,(b->>'afterId')::uuid))
    ORDER BY c.created_at,c.id LIMIT 51) q;
  RETURN jsonb_build_object('status',200,'post',public.hyt_post_json(p,m.id),'comments',result);
 END IF;
 IF a='comments.create' THEN
  IF p.locked THEN RETURN '{"status":409,"error":"post_locked"}'::jsonb; END IF;
  anon=(b->>'anonymous')::boolean OR (p.author_id=m.id AND p.anonymous);
  SELECT * INTO c FROM public.hyt_comments WHERE author_id=m.id AND request_id=(b->>'requestId')::uuid;
  IF FOUND THEN
   IF c.deleted_at IS NOT NULL OR c.post_id<>p.id OR c.body<>b->>'body' OR c.anonymous<>anon OR c.reply_to IS DISTINCT FROM (b->>'replyTo')::uuid THEN RETURN '{"status":409,"error":"request_conflict"}'::jsonb; END IF;
   RETURN jsonb_build_object('status',200,'comment',public.hyt_comment_json(c,m.id));
  END IF;
  IF (SELECT count(*) FROM public.hyt_comments WHERE author_id=m.id AND created_at>now()-interval '1 hour')>=60 THEN RETURN '{"status":429,"error":"posting_too_fast"}'::jsonb; END IF;
  IF b->>'replyTo' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.hyt_comments c WHERE c.id=(b->>'replyTo')::uuid AND c.post_id=p.id AND c.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM public.hyt_blocks bl WHERE bl.member_id=m.id AND bl.blocked_id=c.author_id AND NOT c.anonymous)) THEN RETURN '{"status":404,"error":"reply_unavailable"}'::jsonb; END IF;
  INSERT INTO public.hyt_comments(post_id,author_id,body,anonymous,reply_to,request_id) VALUES(p.id,m.id,b->>'body',anon,(b->>'replyTo')::uuid,(b->>'requestId')::uuid) RETURNING * INTO c;
  INSERT INTO public.hyt_thread_aliases(post_id,member_id) VALUES(p.id,m.id) ON CONFLICT DO NOTHING;
  RETURN jsonb_build_object('status',201,'comment',public.hyt_comment_json(c,m.id));
 END IF;
 IF a='posts.delete' THEN
  IF p.author_id<>m.id THEN RETURN '{"status":403,"error":"forbidden"}'::jsonb; END IF;
  UPDATE public.hyt_posts SET body='已删除',deleted_at=now() WHERE id=p.id; RETURN '{"status":200}'::jsonb;
 END IF;
 IF a='comments.delete' THEN
  UPDATE public.hyt_comments SET body='已删除',deleted_at=now() WHERE id=(b->>'commentId')::uuid AND post_id=p.id AND author_id=m.id;
  IF NOT FOUND THEN RETURN '{"status":404,"error":"not_found"}'::jsonb; END IF;
  RETURN '{"status":200}'::jsonb;
 END IF;
 IF a='reactions.set' THEN
  IF (b->>'enabled')::boolean THEN INSERT INTO public.hyt_reactions VALUES(p.id,m.id,b->>'kind') ON CONFLICT DO NOTHING;
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
   ELSE INSERT INTO public.hyt_blocks VALUES(m.id,target) ON CONFLICT DO NOTHING; END IF;
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
 ('hyt_members','hyt_sessions','hyt_posts','hyt_comments','hyt_thread_aliases','hyt_reactions','hyt_blocks','hyt_hidden_threads','hyt_reports','hyt_moderation','hyt_community_rate') LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',obj.tablename);
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC',obj.tablename);
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=role_name) THEN EXECUTE format('REVOKE ALL ON public.%I FROM %I',obj.tablename,role_name); END IF;
  END LOOP;
 END LOOP;
 FOR obj IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN ('hyt_community','hyt_member_json','hyt_author_json','hyt_post_json','hyt_comment_json') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',obj.signature);
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=role_name) THEN EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I',obj.signature,role_name); END IF;
  END LOOP;
 END LOOP;
END $$;
