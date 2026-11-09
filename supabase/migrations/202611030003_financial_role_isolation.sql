alter table public.user_profiles
  add column if not exists pickup_location_id uuid
  references public.pickup_locations(id);

alter table public.user_profiles
  drop constraint if exists user_profiles_role_check,
  drop constraint if exists user_profiles_check;

alter table public.user_profiles
  add constraint user_profiles_role_check check (
    role in (
      'pending', 'admin', 'accountant', 'production_manager',
      'factory_outlet_manager', 'outlet_manager', 'collector', 'distributor'
    )
  ),
  add constraint user_profiles_assignment_check check (
    (role = 'distributor'
      and distributor_id is not null
      and external_outlet_id is null
      and pickup_location_id is null)
    or (role in ('outlet_manager', 'collector')
      and distributor_id is null
      and external_outlet_id is not null
      and pickup_location_id is null)
    or (role = 'factory_outlet_manager'
      and distributor_id is null
      and external_outlet_id is null
      and pickup_location_id is not null)
    or (role in ('pending', 'admin', 'accountant', 'production_manager')
      and distributor_id is null
      and external_outlet_id is null
      and pickup_location_id is null)
  );

alter table public.factory_sales
  add column if not exists external_outlet_id uuid
  references public.external_outlets(id);

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

create or replace function public.current_user_outlet_id()
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

create function public.current_user_pickup_location_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select profile.pickup_location_id
  from public.user_profiles profile
  where profile.user_id = auth.uid()
    and profile.role = 'factory_outlet_manager';
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

create function public.can_view_financials()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    public.current_user_role() in ('admin', 'accountant'),
    false
  );
$$;

create or replace function public.can_view_factory_sale(p_sale_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    public.current_user_role() in ('admin', 'accountant', 'production_manager')
    or exists (
      select 1
      from public.factory_sales sale
      where sale.id = p_sale_id
        and (
          sale.distributor_id = public.current_user_distributor_id()
          or (
            sale.external_outlet_id = public.current_user_outlet_id()
            and public.current_user_role() in ('outlet_manager', 'collector')
            and exists (
              select 1 from public.distributor_outlets link
              where link.distributor_id = sale.distributor_id
                and link.external_outlet_id = sale.external_outlet_id
            )
          )
          or (
            sale.pickup_location_id =
              public.current_user_pickup_location_id()
            and public.current_user_role() = 'factory_outlet_manager'
          )
        )
    ),
    false
  );
$$;

