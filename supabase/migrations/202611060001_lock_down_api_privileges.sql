-- Supabase يمنح anon وauthenticated صلاحيات افتراضية على كل كائن جديد في public،
-- و"revoke from public" لا يزيلها. هذا الترحيل يغلق ذلك صراحة:
-- 1) anon لا يملك أي صلاحية على جداول ودوال وتسلسلات public.
-- 2) authenticated يقرأ الـ views فقط؛ ست views بسيطة كانت قابلة للكتابة المباشرة
--    وتتجاوز دوال التحقق (role_inventory_balances وrole_crate_movements وغيرهما).
-- 3) دالة المحفز create_user_profile لا تُستدعى من الـ API.
-- 4) تثبيت search_path لدالتين من ترحيل التسعير.
revoke all on all tables in schema public from anon;
revoke all on all functions in schema public from anon;
revoke all on all sequences in schema public from anon;

do $$
declare
  view_name text;
begin
  for view_name in
    select table_name from information_schema.views
    where table_schema = 'public'
  loop
    execute format(
      'revoke insert, update, delete, truncate, references, trigger on public.%I from authenticated, anon',
      view_name
    );
  end loop;
end;
$$;

revoke execute on function public.create_user_profile() from authenticated;

alter function public.reject_pricing_history_change()
  set search_path = public, pg_temp;
alter function public.protect_pricing_policy_scope()
  set search_path = public, pg_temp;

alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on functions from anon;
alter default privileges in schema public revoke all on sequences from anon;
