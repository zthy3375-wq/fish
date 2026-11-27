-- Install after community-schema.sql. This migration is deliberately opt-in.
BEGIN;
CREATE SCHEMA IF NOT EXISTS hyt_commerce;
REVOKE ALL ON SCHEMA hyt_commerce FROM PUBLIC;

CREATE TABLE IF NOT EXISTS hyt_commerce.settings (
 id boolean PRIMARY KEY DEFAULT true CHECK (id),
 ads_enabled boolean NOT NULL DEFAULT false,
 ios_ads_enabled boolean NOT NULL DEFAULT false
);
INSERT INTO hyt_commerce.settings(id) VALUES(true) ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS hyt_commerce.access (
 member_id uuid NOT NULL REFERENCES public.hyt_members(id),
 permission text NOT NULL CHECK(permission IN ('business','student')),
 PRIMARY KEY(member_id, permission)
);
CREATE TABLE IF NOT EXISTS hyt_commerce.categories (
 id text PRIMARY KEY, name text NOT NULL, position integer NOT NULL
);
INSERT INTO hyt_commerce.categories VALUES
 ('food','餐饮',1),('drink','饮品甜点',2),('study','学习文印',3),('fitness','运动健身',4),('life','生活服务',5)
 ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS hyt_commerce.shops (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 merchant_id uuid NOT NULL UNIQUE REFERENCES public.hyt_members(id),
 draft jsonb NOT NULL, published jsonb,
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','approved','rejected','suspended')),
 revision integer NOT NULL DEFAULT 1,
 decision text NOT NULL DEFAULT '', created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS commerce_listings ON hyt_commerce.shops((published->>'category'),id) WHERE published IS NOT NULL AND state <> 'suspended';

CREATE TABLE IF NOT EXISTS hyt_commerce.media (
 id uuid PRIMARY KEY, member_id uuid NOT NULL REFERENCES public.hyt_members(id),
 purpose text NOT NULL CHECK(purpose IN ('shop','ad','qualification','contract')),
 created_at timestamptz NOT NULL DEFAULT now(), ready boolean NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS commerce_recent_uploads ON hyt_commerce.media(member_id,created_at);
CREATE TABLE IF NOT EXISTS hyt_commerce.plans (
 id text PRIMARY KEY, name text NOT NULL, cents integer NOT NULL CHECK(cents>=0),
 category_slot boolean NOT NULL, banner_slot boolean NOT NULL, home_slot boolean NOT NULL, reports boolean NOT NULL
);
INSERT INTO hyt_commerce.plans VALUES
 ('basic','基础版',0,false,false,false,false),('preferred','优选版',4900,true,false,false,true),
 ('featured','精选版',9900,true,true,false,true),('home','首页版',19900,true,true,true,true)
 ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS hyt_commerce.contracts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), request_id uuid UNIQUE NOT NULL,
 shop_id uuid NOT NULL REFERENCES hyt_commerce.shops(id),
 plan_id text NOT NULL REFERENCES hyt_commerce.plans(id), snapshot jsonb NOT NULL,
 kind text NOT NULL CHECK(kind IN ('monthly','trial','short')),
 period tstzrange NOT NULL, cents integer NOT NULL CHECK(cents>=0),
 paid_cents integer NOT NULL DEFAULT 0 CHECK(paid_cents BETWEEN 0 AND cents),
 reference text NOT NULL, attachment uuid REFERENCES hyt_commerce.media(id),
 renewed_from uuid UNIQUE REFERENCES hyt_commerce.contracts(id),
 cancelled_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS commerce_trial_once ON hyt_commerce.contracts(shop_id) WHERE kind='trial';
CREATE INDEX IF NOT EXISTS commerce_shop_contracts ON hyt_commerce.contracts(shop_id,id);
CREATE TABLE IF NOT EXISTS hyt_commerce.receipts (
 id uuid PRIMARY KEY, contract_id uuid NOT NULL REFERENCES hyt_commerce.contracts(id),
 cents integer NOT NULL CHECK(cents<>0), reference text NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS commerce_receipt_contract ON hyt_commerce.receipts(contract_id);
CREATE TABLE IF NOT EXISTS hyt_commerce.inventory (
 contract_id uuid NOT NULL REFERENCES hyt_commerce.contracts(id), placement text NOT NULL,
 slot integer NOT NULL CHECK(slot BETWEEN 1 AND 3), period tstzrange NOT NULL,
 PRIMARY KEY(contract_id,placement)
);
CREATE INDEX IF NOT EXISTS commerce_slot_lookup ON hyt_commerce.inventory(placement,slot);
CREATE TABLE IF NOT EXISTS hyt_commerce.ads (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), shop_id uuid NOT NULL REFERENCES hyt_commerce.shops(id),
 request_id uuid NOT NULL, title text NOT NULL, subtitle text NOT NULL, image uuid NOT NULL REFERENCES hyt_commerce.media(id),
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','approved','rejected','removed')),
 decision text NOT NULL DEFAULT '', created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(shop_id,request_id)
);
CREATE INDEX IF NOT EXISTS commerce_shop_ads ON hyt_commerce.ads(shop_id,id);
CREATE TABLE IF NOT EXISTS hyt_commerce.schedule (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), request_id uuid UNIQUE NOT NULL, ad_id uuid NOT NULL REFERENCES hyt_commerce.ads(id),
 contract_id uuid NOT NULL, placement text NOT NULL, period tstzrange NOT NULL,
 state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','paused','removed')),
 FOREIGN KEY(contract_id,placement) REFERENCES hyt_commerce.inventory(contract_id,placement)
);
CREATE INDEX IF NOT EXISTS commerce_schedule_inventory ON hyt_commerce.schedule(contract_id,placement) WHERE state<>'removed';
CREATE INDEX IF NOT EXISTS commerce_schedule_period ON hyt_commerce.schedule USING gist(period) WHERE state='active';

