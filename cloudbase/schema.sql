CREATE TABLE IF NOT EXISTS public.hyt_devices(id uuid PRIMARY KEY, token_hash text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), first_day date, last_day date, version text NOT NULL DEFAULT '', version_code int NOT NULL DEFAULT 0, last_write timestamptz)
-- statement
CREATE TABLE IF NOT EXISTS public.hyt_daily(device uuid REFERENCES public.hyt_devices(id) ON DELETE CASCADE, day date NOT NULL, features jsonb NOT NULL DEFAULT '{}', PRIMARY KEY(device,day))
-- statement
CREATE INDEX IF NOT EXISTS hyt_daily_day ON public.hyt_daily(day)
-- statement
CREATE TABLE IF NOT EXISTS public.hyt_rate(id text PRIMARY KEY, day date NOT NULL, count int NOT NULL)
-- statement
ALTER TABLE public.hyt_devices ENABLE ROW LEVEL SECURITY
-- statement
ALTER TABLE public.hyt_daily ENABLE ROW LEVEL SECURITY
-- statement
ALTER TABLE public.hyt_rate ENABLE ROW LEVEL SECURITY
-- statement
REVOKE ALL ON public.hyt_devices,public.hyt_daily,public.hyt_rate FROM PUBLIC,anon,authenticated
-- statement
CREATE OR REPLACE FUNCTION public.hyt_metric(a text, uid uuid, th text, b jsonb, rk text) RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,public AS $fn$
DECLARE d public.hyt_devices%ROWTYPE; today date := (now() AT TIME ZONE 'Asia/Shanghai')::date; quota int; result_features jsonb;
BEGIN
 IF a='enroll' THEN
  SELECT * INTO d FROM public.hyt_devices WHERE id=uid;
  IF FOUND THEN RETURN jsonb_build_object('status',CASE WHEN d.token_hash=th THEN 200 ELSE 401 END,'ok',d.token_hash=th); END IF;
  INSERT INTO public.hyt_rate(id,day,count) VALUES(rk,today,1) ON CONFLICT(id) DO UPDATE SET count=hyt_rate.count+1 WHERE hyt_rate.count<3000 RETURNING count INTO quota;
  IF quota IS NULL THEN RETURN '{"status":429,"ok":false}'::jsonb; END IF;
  INSERT INTO public.hyt_devices(id,token_hash) VALUES(uid,th) ON CONFLICT(id) DO NOTHING;
 END IF;
 SELECT * INTO d FROM public.hyt_devices WHERE id=uid FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('status',CASE WHEN a='delete' THEN 200 ELSE 401 END,'ok',a='delete'); END IF;
 IF d.token_hash<>th THEN RETURN '{"status":401,"ok":false}'::jsonb; END IF;
 IF a='enroll' THEN RETURN '{"status":200,"ok":true}'::jsonb; END IF;
 IF a='delete' THEN DELETE FROM public.hyt_devices WHERE id=uid; RETURN '{"status":200,"ok":true}'::jsonb; END IF;
 IF a<>'record' THEN RETURN '{"status":404,"ok":false}'::jsonb; END IF;
 IF d.last_write>now()-interval '60 seconds' THEN RETURN '{"status":202,"ok":false,"retryAfterSeconds":60}'::jsonb; END IF;
 SELECT jsonb_object_agg(k,greatest(coalesce((old.features->>k)::int,0),coalesce((b->'features'->>k)::int,0))) INTO result_features
 FROM unnest(ARRAY['schedule','tasks','learning','shower','wallet','water','laundry','parcel','grades','map']) k
 LEFT JOIN public.hyt_daily old ON old.device=uid AND old.day=(b->>'day')::date;
 INSERT INTO public.hyt_daily(device,day,features) VALUES(uid,(b->>'day')::date,result_features) ON CONFLICT(device,day) DO UPDATE SET features=excluded.features;
 UPDATE public.hyt_devices SET first_day=coalesce(first_day,today),last_day=greatest(last_day,(b->>'day')::date),version=CASE WHEN (b->>'versionCode')::int>=version_code THEN b->>'version' ELSE version END,version_code=greatest(version_code,(b->>'versionCode')::int),last_write=now() WHERE id=uid;
 INSERT INTO public.hyt_rate(id,day,count) VALUES('cleanup:'||today,today,0) ON CONFLICT DO NOTHING;
 IF FOUND THEN
  DELETE FROM public.hyt_daily WHERE day<today-89;
  DELETE FROM public.hyt_rate WHERE day<today-2;
  DELETE FROM public.hyt_devices WHERE first_day IS NULL AND created_at<now()-interval '1 day';
 END IF;
 RETURN '{"status":200,"ok":true}'::jsonb;
END $fn$
-- statement
REVOKE ALL ON FUNCTION public.hyt_metric(text,uuid,text,jsonb,text) FROM PUBLIC,anon,authenticated
-- statement
GRANT SELECT,INSERT,UPDATE,DELETE ON public.hyt_devices,public.hyt_daily,public.hyt_rate TO service_role,cloudbase_postgres
-- statement
GRANT EXECUTE ON FUNCTION public.hyt_metric(text,uuid,text,jsonb,text) TO service_role,cloudbase_postgres
