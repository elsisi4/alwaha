begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000301', 'authenticated',
    'authenticated', 'dec-admin@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000302', 'authenticated',
    'authenticated', 'dec-dist@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000303', 'authenticated',
    'authenticated', 'dec-acct@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000304', 'authenticated',
    'authenticated', 'dec-prod@alwaha.invalid', '', now(), '{}', '{}', now(), now());

insert into public.customer_types (id, name)
values ('10000000-0000-0000-0000-000000000301', 'اختبار قرارات الطلبات');
insert into public.pickup_locations (id, name)
values ('20000000-0000-0000-0000-000000000301', 'موقع قرارات الطلبات');
insert into public.external_outlets (
  id, name, pickup_location_id, allowed_roles
) values (
  '30000000-0000-0000-0000-000000000301', 'منفذ قرارات الطلبات',
  '20000000-0000-0000-0000-000000000301',
  array['outlet_manager', 'collector']::text[]
);
insert into public.distributors (id, name, customer_type_id)
values ('40000000-0000-0000-0000-000000000301', 'موزع قرارات الطلبات',
  '10000000-0000-0000-0000-000000000301');
insert into public.distributor_outlets (
  distributor_id, external_outlet_id, vehicle_group
) values (
  '40000000-0000-0000-0000-000000000301',
  '30000000-0000-0000-0000-000000000301', 'vehicle_1'
);
insert into public.products (id, code, name, crate_capacity)
values ('50000000-0000-0000-0000-000000000301', 'DEC-001', 'صنف قرارات', 3);

update public.user_profiles set role = 'admin'
where user_id = '00000000-0000-0000-0000-000000000301';
update public.user_profiles set role = 'distributor',
  distributor_id = '40000000-0000-0000-0000-000000000301'
where user_id = '00000000-0000-0000-0000-000000000302';
update public.user_profiles set role = 'accountant'
where user_id = '00000000-0000-0000-0000-000000000303';
update public.user_profiles set role = 'production_manager'
where user_id = '00000000-0000-0000-0000-000000000304';

select no_plan();

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000301","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.save_pricing_policy(
    null, 'سياسة اختبار القرارات', 'external_outlet', null, null,
    '30000000-0000-0000-0000-000000000301', now() - interval '1 day',
    '[{"product_id":"50000000-0000-0000-0000-000000000301",
       "factory_purchase_price":3,"distributor_sale_price":5}]'::jsonb
  )$$,
  'إعداد سياسة أسعار الاختبار'
);

create temporary table dec_orders (purpose text, order_id uuid);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000302","role":"authenticated"}',
  true
);
insert into dec_orders
select p, public.create_sales_order(
  '20000000-0000-0000-0000-000000000301',
  '30000000-0000-0000-0000-000000000301',
  '[{"product_id":"50000000-0000-0000-0000-000000000301","quantity":4}]'::jsonb
)
from unnest(array[
  'acct_approve', 'acct_reject', 'admin_reject', 'acct_cancel', 'prod_try'
]) as p;
select public.submit_sales_order(order_id) from dec_orders;

-- المحاسب
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000303","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.review_sales_order(
    (select order_id from dec_orders where purpose = 'acct_approve'),
    'approved', null)$$,
  'المحاسب يعتمد طلب المندوب'
);
select is(
  (select status from public.sales_orders
   where id = (select order_id from dec_orders where purpose = 'acct_approve')),
  'approved',
  'حالة الطلب بعد اعتماد المحاسب معتمد'
);
select is(
  (select decision_by from public.sales_orders
   where id = (select order_id from dec_orders where purpose = 'acct_approve')),
  '00000000-0000-0000-0000-000000000303'::uuid,
  'قرار المحاسب مسجل باسمه'
);
select throws_ok(
  $$select public.review_sales_order(
    (select order_id from dec_orders where purpose = 'acct_reject'),
    'rejected', null)$$,
  'P0001',
  'A reason is required to reject or cancel an order',
  'المحاسب لا يرفض دون سبب'
);
select throws_ok(
  $$select public.review_sales_order(
    (select order_id from dec_orders where purpose = 'acct_reject'),
    'rejected', '   ')$$,
  'P0001',
  'A reason is required to reject or cancel an order',
  'سبب الرفض لا يقبل مسافات فقط'
);
select lives_ok(
  $$select public.review_sales_order(
    (select order_id from dec_orders where purpose = 'acct_reject'),
    'rejected', 'الكمية غير متاحة')$$,
  'المحاسب يرفض الطلب مع السبب'
);
select is(
  (select status_reason from public.sales_orders
   where id = (select order_id from dec_orders where purpose = 'acct_reject')),
  'الكمية غير متاحة',
  'سبب رفض المحاسب محفوظ'
);
select throws_ok(
  $$select public.review_sales_order(
    (select order_id from dec_orders where purpose = 'acct_cancel'),
    'cancelled', 'سبب')$$,
  'P0001',
  'The user is not authorized to review orders',
  'المحاسب لا يملك إلغاء الطلب'
);
select throws_ok(
  $$select public.review_sales_order(
    (select order_id from dec_orders where purpose = 'acct_approve'),
    'rejected', 'رفض متأخر')$$,
  'P0001',
  'Order was not found or cannot transition to the requested state',
  'لا يمكن رفض طلب معتمد بالفعل'
);

-- المدير
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000301","role":"authenticated"}',
  true
);
select throws_ok(
  $$select public.review_sales_order(
    (select order_id from dec_orders where purpose = 'admin_reject'),
    'rejected', null)$$,
  'P0001',
  'A reason is required to reject or cancel an order',
  'المدير لا يرفض دون سبب'
);
select lives_ok(
  $$select public.review_sales_order(
    (select order_id from dec_orders where purpose = 'admin_reject'),
    'rejected', 'مخالف لسياسة الاستلام')$$,
  'المدير يرفض الطلب مع السبب'
);
select lives_ok(
  $$select public.review_sales_order(
    (select order_id from dec_orders where purpose = 'acct_cancel'),
    'cancelled', 'إلغاء إداري')$$,
  'المدير يملك الإلغاء'
);

-- الإنتاج لا يقرر
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000304","role":"authenticated"}',
  true
);
select throws_ok(
  $$select public.review_sales_order(
    (select order_id from dec_orders where purpose = 'prod_try'),
    'approved', null)$$,
  'P0001',
  'The user is not authorized to review orders',
  'دور الإنتاج لا يعتمد الطلبات'
);

-- المندوب لا يقرر ويرى سبب الرفض لطلبه فقط
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000302","role":"authenticated"}',
  true
);
select throws_ok(
  $$select public.review_sales_order(
    (select order_id from dec_orders where purpose = 'prod_try'),
    'approved', null)$$,
  'P0001',
  'The user is not authorized to review orders',
  'المندوب لا يعتمد طلبه'
);
set local role authenticated;
select set_config(
  'test.visible_reason',
  (select status_reason from public.role_orders
   where id = (select order_id from dec_orders where purpose = 'acct_reject')),
  true
);
reset role;
select is(
  current_setting('test.visible_reason'),
  'الكمية غير متاحة',
  'المندوب يرى سبب الرفض في طلبه'
);

select * from finish();
rollback;
