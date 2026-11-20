-- Verify the live permission boundary without using the existing developer's identity.
-- The synthetic member, session and cancelled contest are rolled back before commit.
SAVEPOINT contest_upgrade_smoke;
DO $smoke$
DECLARE
  member_id uuid := gen_random_uuid();
  contest_id uuid := gen_random_uuid();
  member_session text := md5(gen_random_uuid()::text);
  action record;
  response jsonb;
BEGIN
  INSERT INTO public.hyt_members(id,username,nickname,password_hash,recovery_hash)
  VALUES (member_id,'migration_'||member_id,'迁移演练',md5(gen_random_uuid()::text),md5(gen_random_uuid()::text));
  INSERT INTO public.hyt_sessions(hash,member_id,expires_at)
  VALUES (member_session,member_id,now()+interval '1 minute');

  INSERT INTO public.hyt_contests(
    id,title,type,edition,description,rules,starts_at,submission_ends,voting_starts,
    voting_ends,award_at,formats,published,cancelled,auto_publish
  ) VALUES (
    contest_id,'赛事清理迁移演练','文字赛','验证','临时测试赛事','只用于迁移验证',
    now()-interval '5 hours',now()-interval '4 hours',now()-interval '3 hours',
    now()-interval '2 hours',now()-interval '1 hour',ARRAY['text'],true,true,false
  );

  FOR action IN
    SELECT * FROM (VALUES
      ('contests.list', '{"scope":"trash"}'::jsonb),
      ('contests.manage', jsonb_build_object('contestId',contest_id,'operation','remove','reason','验证清理权限')),
      ('contests.manage', jsonb_build_object('contestId',contest_id,'operation','restore','reason','验证恢复权限'))
    ) AS actions(name,payload)
  LOOP
    response := public.hyt_community(action.name,action.payload,member_session);
    IF (response->>'status') IS DISTINCT FROM '403' THEN
      RAISE EXCEPTION 'Ordinary member must not use contest cleanup';
    END IF;
  END LOOP;

  response := public.hyt_community('contests.get',
    jsonb_build_object('contestId',contest_id,'view','public'),member_session);
  IF (response#>>'{contest,visibility}') IS DISTINCT FROM 'visible' OR
     (response#>>'{contest,id}') IS DISTINCT FROM contest_id::text OR
     (response#>>'{contest,state}') IS DISTINCT FROM 'cancelled' THEN
    RAISE EXCEPTION 'Unauthorized contest action changed the fixture';
  END IF;
END
$smoke$;
ROLLBACK TO SAVEPOINT contest_upgrade_smoke;
RELEASE SAVEPOINT contest_upgrade_smoke;
