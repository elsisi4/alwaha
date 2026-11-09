-- التسجيل الذاتي للمندوب: الاسم ورقم الهاتف والمنفذ التابع له.
-- الحساب الجديد يبقى pending حتى يوافق المدير، فتُنشأ بطاقة المندوب وتُربط بالمنفذ.
alter table public.user_profiles
  add column if not exists full_name text,
  add column if not exists phone text,
  add column if not exists requested_outlet_id uuid
    references public.external_outlets(id);

alter table public.user_profiles
  add constraint user_profiles_phone_check
  check (phone is null or phone ~ '^[0-9]{8,15}$');

alter table public.distributors add column if not exists phone text;

grant select (full_name, phone, requested_outlet_id)
  on public.user_profiles to authenticated;

create or replace function public.create_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  meta_name text := left(
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), 120
  );
  meta_phone text := nullif(
    regexp_replace(coalesce(new.raw_user_meta_data ->> 'phone', ''), '[^0-9]', '', 'g'),
    ''
  );
  meta_outlet uuid;
begin
  begin
    meta_outlet := (new.raw_user_meta_data ->> 'requested_outlet_id')::uuid;
  exception when others then
    meta_outlet := null;
  end;
  if meta_outlet is not null and not exists (
    select 1 from public.external_outlets outlet
    where outlet.id = meta_outlet and outlet.is_active
  ) then
    meta_outlet := null;
  end if;
  if meta_phone is not null and meta_phone !~ '^[0-9]{8,15}$' then
    meta_phone := null;
  end if;

  insert into public.user_profiles (
    user_id, role, full_name, phone, requested_outlet_id
  ) values (
    new.id,
    case when new.raw_app_meta_data ->> 'role' = 'admin'
      then 'admin' else 'pending' end,
    meta_name, meta_phone, meta_outlet
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create function public.list_signup_outlets()
returns table (id uuid, name text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select outlet.id, outlet.name
  from public.external_outlets outlet
  where outlet.is_active
  order by outlet.name;
$$;

create function public.admin_list_signup_requests()
returns table (
  user_id uuid,
  full_name text,
  phone text,
  outlet_id uuid,
  outlet_name text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select profile.user_id, profile.full_name, profile.phone,
    profile.requested_outlet_id, outlet.name, profile.created_at
  from public.user_profiles profile
  join public.external_outlets outlet on outlet.id = profile.requested_outlet_id
  where public.is_pricing_admin()
    and profile.role = 'pending'
    and profile.full_name is not null
  order by profile.created_at;
$$;

create function public.approve_distributor_signup(
  p_user_id uuid,
  p_customer_type_id uuid default null,
  p_vehicle_group text default 'shared'
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  profile_row public.user_profiles%rowtype;
  selected_type_id uuid;
  new_distributor_id uuid;
begin
  if auth.uid() is null or not public.is_pricing_admin() then
    raise exception 'Only an administrator can approve distributor signups';
  end if;
  if p_vehicle_group not in ('vehicle_1', 'vehicle_2', 'shared') then
    raise exception 'Unsupported vehicle group';
  end if;
  select * into profile_row
  from public.user_profiles
  where user_id = p_user_id
  for update;
  if not found or profile_row.role <> 'pending'
    or profile_row.full_name is null
    or profile_row.requested_outlet_id is null then
    raise exception 'Signup request was not found or is already processed';
  end if;
  if not exists (
    select 1 from public.external_outlets outlet
    where outlet.id = profile_row.requested_outlet_id and outlet.is_active
  ) then
    raise exception 'The requested outlet is inactive or does not exist';
  end if;
  selected_type_id := coalesce(
    p_customer_type_id,
    (select type.id from public.customer_types type order by type.name limit 1)
  );
  if selected_type_id is null then
    raise exception 'Create a customer type before approving distributors';
  end if;

  insert into public.distributors (name, customer_type_id, phone)
  values (profile_row.full_name, selected_type_id, profile_row.phone)
  returning id into new_distributor_id;
  insert into public.distributor_outlets (
    distributor_id, external_outlet_id, vehicle_group
  ) values (
    new_distributor_id, profile_row.requested_outlet_id, p_vehicle_group
  );
  update public.user_profiles
  set role = 'distributor', distributor_id = new_distributor_id,
      updated_at = now()
  where user_id = p_user_id;
  return new_distributor_id;
end;
$$;

create function public.reject_distributor_signup(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_pricing_admin() then
    raise exception 'Only an administrator can reject distributor signups';
  end if;
  perform 1
  from public.user_profiles
  where user_id = p_user_id and role = 'pending'
    and requested_outlet_id is not null
  for update;
  if not found then
    raise exception 'Signup request was not found or is already processed';
  end if;
  delete from auth.users where id = p_user_id;
end;
$$;

revoke all on function public.list_signup_outlets(),
  public.admin_list_signup_requests(),
  public.approve_distributor_signup(uuid, uuid, text),
  public.reject_distributor_signup(uuid) from public, anon;
grant execute on function public.list_signup_outlets() to anon, authenticated;
grant execute on function public.admin_list_signup_requests(),
  public.approve_distributor_signup(uuid, uuid, text),
  public.reject_distributor_signup(uuid) to authenticated;
