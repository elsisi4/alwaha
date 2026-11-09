-- نشر تحديثات تطبيق الأندرويد: كل إصدار له رقم (version_code) ورابط ملف APK.
-- التطبيق يسأل get_latest_release قبل تسجيل الدخول، والمدير ينشر الإصدار الجديد.
create table public.app_releases (
  id uuid primary key default gen_random_uuid(),
  app text not null check (app in ('distributor', 'admin')),
  version_code integer not null check (version_code > 0),
  version_name text not null check (length(trim(version_name)) > 0),
  apk_url text not null check (apk_url ~* '^https://.+\.apk(\?.*)?$'),
  notes text check (length(coalesce(notes, '')) <= 2000),
  is_required boolean not null default false,
  published_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (app, version_code)
);

alter table public.app_releases enable row level security;
revoke all on public.app_releases from public, anon, authenticated;

create function public.get_latest_release(p_app text)
returns table (
  version_code integer,
  version_name text,
  apk_url text,
  notes text,
  is_required boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select release.version_code, release.version_name, release.apk_url,
    release.notes, release.is_required
  from public.app_releases release
  where release.app = p_app
  order by release.version_code desc
  limit 1;
$$;

create function public.publish_app_release(
  p_app text,
  p_version_code integer,
  p_version_name text,
  p_apk_url text,
  p_notes text default null,
  p_is_required boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  release_id uuid;
  latest_code integer;
begin
  if auth.uid() is null or not public.is_pricing_admin() then
    raise exception 'Only an administrator can publish app releases';
  end if;
  if p_app not in ('distributor', 'admin') then
    raise exception 'Unsupported app';
  end if;
  select max(release.version_code) into latest_code
  from public.app_releases release where release.app = p_app;
  if p_version_code is null or p_version_code <= coalesce(latest_code, 0) then
    raise exception 'The version code must be greater than the latest published code';
  end if;
  insert into public.app_releases (
    app, version_code, version_name, apk_url, notes, is_required, published_by
  ) values (
    p_app, p_version_code, trim(p_version_name), trim(p_apk_url),
    nullif(trim(p_notes), ''), coalesce(p_is_required, false), auth.uid()
  ) returning id into release_id;
  return release_id;
end;
$$;

create function public.admin_list_app_releases()
returns table (
  app text,
  version_code integer,
  version_name text,
  apk_url text,
  is_required boolean,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select release.app, release.version_code, release.version_name,
    release.apk_url, release.is_required, release.created_at
  from public.app_releases release
  where public.is_pricing_admin()
  order by release.created_at desc
  limit 20;
$$;

revoke all on function public.get_latest_release(text),
  public.publish_app_release(text, integer, text, text, text, boolean),
  public.admin_list_app_releases() from public, anon;
grant execute on function public.get_latest_release(text) to anon, authenticated;
grant execute on function public.publish_app_release(text, integer, text, text, text, boolean),
  public.admin_list_app_releases() to authenticated;

-- مخزن عام لملفات APK (يرفع المدير الملف من لوحة Supabase ← Storage).
insert into storage.buckets (id, name, public)
values ('releases', 'releases', true)
on conflict (id) do nothing;
