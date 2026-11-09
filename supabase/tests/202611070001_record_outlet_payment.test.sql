begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

insert into public.pickup_locations (id, name)
values ('20000000-0000-0000-0000-000000000501', 'موقع اختبار دفعة المنفذ');
insert into public.external_outlets (id, name, pickup_location_id)
values ('30000000-0000-0000-0000-000000000501', 'منفذ اختبار الدفعة',
  '20000000-0000-0000-0000-000000000501');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-0000000005a1', 'authenticated', 'authenticated',
    'op-acct@alwaha.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-0000000005a2', 'authenticated', 'authenticated',
    'op-prod@alwaha.invalid', '', now(), '{}', '{}', now(), now());
update public.user_profiles set role = 'accountant'
where user_id = '00000000-0000-0000-0000-0000000005a1';
update public.user_profiles set role = 'production_manager'
where user_id = '00000000-0000-0000-0000-0000000005a2';

select no_plan();

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000005a2","role":"authenticated"}', true);
select throws_ok(
  $$select public.record_outlet_payment('30000000-0000-0000-0000-000000000501', 100)$$,
  'P0001', 'Only administration or accounting can record outlet payments',
  'الإنتاج لا يسجل دفعات المنافذ'
);

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000005a1","role":"authenticated"}', true);
select throws_ok(
  $$select public.record_outlet_payment('30000000-0000-0000-0000-000000000501', 0)$$,
  'P0001', 'A positive payment amount and date are required',
  'المبلغ يجب أن يكون موجبًا'
);
select lives_ok(
  $$select public.record_outlet_payment('30000000-0000-0000-0000-000000000501', 2500.50)$$,
  'المحاسب يسجل دفعة المنفذ'
);
select is(
  (select payments_total from public.outlet_account_balances
   where external_outlet_id = '30000000-0000-0000-0000-000000000501'),
  2500.50::numeric,
  'الدفعة تظهر في حساب المنفذ'
);
select is(
  (select balance from public.outlet_account_balances
   where external_outlet_id = '30000000-0000-0000-0000-000000000501'),
  -2500.50::numeric,
  'الرصيد = المشتريات - المدفوعات'
);
select ok(not has_function_privilege('anon',
  'public.record_outlet_payment(uuid, numeric, timestamptz)', 'EXECUTE'),
  'غير المسجل لا يسجل دفعات');

select * from finish();
rollback;