CREATE TABLE IF NOT EXISTS hyt_commerce.offers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), shop_id uuid NOT NULL REFERENCES hyt_commerce.shops(id), request_id uuid NOT NULL,
 title text NOT NULL, terms text NOT NULL, period tstzrange NOT NULL,
 quota integer NOT NULL CHECK(quota BETWEEN 1 AND 10000),
 claimed integer NOT NULL DEFAULT 0 CHECK(claimed BETWEEN 0 AND quota),
 active boolean NOT NULL DEFAULT true, UNIQUE(shop_id,request_id)
);
CREATE INDEX IF NOT EXISTS commerce_offer_shop ON hyt_commerce.offers(shop_id,id);
CREATE TABLE IF NOT EXISTS hyt_commerce.coupons (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), offer_id uuid NOT NULL REFERENCES hyt_commerce.offers(id),
 member_id uuid REFERENCES public.hyt_members(id), shop_id uuid NOT NULL REFERENCES hyt_commerce.shops(id),
 numeric_code text UNIQUE NOT NULL CHECK(numeric_code ~ '^[0-9]{12}$'),
 claimed_at timestamptz NOT NULL DEFAULT now(), used_at timestamptz,
 UNIQUE(offer_id,member_id)
);
CREATE INDEX IF NOT EXISTS commerce_wallet ON hyt_commerce.coupons(member_id,id);
CREATE INDEX IF NOT EXISTS commerce_coupon_shop ON hyt_commerce.coupons(shop_id,claimed_at);
CREATE TABLE IF NOT EXISTS hyt_commerce.favorites (
 member_id uuid NOT NULL REFERENCES public.hyt_members(id), shop_id uuid NOT NULL REFERENCES hyt_commerce.shops(id),
 PRIMARY KEY(member_id,shop_id)
);
CREATE TABLE IF NOT EXISTS hyt_commerce.reports (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), member_id uuid REFERENCES public.hyt_members(id),
 shop_id uuid NOT NULL REFERENCES hyt_commerce.shops(id), ad_id uuid REFERENCES hyt_commerce.ads(id),
 reason text NOT NULL, report_key text NOT NULL, resolution text, created_at timestamptz NOT NULL DEFAULT now(),
 resolved_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS commerce_open_report ON hyt_commerce.reports(report_key,shop_id,coalesce(ad_id,'00000000-0000-0000-0000-000000000000')) WHERE resolved_at IS NULL;
CREATE INDEX IF NOT EXISTS commerce_reports_by_member ON hyt_commerce.reports(report_key,created_at);
CREATE TABLE IF NOT EXISTS hyt_commerce.audit (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), actor uuid REFERENCES public.hyt_members(id), action text NOT NULL,
 subject uuid, details jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS hyt_commerce.metric_seen (
 day date NOT NULL, signature text NOT NULL, target uuid NOT NULL, kind text NOT NULL, PRIMARY KEY(day,signature,target,kind)
);
CREATE TABLE IF NOT EXISTS hyt_commerce.metrics (
 day date NOT NULL, shop_id uuid NOT NULL REFERENCES hyt_commerce.shops(id), target uuid NOT NULL, kind text NOT NULL,
 total integer NOT NULL DEFAULT 0, PRIMARY KEY(day,shop_id,target,kind)
);
CREATE INDEX IF NOT EXISTS commerce_metrics_shop ON hyt_commerce.metrics(shop_id,day);

CREATE OR REPLACE FUNCTION hyt_commerce.shop_json(s hyt_commerce.shops) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,hyt_commerce AS $$
 SELECT (s.published - 'qualification' - 'qualificationImage' - 'legalName' - 'businessId' - 'legalAddress' - 'legalPhone') || jsonb_build_object('id',s.id);
$$;
CREATE OR REPLACE FUNCTION hyt_commerce.active_ads(slot_filter text, allow_ios boolean)
RETURNS TABLE(id uuid, shop_id uuid, placement text, title text, subtitle text, image uuid, end_at timestamptz, slot integer)
LANGUAGE sql STABLE SET search_path=pg_catalog,hyt_commerce AS $$
 SELECT a.id,a.shop_id,i.placement,a.title,a.subtitle,a.image,upper(d.period),i.slot
 FROM hyt_commerce.schedule d
 JOIN hyt_commerce.inventory i USING(contract_id,placement)
 JOIN hyt_commerce.contracts c ON c.id=i.contract_id
 JOIN hyt_commerce.ads a ON a.id=d.ad_id
 JOIN hyt_commerce.shops s ON s.id=a.shop_id
 JOIN hyt_commerce.settings z ON z.id
 WHERE d.state='active' AND a.state='approved' AND c.cancelled_at IS NULL
 AND c.paid_cents=c.cents
 AND z.ads_enabled AND (NOT allow_ios OR z.ios_ads_enabled)
 AND s.published IS NOT NULL AND s.state<>'suspended'
 AND d.period @> now() AND (slot_filter IS NULL OR d.placement=slot_filter)
 ORDER BY i.slot,a.id;
$$;
CREATE OR REPLACE FUNCTION hyt_commerce.ad_list(slot_filter text, ios boolean) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,hyt_commerce AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'shopId',shop_id,'placement',placement,'title',title,
  'subtitle',subtitle,'image',image,'endsAt',least(end_at,now()+interval '2 minutes')) ORDER BY slot),'[]') FROM hyt_commerce.active_ads(slot_filter,ios);
$$;
CREATE OR REPLACE FUNCTION hyt_commerce.error(code text, status integer DEFAULT 400) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('status',status,'error',code);
$$;
CREATE OR REPLACE FUNCTION hyt_commerce.page(data jsonb) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('items',coalesce(data - 20,'[]'::jsonb),'next',CASE WHEN jsonb_array_length(data)>20 THEN data->19->>'id' END);
$$;
CREATE OR REPLACE FUNCTION hyt_commerce.bump(d date,s uuid,t uuid,k text) RETURNS void
LANGUAGE sql SET search_path=pg_catalog,hyt_commerce AS $$
 INSERT INTO hyt_commerce.metrics(day,shop_id,target,kind,total) VALUES(d,s,t,k,1)
 ON CONFLICT (day,shop_id,target,kind) DO UPDATE SET total=metrics.total+1;
$$;

