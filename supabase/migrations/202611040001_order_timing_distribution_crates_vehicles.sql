create table public.operational_settings (
  id boolean primary key default true check (id),
  order_lead_days integer not null default 2
    check (order_lead_days in (1, 2)),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

insert into public.operational_settings (id, order_lead_days)
values (true, 2)
on conflict (id) do nothing;

alter table public.operational_settings enable row level security;
create policy "administrators read operational settings"
  on public.operational_settings for select to authenticated
  using (public.is_pricing_admin());
revoke all on public.operational_settings from public, anon, authenticated;
grant select on public.operational_settings to authenticated;

create function public.get_order_lead_days()
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select order_lead_days from public.operational_settings where id;
$$;

create function public.set_order_lead_days(p_days integer)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_pricing_admin() then
    raise exception 'Only an administrator can change order timing';
  end if;
  if p_days is null or p_days not in (1, 2) then
    raise exception 'Order lead time must be one or two days';
  end if;
  update public.operational_settings
  set order_lead_days = p_days, updated_by = auth.uid(), updated_at = now()
  where id;
end;
$$;

create table public.sales_order_schedule_changes (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.sales_orders(id),
  previous_date date not null,
  new_date date not null,
  reason text not null check (length(trim(reason)) between 1 and 1000),
  changed_by uuid not null references auth.users(id),
  changed_at timestamptz not null default now(),
  check (previous_date <> new_date)
);

alter table public.sales_orders
  add column if not exists lead_days_snapshot integer not null default 2
    check (lead_days_snapshot in (1, 2)),
  add column if not exists decision_by uuid references auth.users(id),
  add column if not exists decision_at timestamptz;

create function public.snapshot_sales_order_settings()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.lead_days_snapshot := public.get_order_lead_days();
  return new;
end;
$$;

create trigger sales_orders_settings_snapshot
before insert on public.sales_orders
for each row execute function public.snapshot_sales_order_settings();

create function public.create_sales_order(
  p_pickup_location_id uuid,
  p_external_outlet_id uuid,
  p_lines jsonb
)
returns uuid
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.create_sales_order(
    p_pickup_location_id,
    p_external_outlet_id,
    current_date + public.get_order_lead_days(),
    p_lines
  );
$$;

create function public.reschedule_sales_order(
  p_order_id uuid,
  p_requested_for date,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  order_row public.sales_orders%rowtype;
begin
  if auth.uid() is null or not public.is_pricing_admin() then
    raise exception 'Only an administrator can reschedule an order';
  end if;
  if p_requested_for is null or nullif(trim(p_reason), '') is null then
    raise exception 'A new date and a reason are required';
  end if;
  select * into order_row
  from public.sales_orders
  where id = p_order_id
  for update;
  if not found
    or order_row.status in ('delivered', 'closed', 'cancelled', 'rejected')
    or order_row.production_batch_id is not null then
    raise exception 'Order was not found or can no longer be rescheduled';
  end if;
  if order_row.requested_for = p_requested_for then
    raise exception 'The new date matches the current date';
  end if;
  insert into public.sales_order_schedule_changes (
    order_id, previous_date, new_date, reason, changed_by
  ) values (
    p_order_id, order_row.requested_for, p_requested_for,
    trim(p_reason), auth.uid()
  );
  update public.sales_orders
  set requested_for = p_requested_for, updated_at = now()
  where id = p_order_id;
end;
$$;

create or replace function public.review_sales_order(
  p_order_id uuid,
  p_decision text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not (
    public.is_pricing_admin()
    or (public.current_user_role() = 'accountant' and p_decision = 'in_review')
  ) then
    raise exception 'The user is not authorized to review orders';
  end if;
  if p_decision not in ('in_review', 'approved', 'rejected', 'cancelled') then
    raise exception 'Unsupported order decision';
  end if;
  if p_decision in ('rejected', 'cancelled')
    and nullif(trim(p_reason), '') is null then
    raise exception 'A reason is required to reject or cancel an order';
  end if;
  update public.sales_orders
  set status = p_decision,
      status_reason = nullif(trim(p_reason), ''),
      decision_by = case when p_decision = 'in_review' then decision_by else auth.uid() end,
      decision_at = case when p_decision = 'in_review' then decision_at else now() end,
      updated_at = now()
  where id = p_order_id
    and (
      (p_decision = 'in_review' and status = 'submitted')
      or (p_decision in ('approved', 'rejected')
        and status in ('submitted', 'in_review'))
      or (p_decision = 'cancelled'
        and status in ('submitted', 'in_review', 'approved'))
    );
  if not found then
    raise exception 'Order was not found or cannot transition to the requested state';
  end if;
end;
$$;

alter table public.production_batches
  add column if not exists distribution_approved boolean not null default false,
  add column if not exists distribution_approved_by uuid references auth.users(id),
  add column if not exists distribution_approved_at timestamptz;

alter table public.production_allocations
  add column if not exists calculated_quantity integer not null default 0
    check (calculated_quantity >= 0);

update public.production_allocations
set calculated_quantity = allocated_quantity
where calculated_quantity = 0 and allocated_quantity > 0;

create table public.production_allocation_audit (
  id uuid primary key default gen_random_uuid(),
  batch_line_id uuid not null references public.production_batch_lines(id),
  order_line_id uuid not null references public.sales_order_lines(id),
  calculated_quantity integer not null check (calculated_quantity >= 0),
  previous_quantity integer not null check (previous_quantity >= 0),
  new_quantity integer not null check (new_quantity >= 0),
  reason text not null check (length(trim(reason)) between 1 and 1000),
  changed_by uuid not null references auth.users(id),
  changed_at timestamptz not null default now()
);

create function public.audit_initial_production_allocation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.production_allocations
  set calculated_quantity = new.allocated_quantity
  where order_line_id = new.order_line_id;
  insert into public.production_allocation_audit (
    batch_line_id, order_line_id, calculated_quantity,
    previous_quantity, new_quantity, reason, changed_by
  ) values (
    new.batch_line_id, new.order_line_id, new.allocated_quantity,
    new.allocated_quantity, new.allocated_quantity,
    'التوزيع النسبي الأولي', auth.uid()
  );
  return new;
end;
$$;

create trigger production_allocation_initial_audit
after insert on public.production_allocations
for each row execute function public.audit_initial_production_allocation();

create or replace function public.revise_production_distribution(
  p_batch_id uuid,
  p_product_id uuid,
  p_allocations jsonb,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  batch_row public.production_batches%rowtype;
  batch_line public.production_batch_lines%rowtype;
  item record;
  allocation_count integer;
  allocation_sum bigint;
begin
  if auth.uid() is null or not public.is_pricing_admin() then
    raise exception 'Only an administrator can revise production distribution';
  end if;
  if p_allocations is null or jsonb_typeof(p_allocations) is distinct from 'array'
    or jsonb_array_length(p_allocations) = 0
    or nullif(trim(p_reason), '') is null then
    raise exception 'Allocations and an adjustment reason are required';
  end if;
  select * into batch_row
  from public.production_batches
  where id = p_batch_id
  for update;
  if not found or batch_row.status <> 'ready' then
    raise exception 'Production must be finalized before editing distribution';
  end if;
  select * into batch_line
  from public.production_batch_lines
  where batch_id = p_batch_id and product_id = p_product_id
  for update;
  if not found then
    raise exception 'Product was not produced in this batch';
  end if;
  perform pg_advisory_xact_lock(hashtext(p_batch_id::text || ':' || p_product_id::text));
  if exists (
    select 1
    from jsonb_to_recordset(p_allocations) as input_row(
      order_line_id uuid, allocated_quantity integer
    )
    group by input_row.order_line_id having count(*) > 1
  ) then
    raise exception 'An order line may appear only once in a distribution edit';
  end if;
  select count(*), coalesce(sum(input_row.allocated_quantity), 0)
  into allocation_count, allocation_sum
  from jsonb_to_recordset(p_allocations) as input_row(
    order_line_id uuid, allocated_quantity integer
  )
  where input_row.order_line_id is not null
    and input_row.allocated_quantity >= 0;
  if allocation_count <> jsonb_array_length(p_allocations)
    or allocation_sum <> batch_line.produced_quantity then
    raise exception 'Adjusted quantities must be nonnegative and equal available production';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_allocations) as input_row(
      order_line_id uuid, allocated_quantity integer
    )
    where input_row.order_line_id is null
      or input_row.allocated_quantity is null
      or input_row.allocated_quantity < 0
  ) or allocation_count <> (
    select count(*)
    from public.production_allocations allocation
    join public.production_batch_lines produced
      on produced.id = allocation.batch_line_id
    join public.sales_order_lines order_line
      on order_line.id = allocation.order_line_id
    join public.sales_orders orders on orders.id = order_line.order_id
    where produced.id = batch_line.id
      and order_line.product_id = p_product_id
      and orders.production_batch_id = p_batch_id
  ) or exists (
    select 1
    from public.production_allocations allocation
    join public.production_batch_lines produced
      on produced.id = allocation.batch_line_id
    join public.sales_order_lines order_line
      on order_line.id = allocation.order_line_id
    join public.sales_orders orders on orders.id = order_line.order_id
    where produced.id = batch_line.id
      and order_line.product_id = p_product_id
      and orders.production_batch_id = p_batch_id
      and not exists (
        select 1 from jsonb_to_recordset(p_allocations) as input_row(
          order_line_id uuid, allocated_quantity integer
        ) where input_row.order_line_id = allocation.order_line_id
      )
  ) or exists (
    select 1
    from jsonb_to_recordset(p_allocations) as input_row(
      order_line_id uuid, allocated_quantity integer
    )
    where not exists (
      select 1
      from public.production_allocations allocation
      join public.production_batch_lines produced
        on produced.id = allocation.batch_line_id
      join public.sales_order_lines order_line
        on order_line.id = allocation.order_line_id
      join public.sales_orders orders on orders.id = order_line.order_id
      where allocation.order_line_id = input_row.order_line_id
        and produced.id = batch_line.id
        and orders.production_batch_id = p_batch_id
        and order_line.product_id = p_product_id
    )
  ) then
    raise exception 'Every and only assigned order lines for this product must be included';
  end if;

  for item in
    select requested.order_line_id, requested.allocated_quantity,
      allocation.allocated_quantity as previous_quantity,
      allocation.calculated_quantity
    from jsonb_to_recordset(p_allocations) as requested(
      order_line_id uuid, allocated_quantity integer
    )
    join public.production_allocations allocation
      on allocation.order_line_id = requested.order_line_id
  loop
    if item.allocated_quantity < coalesce((
      select sum(delivery_line.quantity)
      from public.order_delivery_lines delivery_line
      where delivery_line.order_line_id = item.order_line_id
    ), 0) then
      raise exception 'An allocation cannot be lower than the quantity already delivered';
    end if;
    if item.allocated_quantity <> item.previous_quantity then
      update public.production_allocations
      set allocated_quantity = item.allocated_quantity
      where order_line_id = item.order_line_id;
      insert into public.production_allocation_audit (
        batch_line_id, order_line_id, calculated_quantity,
        previous_quantity, new_quantity, reason, changed_by
      ) values (
        batch_line.id, item.order_line_id, item.calculated_quantity,
        item.previous_quantity, item.allocated_quantity, trim(p_reason), auth.uid()
      );
    end if;
  end loop;
  if batch_row.distribution_approved then
    update public.production_batches
    set distribution_approved = false,
        distribution_approved_by = null,
        distribution_approved_at = null
    where id = p_batch_id;
  end if;
end;
$$;

create function public.approve_production_distribution(p_batch_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not public.is_pricing_admin() then
    raise exception 'Only an administrator can approve production distribution';
  end if;
  perform 1 from public.production_batches where id = p_batch_id for update;
  if not found or not exists (
    select 1 from public.production_batches
    where id = p_batch_id and status = 'ready'
  ) then
    raise exception 'Production batch is not ready for distribution approval';
  end if;
  if exists (
    select 1
    from public.production_batch_lines produced
    left join (
      select allocation.batch_line_id, sum(allocation.allocated_quantity) as allocated
      from public.production_allocations allocation
      group by allocation.batch_line_id
    ) totals on totals.batch_line_id = produced.id
    where produced.batch_id = p_batch_id
      and coalesce(totals.allocated, 0) <> produced.produced_quantity
  ) then
    raise exception 'Distribution must equal production available for every product';
  end if;
  update public.production_batches
  set distribution_approved = true,
      distribution_approved_by = auth.uid(),
      distribution_approved_at = now()
  where id = p_batch_id;
end;
$$;

alter table public.products
  add column if not exists crate_capacity integer not null default 75
    check (crate_capacity > 0);

alter table public.order_delivery_lines
  add column if not exists crate_count integer not null default 0
    check (crate_count >= 0),
  add column if not exists crate_capacity_snapshot integer not null default 75
    check (crate_capacity_snapshot > 0);

create function public.snapshot_delivery_crate_capacity()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  product_capacity integer;
begin
  select product.crate_capacity into product_capacity
  from public.sales_order_lines order_line
  join public.products product on product.id = order_line.product_id
  where order_line.id = new.order_line_id;
  if product_capacity is null then
    raise exception 'Product crate capacity is not configured';
  end if;
  new.crate_capacity_snapshot := product_capacity;
  new.crate_count := ceil(new.quantity::numeric / product_capacity)::integer;
  return new;
end;
$$;

create trigger order_delivery_crate_snapshot
before insert on public.order_delivery_lines
for each row execute function public.snapshot_delivery_crate_capacity();

alter table public.crate_movements
  add column if not exists product_id uuid references public.products(id),
  add column if not exists sales_unit_quantity integer
    check (sales_unit_quantity is null or sales_unit_quantity > 0),
  add column if not exists product_capacity_snapshot integer
    check (product_capacity_snapshot is null or product_capacity_snapshot > 0),
  add column if not exists crate_type_capacity_snapshot integer
    check (crate_type_capacity_snapshot is null or crate_type_capacity_snapshot > 0);

alter table public.distributor_outlets
  add column if not exists vehicle_group text not null default 'shared'
    check (vehicle_group in ('vehicle_1', 'vehicle_2', 'shared'));

alter table public.external_outlets
  add column if not exists outlet_type text not null default 'external'
    check (outlet_type in ('external', 'factory_pickup')),
  add column if not exists allowed_roles text[] not null
    default array['outlet_manager', 'collector']::text[],
  add constraint external_outlets_allowed_roles_check
    check (
      cardinality(allowed_roles) > 0
      and allowed_roles <@ array['outlet_manager', 'collector']::text[]
    );

create or replace function public.current_user_outlet_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select profile.external_outlet_id
  from public.user_profiles profile
  join public.external_outlets outlet
    on outlet.id = profile.external_outlet_id
  where profile.user_id = auth.uid()
    and profile.role = any(outlet.allowed_roles)
    and profile.role in ('outlet_manager', 'collector')
    and outlet.is_active;
$$;

create function public.validate_outlet_role_assignment()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.role in ('outlet_manager', 'collector')
    and not exists (
      select 1 from public.external_outlets outlet
      where outlet.id = new.external_outlet_id
        and outlet.is_active
        and new.role = any(outlet.allowed_roles)
    ) then
    raise exception 'The selected role is disabled or the outlet is inactive';
  end if;
  return new;
end;
$$;

create trigger user_profiles_outlet_role_guard
before insert or update of role, external_outlet_id on public.user_profiles
for each row execute function public.validate_outlet_role_assignment();

create function public.protect_outlet_history()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  raise exception 'Outlets cannot be deleted; deactivate them to preserve history';
end;
$$;

create trigger external_outlets_no_delete
before delete on public.external_outlets
for each row execute function public.protect_outlet_history();

create function public.save_distributor_assignments(
  p_distributor_id uuid,
  p_name text,
  p_customer_type_id uuid,
  p_is_active boolean,
  p_outlet_assignments jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  saved_distributor_id uuid;
  assignment record;
begin
  if auth.uid() is null or not public.is_pricing_admin() then
    raise exception 'Only an administrator can manage distributor assignments';
  end if;
  if p_outlet_assignments is null
    or jsonb_typeof(p_outlet_assignments) is distinct from 'array' then
    raise exception 'Outlet assignments must be a JSON array';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_outlet_assignments) as item(
      external_outlet_id uuid, vehicle_group text
    )
    where item.external_outlet_id is null
      or coalesce(item.vehicle_group, '') not in ('vehicle_1', 'vehicle_2', 'shared')
  ) then
    raise exception 'Outlet assignment groups are invalid';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_outlet_assignments) as item(
      external_outlet_id uuid, vehicle_group text
    )
    group by item.external_outlet_id
    having count(*) > 1
  ) then
    raise exception 'An outlet can only be assigned once per distributor';
  end if;
  saved_distributor_id := public.save_distributor(
    p_distributor_id, p_name, p_customer_type_id, p_is_active,
    array(
      select item.external_outlet_id
      from jsonb_to_recordset(p_outlet_assignments) as item(
        external_outlet_id uuid, vehicle_group text
      )
    )
  );
  for assignment in
    select * from jsonb_to_recordset(p_outlet_assignments) as item(
      external_outlet_id uuid, vehicle_group text
    )
  loop
    update public.distributor_outlets
    set vehicle_group = assignment.vehicle_group
    where distributor_id = saved_distributor_id
      and external_outlet_id = assignment.external_outlet_id;
  end loop;
  return saved_distributor_id;
