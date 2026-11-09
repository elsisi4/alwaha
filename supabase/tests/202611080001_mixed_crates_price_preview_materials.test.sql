begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

insert into public.customer_types (id, name)
values ('10000000-0000-0000-0000-000000000601', 'نوع اختبار الأسعار');
insert into public.pickup_locations (id, name)
values ('20000000-0000-0000-0000-000000000601', 'موقع اختبار الأسعار');
insert into public.external_outlets (id, name, pickup_location_id)
values ('30000000-0000-0000-0000-000000000601', 'منفذ اختبار الأسعار',
  '20000000-0000-0000-0000-000000000601');
insert into public.distributors (id, name, customer_type_id)
values ('40000000-0000-0000-0000-000000000601', 'موزع اختبار الأسعار',
  '10000000-0000-0000-0000-000000000601');
insert into public.distributor_outlets (distributor_id, external_outlet_id)
values ('40000000-0000-0000-0000-000000000601',
  '30000000-0000-0000-0000-000000000601');
insert into public.products (id, code, name, crate_capacity) values
  ('50000000-0000-0000-0000-0000000006a1', 'PT-A', 'صنف أ', 75),
  ('50000000-0000-0000-0000-0000000006b1', 'PT-B', 'صنف ب', 75),
  ('50000000-0000-0000-0000-0000000006c1', 'PT-C', 'صنف ج بلا وصفة', 60);
insert into public.raw_materials (id, code, name, unit)
values ('60000000-0000-0000-0000-000000000601', 'PT-M', 'لبن', 'لتر');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-0000000006a1', 'authenticated', 'authenticated',
    'pt-admin@alwaha.invalid', '', now(), '{"role":"admin"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-0000000006a2', 'authenticated', 'authenticated',
    'pt-dist@alwaha.invalid', '', now(), '{}', '{}', now(), now());
update public.user_profiles set role = 'distributor',
  distributor_id = '40000000-0000-0000-0000-000000000601'
where user_id = '00000000-0000-0000-0000-0000000006a2';

select no_plan();

select is(public.crates_needed(array[1000, 1000], array[75, 75]), 27,
  'صنفان 1000 + 1000 بسعة 75 = 27 برنيكة مشتركة');
select is(public.crates_needed(array[1500], array[75]), 20, '1500 ÷ 75 = 20');
select is(public.crates_needed(array[1520], array[75]), 21, '1520 ÷ 75 تقرّب إلى 21');
select is(public.crates_needed(array[100, 90], array[50, 60]), 4,
  'سعات مختلفة: 2 + 1.5 = 3.5 تقرّب إلى 4');
select is(public.crates_needed(array[2, 2, 2], array[3, 3, 3]), 2,
  'الكسور الدقيقة لا تتأثر بتقريب الأعداد العشرية');
select throws_ok(
  $$select public.crates_needed(array[10], array[0])$$,
  'P0001', 'Crate quantities must be nonnegative and capacities positive',
  'سعة صفرية مرفوضة'
);

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000006a1","role":"authenticated"}', true);
select lives_ok($$select public.save_pricing_policy(
  null, 'سياسة منفذ', 'external_outlet', null, null,
  '30000000-0000-0000-0000-000000000601', now() - interval '1 day',
  '[{"product_id":"50000000-0000-0000-0000-0000000006a1","factory_purchase_price":9,"distributor_sale_price":10},
    {"product_id":"50000000-0000-0000-0000-0000000006b1","factory_purchase_price":9,"distributor_sale_price":10.5}]'::jsonb)$$,
  'سياسة سعر المنفذ');
select lives_ok($$select public.save_pricing_policy(
  null, 'سياسة نوع العميل', 'customer_type',
  '10000000-0000-0000-0000-000000000601', null, null, now() - interval '1 day',
  '[{"product_id":"50000000-0000-0000-0000-0000000006a1","sale_price":12},
    {"product_id":"50000000-0000-0000-0000-0000000006c1","sale_price":7}]'::jsonb)$$,
  'سياسة نوع العميل');
select lives_ok($$select public.save_product_recipe(
  '50000000-0000-0000-0000-0000000006a1', now() - interval '1 day',
  '[{"raw_material_id":"60000000-0000-0000-0000-000000000601","quantity_per_sales_unit":0.1,"waste_percent":10}]'::jsonb)$$,
  'وصفة الصنف أ');
select lives_ok($$select public.save_product_recipe(
  '50000000-0000-0000-0000-0000000006b1', now() - interval '1 day',
  '[{"raw_material_id":"60000000-0000-0000-0000-000000000601","quantity_per_sales_unit":0.2,"waste_percent":0}]'::jsonb)$$,
  'وصفة الصنف ب');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000006a2","role":"authenticated"}', true);
select is(
  (select unit_price from public.get_order_price_list('30000000-0000-0000-0000-000000000601')
   where product_id = '50000000-0000-0000-0000-0000000006a1'),
  10::numeric, 'سياسة المنفذ تتفوق على سياسة نوع العميل');
select is(
  (select unit_price from public.get_order_price_list('30000000-0000-0000-0000-000000000601')
   where product_id = '50000000-0000-0000-0000-0000000006c1'),
  7::numeric, 'غياب سعر المنفذ يعود إلى سياسة نوع العميل');
select throws_ok(
  $$select * from public.get_order_price_list('30000000-0000-0000-0000-000000000699')$$,
  'P0001', 'The distributor is not authorized for this outlet',
  'المندوب لا يرى أسعار منفذ غير مرتبط به'
);

create temporary table pt_order (id uuid);
insert into pt_order
select public.create_sales_order(
  '20000000-0000-0000-0000-000000000601',
  '30000000-0000-0000-0000-000000000601',
  '[{"product_id":"50000000-0000-0000-0000-0000000006a1","quantity":1000},
    {"product_id":"50000000-0000-0000-0000-0000000006b1","quantity":1000}]'::jsonb);
select is(
  (select requested_crates from public.role_order_crates
   where order_id = (select id from pt_order)),
  27, 'طلب 1000 + 1000 يظهر 27 برنيكة');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000006a1","role":"authenticated"}', true);
select is(
  (select quantity from public.production_material_requirements(
     array[(select id from pt_order)], current_date)
   where kind = 'material'
     and item_id = '60000000-0000-0000-0000-000000000601'),
  310::numeric, 'احتياج اللبن: 1000×0.1×1.1 + 1000×0.2 = 310');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000006a2","role":"authenticated"}', true);
select throws_ok(
  $$select * from public.production_material_requirements(array[gen_random_uuid()], current_date)$$,
  'P0001', 'Only administration or production can calculate material requirements',
  'المندوب لا يحسب الخامات'
);

select * from finish();
rollback;
