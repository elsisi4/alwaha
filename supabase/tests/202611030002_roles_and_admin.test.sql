begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000001', 'authenticated',
    'authenticated', 'admin-test@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000002', 'authenticated',
    'authenticated', 'distributor-test@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000003', 'authenticated',
    'authenticated', 'outlet-manager-test@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000004', 'authenticated',
    'authenticated', 'collector-test@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000005', 'authenticated',
    'authenticated', 'accountant-test@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000006', 'authenticated',
    'authenticated', 'production-test@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000007', 'authenticated',
    'authenticated', 'factory-outlet-test@alwaha.invalid', '', now(), '{}', '{}', now(), now());

insert into public.customer_types (id, name) values
  ('10000000-0000-0000-0000-000000000001', 'اختبار موزعين');

insert into public.pickup_locations (id, name) values
  ('20000000-0000-0000-0000-000000000001', 'استلام الاختبار');

insert into public.external_outlets (id, name, pickup_location_id) values
  ('30000000-0000-0000-0000-000000000001', 'منفذ الاختبار الأول',
    '20000000-0000-0000-0000-000000000001'),
  ('30000000-0000-0000-0000-000000000002', 'منفذ الاختبار الثاني',
    '20000000-0000-0000-0000-000000000001');

insert into public.distributors (id, name, customer_type_id) values
  ('40000000-0000-0000-0000-000000000001', 'موزع الاختبار الأول',
    '10000000-0000-0000-0000-000000000001'),
  ('40000000-0000-0000-0000-000000000002', 'موزع الاختبار الثاني',
    '10000000-0000-0000-0000-000000000001');

insert into public.distributor_outlets (distributor_id, external_outlet_id) values
  ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001'),
  ('40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002');

insert into public.products (id, code, name) values
  ('50000000-0000-0000-0000-000000000001', 'TEST-001', 'صنف الاختبار');

insert into public.raw_materials (id, code, name, unit) values
  ('60000000-0000-0000-0000-000000000001', 'RAW-001', 'خامة الاختبار', 'كجم');

update public.user_profiles set role = 'admin'
where user_id = '00000000-0000-0000-0000-000000000001';
update public.user_profiles set
  role = 'distributor',
  distributor_id = '40000000-0000-0000-0000-000000000001'
where user_id = '00000000-0000-0000-0000-000000000002';
update public.user_profiles set
  role = 'outlet_manager',
  external_outlet_id = '30000000-0000-0000-0000-000000000001'
where user_id = '00000000-0000-0000-0000-000000000003';
update public.user_profiles set
  role = 'collector',
  external_outlet_id = '30000000-0000-0000-0000-000000000001'
where user_id = '00000000-0000-0000-0000-000000000004';
update public.user_profiles set role = 'accountant'
where user_id = '00000000-0000-0000-0000-000000000005';
update public.user_profiles set role = 'production_manager'
where user_id = '00000000-0000-0000-0000-000000000006';
update public.user_profiles set
  role = 'factory_outlet_manager',
  pickup_location_id = '20000000-0000-0000-0000-000000000001'
where user_id = '00000000-0000-0000-0000-000000000007';

select plan(41);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.save_pricing_policy(
    null,
    'أسعار المنفذ الاختباري',
    'external_outlet',
    null,
    null,
    '30000000-0000-0000-0000-000000000001',
    '2026-01-01 00:00:00+00',
    '[{"product_id":"50000000-0000-0000-0000-000000000001",
       "factory_purchase_price":3.50,"distributor_sale_price":7.25}]'::jsonb
  )$$,
  'المدير ينشئ إصدار سياسة سعرية'
);

select is(
  (select category from public.products
   where id = '50000000-0000-0000-0000-000000000001'),
  'غير مصنف',
  'الصنف القديم يحصل على تصنيف افتراضي أثناء الترحيل'
);

select is(
  (select quality from public.products
   where id = '50000000-0000-0000-0000-000000000001'),
  'غير محدد',
  'الصنف القديم يحصل على جودة افتراضية أثناء الترحيل'
);

