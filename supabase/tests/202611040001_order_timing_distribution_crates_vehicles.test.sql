begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000201', 'authenticated',
    'authenticated', 'new-admin@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000202', 'authenticated',
    'authenticated', 'new-dist-1@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000203', 'authenticated',
    'authenticated', 'new-dist-2@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000204', 'authenticated',
    'authenticated', 'new-outlet-a@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000205', 'authenticated',
    'authenticated', 'new-outlet-b@alwaha.invalid', '', now(), '{}', '{}', now(), now());

insert into public.customer_types (id, name)
values ('10000000-0000-0000-0000-000000000201', 'اختبار المتطلبات الجديدة');
insert into public.pickup_locations (id, name)
values ('20000000-0000-0000-0000-000000000201', 'موقع المتطلبات');
insert into public.external_outlets (
  id, name, pickup_location_id, allowed_roles
) values
  ('30000000-0000-0000-0000-000000000201', 'منفذ السيارة الأولى',
    '20000000-0000-0000-0000-000000000201',
    array['outlet_manager', 'collector']::text[]),
  ('30000000-0000-0000-0000-000000000202', 'منفذ السيارة الثانية',
    '20000000-0000-0000-0000-000000000201',
    array['outlet_manager', 'collector']::text[]),
  ('30000000-0000-0000-0000-000000000203', 'منفذ دون مسؤول',
    '20000000-0000-0000-0000-000000000201',
    array['collector']::text[]);
insert into public.distributors (id, name, customer_type_id)
values
  ('40000000-0000-0000-0000-000000000201', 'موزع السيارة الأولى',
    '10000000-0000-0000-0000-000000000201'),
  ('40000000-0000-0000-0000-000000000202', 'موزع السيارة الثانية',
    '10000000-0000-0000-0000-000000000201');
insert into public.distributor_outlets (
  distributor_id, external_outlet_id, vehicle_group
) values
  ('40000000-0000-0000-0000-000000000201',
    '30000000-0000-0000-0000-000000000201', 'vehicle_1'),
  ('40000000-0000-0000-0000-000000000202',
    '30000000-0000-0000-0000-000000000201', 'vehicle_2'),
  ('40000000-0000-0000-0000-000000000202',
    '30000000-0000-0000-0000-000000000202', 'shared');
insert into public.products (id, code, name, crate_capacity)
values
  ('50000000-0000-0000-0000-000000000201', 'NEW-001', 'صنف سعة ثلاثة', 3),
  ('50000000-0000-0000-0000-000000000202', 'NEW-002', 'صنف سعة اثنين', 2);

update public.user_profiles set role = 'admin'
where user_id = '00000000-0000-0000-0000-000000000201';
update public.user_profiles set role = 'distributor',
  distributor_id = '40000000-0000-0000-0000-000000000201'
where user_id = '00000000-0000-0000-0000-000000000202';
update public.user_profiles set role = 'distributor',
  distributor_id = '40000000-0000-0000-0000-000000000202'
where user_id = '00000000-0000-0000-0000-000000000203';
update public.user_profiles set role = 'outlet_manager',
  external_outlet_id = '30000000-0000-0000-0000-000000000201'
where user_id = '00000000-0000-0000-0000-000000000204';
update public.user_profiles set role = 'collector',
  external_outlet_id = '30000000-0000-0000-0000-000000000203'
where user_id = '00000000-0000-0000-0000-000000000205';

select no_plan();
select is(public.get_order_lead_days(), 2,
  'مدة الاستلام الافتراضية يومان');
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000201","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.set_order_lead_days(1)$$,
  'المدير يضبط المدة إلى يوم واحد'
);
select is(public.get_order_lead_days(), 1,
  'إعداد المدة الجديدة محفوظ');
