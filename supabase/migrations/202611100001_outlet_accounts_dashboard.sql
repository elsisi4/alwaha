-- 1) إضافة منفذ جديد بخطوة واحدة: يُنشأ مكان الاستلام والمنفذ معًا.
create function public.create_outlet(
  p_name text,
  p_outlet_type text default 'external',
  p_allowed_roles text[] default array['outlet_manager', 'collector']
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  clean_name text := trim(p_name);
  place_id uuid;
  outlet_id uuid;
begin
  if auth.uid() is null or not public.is_pricing_admin() then
    raise exception 'Only an administrator can add outlets';
  end if;
  if clean_name is null or clean_name = '' then
    raise exception 'Outlet name is required';
  end if;
  if p_outlet_type not in ('external', 'factory_pickup') then
    raise exception 'Unsupported outlet type';
  end if;
  insert into public.pickup_locations (name)
  values (regexp_replace(clean_name, '^منفذ\s+', ''))
  returning id into place_id;
  insert into public.external_outlets (
    name, pickup_location_id, outlet_type, allowed_roles
  ) values (
    case when clean_name like 'منفذ %' then clean_name
      else 'منفذ ' || clean_name end,
    place_id, p_outlet_type, p_allowed_roles
  ) returning id into outlet_id;
  return outlet_id;
end;
$$;

-- 2) حساب كل مندوب داخل كل منفذ (مبيعات مسلّمة - تحصيل - مرتجعات معتمدة بالتعويض).
create view public.role_outlet_distributor_accounts
with (security_barrier = true)
as
select link.external_outlet_id, link.distributor_id,
  distributor.name as distributor_name, link.vehicle_group,
  (coalesce(delivered.total, 0) + coalesce(legacy.total, 0))::numeric(18, 2)
    as sales_total,
  coalesce(payments.total, 0)::numeric(18, 2) as payments_total,
  coalesce(credits.total, 0)::numeric(18, 2) as credits_total,
  (coalesce(delivered.total, 0) + coalesce(legacy.total, 0)
    - coalesce(payments.total, 0) - coalesce(credits.total, 0))::numeric(18, 2)
    as balance
from public.distributor_outlets link
join public.distributors distributor on distributor.id = link.distributor_id
left join (
  select orders.external_outlet_id, orders.distributor_id,
    sum(delivery_line.quantity * order_line.unit_price) as total
  from public.sales_orders orders
  join public.order_deliveries delivery on delivery.order_id = orders.id
  join public.order_delivery_lines delivery_line
    on delivery_line.delivery_id = delivery.id
  join public.sales_order_lines order_line
    on order_line.id = delivery_line.order_line_id
  group by orders.external_outlet_id, orders.distributor_id
) delivered on delivered.external_outlet_id = link.external_outlet_id
  and delivered.distributor_id = link.distributor_id
left join (
  select sale.external_outlet_id, sale.distributor_id,
    sum(line.line_total) as total
  from public.factory_sales sale
  join public.factory_sale_lines line on line.sale_id = sale.id
  where sale.external_outlet_id is not null
  group by sale.external_outlet_id, sale.distributor_id
) legacy on legacy.external_outlet_id = link.external_outlet_id
  and legacy.distributor_id = link.distributor_id
left join (
  select payment.external_outlet_id, payment.distributor_id,
    sum(payment.amount) as total
  from public.distributor_payments payment
  group by payment.external_outlet_id, payment.distributor_id
) payments on payments.external_outlet_id = link.external_outlet_id
  and payments.distributor_id = link.distributor_id
left join (
  select orders.external_outlet_id, orders.distributor_id,
    sum(return_line.approved_quantity * order_line.unit_price) as total
  from public.return_requests request
  join public.sales_orders orders on orders.id = request.order_id
  join public.return_request_lines return_line
    on return_line.return_request_id = request.id
  join public.sales_order_lines order_line
    on order_line.id = return_line.order_line_id
  where request.status = 'approved' and request.resolution = 'credit'
  group by orders.external_outlet_id, orders.distributor_id
) credits on credits.external_outlet_id = link.external_outlet_id
  and credits.distributor_id = link.distributor_id
where public.current_user_role() in ('admin', 'accountant')
  or (
    public.current_user_role() in ('outlet_manager', 'collector')
    and link.external_outlet_id = public.current_user_outlet_id()
  )
  or link.distributor_id = public.current_user_distributor_id();

