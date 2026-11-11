begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000101', 'authenticated',
    'authenticated', 'ops-admin@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000102', 'authenticated',
    'authenticated', 'ops-dist-1@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000103', 'authenticated',
    'authenticated', 'ops-dist-2@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000104', 'authenticated',
    'authenticated', 'ops-production@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000105', 'authenticated',
    'authenticated', 'ops-factory@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000106', 'authenticated',
    'authenticated', 'ops-outlet-other@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000107', 'authenticated',
    'authenticated', 'ops-collector@alwaha.invalid', '', now(), '{}', '{}', now(), now());

insert into public.customer_types (id, name)
values ('10000000-0000-0000-0000-000000000101', 'اختبار دورة التشغيل');
insert into public.pickup_locations (id, name)
values
  ('20000000-0000-0000-0000-000000000101', 'موقع تشغيل الاختبار'),
  ('20000000-0000-0000-0000-000000000102', 'موقع تشغيل آخر');
insert into public.external_outlets (id, name, pickup_location_id)
values
  ('30000000-0000-0000-0000-000000000101',
    'منفذ تشغيل الاختبار', '20000000-0000-0000-0000-000000000101'),
  ('30000000-0000-0000-0000-000000000102',
    'منفذ تشغيل آخر', '20000000-0000-0000-0000-000000000102');
insert into public.distributors (id, name, customer_type_id)
values
  ('40000000-0000-0000-0000-000000000101', 'موزع اختبار أول',
    '10000000-0000-0000-0000-000000000101'),
  ('40000000-0000-0000-0000-000000000102', 'موزع اختبار ثان',
    '10000000-0000-0000-0000-000000000101');
insert into public.distributor_outlets (distributor_id, external_outlet_id)
values
  ('40000000-0000-0000-0000-000000000101', '30000000-0000-0000-0000-000000000101'),
  ('40000000-0000-0000-0000-000000000102', '30000000-0000-0000-0000-000000000101');
insert into public.products (id, code, name)
values ('50000000-0000-0000-0000-000000000101', 'OPS-001', 'صنف تشغيل اختباري');

update public.user_profiles set role = 'admin'
where user_id = '00000000-0000-0000-0000-000000000101';
update public.user_profiles set role = 'distributor',
  distributor_id = '40000000-0000-0000-0000-000000000101'
where user_id = '00000000-0000-0000-0000-000000000102';
update public.user_profiles set role = 'distributor',
  distributor_id = '40000000-0000-0000-0000-000000000102'
where user_id = '00000000-0000-0000-0000-000000000103';
update public.user_profiles set role = 'production_manager'
where user_id = '00000000-0000-0000-0000-000000000104';
update public.user_profiles set role = 'factory_outlet_manager',
  pickup_location_id = '20000000-0000-0000-0000-000000000101'
where user_id = '00000000-0000-0000-0000-000000000105';
update public.user_profiles set role = 'outlet_manager',
  external_outlet_id = '30000000-0000-0000-0000-000000000102'
where user_id = '00000000-0000-0000-0000-000000000106';
update public.user_profiles set role = 'collector',
  external_outlet_id = '30000000-0000-0000-0000-000000000101'
where user_id = '00000000-0000-0000-0000-000000000107';

select no_plan();
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.save_pricing_policy(
    null, 'سياسة اختبار التشغيل', 'external_outlet', null, null,
    '30000000-0000-0000-0000-000000000101', now() - interval '1 day',
    '[{"product_id":"50000000-0000-0000-0000-000000000101",
       "factory_purchase_price":3,"distributor_sale_price":5}]'::jsonb
  )$$,
  'الإدارة تجهز سعرًا لاختبار دورة الطلب'
);

create temporary table test_orders (distributor_id uuid, order_id uuid);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',
  true
);
insert into test_orders values (
  '40000000-0000-0000-0000-000000000101',
  public.create_sales_order(
    '20000000-0000-0000-0000-000000000101',
    '30000000-0000-0000-0000-000000000101',
    current_date + 2,
    '[{"product_id":"50000000-0000-0000-0000-000000000101","quantity":1}]'::jsonb
  )
);
select public.submit_sales_order(order_id) from test_orders;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000103","role":"authenticated"}',
  true
);
insert into test_orders values (
  '40000000-0000-0000-0000-000000000102',
  public.create_sales_order(
    '20000000-0000-0000-0000-000000000101',
    '30000000-0000-0000-0000-000000000101',
    current_date + 2,
    '[{"product_id":"50000000-0000-0000-0000-000000000101","quantity":2}]'::jsonb
  )
);
select public.submit_sales_order(order_id)
from test_orders
where distributor_id = '40000000-0000-0000-0000-000000000102';

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.review_sales_order(order_id, 'approved', null)
    from test_orders$$,
  'الإدارة تعتمد الطلبات المقدمة'
);
select lives_ok(
  $$select public.create_production_batch(
    '20000000-0000-0000-0000-000000000101',
    current_date + 2,
    array(select order_id from test_orders)
  )$$,
  'الإنتاج يجمع الطلبات المعتمدة في دفعة'
);