select lives_ok(
  $$select public.save_pricing_policy(
    null, 'سياسة اختبار المتطلبات', 'external_outlet', null, null,
    '30000000-0000-0000-0000-000000000201', now() - interval '1 day',
    '[{"product_id":"50000000-0000-0000-0000-000000000201",
       "factory_purchase_price":3,"distributor_sale_price":5},
      {"product_id":"50000000-0000-0000-0000-000000000202",
       "factory_purchase_price":4,"distributor_sale_price":6}]'::jsonb
  )$$,
  'إعداد سياسة أسعار الاختبار'
);
select throws_ok(
  $$select public.save_distributor_assignments(
    '40000000-0000-0000-0000-000000000201',
    'موزع السيارة الأولى',
    '10000000-0000-0000-0000-000000000201',
    true,
    '[{"external_outlet_id":"30000000-0000-0000-0000-000000000201",
       "vehicle_group":"vehicle_1"},
      {"external_outlet_id":"30000000-0000-0000-0000-000000000201",
       "vehicle_group":"vehicle_2"}]'::jsonb
  )$$,
  'P0001',
  'An outlet can only be assigned once per distributor',
  'الإدارة لا تستطيع تكرار ربط المنفذ بالموزع'
);
select lives_ok(
  $$select public.save_distributor_assignments(
    '40000000-0000-0000-0000-000000000201',
    'موزع السيارة الأولى',
    '10000000-0000-0000-0000-000000000201',
    true,
    '[{"external_outlet_id":"30000000-0000-0000-0000-000000000201",
       "vehicle_group":"vehicle_1"}]'::jsonb
  )$$,
  'الإدارة تحفظ ارتباط الموزع بالمنفذ ومجموعة السيارة'
);

create temporary table new_test_orders (
  purpose text,
  distributor_id uuid,
  order_id uuid
);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000202","role":"authenticated"}',
  true
);
insert into new_test_orders values (
  'rejected',
  '40000000-0000-0000-0000-000000000201',
  public.create_sales_order(
    '20000000-0000-0000-0000-000000000201',
    '30000000-0000-0000-0000-000000000201',
    '[{"product_id":"50000000-0000-0000-0000-000000000201","quantity":1},
      {"product_id":"50000000-0000-0000-0000-000000000202","quantity":2}]'::jsonb
  )
);
select is(
  (select requested_for from public.sales_orders
   where id = (select order_id from new_test_orders
     where purpose = 'rejected')),
  current_date + 1,
  'إنشاء الطلب يستخدم المدة الحالية من قاعدة البيانات'
);
select is(
  (select lead_days_snapshot from public.sales_orders
   where id = (select order_id from new_test_orders
     where purpose = 'rejected')),
  1,
  'الطلب يحتفظ بلقطة مدة الاستلام المستخدمة'
);
select public.submit_sales_order(order_id) from new_test_orders;
select is(
  (select status from public.sales_orders
   where id = (select order_id from new_test_orders where purpose = 'rejected')),
  'submitted',
  'الطلب المرسل ينتظر مراجعة الإدارة'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000201","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.set_order_lead_days(2)$$,
  'تغيير المدة يؤثر على الطلبات الجديدة فقط'
);
select is(
  (select requested_for from public.sales_orders
   where id = (select order_id from new_test_orders
     where purpose = 'rejected')),
  current_date + 1,
  'تغيير الإعداد لا يغير موعد طلب قائم'
);
select lives_ok(
  $$select public.reschedule_sales_order(
    (select order_id from new_test_orders where purpose = 'rejected'),
    current_date + 3,
    'تعديل موعد موثق للاختبار'
  )$$,
  'تعديل موعد طلب قائم يتطلب سببًا ويسجل'
);
select is(
  (select count(*) from public.sales_order_schedule_changes
   where order_id = (select order_id from new_test_orders
     where purpose = 'rejected')
     and previous_date = current_date + 1
     and new_date = current_date + 3
     and changed_by = '00000000-0000-0000-0000-000000000201'),
  1::bigint,
  'سجل إعادة الجدولة يحفظ التاريخين والسبب والمستخدم'
);
select throws_ok(
  $$select public.review_sales_order(
    (select order_id from new_test_orders where purpose = 'rejected'),
    'rejected', null
  )$$,
  'P0001',
  'A reason is required to reject or cancel an order',
  'رفض الطلب دون سبب ممنوع'
);
select lives_ok(
  $$select public.review_sales_order(
    (select order_id from new_test_orders where purpose = 'rejected'),
    'rejected', 'تعذر التوفير'
  )$$,
  'رفض الطلب مع السبب مسموح'
);
select is(
  (select status_reason from public.sales_orders
   where id = (select order_id from new_test_orders
     where purpose = 'rejected')),
  'تعذر التوفير',
  'سبب الرفض محفوظ ليظهر للموزع'
);
select ok(
  (select decision_by = '00000000-0000-0000-0000-000000000201'
      and decision_at is not null
   from public.sales_orders
   where id = (select order_id from new_test_orders
     where purpose = 'rejected')),
  'يسجل الرفض المستخدم ووقت القرار'
);
select throws_ok(
  $$select public.create_production_batch(
    '20000000-0000-0000-0000-000000000201', current_date + 1,
    array(select order_id from new_test_orders where purpose = 'rejected')
  )$$,
  'P0001',
  'Every order must be approved, unassigned, and at the selected location',
  'الطلب المرفوض لا يدخل دفعة إنتاج'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000203","role":"authenticated"}',
  true
);
insert into new_test_orders values (
  'approved_2',
  '40000000-0000-0000-0000-000000000202',
  public.create_sales_order(
    '20000000-0000-0000-0000-000000000201',
    '30000000-0000-0000-0000-000000000201',
    '[{"product_id":"50000000-0000-0000-0000-000000000201","quantity":2},
      {"product_id":"50000000-0000-0000-0000-000000000202","quantity":1}]'::jsonb
  )
);
select is(
  (select requested_for from public.sales_orders
   where id = (select order_id from new_test_orders
     where purpose = 'approved_2')),
  current_date + 2,
  'الطلب الجديد يستخدم الإعداد الجديد ليومين'
);
select public.submit_sales_order(order_id)
from new_test_orders
where purpose = 'approved_2';
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000202","role":"authenticated"}',
  true
);
insert into new_test_orders values (
  'approved_1',
  '40000000-0000-0000-0000-000000000201',
  public.create_sales_order(
    '20000000-0000-0000-0000-000000000201',
    '30000000-0000-0000-0000-000000000201',
    '[{"product_id":"50000000-0000-0000-0000-000000000201","quantity":1},
      {"product_id":"50000000-0000-0000-0000-000000000202","quantity":2}]'::jsonb
  )
);
select public.submit_sales_order(order_id)
from new_test_orders
where purpose = 'approved_1';
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000201","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.review_sales_order(order_id, 'approved', null)
    from new_test_orders
    where purpose = 'approved_2'$$,
  'الإدارة تعتمد الطلب قبل الإنتاج'
);
select lives_ok(
  $$select public.review_sales_order(
    (select order_id from new_test_orders
     where purpose = 'approved_1'), 'approved', null
  )$$,
  'الإدارة تعتمد الطلب الثاني'
);
select lives_ok(
  $$select public.create_production_batch(
    '20000000-0000-0000-0000-000000000201', current_date + 2,
    array(select order_id from new_test_orders
      where purpose in ('approved_1', 'approved_2'))
  )$$,
  'إنشاء دفعة من الطلبات المعتمدة'
);
select throws_ok(
  $$select public.create_production_batch(
    '20000000-0000-0000-0000-000000000201', current_date + 2,
    array(select order_id from new_test_orders
      where purpose in ('approved_1', 'approved_2'))
  )$$,
  'P0001',
  'Every order must be approved, unassigned, and at the selected location',
  'لا يمكن إدخال الطلب في دفعة إنتاج مرتين'
);