end;
$$;

create view public.role_order_vehicle_groups
with (security_barrier = true)
as
select orders.id as order_id, link.vehicle_group
from public.sales_orders orders
left join public.distributor_outlets link
  on link.distributor_id = orders.distributor_id
  and link.external_outlet_id = orders.external_outlet_id
where public.current_user_role() in ('admin', 'accountant')
  or (
    public.current_user_role() = 'outlet_manager'
    and orders.external_outlet_id = public.current_user_outlet_id()
  );

create view public.role_production_allocation_audit
with (security_barrier = true)
as
select audit.id, audit.batch_line_id, audit.order_line_id,
  audit.calculated_quantity, audit.previous_quantity, audit.new_quantity,
  audit.reason, audit.changed_by, audit.changed_at
from public.production_allocation_audit audit
join public.production_batch_lines batch_line
  on batch_line.id = audit.batch_line_id
join public.production_batches batch on batch.id = batch_line.batch_id
where public.current_user_role() = 'admin';

create or replace view public.role_order_quantities
with (security_barrier = true)
as
select order_line.id, order_line.order_id, order_line.product_id,
  order_line.requested_quantity,
  coalesce(allocation.allocated_quantity, 0) as allocated_quantity,
  coalesce(delivered.quantity, 0)::integer as delivered_quantity,
  coalesce(delivery_crates.crate_count, 0)::integer as delivered_crates,
  delivery_crates.crate_capacity_snapshots,
  coalesce(allocation.calculated_quantity, 0) as calculated_quantity