select is(
  (select capacity from public.crate_types where code = 'standard'),
  75,
  'السعة الافتراضية للبرنيكة قابلة للإدارة وقيمتها 75'
);

select lives_ok(
  $$select public.save_product_recipe(
    '50000000-0000-0000-0000-000000000001',
    '2026-01-01 00:00:00+00',
    '[{"raw_material_id":"60000000-0000-0000-0000-000000000001",
       "quantity_per_sales_unit":0.25,"waste_percent":2}]'::jsonb
  )$$,
  'المدير ينشئ إصدار وصفة مؤرخًا'
);

select throws_ok(
  $$update public.product_recipe_versions
    set starts_at = '2026-01-02 00:00:00+00'
    where product_id = '50000000-0000-0000-0000-000000000001'$$,
  'P0001',
  'Recipe history is immutable; create a new version instead',
  'إصدارات الوصفات السابقة غير قابلة للتعديل'
);

select lives_ok(
  $$select public.create_factory_sale(
    '40000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000001',
    '[{"product_id":"50000000-0000-0000-0000-000000000001","quantity":2}]'::jsonb,
    '2026-02-01 00:00:00+00'
  )$$,
  'إنشاء البيع يثبت سعر الموزع في المنفذ المختار'
);

select is(
  (select line.unit_price
   from public.factory_sale_lines line
   join public.factory_sales sale on sale.id = line.sale_id
   where sale.distributor_id = '40000000-0000-0000-0000-000000000001'
   order by sale.sold_at limit 1),
  7.25::numeric,
  'سعر البيع وقت العملية محفوظ على بند الطلب'
);

select throws_ok(
  $$select public.create_factory_sale(
    '40000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000002',
    '[{"product_id":"50000000-0000-0000-0000-000000000001","quantity":1}]'::jsonb,
    '2026-02-02 00:00:00+00'
  )$$,
  'P0001',
  'The distributor is not authorized to receive from this outlet',
  'قاعدة البيانات ترفض منفذًا غير مربوط بالموزع'
);

select lives_ok(
  $$select public.create_outlet_purchase(
    '30000000-0000-0000-0000-000000000001',
    '[{"product_id":"50000000-0000-0000-0000-000000000001","quantity":2}]'::jsonb,
    '2026-02-03 00:00:00+00'
  )$$,
  'إنشاء شراء المنفذ يستخدم سعر شراء المصنع'
);

insert into public.outlet_payments (
  external_outlet_id, amount, paid_at, created_by
) values (
  '30000000-0000-0000-0000-000000000001',
  3.00,
  '2026-02-04 00:00:00+00',
  '00000000-0000-0000-0000-000000000001'
);

select is(
  (select balance
   from public.outlet_account_balances
   where external_outlet_id = '30000000-0000-0000-0000-000000000001'),
  4.00::numeric,
  'رصيد المنفذ مشتريات مصنع ناقص المدفوعات ولا يتضمن مبيعات الموزعين'
);

select lives_ok(
  $$select public.save_pricing_policy(
    (select id from public.pricing_policies
     where external_outlet_id = '30000000-0000-0000-0000-000000000001'),
    'أسعار المنفذ الاختباري',
    'external_outlet',
    null,
    null,
    '30000000-0000-0000-0000-000000000001',
    '2027-01-01 00:00:00+00',
    '[{"product_id":"50000000-0000-0000-0000-000000000001",
       "factory_purchase_price":4.00,"distributor_sale_price":8.00}]'::jsonb
  )$$,
  'يمكن جدولة إصدار أسعار تالٍ دون تعديل التاريخ'
);

select is(
  (select line.unit_price
   from public.factory_sale_lines line
   join public.factory_sales sale on sale.id = line.sale_id
   where sale.distributor_id = '40000000-0000-0000-0000-000000000001'
     and sale.sold_at = '2026-02-01 00:00:00+00'),
  7.25::numeric,
  'تعديل السياسة لا يغير سعر البيع التاريخي'
);