create temporary table new_test_batch as
select id from public.production_batches
where pickup_location_id = '20000000-0000-0000-0000-000000000201';
select lives_ok(
  $$select public.finalize_production_batch(
    (select id from new_test_batch),
    '[{"product_id":"50000000-0000-0000-0000-000000000201",
       "produced_quantity":5,"rejected_quantity":0},
      {"product_id":"50000000-0000-0000-0000-000000000202",
       "produced_quantity":4,"rejected_quantity":0}]'::jsonb
  )$$,
  'تسجيل الإنتاج الفعلي يجهز التوزيع النسبي الأولي'
);
select is(
  (select sum(allocated_quantity)
   from public.production_allocations allocation
   join public.production_batch_lines batch_line
     on batch_line.id = allocation.batch_line_id
   where batch_line.product_id = '50000000-0000-0000-0000-000000000201'),
  5::bigint,
  'التوزيع الأولي يساوي إنتاج الصنف المتاح'
);
select throws_ok(
  $$select public.revise_production_distribution(
    (select id from new_test_batch),
    '50000000-0000-0000-0000-000000000201',
    (select jsonb_agg(jsonb_build_object(
      'order_line_id', allocation.order_line_id,
      'allocated_quantity', 2
    )) from public.production_allocations allocation
    join public.production_batch_lines batch_line
      on batch_line.id = allocation.batch_line_id
    where batch_line.product_id = '50000000-0000-0000-0000-000000000201'),
    'اختبار توزيع غير مطابق'
  )$$,
  'P0001',
  'Adjusted quantities must be nonnegative and equal available production',
  'قاعدة البيانات تمنع مجموع توزيع لا يطابق الإنتاج'
);
select lives_ok(
  $$select public.revise_production_distribution(
    (select id from new_test_batch),
    '50000000-0000-0000-0000-000000000201',
    (select jsonb_agg(jsonb_build_object(
      'order_line_id', allocation.order_line_id,
      'allocated_quantity', case
        when orders.distributor_id = '40000000-0000-0000-0000-000000000202'
          then 2 else 3 end
    )) from public.production_allocations allocation
    join public.sales_order_lines order_line
      on order_line.id = allocation.order_line_id
    join public.sales_orders orders on orders.id = order_line.order_id
    join public.production_batch_lines batch_line
      on batch_line.id = allocation.batch_line_id
    where batch_line.product_id = '50000000-0000-0000-0000-000000000201'),
    'تعديل يدوي موثق'
  )$$,
  'تعديل الحصص قبل الاعتماد مع سبب مسموح'
);
select is(
  (select count(*) from public.production_allocation_audit
   where reason = 'تعديل يدوي موثق'
     and previous_quantity <> new_quantity),
  2::bigint,
  'التعديل يسجل الكمية المحسوبة والمعدلة لكل مندوب'
);
select ok(
  (select bool_and(changed_by = '00000000-0000-0000-0000-000000000201'
      and changed_at is not null and calculated_quantity >= 0)
   from public.production_allocation_audit
   where reason = 'تعديل يدوي موثق'),
  'سجل التوزيع يحفظ المستخدم والوقت والكمية المحسوبة'
);
select lives_ok(
  $$select public.approve_production_distribution((select id from new_test_batch))$$,
  'الإدارة تعتمد التوزيع المطابق'
);
select lives_ok(
  $$select public.revise_production_distribution(
    (select id from new_test_batch),
    '50000000-0000-0000-0000-000000000201',
    (select jsonb_agg(jsonb_build_object(
      'order_line_id', allocation.order_line_id,
      'allocated_quantity', case
        when orders.distributor_id = '40000000-0000-0000-0000-000000000202'
          then 1 else 4 end
    )) from public.production_allocations allocation
    join public.sales_order_lines order_line
      on order_line.id = allocation.order_line_id
    join public.sales_orders orders on orders.id = order_line.order_id
    join public.production_batch_lines batch_line
      on batch_line.id = allocation.batch_line_id
    where batch_line.product_id = '50000000-0000-0000-0000-000000000201'),
    'تعديل لاحق مسجل'
  )$$,
  'التعديل اللاحق بعد الاعتماد مسموح فقط عبر وظيفة التدقيق'
);
select is(
  (select distribution_approved from public.production_batches
   where id = (select id from new_test_batch)),
  false,
  'التعديل اللاحق يبطل الاعتماد السابق حتى تعاد الموافقة'
);
select lives_ok(
  $$select public.approve_production_distribution((select id from new_test_batch))$$,
  'يمكن إعادة اعتماد التوزيع بعد التعديل الموثق'
);

