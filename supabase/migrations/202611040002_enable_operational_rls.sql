do $$
declare
  table_owner oid;
  owner_count integer;
  relation_name text;
  routine record;
  target_tables text[] := array[
    'sales_orders',
    'sales_order_lines',
    'production_batches',
    'production_batch_lines',
    'production_allocations',
    'inventory_balances',
    'inventory_movements',
    'order_deliveries',
    'order_delivery_lines',
    'return_requests',
    'return_request_lines',
    'crate_movements',
    'sales_order_schedule_changes',
    'production_allocation_audit'
  ];
  target_views text[] := array[
    'role_orders',
    'role_order_quantities',
    'role_financial_order_lines',
    'role_operational_order_summary',
    'operational_distributor_account_balances',
    'role_production_batches',
    'role_production_quantities',
    'role_inventory_balances',
    'role_crate_movements',
    'role_crate_balances',
    'role_returns',
    'role_return_quantities',
    'role_order_vehicle_groups',
    'role_production_allocation_audit'
  ];
  target_routines text[] := array[
    'create_sales_order',
    'submit_sales_order',
    'review_sales_order',
    'create_production_batch',
    'finalize_production_batch',
    'record_order_delivery',
    'submit_return_request',
    'decide_return_request',
    'record_crate_movement',
    'reschedule_sales_order',
    'revise_production_distribution',
    'approve_production_distribution',
    'audit_initial_production_allocation',
    'get_order_lead_days',
    'current_user_role',
    'current_user_distributor_id',
    'current_user_outlet_id',
    'current_user_pickup_location_id',
    'is_pricing_admin',
    'factory_manager_can_view_distributor',
    'factory_manager_can_view_outlet'
  ];
begin
  if has_schema_privilege('anon', 'public', 'CREATE')
    or has_schema_privilege('authenticated', 'public', 'CREATE') then
    raise exception
      'SECURITY DEFINER search_path is unsafe while client roles can create in public';
  end if;

  if exists (
    select 1
    from unnest(target_tables) as target(name)
    left join pg_class relation
      on relation.oid = to_regclass(format('public.%I', target.name))
    where relation.oid is null or relation.relkind <> 'r'
  ) then
    raise exception 'An operational RLS table is missing or is not a table';
  end if;

  select count(distinct relation.relowner)
  into owner_count
  from pg_class relation
  join unnest(target_tables) as target(name)
    on relation.oid = to_regclass(format('public.%I', target.name));
  if owner_count <> 1 then
    raise exception 'Operational tables must share one owner before enabling RLS';
  end if;
  select relation.relowner
  into table_owner
  from pg_class relation
  where relation.oid = to_regclass('public.sales_orders');

  if exists (
    select 1
    from unnest(target_views) as target(name)
    left join pg_class relation
      on relation.oid = to_regclass(format('public.%I', target.name))
    where relation.oid is null or relation.relkind <> 'v'
      or relation.relowner <> table_owner
  ) then
    raise exception 'An operational view is missing or has a different owner than its tables';
  end if;

  for routine in
    select proc.oid, proc.proname, proc.prosecdef,
      proc.proconfig, proc.proowner, role_info.rolsuper
    from pg_proc proc
    join pg_namespace namespace on namespace.oid = proc.pronamespace
    join pg_roles role_info on role_info.oid = proc.proowner
    where namespace.nspname = 'public'
      and proc.proname = any(target_routines)
  loop
    if not routine.prosecdef
      or not coalesce(
        routine.proconfig @> array['search_path=public, pg_temp'],
        false
      )
      or (
        routine.proowner <> table_owner
        and not routine.rolsuper
      ) then
      raise exception
        'Operational SECURITY DEFINER routine % is missing a safe owner or search_path',
        routine.proname;
    end if;
  end loop;

  if (
    select count(distinct proc.proname)
    from pg_proc proc
    join pg_namespace namespace on namespace.oid = proc.pronamespace
    where namespace.nspname = 'public'
      and proc.proname = any(target_routines)
  ) <> cardinality(target_routines) then
    raise exception 'An expected operational RPC is missing';
  end if;

  foreach relation_name in array target_tables loop
    execute format(
      'alter table public.%I enable row level security',
      relation_name
    );
  end loop;
end;
$$;

revoke all on public.sales_orders, public.sales_order_lines,
  public.production_batches, public.production_batch_lines,
  public.production_allocations, public.inventory_balances,
  public.inventory_movements, public.order_deliveries,
  public.order_delivery_lines, public.return_requests,
  public.return_request_lines, public.crate_movements,
  public.sales_order_schedule_changes, public.production_allocation_audit
  from public, anon, authenticated;
