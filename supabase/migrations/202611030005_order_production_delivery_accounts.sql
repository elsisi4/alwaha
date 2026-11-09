create table public.sales_orders (
  id uuid primary key default gen_random_uuid(),
  distributor_id uuid not null references public.distributors(id),
  pickup_location_id uuid not null references public.pickup_locations(id),
  external_outlet_id uuid not null references public.external_outlets(id),
  requested_for date not null,
  status text not null default 'draft' check (
    status in (
      'draft', 'submitted', 'in_review', 'approved', 'in_production',
      'ready', 'partially_delivered', 'delivered', 'closed', 'cancelled',
      'rejected'
    )
  ),
  status_reason text,
  production_batch_id uuid,
  submitted_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(coalesce(status_reason, '')) <= 1000)
);

create index sales_orders_pickup_date_idx
  on public.sales_orders(pickup_location_id, requested_for, status);
create index sales_orders_distributor_created_idx
  on public.sales_orders(distributor_id, created_at desc);
create function public.factory_manager_can_view_distributor(
  p_distributor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.distributor_outlets link
    join public.external_outlets outlet
      on outlet.id = link.external_outlet_id
    where link.distributor_id = p_distributor_id
      and outlet.pickup_location_id =
        public.current_user_pickup_location_id()
  );
$$;

create function public.factory_manager_can_view_outlet(
  p_external_outlet_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.external_outlets outlet
    where outlet.id = p_external_outlet_id
      and outlet.pickup_location_id =
        public.current_user_pickup_location_id()
  );
$$;

create policy "factory managers read operational products"
  on public.products for select to authenticated
  using (
    public.current_user_role() = 'factory_outlet_manager'
    and is_active
  );
create policy "factory managers read assigned distributors"
  on public.distributors for select to authenticated
  using (
    public.current_user_role() = 'factory_outlet_manager'
    and public.factory_manager_can_view_distributor(id)
  );
create policy "factory managers read assigned outlets"
  on public.external_outlets for select to authenticated
  using (
    public.current_user_role() = 'factory_outlet_manager'
    and pickup_location_id = public.current_user_pickup_location_id()
  );
create policy "factory managers read assigned distributor outlets"
  on public.distributor_outlets for select to authenticated
  using (
    public.current_user_role() = 'factory_outlet_manager'
    and public.factory_manager_can_view_outlet(external_outlet_id)
  );

create table public.sales_order_lines (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.sales_orders(id),
  product_id uuid not null references public.products(id),
  requested_quantity integer not null check (requested_quantity > 0),
  policy_version_id uuid not null references public.price_policy_versions(id),
  unit_price numeric(14, 2) not null check (unit_price >= 0),
  created_at timestamptz not null default now(),
  unique (order_id, product_id)
);

create table public.production_batches (
  id uuid primary key default gen_random_uuid(),
  pickup_location_id uuid not null references public.pickup_locations(id),
  scheduled_for date not null,
  status text not null default 'in_production' check (
    status in ('in_production', 'ready', 'cancelled')
  ),
  created_by uuid not null references auth.users(id),
  finalized_by uuid references auth.users(id),
  finalized_at timestamptz,
  created_at timestamptz not null default now(),
  check ((status = 'ready') = (finalized_at is not null))
);

alter table public.sales_orders
  add constraint sales_orders_production_batch_fk
  foreign key (production_batch_id) references public.production_batches(id);

create table public.production_batch_lines (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.production_batches(id),
  product_id uuid not null references public.products(id),
  produced_quantity integer not null check (produced_quantity >= 0),
  rejected_quantity integer not null default 0 check (rejected_quantity >= 0),
  variance_reason text,
  created_at timestamptz not null default now(),
  unique (batch_id, product_id),
  check (produced_quantity + rejected_quantity > 0),
  check (length(coalesce(variance_reason, '')) <= 1000)
);

create table public.production_allocations (
  order_line_id uuid primary key references public.sales_order_lines(id),
  batch_line_id uuid not null references public.production_batch_lines(id),
  allocated_quantity integer not null check (allocated_quantity >= 0),
  created_at timestamptz not null default now()
);

create table public.inventory_balances (
  pickup_location_id uuid not null references public.pickup_locations(id),
  product_id uuid not null references public.products(id),
  quantity integer not null default 0 check (quantity >= 0),
  updated_at timestamptz not null default now(),
  primary key (pickup_location_id, product_id)
);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  pickup_location_id uuid not null references public.pickup_locations(id),
  product_id uuid not null references public.products(id),
  quantity_delta integer not null check (quantity_delta <> 0),
  movement_type text not null check (
    movement_type in ('production', 'delivery', 'transfer_in', 'transfer_out', 'adjustment')
  ),
  reference_id uuid,
  note text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  check (length(coalesce(note, '')) <= 1000)
);

create index inventory_movements_location_product_idx
  on public.inventory_movements(pickup_location_id, product_id, created_at desc);