select throws_ok(
  $$select public.record_order_delivery(
    (select order_id from new_test_orders
     where purpose = 'approved_2'),
    'new-test-delivery-before-approval',
    '[]'::jsonb,
    null
  )$$,
  'P0001',
  'A unique delivery key and at least one delivery line are required',
  'لا يقبل التسليم دون بنود فعلية'
);
select lives_ok(
  $$select public.record_order_delivery(
    (select order_id from new_test_orders
     where purpose = 'approved_2'),
    'new-test-delivery-dist-2',
    (select jsonb_agg(jsonb_build_object(
      'order_line_id', allocation.order_line_id,
      'quantity', allocation.allocated_quantity
    )) from public.production_allocations allocation
    join public.sales_order_lines order_line
      on order_line.id = allocation.order_line_id
    where order_line.order_id = (select order_id from new_test_orders
      where purpose = 'approved_2')),
    null
  )$$,
  'تسليم الطلب المعتمد يسجل سعات البرانيك'
);
update public.products set crate_capacity = 5
where id = '50000000-0000-0000-0000-000000000201';
select is(
  (select crate_capacity_snapshot from public.order_delivery_lines
   where order_line_id = (
     select order_line.id from public.sales_order_lines order_line
     where order_line.order_id = (select order_id from new_test_orders
       where purpose = 'approved_2')
       and order_line.product_id = '50000000-0000-0000-0000-000000000201'
   )),
  3,
  'تغيير سعة الصنف لا يغير لقطة حركة سابقة'
);
select is(
  (select crate_count from public.order_delivery_lines
   where order_line_id = (
     select order_line.id from public.sales_order_lines order_line
     where order_line.order_id = (select order_id from new_test_orders
       where purpose = 'approved_2')
       and order_line.product_id = '50000000-0000-0000-0000-000000000201'
   )),
  1,
  'الكمية الجزئية تحت السعة تحسب برنيكة واحدة غير مكتملة'
);
select is(
  (select crate_capacity_snapshot from public.order_delivery_lines
   where order_line_id = (
     select order_line.id from public.sales_order_lines order_line
     where order_line.order_id = (select order_id from new_test_orders
       where distributor_id = '40000000-0000-0000-0000-000000000202')
       and order_line.product_id = '50000000-0000-0000-0000-000000000202'
   )),
  2,
  'الصنف الآخر يحتفظ بسعة برنيكة مختلفة'
);
select lives_ok(
  $$select public.record_order_delivery(
    (select order_id from new_test_orders
     where purpose = 'approved_1'),
    'new-test-delivery-dist-1',
    (select jsonb_agg(jsonb_build_object(
      'order_line_id', allocation.order_line_id,
      'quantity', allocation.allocated_quantity
    )) from public.production_allocations allocation
    join public.sales_order_lines order_line
      on order_line.id = allocation.order_line_id
    where order_line.order_id = (select order_id from new_test_orders
      where purpose = 'approved_1')),
    null
  )$$,
  'التسليم اللاحق يستخدم سعة الصنف الجديدة'
);
select is(
  (select crate_capacity_snapshot from public.order_delivery_lines
   where order_line_id = (
     select order_line.id from public.sales_order_lines order_line
     where order_line.order_id = (select order_id from new_test_orders
       where purpose = 'approved_1')
       and order_line.product_id = '50000000-0000-0000-0000-000000000201'
   )),
  5,
  'الحركة الجديدة تحتفظ بالسعة المحدثة وقتها'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000204","role":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.outlet_distributor_count',
  (select count(*)::text from public.role_outlet_distributors),
  true
);
select set_config(
  'test.outlet_vehicle_1_count',
  (select count(*)::text from public.role_outlet_distributors
   where vehicle_group = 'vehicle_1'),
  true
);
select set_config(
  'test.outlet_vehicle_2_count',
  (select count(*)::text from public.role_outlet_distributors
   where vehicle_group = 'vehicle_2'),
  true
);
select set_config(
  'test.outlet_cross_outlet_count',
  (select count(*)::text from public.role_outlet_distributors
   where external_outlet_id <> '30000000-0000-0000-0000-000000000201'),
  true
);
reset role;
select is(current_setting('test.outlet_distributor_count')::integer, 2,
  'مسؤول المنفذ يرى مناديب منفذه فقط');
