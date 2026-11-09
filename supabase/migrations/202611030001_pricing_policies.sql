create table public.products (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.customer_types (
  id uuid primary key default gen_random_uuid(),
  name text not null unique
);

create table public.pickup_locations (
  id uuid primary key default gen_random_uuid(),
  name text not null unique
);

create table public.external_outlets (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  pickup_location_id uuid not null references public.pickup_locations(id)
);

create table public.distributors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  customer_type_id uuid not null references public.customer_types(id),
  created_at timestamptz not null default now()
);

create table public.distributor_outlets (
  distributor_id uuid not null references public.distributors(id),
  external_outlet_id uuid not null references public.external_outlets(id),
  primary key (distributor_id, external_outlet_id)
);

create table public.pricing_policies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  scope_type text not null check (
    scope_type in ('customer_type', 'pickup_location', 'external_outlet')
  ),
  customer_type_id uuid references public.customer_types(id),
  pickup_location_id uuid references public.pickup_locations(id),
  external_outlet_id uuid references public.external_outlets(id),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  check (
    (scope_type = 'customer_type'
      and customer_type_id is not null
      and pickup_location_id is null
      and external_outlet_id is null)
    or (scope_type = 'pickup_location'
      and customer_type_id is null
      and pickup_location_id is not null
      and external_outlet_id is null)
    or (scope_type = 'external_outlet'
      and customer_type_id is null
      and pickup_location_id is null
      and external_outlet_id is not null)
  )
);

create unique index pricing_policies_customer_type_unique
  on public.pricing_policies(customer_type_id)
  where scope_type = 'customer_type';
create unique index pricing_policies_pickup_location_unique
  on public.pricing_policies(pickup_location_id)
  where scope_type = 'pickup_location';
create unique index pricing_policies_external_outlet_unique
  on public.pricing_policies(external_outlet_id)
  where scope_type = 'external_outlet';

create table public.price_policy_versions (
  id uuid primary key default gen_random_uuid(),
  policy_id uuid not null references public.pricing_policies(id),
  starts_at timestamptz not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (policy_id, starts_at)
);

create index price_policy_versions_effective_idx
  on public.price_policy_versions(policy_id, starts_at desc);

create table public.price_policy_entries (
  version_id uuid not null references public.price_policy_versions(id),
  product_id uuid not null references public.products(id),
  sale_price numeric(14, 2),
  factory_purchase_price numeric(14, 2),
  distributor_sale_price numeric(14, 2),
  primary key (version_id, product_id),
  check (
    (sale_price is null or sale_price >= 0)
    and (factory_purchase_price is null or factory_purchase_price >= 0)
    and (distributor_sale_price is null or distributor_sale_price >= 0)
    and (sale_price is not null
      or factory_purchase_price is not null
      or distributor_sale_price is not null)
  )
);

create function public.is_pricing_admin()
returns boolean
language sql
stable
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin';
$$;

create function public.validate_price_policy_entry()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  policy_scope text;
begin
  select p.scope_type into policy_scope
  from public.price_policy_versions v
  join public.pricing_policies p on p.id = v.policy_id
  where v.id = new.version_id;

  if policy_scope = 'external_outlet' then
    if new.sale_price is not null
      or new.factory_purchase_price is null
      or new.distributor_sale_price is null then
      raise exception 'Outlet prices must include factory purchase and distributor sale prices only';
    end if;
  elsif policy_scope in ('customer_type', 'pickup_location') then
    if new.sale_price is null
      or new.factory_purchase_price is not null
      or new.distributor_sale_price is not null then
      raise exception 'Customer and pickup policies require a sale price only';
    end if;
  else
    raise exception 'Pricing policy version was not found';
  end if;
  return new;
end;
$$;

create trigger price_policy_entry_validate
before insert on public.price_policy_entries
for each row execute function public.validate_price_policy_entry();

create function public.reject_pricing_history_change()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Pricing history is immutable; create a new effective version instead';
end;
$$;

create trigger price_policy_versions_immutable
before update or delete on public.price_policy_versions
for each row execute function public.reject_pricing_history_change();

create trigger price_policy_entries_immutable
before update or delete on public.price_policy_entries
for each row execute function public.reject_pricing_history_change();

create function public.protect_pricing_policy_scope()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Pricing policies cannot be deleted; preserve their history';
  end if;
  if (new.scope_type, new.customer_type_id, new.pickup_location_id,
      new.external_outlet_id)
      is distinct from
      (old.scope_type, old.customer_type_id, old.pickup_location_id,
      old.external_outlet_id)
      and exists (
        select 1 from public.price_policy_versions v where v.policy_id = old.id
      ) then
    raise exception 'A policy scope cannot change after its first version';
  end if;
  return new;
end;
$$;

