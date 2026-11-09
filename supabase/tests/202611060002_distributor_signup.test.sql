begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

insert into public.customer_types (id, name)
values ('10000000-0000-0000-0000-000000000402', 'نوع اختبار التسجيل');
insert into public.pickup_locations (id, name)
values ('20000000-0000-0000-0000-000000000402', 'موقع اختبار التسجيل');
insert into public.external_outlets (id, name, pickup_location_id)
values ('30000000-0000-0000-0000-000000000402', 'منفذ اختبار التسجيل',
  '20000000-0000-0000-0000-000000000402');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-0000000004a1', 'authenticated', 'authenticated',
    'signup-admin@alwaha.invalid', '', now(), '{"role":"admin"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-0000000004a2', 'authenticated', 'authenticated',
    'signup-app@alwaha.invalid', '', now(), '{}',
    '{"full_name":"أحمد علي","phone":"01012345678","requested_outlet_id":"30000000-0000-0000-0000-000000000402"}',
    now(), now()),
  ('00000000-0000-0000-0000-0000000004a3', 'authenticated', 'authenticated',
    'signup-bad@alwaha.invalid', '', now(), '{}',
    '{"full_name":"  ","phone":"abc","requested_outlet_id":"not-a-uuid"}',
    now(), now()),
  ('00000000-0000-0000-0000-0000000004a4', 'authenticated', 'authenticated',
    'signup-rej@alwaha.invalid', '', now(), '{}',
    '{"full_name":"مرفوض","phone":"01099999999","requested_outlet_id":"30000000-0000-0000-0000-000000000402"}',
    now(), now());

select no_plan();

select is(
  (select role || '|' || full_name || '|' || phone from public.user_profiles
   where user_id = '00000000-0000-0000-0000-0000000004a2'),
  'pending|أحمد علي|01012345678',
  'بيانات التسجيل تُنسخ إلى الملف الشخصي والحساب pending'
);
select is(
  (select count(*) from public.user_profiles
   where user_id = '00000000-0000-0000-0000-0000000004a3'
     and full_name is null and phone is null and requested_outlet_id is null),
  1::bigint,
  'البيانات الفاسدة تُتجاهل ولا تُسقط التسجيل'
);

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000004a2","role":"authenticated"}', true);
select throws_ok(
  $$select public.approve_distributor_signup('00000000-0000-0000-0000-0000000004a2')$$,
  'P0001', 'Only an administrator can approve distributor signups',
  'المسجّل لا يوافق على نفسه'
);

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000004a1","role":"authenticated"}', true);
select is(
  (select count(*) from public.admin_list_signup_requests()
   where user_id in ('00000000-0000-0000-0000-0000000004a2',
                     '00000000-0000-0000-0000-0000000004a4')),
  2::bigint,
  'المدير يرى الطلبات المكتملة'
);
select is(
  (select count(*) from public.admin_list_signup_requests()
   where user_id = '00000000-0000-0000-0000-0000000004a3'),
  0::bigint,
  'الطلب الناقص لا يظهر'
);

select lives_ok(
  $$select public.approve_distributor_signup('00000000-0000-0000-0000-0000000004a2')$$,
  'المدير يوافق على المندوب'
);
select is(
  (select role from public.user_profiles
   where user_id = '00000000-0000-0000-0000-0000000004a2'),
  'distributor',
  'الحساب أصبح مندوبًا'
);
select is(
  (select count(*) from public.distributors d
   join public.distributor_outlets l on l.distributor_id = d.id
   where d.name = 'أحمد علي' and d.phone = '01012345678'
     and l.external_outlet_id = '30000000-0000-0000-0000-000000000402'),
  1::bigint,
  'أُنشئت بطاقة المندوب وربطت بمنفذه'
);
select throws_ok(
  $$select public.approve_distributor_signup('00000000-0000-0000-0000-0000000004a2')$$,
  'P0001', 'Signup request was not found or is already processed',
  'لا موافقة مرتين'
);

select lives_ok(
  $$select public.reject_distributor_signup('00000000-0000-0000-0000-0000000004a4')$$,
  'المدير يرفض طلبًا'
);
select is(
  (select count(*) from auth.users
   where id = '00000000-0000-0000-0000-0000000004a4'),
  0::bigint,
  'الحساب المرفوض يُحذف'
);
select throws_ok(
  $$select public.reject_distributor_signup('00000000-0000-0000-0000-0000000004a2')$$,
  'P0001', 'Signup request was not found or is already processed',
  'لا يمكن رفض مندوب معتمد'
);

select ok(has_function_privilege('anon', 'public.list_signup_outlets()', 'EXECUTE'),
  'غير المسجّل يرى قائمة المنافذ فقط');
select ok(not has_function_privilege('anon',
  'public.approve_distributor_signup(uuid, uuid, text)', 'EXECUTE'),
  'غير المسجّل لا ينفذ الموافقة');

select * from finish();
rollback;
