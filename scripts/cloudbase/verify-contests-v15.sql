-- Run inside the migration transaction. No test account, session, event or audit is committed.
SAVEPOINT contest_upgrade_smoke;
DO $smoke$
DECLARE
  developer_id uuid := gen_random_uuid();
  member_id uuid := gen_random_uuid();
  contest_id uuid := gen_random_uuid();
  contest_type text := '迁移演练-'||left(contest_id::text,8);
  developer_session text := md5(gen_random_uuid()::text);
  member_session text := md5(gen_random_uuid()::text);
  request jsonb;
  response jsonb;
BEGIN
  INSERT INTO public.hyt_members(id,username,nickname,password_hash,recovery_hash,developer_since)
  VALUES
    (developer_id,'migration_'||developer_id,'迁移演练',md5(gen_random_uuid()::text),md5(gen_random_uuid()::text),now()),
    (member_id,'migration_'||member_id,'迁移演练',md5(gen_random_uuid()::text),md5(gen_random_uuid()::text),NULL);
  INSERT INTO public.hyt_sessions(hash,member_id,expires_at)
  VALUES (developer_session,developer_id,now()+interval '1 minute'),
         (member_session,member_id,now()+interval '1 minute');

  INSERT INTO public.hyt_contests(
    id,title,type,edition,description,rules,starts_at,submission_ends,voting_starts,
    voting_ends,award_at,formats,published,cancelled,auto_publish
  ) VALUES (
    contest_id,'赛事清理迁移演练',contest_type,'验证','临时测试赛事','只用于迁移验证',
    now()-interval '5 hours',now()-interval '4 hours',now()-interval '3 hours',
    now()-interval '2 hours',now()-interval '1 hour',ARRAY['text'],true,true,false
  );

  request := jsonb_build_object('contestId',contest_id,'operation','remove',
    'requestId',gen_random_uuid(),'reason','验证取消赛事可移入回收站',
    'expectedCounts',jsonb_build_object('entries',0,'votes',0,'awards',0));
  response := public.hyt_community('contests.manage',request,member_session);
  IF (response->>'status') IS DISTINCT FROM '403' THEN
    RAISE EXCEPTION 'Ordinary member must not remove a contest';
  END IF;

  response := public.hyt_community('contests.manage',request,developer_session);
  IF (response#>>'{contest,visibility}') IS DISTINCT FROM 'deleted' OR
     (response#>>'{contest,id}') IS DISTINCT FROM contest_id::text THEN
    RAISE EXCEPTION 'Developer removal failed';
  END IF;
  response := public.hyt_community('contests.get',
    jsonb_build_object('contestId',contest_id,'view','public'),member_session);
  IF (response->>'status') IS DISTINCT FROM '404' THEN
    RAISE EXCEPTION 'Deleted contest remained visible to members';
  END IF;

  response := public.hyt_community('contests.list',
    jsonb_build_object('scope','trash','type',contest_type),developer_session);
  IF NOT coalesce((response->'contests') @> jsonb_build_array(jsonb_build_object('id',contest_id)),false) THEN
    RAISE EXCEPTION 'Deleted contest missing from recycle bin';
  END IF;

  response := public.hyt_community('contests.manage',
    jsonb_build_object('contestId',contest_id,'operation','restore',
      'requestId',gen_random_uuid(),'reason','验证还原原始记录'),developer_session);
  IF (response#>>'{contest,visibility}') IS DISTINCT FROM 'visible' OR
     (response#>>'{contest,id}') IS DISTINCT FROM contest_id::text OR
     (response#>>'{contest,state}') IS DISTINCT FROM 'cancelled' THEN
    RAISE EXCEPTION 'Contest restoration failed';
  END IF;
END
$smoke$;
ROLLBACK TO SAVEPOINT contest_upgrade_smoke;
RELEASE SAVEPOINT contest_upgrade_smoke;