create function public.assign_user_role_v2(
  p_email text,
  p_role text,
  p_distributor_id uuid default null,
  p_external_outlet_id uuid default null,
  p_pickup_location_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  target_user_id uuid;
begin
  if auth.uid() is null or not public.is_pricing_admin() then
    raise exception 'Only an administrator can assign user roles';
  end if;
  if p_role not in (
    'pending', 'admin', 'accountant', 'production_manager',
    'factory_outlet_manager', 'outlet_manager', 'collector', 'distributor'
  ) then
    raise exception 'Unsupported user role';
  end if;

  if (p_role = 'distributor') <> (p_distributor_id is not null)
    or (p_role in ('outlet_manager', 'collector'))
      <> (p_external_outlet_id is not null)
    or (p_role = 'factory_outlet_manager')
      <> (p_pickup_location_id is not null) then
    raise exception 'The role requires exactly one matching assignment';
  end if;
  if p_distributor_id is not null and not exists (
    select 1 from public.distributors distributor
    where distributor.id = p_distributor_id and distributor.is_active
  ) then
    raise exception 'The distributor is inactive or does not exist';
  end if;
  if p_external_outlet_id is not null and not exists (
    select 1 from public.external_outlets outlet
    where outlet.id = p_external_outlet_id and outlet.is_active
  ) then
    raise exception 'The outlet is inactive or does not exist';
  end if;
  if p_pickup_location_id is not null and not exists (
    select 1 from public.pickup_locations location
    where location.id = p_pickup_location_id and location.is_active
  ) then
    raise exception 'The pickup location is inactive or does not exist';
  end if;

  perform pg_advisory_xact_lock(hashtext('user_profiles_admin_role_change'));
  select account.id into target_user_id
  from auth.users account
  where lower(account.email) = lower(trim(p_email))
  for update;
  if target_user_id is null then
    raise exception 'No registered account was found for that email';
  end if;
  if target_user_id = auth.uid() then
    raise exception 'Administrators cannot modify their own role or assignment';
  end if;
  if p_role <> 'admin'
    and (select count(*) from public.user_profiles where role = 'admin') <= 1
    and (select role from public.user_profiles where user_id = target_user_id)
      = 'admin' then
    raise exception 'The last administrator cannot be demoted';
  end if;

  insert into public.user_profiles (
    user_id, role, distributor_id, external_outlet_id, pickup_location_id,
    updated_at
  ) values (
    target_user_id, p_role, p_distributor_id, p_external_outlet_id,
    p_pickup_location_id, now()
  )
  on conflict (user_id) do update set
    role = excluded.role,
    distributor_id = excluded.distributor_id,
    external_outlet_id = excluded.external_outlet_id,
    pickup_location_id = excluded.pickup_location_id,
    updated_at = now();
  return target_user_id;
end;
$$;

create function public.update_user_role_v2(
  p_user_id uuid,
  p_role text,
  p_distributor_id uuid default null,
  p_external_outlet_id uuid default null,
  p_pickup_location_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  target_email text;
begin
  if auth.uid() is null or not public.is_pricing_admin() then
    raise exception 'Only an administrator can assign user roles';
  end if;
  select email into target_email from auth.users where id = p_user_id;
  if target_email is null then
    raise exception 'User account was not found';
  end if;
  return public.assign_user_role_v2(
    target_email, p_role, p_distributor_id, p_external_outlet_id,
    p_pickup_location_id
  );
end;
$$;

create or replace function public.admin_list_users()
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

create function public.admin_list_users_v2()
returns table (
  user_id uuid,
  email text,
  role text,
  distributor_id uuid,
  external_outlet_id uuid,
  pickup_location_id uuid,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select profile.user_id, account.email, profile.role,
    profile.distributor_id, profile.external_outlet_id,
    profile.pickup_location_id, profile.created_at
  from public.user_profiles profile
  join auth.users account on account.id = profile.user_id
  where public.is_pricing_admin()
  order by profile.created_at desc;
$$;

do $$
declare
  policy_row record;
begin
  for policy_row in
    select policyname, tablename
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'factory_sales', 'factory_sale_lines', 'outlet_purchases',
        'outlet_purchase_lines', 'outlet_payments', 'distributor_payments',
        'pricing_policies', 'price_policy_versions', 'price_policy_entries',
        'user_profiles'
      )
  loop
    execute format(
      'drop policy %I on public.%I',
      policy_row.policyname, policy_row.tablename
    );
  end loop;
end;
$$;

create policy "read assigned sale headers"
  on public.factory_sales for select to authenticated
  using (
    public.current_user_role() in ('admin', 'accountant', 'production_manager')
    or distributor_id = public.current_user_distributor_id()
    or (
      external_outlet_id = public.current_user_outlet_id()
      and public.current_user_role() in ('outlet_manager', 'collector')
      and exists (
        select 1 from public.distributor_outlets link
        where link.distributor_id = factory_sales.distributor_id
          and link.external_outlet_id = factory_sales.external_outlet_id
      )
    )
    or (
      pickup_location_id = public.current_user_pickup_location_id()
      and public.current_user_role() = 'factory_outlet_manager'
    )
  );

create policy "users read own profile or administrators read all"
  on public.user_profiles for select to authenticated
  using (user_id = auth.uid() or public.is_pricing_admin());

create policy "read assigned sale lines"
  on public.factory_sale_lines for select to authenticated
  using (public.can_view_factory_sale(sale_id));

create policy "read authorized outlet purchases"
  on public.outlet_purchases for select to authenticated
  using (
    public.current_user_role() in ('admin', 'accountant')
    or (
      external_outlet_id = public.current_user_outlet_id()
      and public.current_user_role() = 'outlet_manager'
    )
  );

create policy "read authorized outlet purchase lines"
  on public.outlet_purchase_lines for select to authenticated
  using (
    public.current_user_role() in ('admin', 'accountant')
    or exists (
      select 1 from public.outlet_purchases purchase
      where purchase.id = purchase_id
        and purchase.external_outlet_id = public.current_user_outlet_id()
        and public.current_user_role() = 'outlet_manager'
    )
  );

create policy "read authorized outlet payments"
  on public.outlet_payments for select to authenticated
  using (
    public.current_user_role() in ('admin', 'accountant')
    or (
      external_outlet_id = public.current_user_outlet_id()
      and public.current_user_role() = 'outlet_manager'
    )
  );

create policy "accountants and linked users read distributor payments"
  on public.distributor_payments for select to authenticated
  using (
    public.current_user_role() in ('admin', 'accountant')
    or distributor_id = public.current_user_distributor_id()
    or (
      external_outlet_id = public.current_user_outlet_id()
      and public.current_user_role() in ('outlet_manager', 'collector')
      and exists (
        select 1 from public.distributor_outlets link
        where link.distributor_id = distributor_payments.distributor_id
          and link.external_outlet_id = distributor_payments.external_outlet_id
      )
    )
  );

create policy "administrators and accountants read price policies"
  on public.pricing_policies for select to authenticated
  using (public.current_user_role() in ('admin', 'accountant'));
create policy "administrators manage price policies"
  on public.pricing_policies for all to authenticated
  using (public.is_pricing_admin())
  with check (public.is_pricing_admin());
create policy "administrators and accountants read price versions"
  on public.price_policy_versions for select to authenticated
  using (public.current_user_role() in ('admin', 'accountant'));
create policy "administrators and accountants read price entries"
  on public.price_policy_entries for select to authenticated
  using (public.current_user_role() in ('admin', 'accountant'));

create policy "accountants and factory outlet managers read products"
  on public.products for select to authenticated
  using (
    public.current_user_role() in ('accountant', 'factory_outlet_manager')
    and (is_active or public.is_pricing_admin())
  );
create policy "accountants read customer types"
  on public.customer_types for select to authenticated
  using (public.current_user_role() = 'accountant');
create policy "factory outlet managers read assigned pickup location"
  on public.pickup_locations for select to authenticated
  using (
    public.current_user_role() = 'factory_outlet_manager'
    and id = public.current_user_pickup_location_id()
  );
create policy "accountants read all outlets"
  on public.external_outlets for select to authenticated
  using (public.current_user_role() = 'accountant');
create policy "accountants read all distributors"
  on public.distributors for select to authenticated
  using (public.current_user_role() = 'accountant');
create policy "accountants read all distributor outlet links"
  on public.distributor_outlets for select to authenticated
  using (public.current_user_role() = 'accountant');

create or replace view public.outlet_account_balances
with (security_barrier = true)
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
) payments on payments.external_outlet_id = outlet.id
where public.current_user_role() in ('admin', 'accountant')
  or (
    outlet.id = public.current_user_outlet_id()
    and public.current_user_role() = 'outlet_manager'
  );

create or replace view public.distributor_account_balances
with (security_barrier = true)
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
where public.current_user_role() in ('admin', 'accountant')
  or distributor.id = public.current_user_distributor_id()
  or (
    public.current_user_role() in ('outlet_manager', 'collector')
    and exists (
      select 1 from public.distributor_outlets link
      where link.distributor_id = distributor.id
        and link.external_outlet_id = public.current_user_outlet_id()
    )
  );

create view public.role_factory_sales
with (security_barrier = true)
as
select
  sale.id,
  sale.distributor_id,
  sale.pickup_location_id,
  sale.external_outlet_id,
  sale.sold_at,
  sale.created_by,
  sale.created_at
from public.factory_sales sale
where public.current_user_role() in (
    'admin', 'accountant', 'production_manager'
  )
  or sale.distributor_id = public.current_user_distributor_id()
  or (
    sale.external_outlet_id = public.current_user_outlet_id()
    and public.current_user_role() in ('outlet_manager', 'collector')
    and exists (
      select 1 from public.distributor_outlets link
      where link.distributor_id = sale.distributor_id
        and link.external_outlet_id = sale.external_outlet_id
    )
  )
  or (
    sale.pickup_location_id = public.current_user_pickup_location_id()
    and public.current_user_role() = 'factory_outlet_manager'
  );

create view public.role_factory_sale_quantities
with (security_barrier = true)
as
select
  line.id,
  line.sale_id,
  line.product_id,
  line.quantity
from public.factory_sale_lines line
join public.factory_sales sale on sale.id = line.sale_id
where public.current_user_role() in (
    'admin', 'accountant', 'production_manager'
  )
  or sale.distributor_id = public.current_user_distributor_id()
  or (
    sale.external_outlet_id = public.current_user_outlet_id()
    and public.current_user_role() in ('outlet_manager', 'collector')
    and exists (
      select 1 from public.distributor_outlets link
      where link.distributor_id = sale.distributor_id
        and link.external_outlet_id = sale.external_outlet_id
    )
  )
  or (
    sale.pickup_location_id = public.current_user_pickup_location_id()
    and public.current_user_role() = 'factory_outlet_manager'
  );

create view public.role_financial_sale_lines
with (security_barrier = true)
as
select
  line.id,
  line.sale_id,
  line.product_id,
  line.policy_version_id,
  line.quantity,
  line.unit_price,
  line.line_total
from public.factory_sale_lines line
join public.factory_sales sale on sale.id = line.sale_id
where public.current_user_role() in ('admin', 'accountant')
  or sale.distributor_id = public.current_user_distributor_id()
  or (
    sale.external_outlet_id = public.current_user_outlet_id()
    and public.current_user_role() in ('outlet_manager', 'collector')
    and exists (
      select 1 from public.distributor_outlets link
      where link.distributor_id = sale.distributor_id
        and link.external_outlet_id = sale.external_outlet_id
    )
  );

create view public.role_outlet_purchases
with (security_barrier = true)
as
select
  purchase.id,
  purchase.external_outlet_id,
  purchase.purchased_at,
  purchase.created_by,
  purchase.created_at
from public.outlet_purchases purchase
where public.current_user_role() in ('admin', 'accountant')
  or (
    purchase.external_outlet_id = public.current_user_outlet_id()
    and public.current_user_role() = 'outlet_manager'
  );

create view public.role_financial_outlet_purchase_lines
with (security_barrier = true)
as
select
  line.id,
  line.purchase_id,
  line.product_id,
  line.policy_version_id,
  line.quantity,
  line.unit_price,
  line.line_total
from public.outlet_purchase_lines line
join public.outlet_purchases purchase on purchase.id = line.purchase_id
where public.current_user_role() in ('admin', 'accountant')
  or (
    purchase.external_outlet_id = public.current_user_outlet_id()
    and public.current_user_role() = 'outlet_manager'
  );

create view public.role_financial_outlet_payments
with (security_barrier = true)
as
select
  payment.id,
  payment.external_outlet_id,
  payment.amount,
  payment.paid_at,
  payment.created_by,
  payment.created_at
from public.outlet_payments payment
where public.current_user_role() in ('admin', 'accountant')
  or (
    payment.external_outlet_id = public.current_user_outlet_id()
    and public.current_user_role() = 'outlet_manager'
  );

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
    public.current_user_role() = 'admin'
    or (
      public.current_user_role() = 'distributor'
      and public.current_user_distributor_id() = p_distributor_id
    )
  ) then
    raise exception 'The user is not authorized to place this order';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) = 0 then
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
    raise exception 'The distributor is inactive or does not exist';
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

