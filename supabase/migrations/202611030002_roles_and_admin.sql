create table public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'pending' check (
    role in (
      'pending', 'admin', 'production_manager', 'outlet_manager',
      'collector', 'distributor'
    )
  ),
  distributor_id uuid references public.distributors(id),
  external_outlet_id uuid references public.external_outlets(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (role = 'distributor' and distributor_id is not null
      and external_outlet_id is null)
    or (role in ('outlet_manager', 'collector')
      and distributor_id is null and external_outlet_id is not null)
    or (role in ('pending', 'admin', 'production_manager')
      and distributor_id is null and external_outlet_id is null)
  )
);

insert into public.user_profiles (user_id, role)
select id,
  case when raw_app_meta_data ->> 'role' = 'admin' then 'admin' else 'pending' end
from auth.users
on conflict (user_id) do nothing;

create function public.create_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.user_profiles (user_id, role)
  values (
    new.id,
    case when new.raw_app_meta_data ->> 'role' = 'admin'
      then 'admin' else 'pending' end
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger auth_user_profile_created
after insert on auth.users
for each row execute function public.create_user_profile();

create function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select profile.role
  from public.user_profiles profile
  where profile.user_id = auth.uid();
$$;

create function public.current_user_distributor_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select profile.distributor_id
  from public.user_profiles profile
  where profile.user_id = auth.uid()
    and profile.role = 'distributor';
$$;

create function public.current_user_outlet_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select profile.external_outlet_id
  from public.user_profiles profile
  where profile.user_id = auth.uid()
    and profile.role in ('outlet_manager', 'collector');
$$;

create or replace function public.is_pricing_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.current_user_role() = 'admin', false);
$$;

create function public.can_view_distributor(p_distributor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    public.current_user_role() in ('admin', 'production_manager')
    or public.current_user_distributor_id() = p_distributor_id
    or exists (
      select 1
      from public.distributor_outlets link
      where link.distributor_id = p_distributor_id
        and link.external_outlet_id = public.current_user_outlet_id()
    ),
    false
  );
$$;

create function public.can_view_outlet(p_external_outlet_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    public.current_user_role() = 'admin'
    or public.current_user_outlet_id() = p_external_outlet_id,
    false
  );
$$;

create function public.can_view_factory_sale(p_sale_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    public.current_user_role() in ('admin', 'production_manager')
    or exists (
      select 1
      from public.factory_sales sale
      where sale.id = p_sale_id
        and (
          sale.distributor_id = public.current_user_distributor_id()
        )
    ),
    false
  );
$$;