CREATE OR REPLACE FUNCTION hyt_commerce.run(action text, b jsonb, token_hash text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,hyt_commerce AS $fn$
DECLARE
 actor uuid; owner boolean := false; operator boolean := false; student boolean := false;
 own_shop uuid; shop hyt_commerce.shops; ad hyt_commerce.ads; offer hyt_commerce.offers;
 coupon hyt_commerce.coupons; plan hyt_commerce.plans; contract hyt_commerce.contracts;
 schedule_row hyt_commerce.schedule; reservation hyt_commerce.inventory;
 arg_id uuid := (b->>'id')::uuid; shop_id_arg uuid := (b->>'shopId')::uuid; cursor_id uuid := (b->>'next')::uuid;
 receipt_total integer; data jsonb; extra jsonb; event jsonb; target uuid; item uuid; image uuid; arg_placement text; arg_stats_shop uuid; kind text;
 placements text[]; available integer; price integer; window_period tstzrange;
 today date := (now() AT TIME ZONE 'Asia/Shanghai')::date;
 ios boolean := coalesce(b->>'platform','android')='ios';
BEGIN
 IF action='home' THEN RETURN jsonb_build_object('status',200,'ads',hyt_commerce.ad_list('home',ios)); END IF;
 IF action='catalog' THEN
  arg_placement := coalesce(nullif(b->>'category',''),'');
  SELECT jsonb_agg(hyt_commerce.shop_json(r) ORDER BY r.id) INTO data FROM (
   SELECT * FROM hyt_commerce.shops s WHERE s.published IS NOT NULL AND s.state<>'suspended'
   AND (arg_placement='' OR s.published->>'category'=arg_placement)
   AND (cursor_id IS NULL OR s.id>cursor_id)
   AND strpos(lower((s.published->>'name')||' '||(s.published->>'description')||' '||(s.published->>'address')),lower(coalesce(b->>'query','')))>0
   ORDER BY s.id LIMIT 21) r;
  RETURN hyt_commerce.page(data)||jsonb_build_object('status',200,'categories',
   (SELECT jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) ORDER BY c.position) FROM hyt_commerce.categories c),
   'ads',CASE WHEN cursor_id IS NOT NULL OR coalesce(b->>'query','')<>'' THEN '[]'::jsonb
    ELSE hyt_commerce.ad_list(CASE WHEN arg_placement='' THEN 'banner' ELSE 'category:'||arg_placement END,ios) END);
 END IF;
 IF action='shop' THEN
  SELECT * INTO shop FROM hyt_commerce.shops s WHERE s.id=shop_id_arg AND s.state<>'suspended' AND s.published IS NOT NULL;
  IF NOT FOUND THEN RETURN hyt_commerce.error('not_found',404); END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'title',o.title,'terms',o.terms,'endsAt',upper(o.period),'soldOut',o.claimed>=o.quota)
   ORDER BY upper(o.period),o.id),'[]') INTO data FROM (SELECT a.* FROM hyt_commerce.offers a WHERE a.shop_id=shop.id AND a.active AND a.period @> now() ORDER BY upper(a.period),a.id LIMIT 20) o;
  RETURN jsonb_build_object('status',200,'shop',hyt_commerce.shop_json(shop),'offers',data);
 END IF;
 IF action='report' THEN
  SELECT s.id INTO target FROM hyt_commerce.shops s WHERE s.id=shop_id_arg AND s.published IS NOT NULL AND s.state<>'suspended';
  IF target IS NULL OR (arg_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM hyt_commerce.ads a WHERE a.id=arg_id AND a.shop_id=target))
   THEN RETURN hyt_commerce.error('not_found',404); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('commerce:report:'||(b->>'reportKey'),0));
  IF (SELECT count(*) FROM hyt_commerce.reports r WHERE r.report_key=b->>'reportKey' AND r.created_at>now()-interval '1 hour')>=10
   THEN RETURN hyt_commerce.error('too_many_requests',429); END IF;
  INSERT INTO hyt_commerce.reports(shop_id,ad_id,reason,report_key) VALUES(target,arg_id,b->>'reason',b->>'reportKey') ON CONFLICT DO NOTHING;
  RETURN '{"status":200}'::jsonb;
 END IF;
 SELECT m.id,m.developer_since IS NOT NULL INTO actor,owner
 FROM public.hyt_sessions s JOIN public.hyt_members m ON m.id=s.member_id
 WHERE s.hash=token_hash AND s.expires_at>now() AND m.deleted_at IS NULL;
 IF actor IS NULL THEN RETURN hyt_commerce.error('session_expired',401); END IF;
 SELECT s.id INTO own_shop FROM hyt_commerce.shops s WHERE s.merchant_id=actor;
 SELECT owner OR EXISTS(SELECT 1 FROM hyt_commerce.access x WHERE x.member_id=actor AND x.permission='business'),
 EXISTS(SELECT 1 FROM hyt_commerce.access x WHERE x.member_id=actor AND x.permission='student') INTO operator,student;
 IF action='access' THEN
  RETURN jsonb_build_object('status',200,'role',CASE WHEN owner THEN 'owner' WHEN operator THEN 'business' WHEN own_shop IS NOT NULL THEN 'merchant' ELSE 'student' END,
   'shopId',own_shop,'memberId',actor,'verifiedStudent',student);
 END IF;
 IF action LIKE 'admin.%' AND NOT operator THEN RETURN hyt_commerce.error('forbidden',403); END IF;
 IF action IN ('admin.role','admin.plan','admin.settings') AND NOT owner THEN RETURN hyt_commerce.error('forbidden',403); END IF;
 IF action LIKE 'merchant.%' AND action NOT IN ('merchant.apply','merchant.read') AND own_shop IS NULL THEN RETURN hyt_commerce.error('forbidden',403); END IF;

 IF action='media.begin' THEN
  kind:=b->>'purpose';
  IF kind='contract' AND NOT operator THEN RETURN hyt_commerce.error('forbidden',403); END IF;
  IF kind='ad' AND own_shop IS NULL THEN RETURN hyt_commerce.error('forbidden',403); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('commerce:media:'||actor,0));
  IF (SELECT count(*) FROM hyt_commerce.media x WHERE x.member_id=actor AND x.created_at>=now()-interval '1 day')>=20 THEN RETURN hyt_commerce.error('too_many_requests',429); END IF;
  INSERT INTO hyt_commerce.media(id,member_id,purpose) VALUES(arg_id,actor,kind) ON CONFLICT DO NOTHING;
  IF NOT EXISTS(SELECT 1 FROM hyt_commerce.media x WHERE x.id=arg_id AND x.member_id=actor AND x.purpose=kind AND NOT x.ready)
  THEN RETURN hyt_commerce.error('request_conflict',409); END IF;
  RETURN '{"status":200}'::jsonb;
 ELSIF action='media.finish' THEN
  UPDATE hyt_commerce.media x SET ready=true WHERE x.id=arg_id AND x.member_id=actor;
  IF NOT FOUND THEN RETURN hyt_commerce.error('not_found',404); END IF;
  RETURN jsonb_build_object('status',200,'id',arg_id);
 ELSIF action='merchant.apply' THEN
  IF EXISTS(SELECT 1 FROM hyt_commerce.shops s WHERE s.id=own_shop AND s.state='suspended') THEN RETURN hyt_commerce.error('shop_suspended',409); END IF;
  IF NOT EXISTS(SELECT 1 FROM hyt_commerce.categories c WHERE c.id=b->>'category') THEN RETURN hyt_commerce.error('invalid_request'); END IF;
  IF NOT EXISTS(SELECT 1 FROM hyt_commerce.media x WHERE x.id=(b->>'qualificationImage')::uuid AND x.member_id=actor AND x.ready AND x.purpose='qualification')
   OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(b->'images') f(value) WHERE NOT EXISTS(
     SELECT 1 FROM hyt_commerce.media x WHERE x.id=f.value::uuid AND x.member_id=actor AND x.ready AND x.purpose='shop'))
   THEN RETURN hyt_commerce.error('invalid_image'); END IF;
  INSERT INTO hyt_commerce.shops(merchant_id,draft) VALUES(actor,b)
  ON CONFLICT(merchant_id) DO UPDATE SET draft=excluded.draft,state='pending',decision='',revision=shops.revision+1 WHERE shops.state<>'suspended'
  RETURNING shops.id INTO target;
  IF target IS NULL THEN RETURN hyt_commerce.error('shop_suspended',409); END IF;
  INSERT INTO hyt_commerce.audit(actor,action,subject,details) VALUES(actor,action,target,b);
  RETURN jsonb_build_object('status',200,'id',target);
 ELSIF action='merchant.read' THEN
  SELECT jsonb_build_object('id',s.id,'state',s.state,'draft',s.draft,'revision',s.revision,'decision',s.decision) INTO data
  FROM hyt_commerce.shops s WHERE s.id=own_shop;
  RETURN jsonb_build_object('status',200,'shop',data,'plans',(SELECT jsonb_agg(to_jsonb(p) ORDER BY p.cents,p.id) FROM hyt_commerce.plans p));
 ELSIF action='merchant.offers' OR action='merchant.ads' OR action='merchant.contracts' OR action='admin.list' THEN
  kind:=CASE WHEN action='admin.list' THEN b->>'section' ELSE split_part(action,'.',2) END;
  IF action='admin.list' AND kind='shops' THEN
   SELECT jsonb_agg(to_jsonb(x) - 'merchant_id' ORDER BY x.id) INTO data FROM (
    SELECT * FROM hyt_commerce.shops s WHERE (cursor_id IS NULL OR s.id>cursor_id) AND (b->>'filter' IS NULL OR s.state=b->>'filter') ORDER BY s.id LIMIT 21
   ) x;
  ELSIF kind='offers' THEN
   SELECT jsonb_agg(to_jsonb(x)||jsonb_build_object('startsAt',lower(x.period),'endsAt',upper(x.period)) ORDER BY x.id) INTO data FROM (
    SELECT * FROM hyt_commerce.offers o WHERE o.shop_id=own_shop AND (cursor_id IS NULL OR o.id>cursor_id) ORDER BY o.id LIMIT 21
   ) x;
  ELSIF kind='ads' THEN
   SELECT jsonb_agg(to_jsonb(x)||jsonb_build_object('shopName',(SELECT s.published->>'name' FROM hyt_commerce.shops s WHERE s.id=x.shop_id)) ORDER BY x.id) INTO data FROM (
    SELECT * FROM hyt_commerce.ads a WHERE (action='admin.list' OR a.shop_id=own_shop) AND (cursor_id IS NULL OR a.id>cursor_id)
     AND (b->>'filter' IS NULL OR a.state=b->>'filter') ORDER BY a.id LIMIT 21
   ) x;
  ELSIF kind='contracts' THEN
   SELECT jsonb_agg((to_jsonb(x) - 'request_id' - 'period' - 'attachment' - 'reference')||
    CASE WHEN operator AND action='admin.list' THEN jsonb_build_object('reference',x.reference,'attachment',x.attachment) ELSE '{}'::jsonb END ||
    jsonb_build_object('startsAt',lower(x.period),'endsAt',upper(x.period),'placements',
    (SELECT coalesce(jsonb_agg(i.placement ORDER BY i.placement),'[]') FROM hyt_commerce.inventory i WHERE i.contract_id=x.id),
    'paid',(SELECT coalesce(sum(r.cents),0) FROM hyt_commerce.receipts r WHERE r.contract_id=x.id),
    'receipts',CASE WHEN action='admin.list' THEN (SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.recorded_at),'[]') FROM hyt_commerce.receipts r WHERE r.contract_id=x.id) ELSE '[]'::jsonb END)
    ORDER BY x.id) INTO data FROM (
     SELECT * FROM hyt_commerce.contracts c WHERE (action='admin.list' OR c.shop_id=own_shop) AND (cursor_id IS NULL OR c.id>cursor_id)
      AND (shop_id_arg IS NULL OR c.shop_id=shop_id_arg) ORDER BY c.id LIMIT 21
   ) x;
  ELSIF kind='schedule' THEN
   SELECT jsonb_agg((to_jsonb(x)-'period')||jsonb_build_object('startsAt',lower(x.period),'endsAt',upper(x.period),'title',
    (SELECT a.title FROM hyt_commerce.ads a WHERE a.id=x.ad_id)) ORDER BY x.id) INTO data FROM (
     SELECT * FROM hyt_commerce.schedule d WHERE (cursor_id IS NULL OR d.id>cursor_id) ORDER BY d.id LIMIT 21
    ) x;
  ELSIF kind='reports' THEN
   SELECT jsonb_agg(to_jsonb(x)-'member_id'-'report_key' ORDER BY x.id) INTO data FROM (
    SELECT * FROM hyt_commerce.reports r WHERE (cursor_id IS NULL OR r.id>cursor_id)
    AND (b->>'filter' IS NULL OR (r.resolved_at IS NULL)=(b->>'filter'='open')) ORDER BY r.id LIMIT 21
   ) x;
  ELSIF kind='audit' THEN
   SELECT jsonb_agg(to_jsonb(x)-'details'-'actor' ORDER BY x.id) INTO data FROM (
    SELECT * FROM hyt_commerce.audit u WHERE (cursor_id IS NULL OR u.id>cursor_id) ORDER BY u.id LIMIT 21
   ) x;
  ELSE RETURN hyt_commerce.error('invalid_request'); END IF;
  RETURN hyt_commerce.page(data)||'{"status":200}'::jsonb;
 ELSIF action='admin.config' THEN
  RETURN jsonb_build_object('status',200,'settings',(SELECT to_jsonb(z)-'id' FROM hyt_commerce.settings z),
   'plans',(SELECT jsonb_agg(to_jsonb(p) ORDER BY p.cents,p.id) FROM hyt_commerce.plans p));
 ELSIF action='admin.role' OR action='admin.student' THEN
  IF NOT EXISTS(SELECT 1 FROM public.hyt_members m WHERE m.id=arg_id AND m.deleted_at IS NULL) THEN RETURN hyt_commerce.error('not_found',404); END IF;
  kind:=CASE WHEN action='admin.role' THEN 'business' ELSE 'student' END;
  IF (b->>'enabled')::boolean THEN INSERT INTO hyt_commerce.access VALUES(arg_id,kind) ON CONFLICT DO NOTHING;
  ELSE DELETE FROM hyt_commerce.access x WHERE x.member_id=arg_id AND x.permission=kind; END IF;
  target:=arg_id;
 ELSIF action='admin.plan' THEN
  UPDATE hyt_commerce.plans p SET name=b->>'name',cents=(b->>'cents')::integer,
   category_slot=(b->>'categorySlot')::boolean,banner_slot=(b->>'bannerSlot')::boolean,
   home_slot=(b->>'homeSlot')::boolean,reports=(b->>'reports')::boolean WHERE p.id=b->>'plan';
  IF NOT FOUND THEN RETURN hyt_commerce.error('not_found',404); END IF;
 ELSIF action='admin.settings' THEN
  UPDATE hyt_commerce.settings SET ads_enabled=(b->>'adsEnabled')::boolean,ios_ads_enabled=(b->>'iosAdsEnabled')::boolean WHERE settings.id;
 ELSIF action='admin.shop' THEN
  SELECT * INTO shop FROM hyt_commerce.shops s WHERE s.id=arg_id FOR UPDATE;
  IF NOT FOUND THEN RETURN hyt_commerce.error('not_found',404); END IF;
  IF shop.revision<>(b->>'revision')::integer THEN RETURN hyt_commerce.error('request_conflict',409); END IF;
  kind:=b->>'decision';
  IF kind='approved' AND shop.state NOT IN ('pending','suspended') OR kind='rejected' AND shop.state<>'pending'
   THEN RETURN hyt_commerce.error('request_conflict',409); END IF;
  IF kind='approved' AND shop.published IS NOT NULL AND shop.published->>'category'<>shop.draft->>'category' AND EXISTS(
   SELECT 1 FROM hyt_commerce.contracts c JOIN hyt_commerce.inventory i ON i.contract_id=c.id
   WHERE c.shop_id=shop.id AND i.placement LIKE 'category:%' AND c.cancelled_at IS NULL AND upper(c.period)>now()
  ) THEN RETURN hyt_commerce.error('category_reserved',409); END IF;
  UPDATE hyt_commerce.shops s SET state=kind,decision=b->>'reason',revision=s.revision+1,
   published=CASE WHEN kind='approved' THEN draft ELSE published END WHERE s.id=shop.id;
  IF kind='suspended' THEN UPDATE hyt_commerce.schedule d SET state='paused' FROM hyt_commerce.ads a WHERE a.shop_id=shop.id AND d.ad_id=a.id AND d.state='active'; END IF;
  target:=arg_id;
 ELSIF action='merchant.offer' THEN
  SELECT * INTO shop FROM hyt_commerce.shops s WHERE s.id=own_shop AND s.published IS NOT NULL AND s.state<>'suspended';
  IF NOT FOUND THEN RETURN hyt_commerce.error('shop_unavailable',409); END IF;
  IF (b->>'endsAt')::timestamptz<=now() THEN RETURN hyt_commerce.error('invalid_period'); END IF;
  INSERT INTO hyt_commerce.offers(shop_id,request_id,title,terms,period,quota)
  VALUES(own_shop,arg_id,b->>'title',b->>'terms',tstzrange((b->>'startsAt')::timestamptz,(b->>'endsAt')::timestamptz,'[)'),(b->>'quota')::integer)
  ON CONFLICT(shop_id,request_id) DO NOTHING RETURNING offers.id INTO target;
  IF target IS NULL THEN SELECT o.id INTO target FROM hyt_commerce.offers o WHERE o.shop_id=own_shop AND o.request_id=arg_id; END IF;
  RETURN jsonb_build_object('status',200,'id',target);
 ELSIF action='merchant.offer.edit' THEN
  IF (b->>'endsAt')::timestamptz<=now() THEN RETURN hyt_commerce.error('invalid_period'); END IF;
  UPDATE hyt_commerce.offers o SET title=b->>'title',terms=b->>'terms',quota=(b->>'quota')::integer,
   period=tstzrange((b->>'startsAt')::timestamptz,(b->>'endsAt')::timestamptz,'[)')
   WHERE o.id=arg_id AND o.shop_id=own_shop AND o.claimed=0;
  IF NOT FOUND THEN RETURN hyt_commerce.error('request_conflict',409); END IF;
  RETURN jsonb_build_object('status',200,'id',arg_id);
 ELSIF action='merchant.offerstate' THEN
  UPDATE hyt_commerce.offers o SET active=(b->>'enabled')::boolean WHERE o.id=arg_id AND o.shop_id=own_shop;
  IF NOT FOUND THEN RETURN hyt_commerce.error('not_found',404); END IF;
 ELSIF action='merchant.ad' THEN
  image:=(b->>'image')::uuid;
  IF NOT EXISTS(SELECT 1 FROM hyt_commerce.media x WHERE x.id=image AND x.member_id=actor AND x.ready AND x.purpose='ad')
   THEN RETURN hyt_commerce.error('invalid_image'); END IF;
  IF NOT EXISTS(SELECT 1 FROM hyt_commerce.shops s WHERE s.id=own_shop AND s.state<>'suspended' AND s.published IS NOT NULL)
   THEN RETURN hyt_commerce.error('shop_unavailable',409); END IF;
  INSERT INTO hyt_commerce.ads(shop_id,request_id,title,subtitle,image) VALUES(own_shop,arg_id,b->>'title',b->>'subtitle',image)
  ON CONFLICT(shop_id,request_id) DO NOTHING RETURNING ads.id INTO target;
  IF target IS NULL THEN SELECT a.id INTO target FROM hyt_commerce.ads a WHERE a.shop_id=own_shop AND a.request_id=arg_id; END IF;
  INSERT INTO hyt_commerce.audit(actor,action,subject,details) VALUES(actor,action,target,b);
  RETURN jsonb_build_object('status',200,'id',target);
 ELSIF action='admin.ad' THEN
  SELECT * INTO ad FROM hyt_commerce.ads a WHERE a.id=arg_id FOR UPDATE;
  IF NOT FOUND THEN RETURN hyt_commerce.error('not_found',404); END IF;
  kind:=b->>'decision';
  IF kind<>'removed' AND ad.state<>'pending' THEN RETURN hyt_commerce.error('request_conflict',409); END IF;
  UPDATE hyt_commerce.ads a SET state=kind,decision=b->>'reason' WHERE a.id=ad.id;
  IF kind='removed' THEN UPDATE hyt_commerce.schedule d SET state='removed' WHERE d.ad_id=ad.id; END IF;
  target:=arg_id;
 ELSIF action='admin.contract' THEN
  -- Each signed agreement reserves all selected placements for its full interval.
  -- Serialize both inventory allocation and cancellation across all HTTP instances.
  PERFORM pg_advisory_xact_lock(hashtextextended('commerce:inventory',0));
  SELECT * INTO contract FROM hyt_commerce.contracts c WHERE c.request_id=arg_id;
  IF FOUND THEN RETURN jsonb_build_object('status',200,'id',contract.id); END IF;
  SELECT * INTO shop FROM hyt_commerce.shops s WHERE s.id=shop_id_arg AND s.state='approved' FOR UPDATE;
  IF NOT FOUND THEN RETURN hyt_commerce.error('shop_unavailable',409); END IF;
  SELECT * INTO plan FROM hyt_commerce.plans p WHERE p.id=b->>'plan' FOR SHARE;
  IF NOT FOUND THEN RETURN hyt_commerce.error('not_found',404); END IF;
  kind:=b->>'kind';
  price:=CASE WHEN kind='trial' THEN 0 ELSE coalesce((b->>'cents')::integer,plan.cents) END;
  IF NOT owner AND (b->>'cents' IS NOT NULL OR kind='short' AND plan.cents>0)
   THEN RETURN hyt_commerce.error('owner_price_required',403); END IF;
  IF plan.id='basic' AND price<>0 THEN RETURN hyt_commerce.error('invalid_request'); END IF;
  IF kind<>'trial' AND plan.cents>0 AND price=0 AND NOT owner THEN RETURN hyt_commerce.error('owner_price_required',403); END IF;
  window_period:=tstzrange((b->>'startsAt')::timestamptz,
    CASE WHEN kind='trial' THEN (b->>'startsAt')::timestamptz+interval '336 hours' ELSE (b->>'endsAt')::timestamptz END,'[)');
  IF upper(window_period)<=now() OR lower(window_period)<now()-interval '1 day' THEN RETURN hyt_commerce.error('invalid_period'); END IF;
  IF kind='trial' AND (plan.cents=0 OR EXISTS(SELECT 1 FROM hyt_commerce.contracts c WHERE c.shop_id=shop.id AND c.kind='trial'))
   THEN RETURN hyt_commerce.error('trial_used',409); END IF;
  item:=(b->>'renewedFrom')::uuid;
  IF item IS NOT NULL AND (kind='trial' OR NOT EXISTS(
   SELECT 1 FROM hyt_commerce.contracts c WHERE c.id=item AND c.shop_id=shop.id AND lower(window_period)>=upper(c.period) AND c.cancelled_at IS NULL
  ) OR EXISTS(SELECT 1 FROM hyt_commerce.contracts c WHERE c.renewed_from=item))
   THEN RETURN hyt_commerce.error('invalid_renewal',409); END IF;
  IF EXISTS(SELECT 1 FROM hyt_commerce.contracts c WHERE c.shop_id=shop.id AND c.cancelled_at IS NULL AND c.period && window_period)
   THEN RETURN hyt_commerce.error('contract_overlap',409); END IF;
  image:=(b->>'attachment')::uuid;
  IF image IS NOT NULL AND NOT EXISTS(SELECT 1 FROM hyt_commerce.media x WHERE x.id=image AND x.member_id=actor AND x.ready AND x.purpose='contract')
   THEN RETURN hyt_commerce.error('invalid_image'); END IF;
  placements:=ARRAY(SELECT CASE WHEN v='category' THEN 'category:'||(shop.published->>'category') ELSE v END FROM jsonb_array_elements_text(b->'placements') f(v));
  IF EXISTS(SELECT 1 FROM unnest(placements) p WHERE p LIKE 'category:%' AND NOT plan.category_slot OR p='banner' AND NOT plan.banner_slot OR p='home' AND NOT plan.home_slot)
   THEN RETURN hyt_commerce.error('placement_not_in_plan',409); END IF;
  extra:='{}';
  FOREACH arg_placement IN ARRAY placements LOOP
   SELECT n INTO available FROM generate_series(1,CASE WHEN arg_placement LIKE 'category:%' THEN 2 ELSE 3 END) f(n)
   WHERE NOT EXISTS (SELECT 1 FROM hyt_commerce.inventory i JOIN hyt_commerce.contracts c ON c.id=i.contract_id
    WHERE c.cancelled_at IS NULL AND i.placement=arg_placement AND i.slot=n AND i.period && window_period)
   ORDER BY n LIMIT 1;
   IF available IS NULL THEN RETURN hyt_commerce.error('inventory_full',409); END IF;
   extra:=extra||jsonb_build_object(arg_placement,available);
  END LOOP;
  INSERT INTO hyt_commerce.contracts(request_id,shop_id,plan_id,snapshot,kind,period,cents,reference,attachment,renewed_from)
   VALUES(arg_id,shop.id,plan.id,to_jsonb(plan),kind,window_period,price,b->>'reference',image,item) RETURNING contracts.id INTO target;
  INSERT INTO hyt_commerce.inventory(contract_id,placement,slot,period)
   SELECT target,key,value::integer,window_period FROM jsonb_each_text(extra);
 ELSIF action='admin.cancel' THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('commerce:inventory',0));
  UPDATE hyt_commerce.contracts c SET cancelled_at=now() WHERE c.id=arg_id AND c.cancelled_at IS NULL;
  IF NOT FOUND THEN RETURN hyt_commerce.error('not_found',404); END IF;
  UPDATE hyt_commerce.schedule d SET state='removed' WHERE d.contract_id=arg_id;
  target:=arg_id;
 ELSIF action='admin.receipt' THEN
  SELECT * INTO contract FROM hyt_commerce.contracts c WHERE c.id=shop_id_arg FOR UPDATE;
  IF NOT FOUND THEN RETURN hyt_commerce.error('not_found',404); END IF;
  IF EXISTS(SELECT 1 FROM hyt_commerce.receipts r WHERE r.id=arg_id AND r.contract_id=contract.id) THEN RETURN '{"status":200}'::jsonb; END IF;
  price:=(b->>'cents')::integer;
  receipt_total:=contract.paid_cents;
  IF receipt_total+price NOT BETWEEN 0 AND contract.cents THEN RETURN hyt_commerce.error('invalid_receipt',409); END IF;
  INSERT INTO hyt_commerce.receipts VALUES(arg_id,contract.id,price,b->>'reference',now()) ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN hyt_commerce.error('request_conflict',409); END IF;
  UPDATE hyt_commerce.contracts c SET paid_cents=receipt_total+price WHERE c.id=contract.id;
  target:=contract.id;
 ELSIF action='admin.schedule' THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('commerce:inventory',0));
  SELECT d.id INTO target FROM hyt_commerce.schedule d WHERE d.request_id=arg_id;
  IF target IS NOT NULL THEN RETURN jsonb_build_object('status',200,'id',target); END IF;
  SELECT * INTO ad FROM hyt_commerce.ads a WHERE a.id=(b->>'adId')::uuid FOR UPDATE;
  IF NOT FOUND OR ad.state<>'approved' THEN RETURN hyt_commerce.error('ad_not_approved',409); END IF;
  SELECT * INTO shop FROM hyt_commerce.shops s WHERE s.id=ad.shop_id AND s.published IS NOT NULL AND s.state<>'suspended' FOR UPDATE;
  IF NOT FOUND THEN RETURN hyt_commerce.error('shop_unavailable',409); END IF;
  arg_placement:=CASE WHEN b->>'placement'='category' THEN 'category:'||(shop.published->>'category') ELSE b->>'placement' END;
  SELECT * INTO contract FROM hyt_commerce.contracts c WHERE c.id=(b->>'contractId')::uuid AND c.cancelled_at IS NULL AND c.shop_id=shop.id;
  IF NOT FOUND THEN RETURN hyt_commerce.error('contract_unavailable',409); END IF;
  SELECT * INTO reservation FROM hyt_commerce.inventory i WHERE i.contract_id=contract.id AND i.placement=arg_placement;
  IF NOT FOUND THEN RETURN hyt_commerce.error('placement_not_in_plan',409); END IF;
  window_period:=tstzrange((b->>'startsAt')::timestamptz,(b->>'endsAt')::timestamptz,'[)');
  IF NOT reservation.period @> window_period OR upper(window_period)<=now() THEN RETURN hyt_commerce.error('invalid_period'); END IF;
  IF EXISTS(SELECT 1 FROM hyt_commerce.schedule d WHERE d.contract_id=contract.id AND d.placement=arg_placement AND d.state<>'removed' AND d.period && window_period)
   THEN RETURN hyt_commerce.error('schedule_conflict',409); END IF;
  INSERT INTO hyt_commerce.schedule(request_id,ad_id,contract_id,placement,period)
   VALUES(arg_id,ad.id,contract.id,arg_placement,window_period) RETURNING schedule.id INTO target;
 ELSIF action='admin.schedule.state' THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('commerce:inventory',0));
  SELECT * INTO schedule_row FROM hyt_commerce.schedule d WHERE d.id=arg_id AND d.state<>'removed' FOR UPDATE;
  IF NOT FOUND THEN RETURN hyt_commerce.error('not_found',404); END IF;
  kind:=b->>'decision';
  IF kind='active' AND (upper(schedule_row.period)<=now() OR NOT EXISTS(
   SELECT 1 FROM hyt_commerce.ads a JOIN hyt_commerce.shops s ON s.id=a.shop_id JOIN hyt_commerce.contracts c ON c.id=schedule_row.contract_id
   WHERE a.id=schedule_row.ad_id AND a.state='approved' AND s.state<>'suspended' AND c.cancelled_at IS NULL
  )) THEN RETURN hyt_commerce.error('schedule_unavailable',409); END IF;
  UPDATE hyt_commerce.schedule d SET state=kind WHERE d.id=arg_id;
  target:=arg_id;
 ELSIF action='favorite' THEN
  IF (b->>'enabled')::boolean THEN
   INSERT INTO hyt_commerce.favorites(member_id,shop_id) SELECT actor,s.id FROM hyt_commerce.shops s
    WHERE s.id=shop_id_arg AND s.published IS NOT NULL AND s.state<>'suspended' ON CONFLICT DO NOTHING;
  ELSE DELETE FROM hyt_commerce.favorites f WHERE f.member_id=actor AND f.shop_id=shop_id_arg; END IF;
  RETURN '{"status":200}'::jsonb;
 ELSIF action='shop.status' THEN
  RETURN jsonb_build_object('status',200,'favorited',EXISTS(SELECT 1 FROM hyt_commerce.favorites f WHERE f.member_id=actor AND f.shop_id=shop_id_arg));
 ELSIF action='favorites' THEN
  SELECT jsonb_agg(hyt_commerce.shop_json(x) ORDER BY x.id) INTO data FROM (
   SELECT s.* FROM hyt_commerce.favorites f JOIN hyt_commerce.shops s ON s.id=f.shop_id
   WHERE f.member_id=actor AND s.state<>'suspended' AND s.published IS NOT NULL
    AND (cursor_id IS NULL OR s.id>cursor_id) ORDER BY s.id LIMIT 21
  ) x;
  RETURN hyt_commerce.page(data)||'{"status":200}'::jsonb;
 ELSIF action='claim' THEN
  IF NOT student THEN RETURN hyt_commerce.error('student_verification_required',403); END IF;
  SELECT * INTO offer FROM hyt_commerce.offers o WHERE o.id=arg_id FOR UPDATE;
  IF NOT FOUND THEN RETURN hyt_commerce.error('not_found',404); END IF;
  SELECT c.id INTO target FROM hyt_commerce.coupons c WHERE c.offer_id=offer.id AND c.member_id=actor;
  IF target IS NOT NULL THEN RETURN jsonb_build_object('status',200,'id',target); END IF;
  IF NOT offer.active OR NOT offer.period @> now() OR NOT EXISTS(SELECT 1 FROM hyt_commerce.shops s WHERE s.id=offer.shop_id AND s.state<>'suspended')
   THEN RETURN hyt_commerce.error('offer_unavailable',409); END IF;
  IF offer.claimed>=offer.quota THEN RETURN hyt_commerce.error('sold_out',409); END IF;
  INSERT INTO hyt_commerce.coupons(offer_id,member_id,shop_id,numeric_code)
    VALUES(offer.id,actor,offer.shop_id,b->>'code') ON CONFLICT(numeric_code) DO NOTHING RETURNING coupons.id INTO target;
  IF target IS NULL THEN RETURN hyt_commerce.error('code_collision',409); END IF;
  UPDATE hyt_commerce.offers o SET claimed=claimed+1 WHERE o.id=offer.id;
  PERFORM hyt_commerce.bump(today,offer.shop_id,offer.shop_id,'claim');
  RETURN jsonb_build_object('status',200,'id',target);
 ELSIF action='wallet' OR action='coupon' THEN
  SELECT jsonb_agg(jsonb_build_object('id',x.id,'title',x.title,'terms',x.terms,'shopName',x.shop_name,'code',CASE WHEN x.valid THEN x.numeric_code END,
   'claimedAt',x.claimed_at,'endsAt',x.end_at,'usedAt',x.used_at,'state',CASE WHEN x.used_at IS NOT NULL THEN 'used' WHEN x.valid THEN 'available' ELSE 'expired' END) ORDER BY x.id)
  INTO data FROM (
   SELECT c.*,o.title,o.terms,s.published->>'name' AS shop_name,upper(o.period) AS end_at,
    s.state<>'suspended' AND o.period @> now() AND c.used_at IS NULL AS valid
   FROM hyt_commerce.coupons c JOIN hyt_commerce.offers o ON o.id=c.offer_id JOIN hyt_commerce.shops s ON s.id=c.shop_id
   WHERE c.member_id=actor AND (cursor_id IS NULL OR c.id>cursor_id) AND (action='wallet' OR c.id=arg_id) ORDER BY c.id LIMIT 21
  ) x;
  IF action='coupon' THEN
   IF data IS NULL THEN RETURN hyt_commerce.error('not_found',404); END IF;
   RETURN jsonb_build_object('status',200,'coupon',data->0);
  END IF;
  RETURN hyt_commerce.page(data)||'{"status":200}'::jsonb;
 ELSIF action='merchant.redeem' THEN
  -- A durable, per-shop verification allowance protects both QR and manual codes.
  PERFORM pg_advisory_xact_lock(hashtextextended('commerce:redeem:'||own_shop,0));
  IF (SELECT count(*) FROM hyt_commerce.audit u WHERE u.subject=own_shop AND u.action='redeem.attempt' AND u.created_at>=now()-interval '1 minute')>=30
   THEN RETURN hyt_commerce.error('too_many_requests',429); END IF;
  INSERT INTO hyt_commerce.audit(actor,action,subject,details) VALUES(actor,'redeem.attempt',own_shop,'{}');
  SELECT * INTO shop FROM hyt_commerce.shops s WHERE s.id=own_shop FOR UPDATE;
  IF shop.state='suspended' OR shop.published IS NULL THEN RETURN hyt_commerce.error('shop_unavailable',409); END IF;
  SELECT * INTO coupon FROM hyt_commerce.coupons c WHERE c.shop_id=own_shop AND c.numeric_code=b->>'code' FOR UPDATE;
  IF NOT FOUND THEN RETURN hyt_commerce.error('invalid_coupon',404); END IF;
  IF coupon.used_at IS NOT NULL THEN RETURN hyt_commerce.error('already_redeemed',409); END IF;
  SELECT * INTO offer FROM hyt_commerce.offers o WHERE o.id=coupon.offer_id;
  IF coupon.member_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.hyt_members m WHERE m.id=coupon.member_id AND m.deleted_at IS NULL)
   OR NOT offer.period @> now() THEN RETURN hyt_commerce.error('offer_unavailable',409); END IF;
  UPDATE hyt_commerce.coupons c SET used_at=now() WHERE c.id=coupon.id AND c.used_at IS NULL;
  IF NOT FOUND THEN RETURN hyt_commerce.error('already_redeemed',409); END IF;
  PERFORM hyt_commerce.bump(today,own_shop,own_shop,'redeem');
  RETURN jsonb_build_object('status',200,'title',offer.title,'usedAt',now());
 ELSIF action='admin.report' THEN
  UPDATE hyt_commerce.reports r SET resolved_at=now(),resolution=b->>'reason' WHERE r.id=arg_id AND r.resolved_at IS NULL;
  IF NOT FOUND THEN RETURN hyt_commerce.error('not_found',404); END IF;
  target:=arg_id;
 ELSIF action='metrics' THEN
  -- Daily HMACs are scoped to each event target. Only a grouped total reaches reporting.
  WITH input AS (
   SELECT DISTINCT f.value->>'kind' AS k,(f.value->>'id')::uuid AS t,encode(sha256(convert_to((b->>'dailyKey')||':'||actor||':'||(f.value->>'kind')||':'||(f.value->>'id'),'UTF8')),'hex') AS sig
   FROM jsonb_array_elements(b->'events') f(value)
  ), valid AS (
   SELECT e.*,a.shop_id AS s FROM input e JOIN hyt_commerce.active_ads(NULL,ios) a ON a.id=e.t WHERE e.k='impression'
   UNION
   SELECT e.*,x.id AS s FROM input e JOIN hyt_commerce.shops x ON x.id=e.t WHERE e.k='visit' AND x.state<>'suspended' AND x.published IS NOT NULL
  ), added AS (
   INSERT INTO hyt_commerce.metric_seen AS seen(day,signature,target,kind) SELECT today,sig,t,k FROM valid
    ORDER BY sig,t,k ON CONFLICT DO NOTHING RETURNING seen.signature,seen.target,seen.kind
  )
  INSERT INTO hyt_commerce.metrics(day,shop_id,target,kind,total)
   SELECT today,v.s,v.t,v.k,count(*) FROM valid v JOIN added a ON (a.signature,a.target,a.kind)=(v.sig,v.t,v.k)
   GROUP BY v.s,v.t,v.k ORDER BY v.s,v.t,v.k
   ON CONFLICT ON CONSTRAINT metrics_pkey DO UPDATE SET total=metrics.total+EXCLUDED.total;
  RETURN '{"status":200}'::jsonb;
 ELSIF action IN ('merchant.stats','admin.stats') THEN
  arg_stats_shop:=CASE WHEN action='merchant.stats' THEN own_shop ELSE shop_id_arg END;
  IF action='merchant.stats' AND NOT EXISTS (
   SELECT 1 FROM hyt_commerce.contracts c WHERE c.shop_id=arg_stats_shop AND c.cancelled_at IS NULL AND (c.snapshot->>'reports')::boolean
    AND c.period && tstzrange(((today-29)::timestamp AT TIME ZONE 'Asia/Shanghai'),now(),'[]')
  ) THEN RETURN hyt_commerce.error('report_plan_required',403); END IF;
  IF arg_stats_shop IS NOT NULL AND NOT EXISTS(SELECT 1 FROM hyt_commerce.shops s WHERE s.id=arg_stats_shop) THEN RETURN hyt_commerce.error('not_found',404); END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.day,x.kind),'[]') INTO data FROM (
   SELECT m.day,m.kind,sum(m.total) AS total FROM hyt_commerce.metrics m WHERE (arg_stats_shop IS NULL OR m.shop_id=arg_stats_shop) AND m.day BETWEEN today-29 AND today
   GROUP BY m.day,m.kind
  ) x;
  RETURN jsonb_build_object('status',200,'days',data);
 ELSE RETURN hyt_commerce.error('not_found',404);
 END IF;
 INSERT INTO hyt_commerce.audit(actor,action,subject,details) VALUES(actor,action,target,b);
 RETURN jsonb_build_object('status',200,'id',target);