select is(
  (select line.unit_price
   from public.outlet_purchase_lines line
   join public.outlet_purchases purchase on purchase.id = line.purchase_id
   where purchase.external_outlet_id = '30000000-0000-0000-0000-000000000001'),
  3.50::numeric,
  'تعديل السياسة لا يغير سعر الشراء التاريخي'
);

select lives_ok(
  $$select public.create_factory_sale(
    '40000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000001',
    '[{"product_id":"50000000-0000-0000-0000-000000000001","quantity":1}]'::jsonb,
    '2027-01-02 00:00:00+00'
  )$$,
  'بيع بعد تاريخ النفاذ يختار إصدار السياسة الجديد'
);

select is(
  (select line.unit_price
   from public.factory_sale_lines line
   join public.factory_sales sale on sale.id = line.sale_id
   where sale.distributor_id = '40000000-0000-0000-0000-000000000001'
     and sale.sold_at = '2027-01-02 00:00:00+00'),
  8.00::numeric,
  'سعر البيع الجديد يثبت على العملية الجديدة فقط'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.save_pricing_policy(
    null,
    'سياسة المنفذ الثاني',
    'external_outlet',
    null,
    null,
    '30000000-0000-0000-0000-000000000002',
    '2026-01-01 00:00:00+00',
    '[{"product_id":"50000000-0000-0000-0000-000000000001",
       "factory_purchase_price":4.00,"distributor_sale_price":9.00}]'::jsonb
  )$$,
  'المدير ينشئ سياسة منفصلة للمنفذ الآخر'
);

select lives_ok(
  $$select public.create_factory_sale(
    '40000000-0000-0000-0000-000000000002',
    '20000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000002',
    '[{"product_id":"50000000-0000-0000-0000-000000000001","quantity":1}]'::jsonb,
    '2026-03-01 00:00:00+00'
  )$$,
  'الطلب الثاني يسجل تحت منفذه وموزعه'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000004","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.record_distributor_payment(
    '40000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000001',
    2.00,
    '2026-02-05 00:00:00+00'
  )$$,
  'المحصل يستطيع تسجيل تحصيل لموزع مرتبط بمنفذه'
);

select throws_ok(
  $$select public.record_distributor_payment(
    '40000000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000001',
    2.00,
    '2026-02-05 00:00:00+00'
  )$$,
  'P0001',
  'The distributor is not linked to this outlet',
  'المحصل لا يستطيع تسجيل تحصيل لموزع غير مرتبط بمنفذه'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.distributor_sales_count',
  (select count(id)::text from public.factory_sales),
  true
);
select set_config(
  'test.distributor_account_count',
  (select count(*)::text from public.distributor_account_balances),
  true
);
select set_config(
  'test.distributor_own_account_count',
  (select count(*)::text
   from public.distributor_account_balances
   where distributor_id = '40000000-0000-0000-0000-000000000001'),
  true
);
select set_config(
  'test.distributor_balance',
  (select balance::text
   from public.distributor_account_balances
   where distributor_id = '40000000-0000-0000-0000-000000000001'),
  true
);
reset role;

select is(
  current_setting('test.distributor_sales_count')::bigint,
  2::bigint,
  'الموزع لا يقرأ إلا طلباته'
);

select is(
  current_setting('test.distributor_account_count')::bigint,
  1::bigint,
  'كشف حساب الموزع لا يعرض حساب موزع آخر'
);

select is(
  current_setting('test.distributor_own_account_count')::bigint,
  1::bigint,
  'الموزع يستطيع قراءة حسابه'
);

select is(
  current_setting('test.distributor_balance')::numeric,
  20.50::numeric,
  'رصيد الموزع يحسب من الأسعار المثبتة والمدفوعات المسجلة'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.outlet_distributors_count',
  (select count(*)::text from public.distributors),
  true
);
select set_config(
  'test.outlet_sales_count',
  (select count(id)::text from public.factory_sales),
  true
);
reset role;

select is(
  current_setting('test.outlet_distributors_count')::bigint,
  1::bigint,
  'مسؤول المنفذ لا يرى إلا الموزعين المرتبطين بمنفذه'
);

select is(
  current_setting('test.outlet_sales_count')::bigint,
  2::bigint,
  'مسؤول المنفذ لا يرى إلا الطلبات المرتبطة بمنفذه'
);