from public.sales_order_lines order_line
join public.sales_orders orders on orders.id = order_line.order_id
left join public.production_allocations allocation
  on allocation.order_line_id = order_line.id
left join (
  select delivery_line.order_line_id,
    sum(delivery_line.quantity)::integer as quantity
  from public.order_delivery_lines delivery_line
  group by delivery_line.order_line_id
) delivered on delivered.order_line_id = order_line.id
left join (
  select delivery_line.order_line_id,
    sum(delivery_line.crate_count)::integer as crate_count,
    string_agg(
      distinct delivery_line.crate_capacity_snapshot::text,
      ', ' order by delivery_line.crate_capacity_snapshot::text
    ) as crate_capacity_snapshots
  from public.order_delivery_lines delivery_line
  group by delivery_line.order_line_id
) delivery_crates on delivery_crates.order_line_id = order_line.id
where public.current_user_role() in (
    'admin', 'accountant', 'production_manager'
  )
  or orders.distributor_id = public.current_user_distributor_id()
  or (
    orders.external_outlet_id = public.current_user_outlet_id()
    and public.current_user_role() in ('outlet_manager', 'collector')
  )
  or (
    orders.pickup_location_id = public.current_user_pickup_location_id()
    and public.current_user_role() = 'factory_outlet_manager'
  );