END $fn$;
CREATE INDEX IF NOT EXISTS commerce_redeem_throttle ON hyt_commerce.audit(subject,created_at) WHERE action='redeem.attempt';

-- Invoke daily through the CloudBase maintenance job, using a server-only principal.
CREATE OR REPLACE FUNCTION hyt_commerce.prune_private() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,hyt_commerce AS $$
 DELETE FROM hyt_commerce.metric_seen WHERE day < (now() AT TIME ZONE 'Asia/Shanghai')::date-1;
 DELETE FROM hyt_commerce.audit WHERE action='redeem.attempt' AND created_at<now()-interval '2 days';
 DELETE FROM hyt_commerce.access x USING public.hyt_members m WHERE m.id=x.member_id AND m.deleted_at IS NOT NULL;
 DELETE FROM hyt_commerce.favorites f USING public.hyt_members m WHERE m.id=f.member_id AND m.deleted_at IS NOT NULL;
 UPDATE hyt_commerce.coupons c SET member_id=NULL FROM public.hyt_members m WHERE m.id=c.member_id AND m.deleted_at IS NOT NULL;
 UPDATE hyt_commerce.reports SET report_key=id::text WHERE created_at<now()-interval '2 days' AND report_key<>id::text;
$$;
DO $$ DECLARE role_name text; obj record; BEGIN
 REVOKE ALL ON ALL FUNCTIONS IN SCHEMA hyt_commerce FROM PUBLIC;
 REVOKE ALL ON ALL TABLES IN SCHEMA hyt_commerce FROM PUBLIC;
 FOR obj IN SELECT tablename FROM pg_tables WHERE schemaname='hyt_commerce' LOOP
  EXECUTE format('ALTER TABLE hyt_commerce.%I ENABLE ROW LEVEL SECURITY',obj.tablename);
 END LOOP;
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=role_name) THEN
   EXECUTE format('REVOKE ALL ON SCHEMA hyt_commerce FROM %I',role_name);
   EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA hyt_commerce FROM %I',role_name);
   EXECUTE format('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA hyt_commerce FROM %I',role_name);
  END IF;
 END LOOP;
END $$;
-- Storage policies are installed with the migration when CloudBase provisions storage.
DO $$ BEGIN
 IF to_regclass('storage.objects') IS NOT NULL AND to_regclass('storage.buckets') IS NOT NULL
 AND EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') AND EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
  DROP POLICY IF EXISTS hyt_commerce_private_objects ON storage.objects;
  CREATE POLICY hyt_commerce_private_objects ON storage.objects AS RESTRICTIVE FOR ALL TO anon,authenticated
   USING(bucket_id<>'hyt-commerce') WITH CHECK(bucket_id<>'hyt-commerce');
  DROP POLICY IF EXISTS hyt_commerce_private_bucket ON storage.buckets;
  CREATE POLICY hyt_commerce_private_bucket ON storage.buckets AS RESTRICTIVE FOR ALL TO anon,authenticated
   USING(id<>'hyt-commerce') WITH CHECK(id<>'hyt-commerce');
 END IF;
END $$;
COMMIT;