create function public.assign_user_role(
  p_email text,
  p_role text,
  p_distributor_id uuid default null,
  p_external_outlet_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  target_user_id uuid;
begin
  if not public.is_pricing_admin() then
    raise exception 'Only an administrator can assign user roles';
  end if;
  if p_role not in (
    'pending', 'admin', 'production_manager', 'outlet_manager', 'collector',
    'distributor'
  ) then
    raise exception 'Unsupported user role';
  end if;
  if (p_role = 'distributor') <> (p_distributor_id is not null)
    or (p_role in ('outlet_manager', 'collector'))
      <> (p_external_outlet_id is not null)
    or (p_role not in ('distributor', 'outlet_manager', 'collector')
      and (p_distributor_id is not null or p_external_outlet_id is not null)) then
    raise exception 'The role requires a matching distributor or outlet';
  end if;
  if p_role = 'distributor' and not exists (
    select 1 from public.distributors distributor
    where distributor.id = p_distributor_id and distributor.is_active
  ) then
    raise exception 'The distributor is inactive or does not exist';
  end if;
  if p_role in ('outlet_manager', 'collector') and not exists (
    select 1 from public.external_outlets outlet
    where outlet.id = p_external_outlet_id and outlet.is_active
  ) then
    raise exception 'The outlet is inactive or does not exist';
  end if;

  select id into target_user_id
  from auth.users
  where lower(email) = lower(trim(p_email));
  if target_user_id is null then
    raise exception 'No registered account was found for that email';
  end if;

  insert into public.user_profiles (
    user_id, role, distributor_id, external_outlet_id, updated_at
  ) values (
    target_user_id, p_role, p_distributor_id, p_external_outlet_id, now()
  )
  on conflict (user_id) do update set
    role = excluded.role,
    distributor_id = excluded.distributor_id,
    external_outlet_id = excluded.external_outlet_id,
    updated_at = now();
  return target_user_id;
end;
$$;

create function public.update_user_role(
  p_user_id uuid,
  p_role text,
  p_distributor_id uuid default null,
  p_external_outlet_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target_email text;
begin
  if not public.is_pricing_admin() then
    raise exception 'Only an administrator can assign user roles';
  end if;
  select email into target_email from auth.users where id = p_user_id;
  if target_email is null then
    raise exception 'User account was not found';
  end if;
  return public.assign_user_role(
    target_email, p_role, p_distributor_id, p_external_outlet_id
  );
end;
$$;

create function public.admin_list_users()
returns table (
  user_id uuid,
  email text,
  role text,
  distributor_id uuid,
  external_outlet_id uuid,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select profile.user_id, account.email, profile.role,
    profile.distributor_id, profile.external_outlet_id, profile.created_at
  from public.user_profiles profile
  join auth.users account on account.id = profile.user_id
  where public.is_pricing_admin()
  order by profile.created_at desc;
$$;

create function public.save_distributor(
  p_distributor_id uuid,
  p_name text,
  p_customer_type_id uuid,
  p_is_active boolean,
  p_outlet_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  saved_distributor_id uuid;
begin
  if not public.is_pricing_admin() then
    raise exception 'Only an administrator can manage distributors';
  end if;
  if nullif(trim(p_name), '') is null or p_customer_type_id is null
    or p_is_active is null then
    raise exception 'Distributor name, customer type, and status are required';
  end if;
  if exists (
    select 1
    from unnest(coalesce(p_outlet_ids, '{}'::uuid[])) requested(id)
    left join public.external_outlets outlet on outlet.id = requested.id
    where outlet.id is null or not outlet.is_active
  ) then
    raise exception 'A selected outlet is inactive or does not exist';
  end if;

  if p_distributor_id is null then
    insert into public.distributors (name, customer_type_id, is_active)
    values (trim(p_name), p_customer_type_id, p_is_active)
    returning id into saved_distributor_id;
  else
    update public.distributors set
      name = trim(p_name),
      customer_type_id = p_customer_type_id,
      is_active = p_is_active
    where id = p_distributor_id
    returning id into saved_distributor_id;
    if saved_distributor_id is null then
      raise exception 'Distributor was not found';
    end if;
  end if;

  delete from public.distributor_outlets
  where distributor_id = saved_distributor_id;
  insert into public.distributor_outlets (distributor_id, external_outlet_id)
  select saved_distributor_id, requested.id
  from unnest(coalesce(p_outlet_ids, '{}'::uuid[])) requested(id)
  on conflict do nothing;
  return saved_distributor_id;
end;
$$;

alter table public.distributors
  add column if not exists is_active boolean not null default true;
alter table public.external_outlets
  add column if not exists is_active boolean not null default true;
alter table public.pickup_locations
  add column if not exists is_active boolean not null default true;

alter table public.factory_sales
  add column if not exists external_outlet_id uuid
  references public.external_outlets(id);
create index if not exists factory_sales_distributor_date_idx
  on public.factory_sales(distributor_id, sold_at desc);
create index if not exists factory_sales_outlet_date_idx
  on public.factory_sales(external_outlet_id, sold_at desc);

update public.factory_sales sale
set external_outlet_id = link.external_outlet_id
from public.distributor_outlets link
join public.external_outlets outlet
  on outlet.id = link.external_outlet_id
where sale.external_outlet_id is null
  and link.distributor_id = sale.distributor_id
  and outlet.pickup_location_id = sale.pickup_location_id
  and (
    select count(*)
    from public.distributor_outlets candidate_link
    join public.external_outlets candidate_outlet
      on candidate_outlet.id = candidate_link.external_outlet_id
    where candidate_link.distributor_id = sale.distributor_id
      and candidate_outlet.pickup_location_id = sale.pickup_location_id
  ) = 1;

create table public.distributor_payments (
  id uuid primary key default gen_random_uuid(),
  distributor_id uuid not null references public.distributors(id),
  external_outlet_id uuid not null references public.external_outlets(id),
  amount numeric(14, 2) not null check (amount > 0),
  paid_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create index distributor_payments_account_idx
  on public.distributor_payments(distributor_id, paid_at desc);

create function public.record_distributor_payment(
  p_distributor_id uuid,
  p_external_outlet_id uuid,
  p_amount numeric,
  p_paid_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  payment_id uuid;
begin
  if auth.uid() is null or not (
    public.is_pricing_admin()
    or (
      public.current_user_role() = 'collector'
      and public.current_user_outlet_id() = p_external_outlet_id
    )
  ) then
    raise exception 'Only an administrator or the assigned outlet collector can record payments';
  end if;
  if not exists (
    select 1 from public.distributor_outlets link
    where link.distributor_id = p_distributor_id
      and link.external_outlet_id = p_external_outlet_id
  ) then
    raise exception 'The distributor is not linked to this outlet';
  end if;
  if p_amount is null or p_amount <= 0 or p_paid_at is null then
    raise exception 'A positive payment amount and date are required';
  end if;

  insert into public.distributor_payments (
    distributor_id, external_outlet_id, amount, paid_at, created_by
  ) values (
    p_distributor_id, p_external_outlet_id, p_amount, p_paid_at, auth.uid()
  ) returning id into payment_id;
  return payment_id;
end;
$$;

create or replace function public.create_factory_sale(
  p_distributor_id uuid,
  p_pickup_location_id uuid,
  p_external_outlet_id uuid,
  p_lines jsonb,
  p_sold_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  sale_id uuid;
  line record;
  selected_version_id uuid;
  selected_price numeric(14, 2);
begin
  if auth.uid() is null or not (
    public.is_pricing_admin()
    or (
      public.current_user_role() = 'distributor'
      and public.current_user_distributor_id() = p_distributor_id
    )
  ) then
    raise exception 'Only an administrator or the owning distributor can place an order';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception 'Sale lines must be a JSON array';
  end if;
  if jsonb_array_length(p_lines) = 0 then
    raise exception 'At least one sale line is required';
  end if;
  if p_sold_at is null then
    raise exception 'Sale date is required';
  end if;
  if not exists (
    select 1
    from public.distributor_outlets link
    join public.external_outlets outlet
      on outlet.id = link.external_outlet_id
    where link.distributor_id = p_distributor_id
      and link.external_outlet_id = p_external_outlet_id
      and outlet.pickup_location_id = p_pickup_location_id
      and outlet.is_active
  ) then
    raise exception 'The distributor is not authorized to receive from this outlet';
  end if;
  if not exists (
    select 1 from public.distributors distributor
    where distributor.id = p_distributor_id and distributor.is_active
  ) then
    raise exception 'The distributor is not active or does not exist';
  end if;

  insert into public.factory_sales (
    distributor_id, pickup_location_id, external_outlet_id, sold_at, created_by
  ) values (
    p_distributor_id, p_pickup_location_id, p_external_outlet_id,
    p_sold_at, auth.uid()
  ) returning id into sale_id;

  for line in
    select * from jsonb_to_recordset(p_lines) as item(
      product_id uuid, quantity numeric
    )
  loop
    if line.product_id is null or line.quantity is null or line.quantity <= 0 then
      raise exception 'Every sale line needs a product and positive quantity';
    end if;

    select version.id,
      case when policy.scope_type = 'external_outlet'
        then entry.distributor_sale_price else entry.sale_price end
    into selected_version_id, selected_price
    from public.pricing_policies policy
    join public.price_policy_versions version
      on version.policy_id = policy.id
    join public.price_policy_entries entry
      on entry.version_id = version.id
      and entry.product_id = line.product_id
    where version.starts_at <= p_sold_at
      and (
        (policy.scope_type = 'external_outlet'
          and policy.external_outlet_id = p_external_outlet_id)
        or (policy.scope_type = 'pickup_location'
          and policy.pickup_location_id = p_pickup_location_id)
        or (policy.scope_type = 'customer_type'
          and policy.customer_type_id = (
            select distributor.customer_type_id
            from public.distributors distributor
            where distributor.id = p_distributor_id
          ))
      )
    order by case policy.scope_type
      when 'external_outlet' then 1
      when 'pickup_location' then 2
      else 3
    end, version.starts_at desc
    limit 1;

    if selected_version_id is null or selected_price is null then
      raise exception 'No effective price for product % at %',
        line.product_id, p_sold_at;
    end if;
    insert into public.factory_sale_lines (
      sale_id, product_id, policy_version_id, quantity, unit_price
    ) values (
      sale_id, line.product_id, selected_version_id, line.quantity, selected_price
    );
  end loop;
  return sale_id;
end;
$$;

create or replace function public.create_factory_sale(
  p_distributor_id uuid,
  p_pickup_location_id uuid,
  p_lines jsonb,
  p_sold_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  matching_outlet_id uuid;
  matching_outlet_count integer;
begin
  select (array_agg(outlet.id order by outlet.id))[1], count(*)::integer
    into matching_outlet_id, matching_outlet_count
  from public.distributor_outlets link
  join public.external_outlets outlet
    on outlet.id = link.external_outlet_id
  where link.distributor_id = p_distributor_id
    and outlet.pickup_location_id = p_pickup_location_id
    and outlet.is_active;

  if matching_outlet_count = 0 then
    raise exception 'The distributor is not authorized to receive from this pickup location';
  end if;
  if matching_outlet_count > 1 then
    raise exception 'Specify the external outlet when more than one is authorized';
  end if;
  return public.create_factory_sale(
    p_distributor_id, p_pickup_location_id, matching_outlet_id, p_lines, p_sold_at
  );
end;
$$;

create or replace function public.create_outlet_purchase(
  p_external_outlet_id uuid,
  p_lines jsonb,
  p_purchased_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  purchase_id uuid;
  line record;
  selected_version_id uuid;
  selected_price numeric(14, 2);
begin
  if auth.uid() is null or not (
    public.is_pricing_admin()
    or (
      public.current_user_role() = 'outlet_manager'
      and public.current_user_outlet_id() = p_external_outlet_id
    )
  ) then
    raise exception 'Only an administrator or the assigned outlet manager can record purchases';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception 'Purchase lines must be a JSON array';
  end if;
  if jsonb_array_length(p_lines) = 0 then
    raise exception 'At least one purchase line is required';
  end if;
  if p_purchased_at is null then
    raise exception 'Purchase date is required';
  end if;
  if not exists (
    select 1 from public.external_outlets outlet
    where outlet.id = p_external_outlet_id and outlet.is_active
  ) then
    raise exception 'The outlet is not active or does not exist';
  end if;

  insert into public.outlet_purchases (
    external_outlet_id, purchased_at, created_by
  ) values (p_external_outlet_id, p_purchased_at, auth.uid())
  returning id into purchase_id;

  for line in
    select * from jsonb_to_recordset(p_lines) as item(
      product_id uuid, quantity numeric
    )
  loop
    if line.product_id is null or line.quantity is null or line.quantity <= 0 then
      raise exception 'Every purchase line needs a product and positive quantity';
    end if;
    select version.id, entry.factory_purchase_price
    into selected_version_id, selected_price
    from public.pricing_policies policy
    join public.price_policy_versions version on version.policy_id = policy.id
    join public.price_policy_entries entry
      on entry.version_id = version.id
      and entry.product_id = line.product_id
    where policy.scope_type = 'external_outlet'
      and policy.external_outlet_id = p_external_outlet_id
      and version.starts_at <= p_purchased_at
    order by version.starts_at desc
    limit 1;

    if selected_version_id is null or selected_price is null then
      raise exception 'No effective factory purchase price for product % at %',
        line.product_id, p_purchased_at;
    end if;
    insert into public.outlet_purchase_lines (
      purchase_id, product_id, policy_version_id, quantity, unit_price
    ) values (
      purchase_id, line.product_id, selected_version_id, line.quantity, selected_price
    );
  end loop;
  return purchase_id;
end;
$$;

create view public.distributor_account_balances
with (security_invoker = true)
as
select
  distributor.id as distributor_id,
  distributor.name as distributor_name,
  coalesce(sales.total, 0)::numeric(18, 2) as factory_sales_total,
  coalesce(payments.total, 0)::numeric(18, 2) as payments_total,
  (coalesce(sales.total, 0) - coalesce(payments.total, 0))::numeric(18, 2)
    as balance
from public.distributors distributor
left join (
  select sale.distributor_id, sum(line.line_total) as total
  from public.factory_sales sale
  join public.factory_sale_lines line on line.sale_id = sale.id
  group by sale.distributor_id
) sales on sales.distributor_id = distributor.id
left join (
  select payment.distributor_id, sum(payment.amount) as total
  from public.distributor_payments payment
  group by payment.distributor_id
) payments on payments.distributor_id = distributor.id
where public.current_user_role() in (
  'admin', 'distributor', 'outlet_manager', 'collector'
);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'products', 'customer_types', 'pickup_locations', 'external_outlets',
    'distributors', 'distributor_outlets', 'pricing_policies',
    'price_policy_versions', 'price_policy_entries', 'factory_sales',
    'factory_sale_lines', 'outlet_purchases', 'outlet_purchase_lines',
    'outlet_payments'
  ] loop
    execute format(
      'drop policy if exists "pricing administrators can read %1$I" on public.%1$I',
      table_name
    );
  end loop;
end;
$$;

drop policy if exists "pricing administrators record outlet payments"
  on public.outlet_payments;

alter table public.user_profiles enable row level security;
alter table public.distributor_payments enable row level security;

create policy "users read own profile or administrators read all"
  on public.user_profiles for select to authenticated
  using (user_id = auth.uid() or public.is_pricing_admin());

create policy "administrators update user profiles"
  on public.user_profiles for update to authenticated
  using (public.is_pricing_admin())
  with check (public.is_pricing_admin());

create policy "authenticated users read active products"
  on public.products for select to authenticated
  using (
    public.current_user_role() in (
      'admin', 'production_manager', 'distributor', 'outlet_manager', 'collector'
    )
    and (is_active or public.is_pricing_admin())
  );
create policy "administrators manage products"
  on public.products for all to authenticated
  using (public.is_pricing_admin())
  with check (public.is_pricing_admin());

create policy "authenticated users read customer types"
  on public.customer_types for select to authenticated
  using (public.current_user_role() <> 'pending');
create policy "administrators manage customer types"
  on public.customer_types for all to authenticated
  using (public.is_pricing_admin())
  with check (public.is_pricing_admin());

create policy "users read assigned pickup locations"
  on public.pickup_locations for select to authenticated
  using (
    public.is_pricing_admin()
    or public.current_user_role() = 'production_manager'
    or (public.current_user_role() = 'distributor' and exists (
      select 1
      from public.distributor_outlets link
      join public.external_outlets outlet
        on outlet.id = link.external_outlet_id
      where link.distributor_id = public.current_user_distributor_id()
        and outlet.pickup_location_id = public.pickup_locations.id
    ))
    or exists (
      select 1 from public.external_outlets outlet
      where outlet.id = public.current_user_outlet_id()
        and outlet.pickup_location_id = public.pickup_locations.id
    )
  );
create policy "administrators manage pickup locations"
  on public.pickup_locations for all to authenticated
  using (public.is_pricing_admin())
  with check (public.is_pricing_admin());

create policy "users read assigned outlets"
  on public.external_outlets for select to authenticated
  using (
    public.is_pricing_admin()
    or public.current_user_role() = 'production_manager'
    or public.current_user_outlet_id() = id
    or exists (
      select 1 from public.distributor_outlets link
      where link.distributor_id = public.current_user_distributor_id()
        and link.external_outlet_id = id
    )
  );
create policy "administrators manage outlets"
  on public.external_outlets for all to authenticated
  using (public.is_pricing_admin())
  with check (public.is_pricing_admin());

create policy "users read assigned distributors"
  on public.distributors for select to authenticated
  using (
    public.is_pricing_admin()
    or public.current_user_role() = 'production_manager'
    or id = public.current_user_distributor_id()
    or exists (
      select 1 from public.distributor_outlets link
      where link.distributor_id = id
        and link.external_outlet_id = public.current_user_outlet_id()
    )
  );
create policy "administrators manage distributors"
  on public.distributors for all to authenticated
  using (public.is_pricing_admin())
  with check (public.is_pricing_admin());

create policy "users read assigned distributor outlets"
  on public.distributor_outlets for select to authenticated
  using (
    public.is_pricing_admin()
    or public.current_user_role() = 'production_manager'
    or distributor_id = public.current_user_distributor_id()
    or external_outlet_id = public.current_user_outlet_id()
  );
create policy "administrators manage distributor outlets"
  on public.distributor_outlets for all to authenticated
  using (public.is_pricing_admin())
  with check (public.is_pricing_admin());

create policy "administrators manage pricing policies"
  on public.pricing_policies for all to authenticated
  using (public.is_pricing_admin())
  with check (public.is_pricing_admin());
create policy "administrators read price versions"
  on public.price_policy_versions for select to authenticated
  using (public.is_pricing_admin());
create policy "administrators read price entries"
  on public.price_policy_entries for select to authenticated
  using (public.is_pricing_admin());

create policy "users read assigned sales"
  on public.factory_sales for select to authenticated
  using (public.can_view_distributor(distributor_id)
    and (
      public.current_user_role() in ('admin', 'production_manager', 'distributor')
      or external_outlet_id = public.current_user_outlet_id()
    ));
create policy "users read assigned sale lines"
  on public.factory_sale_lines for select to authenticated
  using (public.can_view_factory_sale(sale_id));

create policy "users read assigned outlet purchases"
  on public.outlet_purchases for select to authenticated
  using (public.can_view_outlet(external_outlet_id));
create policy "users read assigned outlet purchase lines"
  on public.outlet_purchase_lines for select to authenticated
  using (exists (
    select 1 from public.outlet_purchases purchase
    where purchase.id = purchase_id
      and public.can_view_outlet(purchase.external_outlet_id)
  ));
create policy "users read assigned outlet payments"
  on public.outlet_payments for select to authenticated
  using (public.can_view_outlet(external_outlet_id));
create policy "assigned users record outlet payments"
  on public.outlet_payments for insert to authenticated
  with check (
    created_by = auth.uid()
    and (
      public.is_pricing_admin()
      or (
        public.current_user_role() = 'outlet_manager'
        and public.current_user_outlet_id() = external_outlet_id
      )
    )
  );

create policy "users read assigned distributor payments"
  on public.distributor_payments for select to authenticated
  using (
    public.is_pricing_admin()
    or distributor_id = public.current_user_distributor_id()
    or (
      external_outlet_id = public.current_user_outlet_id()
      and exists (
        select 1 from public.distributor_outlets link
        where link.distributor_id = distributor_payments.distributor_id
          and link.external_outlet_id = distributor_payments.external_outlet_id
      )
    )
  );

grant select, insert, update on
  public.products, public.customer_types, public.pickup_locations,
  public.external_outlets, public.distributors, public.distributor_outlets
to authenticated;
grant delete on public.distributor_outlets to authenticated;
grant select on
  public.user_profiles, public.distributor_payments,
  public.distributor_account_balances
to authenticated;
grant execute on function public.current_user_role() to authenticated;
grant execute on function public.current_user_distributor_id() to authenticated;
grant execute on function public.current_user_outlet_id() to authenticated;
grant execute on function public.is_pricing_admin() to authenticated;
grant execute on function public.can_view_distributor(uuid) to authenticated;
grant execute on function public.can_view_outlet(uuid) to authenticated;
grant execute on function public.can_view_factory_sale(uuid) to authenticated;
grant execute on function public.assign_user_role(text, text, uuid, uuid)
  to authenticated;
grant execute on function public.update_user_role(uuid, text, uuid, uuid)
  to authenticated;
grant execute on function public.admin_list_users() to authenticated;
grant execute on function public.save_distributor(uuid, text, uuid, boolean, uuid[])
  to authenticated;
grant execute on function public.record_distributor_payment(
  uuid, uuid, numeric, timestamptz
) to authenticated;
grant execute on function public.create_factory_sale(
  uuid, uuid, uuid, jsonb, timestamptz
) to authenticated;
grant execute on function public.create_factory_sale(
  uuid, uuid, jsonb, timestamptz
) to authenticated;
grant execute on function public.create_outlet_purchase(
  uuid, jsonb, timestamptz
) to authenticated;
grant select on public.outlet_account_balances to authenticated;

revoke all on function public.assign_user_role(text, text, uuid, uuid) from public;
revoke all on function public.update_user_role(uuid, text, uuid, uuid) from public;
revoke all on function public.admin_list_users() from public;
revoke all on function public.save_distributor(
  uuid, text, uuid, boolean, uuid[]
) from public;
revoke all on function public.create_user_profile() from public;
revoke all on function public.current_user_role() from public;
revoke all on function public.current_user_distributor_id() from public;
revoke all on function public.current_user_outlet_id() from public;
revoke all on function public.is_pricing_admin() from public;
revoke all on function public.can_view_distributor(uuid) from public;
revoke all on function public.can_view_outlet(uuid) from public;
revoke all on function public.can_view_factory_sale(uuid) from public;
revoke all on function public.record_distributor_payment(
  uuid, uuid, numeric, timestamptz
) from public;
revoke all on function public.create_factory_sale(
  uuid, uuid, uuid, jsonb, timestamptz
) from public;
revoke all on function public.create_factory_sale(
  uuid, uuid, jsonb, timestamptz
) from public;