create or replace view public.role_production_batches
with (security_barrier = true)
as
select batch.id, batch.pickup_location_id, batch.scheduled_for, batch.status,
  batch.created_by, batch.finalized_by, batch.finalized_at, batch.created_at,
  batch.distribution_approved, batch.distribution_approved_by,
  batch.distribution_approved_at
from public.production_batches batch
where public.current_user_role() in (
    'admin', 'accountant', 'production_manager'
  )
  or (
    batch.pickup_location_id = public.current_user_pickup_location_id()
    and public.current_user_role() = 'factory_outlet_manager'
  );

create view public.role_outlet_distributors
with (security_barrier = true)
as
select link.external_outlet_id, link.distributor_id,
  distributor.name as distributor_name, link.vehicle_group
from public.distributor_outlets link
join public.distributors distributor on distributor.id = link.distributor_id
where link.external_outlet_id = public.current_user_outlet_id()
  and public.current_user_role() in ('outlet_manager', 'collector');

create or replace view public.role_orders
with (security_barrier = true)
as
select orders.id, orders.distributor_id, orders.pickup_location_id,
  orders.external_outlet_id, orders.requested_for, orders.status,
  orders.status_reason, orders.production_batch_id, orders.submitted_at,
  orders.created_by, orders.created_at, orders.lead_days_snapshot,
  orders.decision_by, orders.decision_at, link.vehicle_group
