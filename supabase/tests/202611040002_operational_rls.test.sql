begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(9);

select ok(
  not exists (
    select 1
    from unnest(array[
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
    ]) as target(name)
    left join pg_class relation
      on relation.oid = to_regclass(format('public.%I', target.name))
    where relation.oid is null
      or not relation.relrowsecurity
      or relation.relforcerowsecurity
  ),
  'all operational tables have RLS enabled without FORCE'
);

select is(
  (
    select count(*)
    from pg_policy policy
    join pg_class relation on relation.oid = policy.polrelid
    where relation.oid = any(array[
      'public.sales_orders'::regclass,
      'public.sales_order_lines'::regclass,
      'public.production_batches'::regclass,
      'public.production_batch_lines'::regclass,
      'public.production_allocations'::regclass,
      'public.inventory_balances'::regclass,
      'public.inventory_movements'::regclass,
      'public.order_deliveries'::regclass,
      'public.order_delivery_lines'::regclass,
      'public.return_requests'::regclass,
      'public.return_request_lines'::regclass,
      'public.crate_movements'::regclass,
      'public.sales_order_schedule_changes'::regclass,
      'public.production_allocation_audit'::regclass
    ])
  ),
  0::bigint,
  'no allow policies are added to the operational tables'
);

select ok(
  not exists (
    select 1
    from unnest(array[
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
    ]) as target(name)
    where has_table_privilege(
      'anon', format('public.%I', target.name), 'SELECT'
    ) or has_table_privilege(
      'anon', format('public.%I', target.name), 'INSERT'
    ) or has_table_privilege(
      'anon', format('public.%I', target.name), 'UPDATE'
    ) or has_table_privilege(
      'anon', format('public.%I', target.name), 'DELETE'
    ) or has_any_column_privilege(
      'anon', format('public.%I', target.name), 'SELECT'
    ) or has_any_column_privilege(
      'anon', format('public.%I', target.name), 'INSERT'
    ) or has_any_column_privilege(
      'anon', format('public.%I', target.name), 'UPDATE'
    )
  ),
  'anon has no direct table or column access'
);

select ok(
  not exists (
    select 1
    from unnest(array[
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
    ]) as target(name)
    where has_table_privilege(
      'authenticated', format('public.%I', target.name), 'SELECT'
    ) or has_table_privilege(
      'authenticated', format('public.%I', target.name), 'INSERT'
    ) or has_table_privilege(
      'authenticated', format('public.%I', target.name), 'UPDATE'
    ) or has_table_privilege(
      'authenticated', format('public.%I', target.name), 'DELETE'
    ) or has_any_column_privilege(
      'authenticated', format('public.%I', target.name), 'SELECT'
    ) or has_any_column_privilege(
      'authenticated', format('public.%I', target.name), 'INSERT'
    ) or has_any_column_privilege(
      'authenticated', format('public.%I', target.name), 'UPDATE'
    )
  ),
  'authenticated has no direct table or column access'
);

set local role anon;
do $$
declare
  relation_name text;
begin
  foreach relation_name in array array[
    'sales_orders', 'sales_order_lines', 'production_batches',
    'production_batch_lines', 'production_allocations',
    'inventory_balances', 'inventory_movements', 'order_deliveries',
    'order_delivery_lines', 'return_requests', 'return_request_lines',
    'crate_movements', 'sales_order_schedule_changes',
    'production_allocation_audit'
  ] loop
    begin
      execute format('select * from public.%I limit 0', relation_name);
      raise exception 'anon unexpectedly accessed public.%', relation_name;
    exception when insufficient_privilege then
      null;
    end;
  end loop;
end;
$$;
reset role;

set local role authenticated;
do $$
declare
  relation_name text;
begin
  foreach relation_name in array array[
    'sales_orders', 'sales_order_lines', 'production_batches',
    'production_batch_lines', 'production_allocations',
    'inventory_balances', 'inventory_movements', 'order_deliveries',
    'order_delivery_lines', 'return_requests', 'return_request_lines',
    'crate_movements', 'sales_order_schedule_changes',
    'production_allocation_audit'
  ] loop
    begin
      execute format('select * from public.%I limit 0', relation_name);
      raise exception 'authenticated unexpectedly accessed public.%', relation_name;
    exception when insufficient_privilege then
      null;
    end;
  end loop;