create temporary table test_batch as
select id from public.production_batches;
select set_config(
  'test.batch_id',
  (select id::text from test_batch),
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000104","role":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  $$select public.finalize_production_batch(
    current_setting('test.batch_id')::uuid,
    '[{"product_id":"50000000-0000-0000-0000-000000000101",
       "produced_quantity":5,"rejected_quantity":1,
       "variance_reason":"اختبار فرق الإنتاج"}]'::jsonb
  )$$,
  'اعتماد الإنتاج يحفظ التالف والإنتاج السليم'
);
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000104","role":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.approve_production_distribution(
    current_setting('test.batch_id')::uuid
  )$$,
  'P0001',
  'Only an administrator can approve production distribution',
  'مسؤول الإنتاج لا يستطيع اعتماد التوزيع'
);
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  $$select public.approve_production_distribution(
    current_setting('test.batch_id')::uuid
  )$$,
  'الإدارة تعتمد مجموع التوزيع قبل التسليم'
);
reset role;
select is(
  (select sum(allocated_quantity) from public.production_allocations),
  5::bigint,
  'التوزيع النسبي بالبواقي الأكبر يطابق الإنتاج المتاح'
);
select is(
  (select sum(allocated_quantity)
   from public.production_allocations allocation
   join public.sales_order_lines line on line.id = allocation.order_line_id
   join public.sales_orders orders on orders.id = line.order_id
   where orders.distributor_id = '40000000-0000-0000-0000-000000000101'),
  2::bigint,
  'حصة الموزع ذي الطلب الأصغر تأخذ أكبر باقي نسبي'
);
select is(
  (select sum(allocated_quantity)
   from public.production_allocations allocation
   join public.sales_order_lines line on line.id = allocation.order_line_id
   join public.sales_orders orders on orders.id = line.order_id
   where orders.distributor_id = '40000000-0000-0000-0000-000000000102'),
  3::bigint,
  'حصة الموزع الثاني تأخذ حصته النسبية من الإنتاج'
);
select is(
  (select quantity from public.inventory_balances
   where pickup_location_id = '20000000-0000-0000-0000-000000000101'
     and product_id = '50000000-0000-0000-0000-000000000101'),
  5,
  'الإنتاج السليم يزيد مخزون موقع الاستلام'
);
select set_config(
  'test.delivery_order_id',
  (select order_id::text from test_orders
   where distributor_id = '40000000-0000-0000-0000-000000000101'),
  true
);
select set_config(
  'test.delivery_lines',
  (select jsonb_agg(jsonb_build_object(
     'order_line_id', allocation.order_line_id,
     'quantity', allocation.allocated_quantity
   ))::text from public.production_allocations allocation
   join public.sales_order_lines line on line.id = allocation.order_line_id
   where line.order_id = current_setting('test.delivery_order_id')::uuid),
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000105","role":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  $$select public.record_order_delivery(
    current_setting('test.delivery_order_id')::uuid,
    'ops-test-delivery-one',
    current_setting('test.delivery_lines')::jsonb,
    null
  )$$,
  'يتم تسجيل تسليم فعلي للموزع'
);
reset role;
-- مسؤول منفذ المصنع لا يرى الأرصدة المالية بتصميم النظام، فنقرأ الحساب بصفة المدير
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',
  true
);
select is(
  (select balance
   from public.operational_distributor_account_balances
   where distributor_id = '40000000-0000-0000-0000-000000000101'),
  10::numeric,
  'الحساب يضيف قيمة التسليم بسعره المثبت'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000107","role":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  $$select public.record_distributor_payment(
    '40000000-0000-0000-0000-000000000101',
    '30000000-0000-0000-0000-000000000101',
    3.00,
    now()
  )$$,
  'المحصّل المرتبط بالمنفذ يسجل تحصيل الموزع'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  $$select set_config(
    'test.return_request_id',
    public.submit_return_request(
      (select id from public.role_orders
       where distributor_id = '40000000-0000-0000-0000-000000000101'
       limit 1),
      'طلب مرتجع بعد التسليم',
      (select jsonb_agg(jsonb_build_object(
        'order_line_id', id,
        'quantity', 1
      )) from public.role_order_quantities
       where order_id = (
         select id from public.role_orders
         where distributor_id = '40000000-0000-0000-0000-000000000101'
         limit 1
       ))
    )::text,
    true
  )$$,
  'الموزع يطلب مرتجعًا ضمن الكمية التي تسلمها'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  $$select public.decide_return_request(
    current_setting('test.return_request_id')::uuid,
    'credit',
    'اعتماد مرتجع الاختبار',
    (select jsonb_agg(jsonb_build_object(
      'return_line_id', id,
      'approved_quantity', 1
    )) from public.role_return_quantities
     where return_request_id =
       current_setting('test.return_request_id')::uuid)
  )$$,
  'الإدارة تعتمد المرتجع بكميته المصرح بها'
);
reset role;
select is(
  (select status from public.return_requests
   where id = current_setting('test.return_request_id')::uuid),
  'approved',
  'قرار المرتجع المسجل أصبح معتمدًا'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000104","role":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.production_price_rows',
  (select count(*)::text from public.role_financial_order_lines),
  true
);
select set_config(
  'test.production_balance_rows',
  (select count(*)::text from public.operational_distributor_account_balances),
  true
);
reset role;
select is(current_setting('test.production_price_rows')::integer, 0,
  'مسؤول الإنتاج لا يرى واجهة أسعار الطلب');