select is(current_setting('test.outlet_vehicle_1_count')::integer, 1,
  'قائمة السيارة الأولى معزولة حسب تصنيف المندوب');
select is(current_setting('test.outlet_vehicle_2_count')::integer, 1,
  'قائمة السيارة الثانية معزولة حسب تصنيف المندوب');
select is(current_setting('test.outlet_cross_outlet_count')::integer, 0,
  'مسؤول المنفذ لا يرى مناديب منفذ آخر');
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000204","role":"authenticated"}',
  true
);
select throws_ok(
  $$update public.user_profiles
    set external_outlet_id = '30000000-0000-0000-0000-000000000203'
    where user_id = '00000000-0000-0000-0000-000000000204'$$,
  'P0001',
  'The selected role is disabled or the outlet is inactive',
  'صلاحيات المنفذ المقيدة تطبق على إسناد الدور في قاعدة البيانات'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000201","role":"authenticated"}',
  true
);
select throws_ok(
  $$delete from public.external_outlets
    where id = '30000000-0000-0000-0000-000000000201'$$,
  'P0001',
  'Outlets cannot be deleted; deactivate them to preserve history',
  'المنفذ لا يحذف حتى مع وجود سجل تاريخي'
);
update public.external_outlets set is_active = false
where id = '30000000-0000-0000-0000-000000000201';
select is(
  (select count(*) from public.sales_orders
   where external_outlet_id = '30000000-0000-0000-0000-000000000201'),
  3::bigint,
  'تعطيل المنفذ يحافظ على الطلبات التاريخية'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000204","role":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.disabled_outlet_distributors',
  (select count(*)::text from public.role_outlet_distributors),
  true
);
reset role;
select is(current_setting('test.disabled_outlet_distributors')::integer, 0,
  'تعطيل المنفذ يلغي وصول مسؤول المنفذ في قاعدة البيانات');

select * from finish();
rollback;
