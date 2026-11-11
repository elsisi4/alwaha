begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select no_plan();

select is(
  (select count(*) from information_schema.role_table_grants
   where table_schema = 'public' and grantee = 'anon'),
  0::bigint,
  'anon لا يملك أي صلاحية على جداول أو views في public'
);
select is(
  (select count(*) from information_schema.routine_privileges
   where routine_schema = 'public' and grantee = 'anon'
     and privilege_type = 'EXECUTE'
     and routine_name not in ('list_signup_outlets', 'get_latest_release')),
  0::bigint,
  'anon لا ينفذ أي دالة في public عدا دالتي التسجيل والتحديث المسموحتين'
);
select is(
  (select count(*) from information_schema.role_table_grants g
   join information_schema.views v
     on v.table_schema = g.table_schema and v.table_name = g.table_name
   where g.table_schema = 'public' and g.grantee = 'authenticated'
     and g.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')),
  0::bigint,
  'authenticated لا يكتب في أي view'
);
select ok(
  has_table_privilege('authenticated', 'public.role_orders', 'SELECT'),
  'authenticated ما زال يقرأ role_orders'
);
select ok(
  not has_table_privilege('authenticated', 'public.role_inventory_balances', 'UPDATE'),
  'لا تعديل مباشر لأرصدة المخزون عبر view'
);
select ok(
  not has_table_privilege('authenticated', 'public.role_crate_movements', 'INSERT'),
  'لا إدخال مباشر لحركات البرانيك عبر view'
);
select ok(
  not has_function_privilege('authenticated', 'public.create_user_profile()', 'EXECUTE'),
  'دالة المحفز غير متاحة للمستخدمين'
);
select ok(
  has_function_privilege('authenticated', 'public.review_sales_order(uuid, text, text)', 'EXECUTE'),
  'دوال التطبيق ما زالت متاحة للمستخدم المسجل'
);

select * from finish();
rollback;
