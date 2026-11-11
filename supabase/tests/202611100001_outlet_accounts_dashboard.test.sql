begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

insert into public.customer_types (id, name)
values ('10000000-0000-0000-0000-000000001001', 'نوع اختبار الحسابات');
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-0000000010a1', 'authenticated', 'authenticated',
    'oa-admin@alwaha.invalid', '', now(), '{"role":"admin"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-0000000010a2', 'authenticated', 'authenticated',
    'oa-mgr@alwaha.invalid', '', now(), '{}', '{}', now(), now());

select no_plan();

-- إضافة منفذ بخطوة واحدة
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000010a2","role":"authenticated"}', true);
select throws_ok(
  $$select public.create_outlet('منفذ ممنوع')$$,
  'P0001', 'Only an administrator can add outlets',
  'غير المدير لا يضيف منفذًا'
);

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000010a1","role":"authenticated"}', true);
create temporary table oa_outlets (name text, id uuid);
insert into oa_outlets values
  ('main', public.create_outlet('اختبار حسابات')),
  ('other', public.create_outlet('منفذ آخر للحسابات'));
select is(
  (select name from public.external_outlets
   where id = (select id from oa_outlets where name = 'main')),
  'منفذ اختبار حسابات', 'يُضاف الاسم بالبادئة «منفذ»');
select is(
  (select name from public.external_outlets
   where id = (select id from oa_outlets where name = 'other')),
  'منفذ آخر للحسابات', 'لا تتكرر البادئة إن كتبها المدير');
select is(
  (select count(*) from public.pickup_locations
   where name = 'اختبار حسابات'), 1::bigint,
  'يُنشأ مكان الاستلام مع المنفذ تلقائيًا');
select throws_ok(
  $$select public.create_outlet('اختبار حسابات')$$,
  '23505', null, 'اسم المنفذ لا يتكرر');

-- مبيعات وتسليم وحسابات المنفذ
create temporary table oa_ctx (k text, v uuid);
do $$
declare
  outlet uuid := (select id from oa_outlets where name = 'main');
  pickup uuid;
  version_id uuid;
  prod uuid;
  d1 uuid;
  d2 uuid;
  o1 uuid;
  o2 uuid;
  batch uuid;
  l1 uuid;
  l2 uuid;
begin
  select pickup_location_id into pickup from public.external_outlets where id = outlet;
  insert into public.distributors (name, customer_type_id)
  values ('موزع حسابات أ', '10000000-0000-0000-0000-000000001001') returning id into d1;
  insert into public.distributors (name, customer_type_id)
  values ('موزع حسابات ب', '10000000-0000-0000-0000-000000001001') returning id into d2;
  insert into public.distributor_outlets (distributor_id, external_outlet_id)
  values (d1, outlet), (d2, outlet);
  insert into public.products (code, name, crate_capacity)
  values ('OA-1', 'صنف حسابات', 75) returning id into prod;
  perform public.save_pricing_policy(null, 'سياسة حسابات', 'external_outlet',
    null, null, outlet, now() - interval '1 day',
    jsonb_build_array(jsonb_build_object('product_id', prod,
      'factory_purchase_price', 9, 'distributor_sale_price', 10)));
  select v.id into version_id from public.price_policy_versions v
  join public.pricing_policies p on p.id = v.policy_id
  where p.external_outlet_id = outlet;
  insert into public.sales_orders (distributor_id, pickup_location_id,
    external_outlet_id, requested_for, status, created_by)
  values (d1, pickup, outlet, current_date + 2, 'approved',
    '00000000-0000-0000-0000-0000000010a1') returning id into o1;
  insert into public.sales_orders (distributor_id, pickup_location_id,
    external_outlet_id, requested_for, status, created_by)
  values (d2, pickup, outlet, current_date + 2, 'approved',
    '00000000-0000-0000-0000-0000000010a1') returning id into o2;
  insert into public.sales_order_lines (order_id, product_id, requested_quantity,
    policy_version_id, unit_price) values (o1, prod, 800, version_id, 10)
  returning id into l1;
  insert into public.sales_order_lines (order_id, product_id, requested_quantity,
    policy_version_id, unit_price) values (o2, prod, 1200, version_id, 10)
  returning id into l2;
  batch := public.create_production_batch(pickup, current_date + 2, array[o1, o2]);
  perform public.finalize_production_batch(batch, jsonb_build_array(
    jsonb_build_object('product_id', prod, 'produced_quantity', 2000,
      'rejected_quantity', 0)));
  perform public.approve_production_distribution(batch);
  perform public.record_order_delivery(o1, 'oa-1',
    jsonb_build_array(jsonb_build_object('order_line_id', l1, 'quantity', 800)));
  perform public.record_order_delivery(o2, 'oa-2',
    jsonb_build_array(jsonb_build_object('order_line_id', l2, 'quantity', 1200)));
  insert into oa_ctx values ('d1', d1), ('d2', d2);