select ok(
  not has_table_privilege(
    'authenticated', 'public.factory_sale_lines', 'SELECT'
  ),
  'لا يملك مستخدمو العميل صلاحية قراءة جدول بنود البيع المالي مباشرة'
);

select ok(
  not has_column_privilege(
    'authenticated', 'public.factory_sale_lines', 'unit_price', 'SELECT'
  ),
  'عمود سعر الوحدة غير مكشوف عبر صلاحيات الجدول'
);

select ok(
  has_table_privilege(
    'authenticated', 'public.role_factory_sale_quantities', 'SELECT'
  ),
  'تتوفر واجهة قراءة تشغيلية آمنة للكميات'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.assign_user_role(text, text, uuid, uuid)',
    'EXECUTE'
  ),
  'مسار إسناد الدور القديم غير متاح بعد إضافة المسار المحمي'
);

select ok(
  not has_table_privilege('authenticated', 'public.user_profiles', 'UPDATE'),
  'لا يمكن للمستخدم تعديل دوره أو ارتباطه مباشرة'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000006","role":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.production_quantity_count',
  (select count(*)::text from public.role_factory_sale_quantities),
  true
);
select set_config(
  'test.production_financial_line_count',
  (select count(*)::text from public.role_financial_sale_lines),
  true
);
select set_config(
  'test.production_account_count',
  (select count(*)::text from public.distributor_account_balances),
  true
);
reset role;

select is(
  current_setting('test.production_quantity_count')::bigint,
  3::bigint,
  'الإنتاج يرى كميات الطلبات اللازمة للتشغيل'
);

select is(
  current_setting('test.production_financial_line_count')::bigint,
  0::bigint,
  'الإنتاج لا يرى واجهة بنود البيع المالية'
);

select is(
  current_setting('test.production_account_count')::bigint,
  0::bigint,
  'الإنتاج لا يرى أرصدة الموزعين'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000007","role":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.factory_outlet_quantity_count',
  (select count(*)::text from public.role_factory_sale_quantities),
  true
);
select set_config(
  'test.factory_outlet_financial_line_count',
  (select count(*)::text from public.role_financial_sale_lines),
  true
);
select set_config(
  'test.factory_outlet_balance_count',
  (select count(*)::text from public.distributor_account_balances),
  true
);
reset role;

select is(
  current_setting('test.factory_outlet_quantity_count')::bigint,
  3::bigint,
  'مسؤول منفذ المصنع يرى الكميات التشغيلية لموقعه'
);

select is(
  current_setting('test.factory_outlet_financial_line_count')::bigint,
  0::bigint,
  'مسؤول منفذ المصنع لا يرى بنود الأسعار'
);

select is(
  current_setting('test.factory_outlet_balance_count')::bigint,
  0::bigint,
  'مسؤول منفذ المصنع لا يرى الحسابات'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000005","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.record_distributor_payment(
    '40000000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000002',
    1.00,
    '2026-02-06 00:00:00+00'
  )$$,
  'المحاسب يستطيع تسجيل تحصيل لموزع مرتبط بالمنفذ'
);
set local role authenticated;
select set_config(
  'test.accountant_financial_line_count',
  (select count(*)::text from public.role_financial_sale_lines),
  true
);
select set_config(
  'test.accountant_distributor_account_count',
  (select count(*)::text from public.distributor_account_balances),
  true
);
select set_config(
  'test.accountant_outlet_account_count',
  (select count(*)::text from public.outlet_account_balances),
  true
);
reset role;

select is(
  current_setting('test.accountant_financial_line_count')::bigint,
  3::bigint,
  'المحاسب يرى جميع بنود البيع المالية'
);

select is(
  current_setting('test.accountant_distributor_account_count')::bigint,
  2::bigint,
  'المحاسب يرى جميع حسابات الموزعين'
);

select is(
  current_setting('test.accountant_outlet_account_count')::bigint,
  2::bigint,
  'المحاسب يرى جميع حسابات المنافذ'
);

select * from finish();
rollback;