create table public.order_deliveries (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.sales_orders(id),
  idempotency_key text not null unique,
  delivered_at timestamptz not null default now(),
  delivered_by uuid not null references auth.users(id),
  note text,
  check (length(trim(idempotency_key)) between 1 and 120),
  check (length(coalesce(note, '')) <= 1000)
);

create table public.order_delivery_lines (
  delivery_id uuid not null references public.order_deliveries(id),
  order_line_id uuid not null references public.sales_order_lines(id),
  quantity integer not null check (quantity > 0),
  primary key (delivery_id, order_line_id)
);

create table public.return_requests (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.sales_orders(id),
  reason text not null check (length(trim(reason)) between 1 and 1000),
  status text not null default 'pending' check (
    status in ('pending', 'approved', 'rejected')
  ),
  resolution text check (
    resolution is null or resolution in ('credit', 'replacement', 'destroy')
  ),
  decision_reason text,
  requested_by uuid not null references auth.users(id),
  decided_by uuid references auth.users(id),
  requested_at timestamptz not null default now(),
  decided_at timestamptz,
  check ((status = 'pending') = (decided_at is null)),
  check (length(coalesce(decision_reason, '')) <= 1000)
);

create table public.return_request_lines (
  id uuid primary key default gen_random_uuid(),
  return_request_id uuid not null references public.return_requests(id),
  order_line_id uuid not null references public.sales_order_lines(id),
  requested_quantity integer not null check (requested_quantity > 0),
  approved_quantity integer not null default 0 check (approved_quantity >= 0),
  unique (return_request_id, order_line_id),
  check (approved_quantity <= requested_quantity)
);

create table public.crate_movements (
  id uuid primary key default gen_random_uuid(),
  distributor_id uuid not null references public.distributors(id),
  external_outlet_id uuid not null references public.external_outlets(id),
  pickup_location_id uuid not null references public.pickup_locations(id),
  crate_type_id uuid not null references public.crate_types(id),
  movement_type text not null check (
    movement_type in ('issued', 'returned', 'lost', 'damaged')
  ),
  quantity integer not null check (quantity > 0),
  reference_id uuid,
  note text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  check (length(coalesce(note, '')) <= 1000)
);

create index crate_movements_distributor_idx
  on public.crate_movements(distributor_id, created_at desc);

create function public.reject_operational_history_change()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  raise exception 'Operational history is immutable; record a correcting movement instead';
end;
$$;

create trigger inventory_movements_immutable
before update or delete on public.inventory_movements
for each row execute function public.reject_operational_history_change();
create trigger order_delivery_lines_immutable
before update or delete on public.order_delivery_lines
for each row execute function public.reject_operational_history_change();
create trigger crate_movements_immutable
before update or delete on public.crate_movements
for each row execute function public.reject_operational_history_change();