from public.sales_orders orders
left join public.distributor_outlets link
  on link.distributor_id = orders.distributor_id
  and link.external_outlet_id = orders.external_outlet_id
where public.current_user_role() in (
    'admin', 'accountant', 'production_manager'
  )
  or orders.distributor_id = public.current_user_distributor_id()
  or (
    orders.external_outlet_id = public.current_user_outlet_id()
    and public.current_user_role() in ('outlet_manager', 'collector')
  )
  or (
    orders.pickup_location_id = public.current_user_pickup_location_id()
    and public.current_user_role() = 'factory_outlet_manager'
  );

revoke all on public.operational_settings, public.sales_order_schedule_changes,
  public.production_allocation_audit from public, anon, authenticated;
grant select on public.role_orders, public.role_order_quantities,
  public.role_order_vehicle_groups, public.role_production_allocation_audit,
  public.role_outlet_distributors
  to authenticated;

revoke all on function public.get_order_lead_days(),
  public.create_sales_order(uuid, uuid, jsonb),
  public.set_order_lead_days(integer),
  public.reschedule_sales_order(uuid, date, text),
  public.revise_production_distribution(uuid, uuid, jsonb, text),
  public.approve_production_distribution(uuid),
  public.save_distributor_assignments(uuid, text, uuid, boolean, jsonb)
  from public, anon;