select is(current_setting('test.production_balance_rows')::integer, 0,
  'مسؤول الإنتاج لا يرى أرصدة الحسابات');
select ok(
  not has_table_privilege('authenticated', 'public.sales_order_lines', 'SELECT'),
  'جداول الطلبات المالية غير متاحة مباشرة لمستخدمي العميل'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000105","role":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.factory_distributor_count',
  (select count(*)::text from public.distributors),
  true
);
reset role;
select is(current_setting('test.factory_distributor_count')::integer, 2,
  'مسؤول منفذ المصنع يرى الموزعين المرتبطين بموقعه دون تسرب مالي');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'test.crate_type_id',
  (select id::text from public.crate_types where code = 'standard'),
  true
);
set local role authenticated;
select lives_ok(
  $$select public.record_crate_movement(
    '40000000-0000-0000-0000-000000000101',
    '30000000-0000-0000-0000-000000000101',
    '20000000-0000-0000-0000-000000000101',
    current_setting('test.crate_type_id')::uuid,
    'issued', 2
  )$$,
  'الإدارة تسجل حركة برانيك للموزع والمنفذ المرتبطين'
);
select lives_ok(
  $$select public.record_crate_movement(
    '40000000-0000-0000-0000-000000000102',
    '30000000-0000-0000-0000-000000000101',
    '20000000-0000-0000-0000-000000000101',
    current_setting('test.crate_type_id')::uuid,
    'issued', 2
  )$$,
  'الإدارة تسجل حركة مستقلة للموزع الثاني'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000102","role":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.dist_one_other_crate_count',
  (select count(*)::text from public.role_crate_movements
   where distributor_id = '40000000-0000-0000-0000-000000000102'),
  true
);
select set_config(
  'test.dist_one_other_order_count',
  (select count(*)::text from public.role_orders
   where distributor_id = '40000000-0000-0000-0000-000000000102'),
  true
);
reset role;
select is(current_setting('test.dist_one_other_crate_count')::integer, 0,
  'الموزع الأول لا يرى حركة برانيك الموزع الثاني');
select is(current_setting('test.dist_one_other_order_count')::integer, 0,
  'الموزع الأول لا يرى طلبات الموزع الثاني');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000103","role":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.dist_two_other_crate_count',
  (select count(*)::text from public.role_crate_movements
   where distributor_id = '40000000-0000-0000-0000-000000000101'),
  true
);
reset role;
select is(current_setting('test.dist_two_other_crate_count')::integer, 0,
  'الموزع الثاني لا يرى حركة برانيك الموزع الأول');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000106","role":"authenticated"}',
  true
);
select set_config(
  'test.other_outlet_crate_type_id',
  current_setting('test.crate_type_id'),
  true
);
set local role authenticated;
select set_config(
  'test.other_outlet_order_count',
  (select count(*)::text from public.role_orders
   where external_outlet_id <> '30000000-0000-0000-0000-000000000102'),
  true
);
select set_config(
  'test.other_outlet_crate_count',
  (select count(*)::text from public.role_crate_movements
   where external_outlet_id <> '30000000-0000-0000-0000-000000000102'),
  true
);
reset role;
select is(current_setting('test.other_outlet_order_count')::integer, 0,
  'مسؤول المنفذ الآخر لا يرى طلبات منفذ التشغيل');
select is(current_setting('test.other_outlet_crate_count')::integer, 0,
  'مسؤول المنفذ الآخر لا يرى حركات برانيك منفذ التشغيل');
select throws_ok(
  $$select public.record_crate_movement(
    '40000000-0000-0000-0000-000000000101',
    '30000000-0000-0000-0000-000000000102',
    '20000000-0000-0000-0000-000000000102',
    current_setting('test.other_outlet_crate_type_id')::uuid,
    'issued', 1
  )$$,
  'P0001',
  'The distributor is not assigned to this outlet',
  'مسؤول المنفذ لا يسجل حركة لموزع غير مربوط بمنفذه'
);
select throws_ok(
  $$select public.record_crate_movement(
    '40000000-0000-0000-0000-000000000101',
    '30000000-0000-0000-0000-000000000101',
    '20000000-0000-0000-0000-000000000101',
    (select id from public.crate_types where code = 'standard'),
    'issued', 1
  )$$,
  'P0001',
  'The user is not authorized to record crate movements',
  'مسؤول منفذ آخر لا يسجل حركة خارج منفذه'
);
reset role;

select * from finish();
rollback;