create or replace function public.record_distributor_payment(
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
    public.current_user_role() in ('admin', 'accountant')
    or (
      public.current_user_role() = 'collector'
      and public.current_user_outlet_id() = p_external_outlet_id
    )
  ) then
    raise exception 'The user is not authorized to record this payment';
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

revoke all on public.user_profiles from authenticated;
grant select (user_id, role, distributor_id, external_outlet_id,
  pickup_location_id, created_at, updated_at)
  on public.user_profiles to authenticated;

revoke all on public.user_profiles from public, anon;
revoke all on public.factory_sale_lines from authenticated;
revoke all on public.factory_sale_lines from public, anon;
revoke all on public.factory_sales from authenticated;
revoke all on public.factory_sales from public, anon;
revoke all on public.outlet_purchases, public.outlet_purchase_lines,
  public.outlet_payments from authenticated, public, anon;
grant select (id, distributor_id, pickup_location_id, external_outlet_id,
  sold_at, created_by, created_at) on public.factory_sales to authenticated;
grant select on public.role_factory_sales,
  public.role_factory_sale_quantities,
  public.role_outlet_purchases to authenticated;
grant select on public.role_financial_sale_lines to authenticated;
grant select on public.role_financial_outlet_purchase_lines,
  public.role_financial_outlet_payments to authenticated;