create trigger pricing_policy_scope_guard
before update or delete on public.pricing_policies
for each row execute function public.protect_pricing_policy_scope();

create function public.save_pricing_policy(
  p_policy_id uuid,
  p_name text,
  p_scope_type text,
  p_customer_type_id uuid,
  p_pickup_location_id uuid,
  p_external_outlet_id uuid,
  p_starts_at timestamptz,
  p_prices jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  saved_policy_id uuid;
  saved_version_id uuid;
  price_count integer;
begin
  if auth.uid() is null or not public.is_pricing_admin() then
    raise exception 'Only an authenticated pricing administrator can save policies';
  end if;
  if nullif(trim(p_name), '') is null then
    raise exception 'Policy name is required';
  end if;
  if p_starts_at is null or p_prices is null or jsonb_typeof(p_prices) <> 'array' then
    raise exception 'An effective date and price list are required';
  end if;

  if p_policy_id is null then
    insert into public.pricing_policies (
      name, scope_type, customer_type_id, pickup_location_id,
      external_outlet_id, created_by
    ) values (
      trim(p_name), p_scope_type, p_customer_type_id, p_pickup_location_id,
      p_external_outlet_id, auth.uid()
    ) returning id into saved_policy_id;
  else
    select id into saved_policy_id
    from public.pricing_policies
    where id = p_policy_id
      and scope_type = p_scope_type
      and customer_type_id is not distinct from p_customer_type_id
      and pickup_location_id is not distinct from p_pickup_location_id
      and external_outlet_id is not distinct from p_external_outlet_id
    for update;
    if saved_policy_id is null then
      raise exception 'Policy not found or its scope does not match';
    end if;
    update public.pricing_policies set name = trim(p_name)
    where id = saved_policy_id;
  end if;

  insert into public.price_policy_versions (policy_id, starts_at, created_by)
  values (saved_policy_id, p_starts_at, auth.uid())
  returning id into saved_version_id;

  insert into public.price_policy_entries (
    version_id, product_id, sale_price, factory_purchase_price,
    distributor_sale_price
  )
  select
    saved_version_id, prices.product_id, prices.sale_price,
    prices.factory_purchase_price, prices.distributor_sale_price
  from jsonb_to_recordset(p_prices) as prices(
    product_id uuid,
    sale_price numeric,
    factory_purchase_price numeric,
    distributor_sale_price numeric
  );
  get diagnostics price_count = row_count;
  if price_count = 0 then
    raise exception 'At least one product price is required';
  end if;

  return saved_policy_id;
end;
$$;

create table public.factory_sales (
  id uuid primary key default gen_random_uuid(),
  distributor_id uuid not null references public.distributors(id),
  pickup_location_id uuid not null references public.pickup_locations(id),
  sold_at timestamptz not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.factory_sale_lines (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.factory_sales(id),
  product_id uuid not null references public.products(id),
  policy_version_id uuid not null references public.price_policy_versions(id),
  quantity numeric(14, 3) not null check (quantity > 0),
  unit_price numeric(14, 2) not null check (unit_price >= 0),
  line_total numeric(18, 2) generated always as (quantity * unit_price) stored
);

create table public.outlet_purchases (
  id uuid primary key default gen_random_uuid(),
  external_outlet_id uuid not null references public.external_outlets(id),
  purchased_at timestamptz not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.outlet_purchase_lines (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.outlet_purchases(id),
  product_id uuid not null references public.products(id),
  policy_version_id uuid not null references public.price_policy_versions(id),
  quantity numeric(14, 3) not null check (quantity > 0),
  unit_price numeric(14, 2) not null check (unit_price >= 0),
  line_total numeric(18, 2) generated always as (quantity * unit_price) stored
);

create table public.outlet_payments (
  id uuid primary key default gen_random_uuid(),
  external_outlet_id uuid not null references public.external_outlets(id),
  amount numeric(14, 2) not null check (amount > 0),
  paid_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create function public.create_factory_sale(
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
  sale_id uuid;
  line record;
  selected_version_id uuid;
  selected_price numeric(14, 2);
begin
  if auth.uid() is null or not public.is_pricing_admin() then
    raise exception 'Only an authenticated pricing administrator can record sales';
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

  insert into public.factory_sales (
    distributor_id, pickup_location_id, sold_at, created_by
  ) values (p_distributor_id, p_pickup_location_id, p_sold_at, auth.uid())
  returning id into sale_id;

  for line in
    select * from jsonb_to_recordset(p_lines) as item(
      product_id uuid, quantity numeric
    )
  loop
    if line.quantity is null or line.quantity <= 0 then
      raise exception 'Sale quantities must be positive';
    end if;

    select v.id,
      case when p.scope_type = 'external_outlet'
        then e.distributor_sale_price else e.sale_price end
    into selected_version_id, selected_price
    from public.pricing_policies p
    join public.price_policy_versions v on v.policy_id = p.id
    join public.price_policy_entries e on e.version_id = v.id
      and e.product_id = line.product_id
    where v.starts_at <= p_sold_at
      and (
        (p.scope_type = 'external_outlet' and p.external_outlet_id in (
          select outlet.external_outlet_id
          from public.distributor_outlets outlet
          join public.external_outlets target
            on target.id = outlet.external_outlet_id
          where outlet.distributor_id = p_distributor_id
            and target.pickup_location_id = p_pickup_location_id
        ))
        or (p.scope_type = 'pickup_location'
          and p.pickup_location_id = p_pickup_location_id)
        or (p.scope_type = 'customer_type'
          and p.customer_type_id = (
            select d.customer_type_id from public.distributors d
            where d.id = p_distributor_id
          ))
      )
    order by case p.scope_type
      when 'external_outlet' then 1
      when 'pickup_location' then 2
      else 3
    end, v.starts_at desc
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

create function public.create_outlet_purchase(
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
  if auth.uid() is null or not public.is_pricing_admin() then
    raise exception 'Only an authenticated pricing administrator can record purchases';
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

  insert into public.outlet_purchases (
    external_outlet_id, purchased_at, created_by
  ) values (p_external_outlet_id, p_purchased_at, auth.uid())
  returning id into purchase_id;

  for line in
    select * from jsonb_to_recordset(p_lines) as item(
      product_id uuid, quantity numeric
    )
  loop
    if line.quantity is null or line.quantity <= 0 then
      raise exception 'Purchase quantities must be positive';
    end if;
    select v.id, e.factory_purchase_price
    into selected_version_id, selected_price
    from public.pricing_policies p
    join public.price_policy_versions v on v.policy_id = p.id
    join public.price_policy_entries e on e.version_id = v.id
      and e.product_id = line.product_id
    where p.scope_type = 'external_outlet'
      and p.external_outlet_id = p_external_outlet_id
      and v.starts_at <= p_purchased_at
    order by v.starts_at desc
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

create view public.outlet_account_balances
with (security_invoker = true)
as
select
  outlet.id as external_outlet_id,
  outlet.name as external_outlet_name,
  coalesce(purchases.total, 0)::numeric(18, 2) as factory_purchase_total,
  coalesce(payments.total, 0)::numeric(18, 2) as payments_total,
  (coalesce(purchases.total, 0) - coalesce(payments.total, 0))::numeric(18, 2)
    as balance
from public.external_outlets outlet
left join (
  select purchase.external_outlet_id, sum(line.line_total) as total
  from public.outlet_purchases purchase
  join public.outlet_purchase_lines line on line.purchase_id = purchase.id
  group by purchase.external_outlet_id
) purchases on purchases.external_outlet_id = outlet.id
left join (
  select payment.external_outlet_id, sum(payment.amount) as total
  from public.outlet_payments payment
  group by payment.external_outlet_id
) payments on payments.external_outlet_id = outlet.id;

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
    execute format('alter table public.%I enable row level security', table_name);
    execute format(
      'create policy "pricing administrators can read %1$I" on public.%1$I '
      'for select to authenticated using (public.is_pricing_admin())',
      table_name
    );
  end loop;
end;
$$;

create policy "pricing administrators record outlet payments"
  on public.outlet_payments for insert to authenticated
  with check (
    public.is_pricing_admin()
    and created_by = auth.uid()
  );

grant select on
  public.products,
  public.customer_types,
  public.pickup_locations,
  public.external_outlets,
  public.distributors,
  public.distributor_outlets,
  public.pricing_policies,
  public.price_policy_versions,
  public.price_policy_entries,
  public.factory_sales,
  public.factory_sale_lines,
  public.outlet_purchases,
  public.outlet_purchase_lines,
  public.outlet_payments,
  public.outlet_account_balances
to authenticated;
grant insert on public.outlet_payments to authenticated;

grant execute on function public.save_pricing_policy(
  uuid, text, text, uuid, uuid, uuid, timestamptz, jsonb
) to authenticated;
grant execute on function public.create_factory_sale(
  uuid, uuid, jsonb, timestamptz
) to authenticated;
grant execute on function public.create_outlet_purchase(
  uuid, jsonb, timestamptz
) to authenticated;

revoke all on function public.save_pricing_policy(
  uuid, text, text, uuid, uuid, uuid, timestamptz, jsonb
) from public;
revoke all on function public.create_factory_sale(
  uuid, uuid, jsonb, timestamptz
) from public;
revoke all on function public.create_outlet_purchase(
  uuid, jsonb, timestamptz
) from public;
