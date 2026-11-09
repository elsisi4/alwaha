-- 1) البرانيك تُحسب على إجمالي الطلب لا لكل صنف: كل صنف يشغل (الكمية ÷ سعته)
--    من البرنيكة، ويُقرَّب المجموع لأعلى. مثال: صنفان بسعة 75 و1000 علبة لكل منهما
--    = 2000 ÷ 75 = 26.67 فتكون 27 برنيكة (وليس 14 + 14).
--    الحساب بكسور دقيقة (مقام مشترك) كي لا تتأثر النتيجة بتقريب الأعداد العشرية.
create function public.crates_needed(
  p_quantities integer[],
  p_capacities integer[]
)
returns integer
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  total_num numeric := 0;
  total_den numeric := 1;
  new_den numeric;
  idx integer;
  item_quantity integer;
  item_capacity integer;
begin
  if coalesce(array_length(p_quantities, 1), 0)
    <> coalesce(array_length(p_capacities, 1), 0) then
    raise exception 'Quantities and capacities must have the same length';
  end if;
  for idx in 1..coalesce(array_length(p_quantities, 1), 0) loop
    item_quantity := p_quantities[idx];
    item_capacity := p_capacities[idx];
    if item_quantity is null or item_quantity < 0
      or item_capacity is null or item_capacity <= 0 then
      raise exception 'Crate quantities must be nonnegative and capacities positive';
    end if;
    new_den := lcm(total_den, item_capacity::numeric);
    total_num := total_num * (new_den / total_den)
      + item_quantity::numeric * (new_den / item_capacity::numeric);
    total_den := new_den;
  end loop;
  return div(total_num + total_den - 1, total_den)::integer;
end;
$$;

create view public.role_order_crates
with (security_barrier = true)
as
select orders.id as order_id,
  public.crates_needed(
    array_agg(line.requested_quantity order by line.id),
    array_agg(product.crate_capacity order by line.id)
  ) as requested_crates,
  public.crates_needed(
    array_agg(coalesce(allocation.allocated_quantity, 0) order by line.id),
    array_agg(product.crate_capacity order by line.id)
  ) as allocated_crates,
  coalesce((
    select sum(per_delivery.crates)::integer
    from (
      select public.crates_needed(
        array_agg(delivery_line.quantity order by delivery_line.order_line_id),
        array_agg(delivery_line.crate_capacity_snapshot
          order by delivery_line.order_line_id)
      ) as crates
      from public.order_deliveries delivery
      join public.order_delivery_lines delivery_line
        on delivery_line.delivery_id = delivery.id
      where delivery.order_id = orders.id
      group by delivery.id
    ) per_delivery
  ), 0) as delivered_crates
from public.sales_orders orders
join public.sales_order_lines line on line.order_id = orders.id
join public.products product on product.id = line.product_id
left join public.production_allocations allocation
  on allocation.order_line_id = line.id
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
  )
group by orders.id;

revoke all on public.role_order_crates from public, anon, authenticated;
grant select on public.role_order_crates to authenticated;

-- 2) قائمة أسعار المندوب قبل تأكيد الطلب، بنفس قاعدة اختيار السعر عند إنشاء الطلب
--    (منفذ ثم موقع استلام ثم نوع عميل). المندوب لا يقرأ جداول الأسعار مباشرة.
create function public.get_order_price_list(p_external_outlet_id uuid)
returns table (product_id uuid, unit_price numeric, crate_capacity integer)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  own_distributor_id uuid := public.current_user_distributor_id();
  outlet_row public.external_outlets%rowtype;
begin
  if auth.uid() is null or public.current_user_role() <> 'distributor'
    or own_distributor_id is null then
    raise exception 'Only a distributor can preview order prices';
  end if;
  select outlet.* into outlet_row
  from public.external_outlets outlet
  where outlet.id = p_external_outlet_id and outlet.is_active
    and exists (
      select 1 from public.distributor_outlets link
      where link.distributor_id = own_distributor_id
        and link.external_outlet_id = outlet.id
    );
  if not found then
    raise exception 'The distributor is not authorized for this outlet';
  end if;
  return query
  select item.id,
    (
      select case when policy.scope_type = 'external_outlet'
          then entry.distributor_sale_price else entry.sale_price end
      from public.pricing_policies policy
      join public.price_policy_versions version on version.policy_id = policy.id
      join public.price_policy_entries entry
        on entry.version_id = version.id and entry.product_id = item.id
      where version.starts_at <= now()
        and (
          (policy.scope_type = 'external_outlet'
            and policy.external_outlet_id = p_external_outlet_id)
          or (policy.scope_type = 'pickup_location'
            and policy.pickup_location_id = outlet_row.pickup_location_id)
          or (policy.scope_type = 'customer_type'
            and policy.customer_type_id = (
              select distributor.customer_type_id
              from public.distributors distributor
              where distributor.id = own_distributor_id
            ))
        )
      order by case policy.scope_type
        when 'external_outlet' then 1
        when 'pickup_location' then 2
        else 3
      end, version.starts_at desc
      limit 1
    ),
    item.crate_capacity
  from public.products item
  where item.is_active;
end;
$$;

-- 3) احتياجات الخامات للطلبات المحددة من الوصفة السارية في يوم الإنتاج،
--    مع نسبة الهالك المتوقعة. الأصناف التي بلا وصفة تُرجَع كتنبيه.
create function public.production_material_requirements(
  p_order_ids uuid[],
  p_for_date date default current_date
)
returns table (
  kind text,
  item_id uuid,
  item_name text,
  unit text,
  quantity numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  if auth.uid() is null
    or public.current_user_role() not in ('admin', 'production_manager') then
    raise exception 'Only administration or production can calculate material requirements';
  end if;
  if p_for_date is null then
    raise exception 'Production date is required';
  end if;
  return query
  with requested as (
    select line.product_id as req_product_id,
      sum(line.requested_quantity)::numeric as total_quantity
    from public.sales_order_lines line
    where line.order_id = any(coalesce(p_order_ids, '{}'::uuid[]))
    group by line.product_id
  ), recipe as (
    select requested.req_product_id, requested.total_quantity,
      (
        select version.id
        from public.product_recipe_versions version
        where version.product_id = requested.req_product_id
          and version.starts_at < (p_for_date + 1)::timestamptz
        order by version.starts_at desc
        limit 1
      ) as version_id
    from requested
  )
  select 'material'::text, material.id, material.name, material.unit,
    round(sum(
      recipe.total_quantity * recipe_line.quantity_per_sales_unit
      * (1 + recipe_line.waste_percent / 100)
    ), 3)
  from recipe
  join public.product_recipe_lines recipe_line
    on recipe_line.version_id = recipe.version_id
  join public.raw_materials material on material.id = recipe_line.raw_material_id
  group by material.id, material.name, material.unit
  union all
  select 'missing_recipe'::text, product.id, product.name, null::text,
    recipe.total_quantity
  from recipe
  join public.products product on product.id = recipe.req_product_id
  where recipe.version_id is null;
end;
$$;

revoke all on function public.get_order_price_list(uuid),
  public.production_material_requirements(uuid[], date),
  public.crates_needed(integer[], integer[]) from public, anon;
grant execute on function public.get_order_price_list(uuid),
  public.production_material_requirements(uuid[], date),
  public.crates_needed(integer[], integer[]) to authenticated;