-- 3) الرقم المجمّع للمنفذ: ما على مناديبه، وما اشتراه من المصنع بسعره الخاص
--    (الكمية المسلّمة × سعر شراء المنفذ المثبت في الطلب) وما دفعه للمصنع.
create view public.role_outlet_account_summary
with (security_barrier = true)
as
select outlet.id as external_outlet_id, outlet.name as external_outlet_name,
  outlet.outlet_type,
  coalesce(accounts.sales_total, 0)::numeric(18, 2) as distributors_sales,
  coalesce(accounts.payments_total, 0)::numeric(18, 2) as distributors_paid,
  coalesce(accounts.credits_total, 0)::numeric(18, 2) as distributors_credits,
  coalesce(accounts.balance, 0)::numeric(18, 2) as distributors_balance,
  coalesce(accounts.distributor_count, 0)::integer as distributor_count,
  (coalesce(derived.total, 0) + coalesce(manual.total, 0))::numeric(18, 2)
    as purchased_from_factory,
  coalesce(outlet_paid.total, 0)::numeric(18, 2) as paid_to_factory,
  (coalesce(derived.total, 0) + coalesce(manual.total, 0)
    - coalesce(outlet_paid.total, 0))::numeric(18, 2) as outlet_balance
from public.external_outlets outlet
left join (
  select account.external_outlet_id,
    sum(account.sales_total) as sales_total,
    sum(account.payments_total) as payments_total,
    sum(account.credits_total) as credits_total,
    sum(account.balance) as balance,
    count(*) as distributor_count
  from public.role_outlet_distributor_accounts account
  group by account.external_outlet_id
) accounts on accounts.external_outlet_id = outlet.id
left join (
  select orders.external_outlet_id,
    sum(delivery_line.quantity * entry.factory_purchase_price) as total
  from public.sales_orders orders
  join public.order_deliveries delivery on delivery.order_id = orders.id
  join public.order_delivery_lines delivery_line
    on delivery_line.delivery_id = delivery.id
  join public.sales_order_lines order_line
    on order_line.id = delivery_line.order_line_id
  join public.price_policy_entries entry
    on entry.version_id = order_line.policy_version_id
    and entry.product_id = order_line.product_id
  where entry.factory_purchase_price is not null
  group by orders.external_outlet_id
) derived on derived.external_outlet_id = outlet.id
left join (
  select purchase.external_outlet_id, sum(line.line_total) as total
  from public.outlet_purchases purchase
  join public.outlet_purchase_lines line on line.purchase_id = purchase.id
  group by purchase.external_outlet_id
) manual on manual.external_outlet_id = outlet.id
left join (
  select payment.external_outlet_id, sum(payment.amount) as total
  from public.outlet_payments payment
  group by payment.external_outlet_id
) outlet_paid on outlet_paid.external_outlet_id = outlet.id
where public.current_user_role() in ('admin', 'accountant')
  or (
    public.current_user_role() = 'outlet_manager'
    and outlet.id = public.current_user_outlet_id()
  );

-- 4) أرقام لوحة المدير.
create function public.admin_dashboard_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  result jsonb;
begin
  if auth.uid() is null
    or public.current_user_role() not in ('admin', 'accountant') then
    raise exception 'Only administration or accounting can read the dashboard';
  end if;
  select jsonb_build_object(
    'new_orders', (
      select count(*) from public.sales_orders
      where status in ('submitted', 'in_review')
    ),
    'orders_in_production', (
      select count(*) from public.sales_orders where status = 'in_production'
    ),
    'orders_ready', (
      select count(*) from public.sales_orders
      where status in ('ready', 'partially_delivered')
    ),
    'pending_signups', (
      select count(*) from public.user_profiles
      where role = 'pending' and full_name is not null
    ),
    'today_production', (
      select coalesce(sum(line.produced_quantity), 0)
      from public.production_batch_lines line
      join public.production_batches batch on batch.id = line.batch_id
      where batch.finalized_at::date = current_date
    ),
    'monthly_sales', (
      select jsonb_agg(jsonb_build_object(
        'month', to_char(month_start, 'YYYY-MM'),
        'total', coalesce(sales.total, 0)
      ) order by month_start)
      from generate_series(
        date_trunc('month', now()) - interval '5 months',
        date_trunc('month', now()),
        interval '1 month'
      ) month_start
      left join (
        select date_trunc('month', delivery.delivered_at) as month,
          sum(delivery_line.quantity * order_line.unit_price) as total
        from public.order_deliveries delivery
        join public.order_delivery_lines delivery_line
          on delivery_line.delivery_id = delivery.id
        join public.sales_order_lines order_line
          on order_line.id = delivery_line.order_line_id
        group by 1
      ) sales on sales.month = month_start
    )
  ) into result;
  return result;
end;
$$;

revoke all on public.role_outlet_distributor_accounts,
  public.role_outlet_account_summary from public, anon, authenticated;
grant select on public.role_outlet_distributor_accounts,
  public.role_outlet_account_summary to authenticated;
revoke all on function public.create_outlet(text, text, text[]),
  public.admin_dashboard_summary() from public, anon;
grant execute on function public.create_outlet(text, text, text[]),
  public.admin_dashboard_summary() to authenticated;