grant execute on function public.get_order_lead_days(),
  public.create_sales_order(uuid, uuid, jsonb),
  public.set_order_lead_days(integer),
  public.reschedule_sales_order(uuid, date, text),
  public.revise_production_distribution(uuid, uuid, jsonb, text),
  public.approve_production_distribution(uuid),
  public.save_distributor_assignments(uuid, text, uuid, boolean, jsonb)
  to authenticated;

create or replace function public.record_order_delivery(
  p_order_id uuid,
  p_idempotency_key text,
  p_lines jsonb,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  order_row public.sales_orders%rowtype;
  delivery_id uuid;
  line record;
  remaining_quantity integer;
begin
  if auth.uid() is null or not (
    public.is_pricing_admin()
    or public.current_user_role() = 'accountant'
    or (
      public.current_user_role() = 'factory_outlet_manager'
      and public.current_user_pickup_location_id() is not distinct from
        (select orders.pickup_location_id from public.sales_orders orders
         where orders.id = p_order_id)
    )
    or (
      public.current_user_role() = 'outlet_manager'
      and public.current_user_outlet_id() is not distinct from
        (select orders.external_outlet_id from public.sales_orders orders
         where orders.id = p_order_id)
    )
  ) then
    raise exception 'The user is not authorized to deliver this order';
  end if;
  if nullif(trim(p_idempotency_key), '') is null
    or length(p_idempotency_key) > 120
    or p_lines is null or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) = 0 then
    raise exception 'A unique delivery key and at least one delivery line are required';
  end if;
  select * into order_row
  from public.sales_orders
  where id = p_order_id
  for update;
  if not found or order_row.status not in ('ready', 'partially_delivered')
    or not exists (
      select 1 from public.production_batches batch
      where batch.id = order_row.production_batch_id
        and batch.distribution_approved
    ) then
    raise exception 'Order distribution is not approved for delivery';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_lines) as item(order_line_id uuid, quantity integer)
    group by order_line_id having count(*) > 1
  ) then
    raise exception 'A delivery line may appear only once';
  end if;
  insert into public.order_deliveries (
    order_id, idempotency_key, delivered_by, note
  ) values (
    p_order_id, trim(p_idempotency_key), auth.uid(), nullif(trim(p_note), '')
  ) returning id into delivery_id;

  for line in
    select * from jsonb_to_recordset(p_lines) as item(
      order_line_id uuid, quantity integer
    )
  loop
    if line.order_line_id is null or line.quantity is null or line.quantity <= 0 then
      raise exception 'Every delivery line needs an order line and positive quantity';
    end if;
    select allocation.allocated_quantity - coalesce(sum(delivered.quantity), 0)
    into remaining_quantity
    from public.production_allocations allocation
    left join public.order_delivery_lines delivered
      on delivered.order_line_id = allocation.order_line_id
    where allocation.order_line_id = line.order_line_id
      and exists (
        select 1 from public.sales_order_lines order_line
        where order_line.id = line.order_line_id
          and order_line.order_id = p_order_id
      )
    group by allocation.allocated_quantity;
    if remaining_quantity is null or line.quantity > remaining_quantity then
      raise exception 'Delivery quantity exceeds the order allocation';
    end if;
    update public.inventory_balances
    set quantity = quantity - line.quantity, updated_at = now()
    where pickup_location_id = order_row.pickup_location_id
      and product_id = (
        select order_line.product_id from public.sales_order_lines order_line
        where order_line.id = line.order_line_id
      )
      and quantity >= line.quantity;
    if not found then
      raise exception 'Insufficient available stock for delivery';
    end if;
    insert into public.order_delivery_lines (
      delivery_id, order_line_id, quantity
    ) values (delivery_id, line.order_line_id, line.quantity);
    insert into public.inventory_movements (
      pickup_location_id, product_id, quantity_delta,
      movement_type, reference_id, note, created_by
    ) values (
      order_row.pickup_location_id,
      (select order_line.product_id from public.sales_order_lines order_line
       where order_line.id = line.order_line_id),
      -line.quantity, 'delivery', delivery_id,
      'تسليم طلب للموزع', auth.uid()
    );
  end loop;
  if not exists (
    select 1
    from public.production_allocations allocation
    join public.sales_order_lines order_line
      on order_line.id = allocation.order_line_id
    left join (
      select delivery_line.order_line_id, sum(delivery_line.quantity) as quantity
      from public.order_delivery_lines delivery_line
      join public.order_deliveries delivery
        on delivery.id = delivery_line.delivery_id
      where delivery.order_id = p_order_id
      group by delivery_line.order_line_id
    ) delivered on delivered.order_line_id = allocation.order_line_id
    where order_line.order_id = p_order_id
      and coalesce(delivered.quantity, 0) < allocation.allocated_quantity
  ) then
    update public.sales_orders set status = 'delivered', updated_at = now()
    where id = p_order_id;
  else
    update public.sales_orders
    set status = 'partially_delivered', updated_at = now()
    where id = p_order_id;
  end if;
  return delivery_id;
end;
$$;

revoke all on function public.snapshot_sales_order_settings(),
  public.audit_initial_production_allocation(),
  public.snapshot_delivery_crate_capacity(),
  public.validate_outlet_role_assignment(),
  public.protect_outlet_history() from public, anon, authenticated;
revoke all on function public.record_order_delivery(uuid, text, jsonb, text)
  from public, anon;
grant execute on function public.record_order_delivery(uuid, text, jsonb, text)
  to authenticated;