create function public.create_sales_order(
  p_pickup_location_id uuid,
  p_external_outlet_id uuid,
  p_requested_for date,
  p_lines jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  saved_order_id uuid;
  line record;
  selected_version_id uuid;
  selected_price numeric(14, 2);
  order_time timestamptz := now();
begin
  if auth.uid() is null
    or public.current_user_role() <> 'distributor'
    or public.current_user_distributor_id() is null then
    raise exception 'Only an assigned distributor can create an order';
  end if;
  if p_pickup_location_id is null or p_external_outlet_id is null
    or p_requested_for is null
    or p_lines is null or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) = 0 then
    raise exception 'Pickup location, outlet, requested date, and order lines are required';
  end if;
  if not exists (
    select 1
    from public.distributor_outlets link
    join public.external_outlets outlet
      on outlet.id = link.external_outlet_id
    join public.pickup_locations location
      on location.id = outlet.pickup_location_id
    where link.distributor_id = public.current_user_distributor_id()
      and outlet.id = p_external_outlet_id
      and location.id = p_pickup_location_id
      and outlet.is_active
      and location.is_active
  ) then
    raise exception 'The distributor is not authorized for this pickup location';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_lines) as item(product_id uuid, quantity integer)
    group by product_id
    having count(*) > 1
  ) then
    raise exception 'A product may appear only once in an order';
  end if;

  insert into public.sales_orders (
    distributor_id, pickup_location_id, external_outlet_id,
    requested_for, created_by
  ) values (
    public.current_user_distributor_id(), p_pickup_location_id,
    p_external_outlet_id, p_requested_for, auth.uid()
  ) returning id into saved_order_id;

  for line in
    select * from jsonb_to_recordset(p_lines) as item(
      product_id uuid, quantity integer
    )
  loop
    if line.product_id is null or line.quantity is null or line.quantity <= 0 then
      raise exception 'Every order line requires a product and positive whole quantity';
    end if;
    if not exists (
      select 1 from public.products product
      where product.id = line.product_id and product.is_active
    ) then
      raise exception 'An order product is inactive or does not exist';
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
    where version.starts_at <= order_time
      and (
        (policy.scope_type = 'external_outlet'
          and policy.external_outlet_id = p_external_outlet_id)
        or (policy.scope_type = 'pickup_location'
          and policy.pickup_location_id = p_pickup_location_id)
        or (policy.scope_type = 'customer_type'
          and policy.customer_type_id = (
            select distributor.customer_type_id
            from public.distributors distributor
            where distributor.id = public.current_user_distributor_id()
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
        line.product_id, order_time;
    end if;
    insert into public.sales_order_lines (
      order_id, product_id, requested_quantity, policy_version_id, unit_price
    ) values (
      saved_order_id, line.product_id, line.quantity,
      selected_version_id, selected_price
    );
  end loop;
  return saved_order_id;
end;
$$;

create function public.submit_sales_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.sales_orders
  set status = 'submitted', submitted_at = now(), updated_at = now()
  where id = p_order_id
    and status = 'draft'
    and distributor_id = public.current_user_distributor_id()
    and public.current_user_role() = 'distributor';
  if not found then
    raise exception 'Draft order was not found or cannot be submitted';
  end if;
end;
$$;

create function public.review_sales_order(
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
      updated_at = now()
  where id = p_order_id
    and (
      (p_decision = 'in_review' and status = 'submitted')
      or (p_decision in ('approved', 'rejected', 'cancelled')
        and status in ('submitted', 'in_review', 'approved'))
    )
    and (p_decision <> 'cancelled' or status <> 'in_production');
  if not found then
    raise exception 'Order was not found or cannot transition to the requested state';
  end if;
end;
$$;

create function public.create_production_batch(
  p_pickup_location_id uuid,
  p_scheduled_for date,
  p_order_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  saved_batch_id uuid;
begin
  if auth.uid() is null or public.current_user_role() not in (
    'admin', 'production_manager'
  ) then
    raise exception 'Only administration or production can schedule a batch';
  end if;
  if p_pickup_location_id is null or p_scheduled_for is null
    or coalesce(array_length(p_order_ids, 1), 0) = 0 then
    raise exception 'Pickup location, production date, and orders are required';
  end if;
  perform orders.id
  from public.sales_orders orders
  where orders.id = any(p_order_ids)
  order by orders.id
  for update;
  if exists (
    select 1 from unnest(p_order_ids) requested(id)
    left join public.sales_orders orders on orders.id = requested.id
    where orders.id is null
      or orders.status <> 'approved'
      or orders.production_batch_id is not null
      or orders.pickup_location_id <> p_pickup_location_id
  ) then
    raise exception 'Every order must be approved, unassigned, and at the selected location';
  end if;
  insert into public.production_batches (
    pickup_location_id, scheduled_for, created_by
  ) values (p_pickup_location_id, p_scheduled_for, auth.uid())
  returning id into saved_batch_id;
  update public.sales_orders
  set production_batch_id = saved_batch_id,
      status = 'in_production',
      updated_at = now()
  where id = any(p_order_ids);
  return saved_batch_id;
end;
$$;

create function public.finalize_production_batch(
  p_batch_id uuid,
  p_lines jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  batch_row public.production_batches%rowtype;
  production_line record;
  batch_line_id uuid;
  total_requested bigint;
  base_allocated bigint;
  remainder_count bigint;
begin
  if auth.uid() is null or public.current_user_role() not in (
    'admin', 'production_manager'
  ) then
    raise exception 'Only administration or production can finalize a batch';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) = 0 then
    raise exception 'Production results are required';
  end if;
  select * into batch_row
  from public.production_batches
  where id = p_batch_id
  for update;
  if not found or batch_row.status <> 'in_production' then
    raise exception 'Production batch was not found or is already finalized';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_lines) as item(
      product_id uuid, produced_quantity integer,
      rejected_quantity integer, variance_reason text
    )
    group by product_id having count(*) > 1
  ) then
    raise exception 'A product may appear only once in a production result';
  end if;
  if exists (
    select 1
    from (
      select distinct order_item.product_id
      from public.sales_orders orders
        join public.sales_order_lines order_item on order_item.order_id = orders.id
      where orders.production_batch_id = p_batch_id
    ) requested
    where not exists (
      select 1 from jsonb_to_recordset(p_lines) as item(
        product_id uuid, produced_quantity integer,
        rejected_quantity integer, variance_reason text
      ) where item.product_id = requested.product_id
    )
  ) then
    raise exception 'Production results must include every requested product';
  end if;

  for production_line in
    select * from jsonb_to_recordset(p_lines) as item(
      product_id uuid, produced_quantity integer,
      rejected_quantity integer, variance_reason text
    )
  loop
    if production_line.product_id is null
      or coalesce(production_line.produced_quantity, -1) < 0
      or coalesce(production_line.rejected_quantity, -1) < 0
      or production_line.produced_quantity + production_line.rejected_quantity = 0
      or (production_line.rejected_quantity > 0
        and nullif(trim(production_line.variance_reason), '') is null)
      or length(coalesce(production_line.variance_reason, '')) > 1000 then
      raise exception 'Production quantities and variance reason are invalid';
    end if;
    select coalesce(sum(order_line.requested_quantity), 0)
    into total_requested
    from public.sales_orders orders
    join public.sales_order_lines order_line on order_line.order_id = orders.id
    where orders.production_batch_id = p_batch_id
      and order_line.product_id = production_line.product_id;
    if total_requested = 0 then
      raise exception 'Production result includes an unrequested product';
    end if;

    insert into public.production_batch_lines (
      batch_id, product_id, produced_quantity,
      rejected_quantity, variance_reason
    ) values (
      p_batch_id, production_line.product_id, production_line.produced_quantity,
      production_line.rejected_quantity,
      nullif(trim(production_line.variance_reason), '')
    ) returning id into batch_line_id;

    insert into public.inventory_balances (
      pickup_location_id, product_id, quantity, updated_at
    ) values (
      batch_row.pickup_location_id, production_line.product_id,
      production_line.produced_quantity, now()
    )
    on conflict (pickup_location_id, product_id) do update
      set quantity = inventory_balances.quantity + excluded.quantity,
          updated_at = now();

    if production_line.produced_quantity > 0 then
      insert into public.inventory_movements (
        pickup_location_id, product_id, quantity_delta,
        movement_type, reference_id, note, created_by
      ) values (
        batch_row.pickup_location_id, production_line.product_id,
        production_line.produced_quantity, 'production', p_batch_id,
        'استلام إنتاج فعلي', auth.uid()
      );
    end if;
    select coalesce(sum(base_quantity), 0)
    into base_allocated
    from (
      select floor(
        production_line.produced_quantity::numeric * order_line.requested_quantity
        / total_requested
      )::bigint as base_quantity
      from public.sales_orders orders
      join public.sales_order_lines order_line on order_line.order_id = orders.id
      where orders.production_batch_id = p_batch_id
        and order_line.product_id = production_line.product_id
    ) bases;
    remainder_count := production_line.produced_quantity - base_allocated;

    insert into public.production_allocations (
      order_line_id, batch_line_id, allocated_quantity
    )
    select order_line.id,
      batch_line_id,
      floor(
      production_line.produced_quantity::numeric * order_line.requested_quantity
        / total_requested
      )::integer
      + case when ranked.rank <= remainder_count then 1 else 0 end
    from (
      select order_line.id,
        row_number() over (
          order by
            mod(
              production_line.produced_quantity::numeric * order_line.requested_quantity,
              total_requested
            ) desc,
            orders.id, order_line.id
        ) as rank
      from public.sales_orders orders
      join public.sales_order_lines order_line on order_line.order_id = orders.id
      where orders.production_batch_id = p_batch_id
        and order_line.product_id = production_line.product_id
    ) ranked
    join public.sales_order_lines order_line on order_line.id = ranked.id;
  end loop;

  update public.production_batches
  set status = 'ready', finalized_by = auth.uid(), finalized_at = now()
  where id = p_batch_id;
  update public.sales_orders
  set status = 'ready', updated_at = now()
  where production_batch_id = p_batch_id;
end;
$$;

create function public.record_order_delivery(
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
  if not found or order_row.status not in (
    'ready', 'partially_delivered'
  ) then
    raise exception 'Order is not ready for delivery';
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
    update public.sales_orders
    set status = 'delivered', updated_at = now()
    where id = p_order_id;
  else
    update public.sales_orders
    set status = 'partially_delivered', updated_at = now()
    where id = p_order_id;
  end if;
  return delivery_id;
end;
$$;

create function public.submit_return_request(
  p_order_id uuid,
  p_reason text,
  p_lines jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  return_id uuid;
  order_row public.sales_orders%rowtype;
  line record;
  delivered_quantity bigint;
  requested_before bigint;
begin
  if auth.uid() is null or public.current_user_role() <> 'distributor' then
    raise exception 'Only a distributor can request a return';
  end if;
  if nullif(trim(p_reason), '') is null
    or p_lines is null or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) = 0 then
    raise exception 'A return reason and at least one item are required';
  end if;
  select * into order_row
  from public.sales_orders orders
  where orders.id = p_order_id
    and orders.distributor_id = public.current_user_distributor_id()
  for update;
  if order_row.id is null then
    raise exception 'Order does not belong to the current distributor';
  end if;
  insert into public.return_requests (
    order_id, reason, requested_by
  ) values (p_order_id, trim(p_reason), auth.uid())
  returning id into return_id;

  for line in
    select * from jsonb_to_recordset(p_lines) as item(
      order_line_id uuid, quantity integer
    )
  loop
    if line.order_line_id is null or line.quantity is null or line.quantity <= 0 then
      raise exception 'Every return line requires an order line and positive quantity';
    end if;
    select coalesce(sum(delivery_line.quantity), 0)
    into delivered_quantity
    from public.order_delivery_lines delivery_line
    join public.order_deliveries delivery
      on delivery.id = delivery_line.delivery_id
    where delivery.order_id = p_order_id
      and delivery_line.order_line_id = line.order_line_id;
    select coalesce(sum(
      case when request.status = 'pending'
        then return_line.requested_quantity
        else return_line.approved_quantity
      end
    ), 0)
    into requested_before
    from public.return_request_lines return_line
    join public.return_requests request
      on request.id = return_line.return_request_id
    where return_line.order_line_id = line.order_line_id
      and request.status in ('pending', 'approved');
    if not exists (
      select 1 from public.sales_order_lines order_line
      where order_line.id = line.order_line_id
        and order_line.order_id = p_order_id
    ) or line.quantity + requested_before > delivered_quantity then
      raise exception 'Return quantity exceeds the unreturned delivered quantity';
    end if;
    insert into public.return_request_lines (
      return_request_id, order_line_id, requested_quantity
    ) values (return_id, line.order_line_id, line.quantity);
  end loop;
  return return_id;
end;
$$;

create function public.decide_return_request(
  p_return_request_id uuid,
  p_resolution text,
  p_reason text,
  p_lines jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  request_row public.return_requests%rowtype;
  line record;
begin
  if auth.uid() is null or public.current_user_role() not in (
    'admin', 'accountant'
  ) then
    raise exception 'Only administration or accounting can decide returns';
  end if;
  if p_resolution not in ('credit', 'replacement', 'destroy', 'reject')
    or nullif(trim(p_reason), '') is null then
    raise exception 'Return decision and reason are required';
  end if;
  select * into request_row
  from public.return_requests
  where id = p_return_request_id
  for update;
  if not found or request_row.status <> 'pending' then
    raise exception 'Return request was not found or is already decided';
  end if;
  if p_resolution = 'reject' then
    update public.return_requests
    set status = 'rejected', decision_reason = trim(p_reason),
        decided_by = auth.uid(), decided_at = now()
    where id = p_return_request_id;
    return;
  end if;
  if p_lines is null or jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception 'Approved return quantities are required';
  end if;
  for line in
    select * from jsonb_to_recordset(p_lines) as item(
      return_line_id uuid, approved_quantity integer
    )
  loop
    if line.return_line_id is null or line.approved_quantity is null
      or line.approved_quantity < 0 then
      raise exception 'Approved return quantities are invalid';
    end if;
    update public.return_request_lines
    set approved_quantity = line.approved_quantity
    where id = line.return_line_id
      and return_request_id = p_return_request_id
      and line.approved_quantity <= requested_quantity;
    if not found then
      raise exception 'Approved quantity exceeds request or line does not belong to return';
    end if;
  end loop;
  if exists (
    select 1
    from public.return_request_lines return_line
    where return_line.return_request_id = p_return_request_id
      and not exists (
        select 1
        from jsonb_to_recordset(p_lines) as item(
          return_line_id uuid, approved_quantity integer
        )
        where item.return_line_id = return_line.id
      )
  ) then
    raise exception 'Every return line requires an explicit approved quantity';
  end if;
  if exists (
    select 1 from public.return_request_lines
    where return_request_id = p_return_request_id
      and approved_quantity > requested_quantity
  ) then
    raise exception 'Approved return quantity is invalid';
  end if;
  update public.return_requests
  set status = 'approved', resolution = p_resolution,
      decision_reason = trim(p_reason), decided_by = auth.uid(),
      decided_at = now()
  where id = p_return_request_id;
end;
$$;

create function public.record_crate_movement(
  p_distributor_id uuid,
  p_external_outlet_id uuid,
  p_pickup_location_id uuid,
  p_crate_type_id uuid,
  p_movement_type text,
  p_quantity integer,
  p_reference_id uuid default null,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  movement_id uuid;
begin
  if auth.uid() is null or not (
    public.current_user_role() in ('admin', 'accountant')
    or (
      public.current_user_role() = 'factory_outlet_manager'
      and public.current_user_pickup_location_id() = p_pickup_location_id
    )
    or (
      public.current_user_role() = 'outlet_manager'
      and public.current_user_outlet_id() = p_external_outlet_id
    )
  ) then
    raise exception 'The user is not authorized to record crate movements';
  end if;
  if p_movement_type not in ('issued', 'returned', 'lost', 'damaged')
    or p_quantity is null or p_quantity <= 0
    or p_distributor_id is null or p_external_outlet_id is null
    or p_pickup_location_id is null or p_crate_type_id is null then
    raise exception 'Crate movement details are invalid';
  end if;
  if not exists (
    select 1 from public.distributor_outlets link
    join public.external_outlets outlet
      on outlet.id = link.external_outlet_id
    where link.distributor_id = p_distributor_id
      and link.external_outlet_id = p_external_outlet_id
      and outlet.pickup_location_id = p_pickup_location_id
  ) then
    raise exception 'The distributor is not assigned to this outlet';
  end if;
  perform pg_advisory_xact_lock(
    hashtext(
      p_distributor_id::text || ':' || p_external_outlet_id::text
      || ':' || p_crate_type_id::text
    )
  );
  if p_movement_type in ('returned', 'lost', 'damaged') then
    if coalesce((
      select sum(case movement_type
        when 'issued' then quantity
        when 'returned' then -quantity
        when 'lost' then -quantity
        when 'damaged' then -quantity
      end)
      from public.crate_movements
      where distributor_id = p_distributor_id
        and external_outlet_id = p_external_outlet_id
        and pickup_location_id = p_pickup_location_id
        and crate_type_id = p_crate_type_id
    ), 0) < p_quantity then
      raise exception 'Crate movement exceeds the distributor crate balance';
    end if;
  end if;
  insert into public.crate_movements (
    distributor_id, external_outlet_id, pickup_location_id,
    crate_type_id, movement_type, quantity, reference_id, note, created_by
  ) values (
    p_distributor_id, p_external_outlet_id, p_pickup_location_id,
    p_crate_type_id, p_movement_type, p_quantity, p_reference_id,
    nullif(trim(p_note), ''), auth.uid()
  ) returning id into movement_id;
  return movement_id;
end;
$$;

create view public.role_orders
with (security_barrier = true)
as
select orders.id, orders.distributor_id, orders.pickup_location_id,
  orders.external_outlet_id, orders.requested_for, orders.status,
  orders.status_reason, orders.production_batch_id, orders.submitted_at,
  orders.created_by, orders.created_at
from public.sales_orders orders
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

create view public.role_order_quantities
with (security_barrier = true)
as
select order_line.id, order_line.order_id, order_line.product_id,
  order_line.requested_quantity,
  coalesce(allocation.allocated_quantity, 0) as allocated_quantity,
  coalesce(delivered.quantity, 0)::integer as delivered_quantity
from public.sales_order_lines order_line
join public.sales_orders orders on orders.id = order_line.order_id
left join public.production_allocations allocation
  on allocation.order_line_id = order_line.id
left join (
  select delivery_line.order_line_id, sum(delivery_line.quantity)::integer as quantity
  from public.order_delivery_lines delivery_line
  group by delivery_line.order_line_id
) delivered on delivered.order_line_id = order_line.id
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

create view public.role_financial_order_lines
with (security_barrier = true)
as
select order_line.id, order_line.order_id, order_line.product_id,
  order_line.requested_quantity, order_line.policy_version_id,
  order_line.unit_price,
  (order_line.requested_quantity * order_line.unit_price)::numeric(18, 2)
    as requested_total
from public.sales_order_lines order_line
join public.sales_orders orders on orders.id = order_line.order_id
where public.current_user_role() in ('admin', 'accountant')
  or orders.distributor_id = public.current_user_distributor_id()
  or (
    orders.external_outlet_id = public.current_user_outlet_id()
    and public.current_user_role() = 'outlet_manager'
  );

create view public.role_production_batches
with (security_barrier = true)
as
select batch.id, batch.pickup_location_id, batch.scheduled_for, batch.status,
  batch.created_by, batch.finalized_by, batch.finalized_at, batch.created_at
from public.production_batches batch
where public.current_user_role() in ('admin', 'accountant', 'production_manager')
  or (
    batch.pickup_location_id = public.current_user_pickup_location_id()
    and public.current_user_role() = 'factory_outlet_manager'
  );

create view public.role_production_quantities
with (security_barrier = true)
as
select line.id, line.batch_id, line.product_id, line.produced_quantity,
  line.rejected_quantity, line.variance_reason
from public.production_batch_lines line
join public.production_batches batch on batch.id = line.batch_id
where public.current_user_role() in ('admin', 'accountant', 'production_manager')
  or (
    batch.pickup_location_id = public.current_user_pickup_location_id()
    and public.current_user_role() = 'factory_outlet_manager'
  );

create view public.role_inventory_balances
with (security_barrier = true)
as
select balance.pickup_location_id, balance.product_id, balance.quantity,
  balance.updated_at
from public.inventory_balances balance
where public.current_user_role() in (
    'admin', 'accountant', 'production_manager'
  )
  or (
    balance.pickup_location_id = public.current_user_pickup_location_id()
    and public.current_user_role() = 'factory_outlet_manager'
  );

create view public.role_crate_movements
with (security_barrier = true)
as
select movement.id, movement.distributor_id, movement.external_outlet_id,
  movement.pickup_location_id, movement.crate_type_id,
  movement.movement_type, movement.quantity, movement.reference_id,
  movement.note, movement.created_by, movement.created_at
from public.crate_movements movement
where public.current_user_role() in ('admin', 'accountant')
  or movement.distributor_id = public.current_user_distributor_id()
  or (
    movement.external_outlet_id = public.current_user_outlet_id()
    and public.current_user_role() in ('outlet_manager', 'collector')
  )
  or (
    movement.pickup_location_id = public.current_user_pickup_location_id()
    and public.current_user_role() = 'factory_outlet_manager'
  );

create view public.role_crate_balances
with (security_barrier = true)
as
select movement.distributor_id, movement.external_outlet_id,
  movement.pickup_location_id, movement.crate_type_id,
  sum(case movement.movement_type
    when 'issued' then movement.quantity
    when 'returned' then -movement.quantity
    when 'lost' then -movement.quantity
    when 'damaged' then -movement.quantity
  end)::bigint as balance,
  sum(case when movement.movement_type = 'lost'
    then movement.quantity else 0 end)::bigint as lost,
  sum(case when movement.movement_type = 'damaged'
    then movement.quantity else 0 end)::bigint as damaged
from public.crate_movements movement
where public.current_user_role() in ('admin', 'accountant')
  or movement.distributor_id = public.current_user_distributor_id()
  or (
    movement.external_outlet_id = public.current_user_outlet_id()
    and public.current_user_role() in ('outlet_manager', 'collector')
  )
  or (
    movement.pickup_location_id = public.current_user_pickup_location_id()
    and public.current_user_role() = 'factory_outlet_manager'
  )
group by movement.distributor_id, movement.external_outlet_id,
  movement.pickup_location_id, movement.crate_type_id;

create view public.role_returns
with (security_barrier = true)
as
select request.id, request.order_id, request.reason, request.status,
  request.resolution, request.decision_reason, request.requested_by,
  request.decided_by, request.requested_at, request.decided_at,
  orders.distributor_id, orders.external_outlet_id, orders.pickup_location_id
from public.return_requests request
join public.sales_orders orders on orders.id = request.order_id
where public.current_user_role() in ('admin', 'accountant')
  or orders.distributor_id = public.current_user_distributor_id()
  or (
    orders.external_outlet_id = public.current_user_outlet_id()
    and public.current_user_role() = 'outlet_manager'
  );

create view public.role_return_quantities
with (security_barrier = true)
as
select line.id, line.return_request_id, line.order_line_id,
  line.requested_quantity, line.approved_quantity
from public.return_request_lines line
join public.return_requests request on request.id = line.return_request_id
join public.sales_orders orders on orders.id = request.order_id
where public.current_user_role() in ('admin', 'accountant')
  or orders.distributor_id = public.current_user_distributor_id()
  or (
    orders.external_outlet_id = public.current_user_outlet_id()
    and public.current_user_role() = 'outlet_manager'
  );

create view public.operational_distributor_account_balances
with (security_barrier = true)
as
select distributor.id as distributor_id,
  distributor.name as distributor_name,
  (
    coalesce(old_sales.total, 0) + coalesce(delivered.total, 0)
  )::numeric(18, 2) as sales_total,
  coalesce(payments.total, 0)::numeric(18, 2) as payments_total,
  coalesce(credits.total, 0)::numeric(18, 2) as approved_return_credits,
  (
    coalesce(old_sales.total, 0) + coalesce(delivered.total, 0)
    - coalesce(payments.total, 0) - coalesce(credits.total, 0)
  )::numeric(18, 2) as balance
from public.distributors distributor
left join (
  select sale.distributor_id, sum(line.line_total) as total
  from public.factory_sales sale
  join public.factory_sale_lines line on line.sale_id = sale.id
  where public.current_user_role() not in ('outlet_manager', 'collector')
    or sale.external_outlet_id = public.current_user_outlet_id()
  group by sale.distributor_id
) old_sales on old_sales.distributor_id = distributor.id
left join (
  select orders.distributor_id,
    sum(delivery_line.quantity * order_line.unit_price) as total
  from public.sales_orders orders
  join public.order_deliveries delivery
    on delivery.order_id = orders.id
  join public.order_delivery_lines delivery_line
    on delivery_line.delivery_id = delivery.id
  join public.sales_order_lines order_line
    on order_line.id = delivery_line.order_line_id
  where public.current_user_role() not in ('outlet_manager', 'collector')
    or orders.external_outlet_id = public.current_user_outlet_id()
  group by orders.distributor_id
) delivered on delivered.distributor_id = distributor.id
left join (
  select payment.distributor_id, sum(payment.amount) as total
  from public.distributor_payments payment
  where public.current_user_role() not in ('outlet_manager', 'collector')
    or payment.external_outlet_id = public.current_user_outlet_id()
  group by payment.distributor_id
) payments on payments.distributor_id = distributor.id
left join (
  select orders.distributor_id,
    sum(return_line.approved_quantity * order_line.unit_price) as total
  from public.return_requests request
  join public.sales_orders orders on orders.id = request.order_id
  join public.return_request_lines return_line
    on return_line.return_request_id = request.id
  join public.sales_order_lines order_line on order_line.id = return_line.order_line_id
  where request.status = 'approved' and request.resolution = 'credit'
    and (
      public.current_user_role() not in ('outlet_manager', 'collector')
      or orders.external_outlet_id = public.current_user_outlet_id()
    )
  group by orders.distributor_id
) credits on credits.distributor_id = distributor.id
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

create or replace view public.distributor_account_balances
with (security_barrier = true)
as
select distributor.id as distributor_id,
  distributor.name as distributor_name,
  coalesce(sales.total, 0)::numeric(18, 2) as factory_sales_total,
  coalesce(payments.total, 0)::numeric(18, 2) as payments_total,
  (
    coalesce(sales.total, 0) - coalesce(payments.total, 0)
  )::numeric(18, 2) as balance
from public.distributors distributor
left join (
  select sale.distributor_id, sum(line.line_total) as total
  from public.factory_sales sale
  join public.factory_sale_lines line on line.sale_id = sale.id
  where public.current_user_role() not in ('outlet_manager', 'collector')
    or sale.external_outlet_id = public.current_user_outlet_id()
  group by sale.distributor_id
) sales on sales.distributor_id = distributor.id
left join (
  select payment.distributor_id, sum(payment.amount) as total
  from public.distributor_payments payment
  where public.current_user_role() not in ('outlet_manager', 'collector')
    or payment.external_outlet_id = public.current_user_outlet_id()
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

create view public.role_operational_order_summary
with (security_barrier = true)
as
select orders.requested_for, orders.pickup_location_id,
  order_line.product_id,
  sum(order_line.requested_quantity)::bigint as requested_quantity,
  sum(coalesce(allocation.allocated_quantity, 0))::bigint as allocated_quantity,
  sum(coalesce(delivered.quantity, 0))::bigint as delivered_quantity
from public.sales_orders orders
join public.sales_order_lines order_line on order_line.order_id = orders.id
left join public.production_allocations allocation
  on allocation.order_line_id = order_line.id
left join (
  select delivery_line.order_line_id, sum(delivery_line.quantity)::bigint as quantity
  from public.order_delivery_lines delivery_line
  group by delivery_line.order_line_id
) delivered on delivered.order_line_id = order_line.id
where public.current_user_role() in ('admin', 'accountant', 'production_manager')
  or orders.distributor_id = public.current_user_distributor_id()
  or (
    orders.external_outlet_id = public.current_user_outlet_id()
    and public.current_user_role() in ('outlet_manager', 'collector')
  )
  or (
    orders.pickup_location_id = public.current_user_pickup_location_id()
    and public.current_user_role() = 'factory_outlet_manager'
  )
group by orders.requested_for, orders.pickup_location_id, order_line.product_id;

revoke all on public.sales_orders, public.sales_order_lines,
  public.production_batches, public.production_batch_lines,
  public.production_allocations, public.inventory_balances,
  public.inventory_movements, public.order_deliveries,
  public.order_delivery_lines, public.return_requests,
  public.return_request_lines, public.crate_movements
  from public, anon, authenticated;

grant select on public.role_orders, public.role_order_quantities,
  public.role_financial_order_lines, public.role_production_batches,
  public.role_production_quantities, public.role_inventory_balances,
  public.role_crate_movements, public.role_crate_balances,
  public.role_returns, public.role_return_quantities,
  public.operational_distributor_account_balances,
  public.role_operational_order_summary to authenticated;

revoke all on function public.reject_operational_history_change()
  from public, anon, authenticated;
revoke all on function public.factory_manager_can_view_distributor(uuid),
  public.factory_manager_can_view_outlet(uuid) from public, anon;
grant execute on function public.factory_manager_can_view_distributor(uuid),
  public.factory_manager_can_view_outlet(uuid) to authenticated;
revoke all on function public.create_sales_order(uuid, uuid, date, jsonb),
  public.submit_sales_order(uuid), public.review_sales_order(uuid, text, text),
  public.create_production_batch(uuid, date, uuid[]),
  public.finalize_production_batch(uuid, jsonb),
  public.record_order_delivery(uuid, text, jsonb, text),
  public.submit_return_request(uuid, text, jsonb),
  public.decide_return_request(uuid, text, text, jsonb),
  public.record_crate_movement(uuid, uuid, uuid, uuid, text, integer, uuid, text)
  from public, anon;
grant execute on function public.create_sales_order(uuid, uuid, date, jsonb),
  public.submit_sales_order(uuid), public.review_sales_order(uuid, text, text),
  public.create_production_batch(uuid, date, uuid[]),
  public.finalize_production_batch(uuid, jsonb),
  public.record_order_delivery(uuid, text, jsonb, text),
  public.submit_return_request(uuid, text, jsonb),
  public.decide_return_request(uuid, text, text, jsonb),
  public.record_crate_movement(uuid, uuid, uuid, uuid, text, integer, uuid, text)
  to authenticated;