end;
$$;

select is(
  (select sales_total from public.role_outlet_distributor_accounts
   where external_outlet_id = (select id from oa_outlets where name = 'main')
     and distributor_id = (select v from oa_ctx where k = 'd1')),
  8000::numeric, 'حساب المندوب الأول: 800 × 10');
select is(
  (select purchased_from_factory from public.role_outlet_account_summary
   where external_outlet_id = (select id from oa_outlets where name = 'main')),
  18000::numeric, 'مشتريات المنفذ بسعره الخاص: 2000 × 9');
select is(
  (select distributors_sales from public.role_outlet_account_summary
   where external_outlet_id = (select id from oa_outlets where name = 'main')),
  20000::numeric, 'مبيعات مناديب المنفذ: 2000 × 10');

select lives_ok($$select public.record_distributor_payment(
  (select v from oa_ctx where k = 'd1'),
  (select id from oa_outlets where name = 'main'), 3000)$$,
  'تحصيل من مندوب');
select lives_ok($$select public.record_outlet_payment(
  (select id from oa_outlets where name = 'main'), 5000)$$,
  'دفعة المنفذ للمصنع');
select is(
  (select outlet_balance from public.role_outlet_account_summary
   where external_outlet_id = (select id from oa_outlets where name = 'main')),
  13000::numeric, 'المتبقي على المنفذ = 18000 - 5000');
select is(
  (select distributors_balance from public.role_outlet_account_summary
   where external_outlet_id = (select id from oa_outlets where name = 'main')),
  17000::numeric, 'المستحق على المناديب = 20000 - 3000');

-- لوحة المدير
select is(
  ((public.admin_dashboard_summary() ->> 'today_production')::integer),
  2000, 'إنتاج اليوم في اللوحة');
select is(
  jsonb_array_length(public.admin_dashboard_summary() -> 'monthly_sales'),
  6, 'المبيعات الشهرية لآخر 6 أشهر');

-- مسؤول المنفذ يرى منفذه فقط ولا يقرأ اللوحة
update public.user_profiles
set role = 'outlet_manager',
    external_outlet_id = (select id from oa_outlets where name = 'main')
where user_id = '00000000-0000-0000-0000-0000000010a2';
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000010a2","role":"authenticated"}', true);
select is((select count(*) from public.role_outlet_account_summary), 1::bigint,
  'مسؤول المنفذ يرى ملخص منفذه فقط');
select is(
  (select count(*) from public.role_outlet_distributor_accounts
   where external_outlet_id = (select id from oa_outlets where name = 'other')),
  0::bigint, 'ولا يرى مناديب منفذ آخر');
select throws_ok(
  $$select public.admin_dashboard_summary()$$,
  'P0001', 'Only administration or accounting can read the dashboard',
  'اللوحة للمدير والمحاسب فقط');

select * from finish();
rollback;