grant select on public.outlet_account_balances,
  public.distributor_account_balances to authenticated;

grant select on public.pricing_policies,
  public.price_policy_versions, public.price_policy_entries to authenticated;

grant execute on function public.current_user_pickup_location_id()
  to authenticated;
grant execute on function public.can_view_financials() to authenticated;
grant execute on function public.assign_user_role_v2(
  text, text, uuid, uuid, uuid
) to authenticated;
grant execute on function public.update_user_role_v2(
  uuid, text, uuid, uuid, uuid
) to authenticated;
grant execute on function public.admin_list_users_v2() to authenticated;
grant execute on function public.create_factory_sale(
  uuid, uuid, uuid, jsonb, timestamptz
) to authenticated;
grant execute on function public.record_distributor_payment(
  uuid, uuid, numeric, timestamptz
) to authenticated;
revoke all on function public.assign_user_role(text, text, uuid, uuid)
  from authenticated, public;
revoke all on function public.update_user_role(uuid, text, uuid, uuid)
  from authenticated, public;

revoke all on function public.assign_user_role_v2(
  text, text, uuid, uuid, uuid
) from public;
revoke all on function public.update_user_role_v2(
  uuid, text, uuid, uuid, uuid
) from public;
revoke all on function public.admin_list_users_v2() from public;
revoke all on function public.current_user_pickup_location_id() from public;
revoke all on function public.can_view_financials() from public;
revoke all on function public.create_factory_sale(
  uuid, uuid, uuid, jsonb, timestamptz
) from public;