end;
$$;
reset role;

select ok(
  has_table_privilege('authenticated', 'public.role_orders', 'SELECT')
  and has_table_privilege(
    'authenticated', 'public.role_crate_movements', 'SELECT'
  )
  and has_table_privilege(
    'authenticated', 'public.role_order_vehicle_groups', 'SELECT'
  )
  and has_table_privilege(
    'authenticated', 'public.role_production_allocation_audit', 'SELECT'
  ),
  'intended filtered view grants remain available'
);

select ok(
  not exists (
    select 1
    from (values
      ('public.create_sales_order(uuid,uuid,date,jsonb)'),
      ('public.create_sales_order(uuid,uuid,jsonb)'),
      ('public.submit_sales_order(uuid)'),
      ('public.review_sales_order(uuid,text,text)'),
      ('public.create_production_batch(uuid,date,uuid[])'),
      ('public.finalize_production_batch(uuid,jsonb)'),
      ('public.record_order_delivery(uuid,text,jsonb,text)'),
      ('public.submit_return_request(uuid,text,jsonb)'),
      ('public.decide_return_request(uuid,text,text,jsonb)'),
      ('public.record_crate_movement(uuid,uuid,uuid,uuid,text,integer,uuid,text)'),
      ('public.reschedule_sales_order(uuid,date,text)'),
      ('public.revise_production_distribution(uuid,uuid,jsonb,text)'),
      ('public.approve_production_distribution(uuid)')
    ) as rpc(signature)
    where not has_function_privilege(
      'authenticated', rpc.signature, 'EXECUTE'
    ) or has_function_privilege('anon', rpc.signature, 'EXECUTE')
  ),
  'operational RPC grants remain available only to authenticated users'
);

select ok(
  not exists (
    select 1
    from pg_class relation
    where relation.oid = any(array[
      'public.sales_orders'::regclass,
      'public.sales_order_lines'::regclass,
      'public.production_batches'::regclass,
      'public.production_batch_lines'::regclass,
      'public.production_allocations'::regclass,
      'public.inventory_balances'::regclass,
      'public.inventory_movements'::regclass,
      'public.order_deliveries'::regclass,
      'public.order_delivery_lines'::regclass,
      'public.return_requests'::regclass,
      'public.return_request_lines'::regclass,
      'public.crate_movements'::regclass,
      'public.sales_order_schedule_changes'::regclass,
      'public.production_allocation_audit'::regclass
    ])
      and relation.relowner <> (
        select relowner from pg_class where oid = 'public.sales_orders'::regclass
      )
  )
  and not exists (
    select 1
    from unnest(array[
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
    ]) as target(name)
    join pg_class relation
      on relation.oid = to_regclass(format('public.%I', target.name))
    where relation.relowner <> (
      select relowner from pg_class where oid = 'public.sales_orders'::regclass
    )
  ),
  'operational tables and filtered views retain a common owner'
);

select ok(
  not exists (
    select 1
    from pg_proc proc
    join pg_namespace namespace on namespace.oid = proc.pronamespace
    join pg_roles role_info on role_info.oid = proc.proowner
    where namespace.nspname = 'public'
      and proc.proname = any(array[
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
      ])
      and (
        not proc.prosecdef
        or not coalesce(
          proc.proconfig @> array['search_path=public, pg_temp'],
          false
        )
        or (
          proc.proowner <> (
            select relowner from pg_class
            where oid = 'public.sales_orders'::regclass
          )
          and not role_info.rolsuper
        )
      )
  ),
  'operational SECURITY DEFINER RPCs use a safe search_path and RLS-capable owner'
);

select ok(
  not has_schema_privilege('anon', 'public', 'CREATE')
  and not has_schema_privilege('authenticated', 'public', 'CREATE'),
  'client roles cannot shadow objects in the SECURITY DEFINER search_path'
);

select * from finish();
rollback;
