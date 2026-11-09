begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

-- 7 مناديب بطلبات 800/1500/2000/1200/900/2500/1100 = 10000 علبة لكل صنف
insert into public.customer_types (id, name)
values ('10000000-0000-0000-0000-000000000701', 'نوع اختبار التوزيع');
insert into public.pickup_locations (id, name)
values ('20000000-0000-0000-0000-000000000701', 'موقع اختبار التوزيع');
insert into public.external_outlets (id, name, pickup_location_id)
values ('30000000-0000-0000-0000-000000000701', 'منفذ اختبار التوزيع',
  '20000000-0000-0000-0000-000000000701');
insert into public.products (id, code, name, crate_capacity) values
  ('50000000-0000-0000-0000-0000000007a1', 'PD-1', 'صنف زيادة', 75),
  ('50000000-0000-0000-0000-0000000007a2', 'PD-2', 'صنف نقص', 75),
  ('50000000-0000-0000-0000-0000000007a3', 'PD-3', 'صنف كسور', 75);
insert into public.distributors (id, name, customer_type_id)
select ('40000000-0000-0000-0000-00000000070' || g)::uuid, 'موزع ' || g,
  '10000000-0000-0000-0000-000000000701'
from generate_series(1, 7) g;
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values ('00000000-0000-0000-0000-0000000007a1', 'authenticated',
  'authenticated', 'pd-admin@alwaha.invalid', '', now(),
  '{"role":"admin"}', '{}', now(), now());

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000007a1","role":"authenticated"}', true);
select public.save_pricing_policy(null, 'سياسة توزيع', 'external_outlet',
  null, null, '30000000-0000-0000-0000-000000000701', now() - interval '1 day',
  '[{"product_id":"50000000-0000-0000-0000-0000000007a1","factory_purchase_price":9,"distributor_sale_price":10},
    {"product_id":"50000000-0000-0000-0000-0000000007a2","factory_purchase_price":9,"distributor_sale_price":10},
    {"product_id":"50000000-0000-0000-0000-0000000007a3","factory_purchase_price":9,"distributor_sale_price":10}]'::jsonb);

create temporary table pd_orders (idx integer, order_id uuid);
do $$
declare
  quantities integer[] := array[800, 1500, 2000, 1200, 900, 2500, 1100];
  version_id uuid;
  new_order uuid;
  g integer;
  item uuid;
begin
  select v.id into version_id from public.price_policy_versions v
  join public.pricing_policies p on p.id = v.policy_id
  where p.external_outlet_id = '30000000-0000-0000-0000-000000000701';
  for g in 1..7 loop
    insert into public.sales_orders (
      distributor_id, pickup_location_id, external_outlet_id, requested_for,
      status, created_by
    ) values (
      ('40000000-0000-0000-0000-00000000070' || g)::uuid,
      '20000000-0000-0000-0000-000000000701',
      '30000000-0000-0000-0000-000000000701',
      current_date + 2, 'approved',
      '00000000-0000-0000-0000-0000000007a1'
    ) returning id into new_order;
    insert into pd_orders values (g, new_order);
    foreach item in array array[
      '50000000-0000-0000-0000-0000000007a1',
      '50000000-0000-0000-0000-0000000007a2',
      '50000000-0000-0000-0000-0000000007a3']::uuid[] loop
      insert into public.sales_order_lines (
        order_id, product_id, requested_quantity, policy_version_id, unit_price
      ) values (new_order, item, quantities[g], version_id, 10);
    end loop;
  end loop;
end;
$$;

create temporary table pd_batch (id uuid);
insert into pd_batch
select public.create_production_batch(
  '20000000-0000-0000-0000-000000000701', current_date + 2,
  (select array_agg(order_id) from pd_orders));

select no_plan();

select lives_ok($$select public.finalize_production_batch(
  (select id from pd_batch),
  '[{"product_id":"50000000-0000-0000-0000-0000000007a1","produced_quantity":10400,"rejected_quantity":0},
    {"product_id":"50000000-0000-0000-0000-0000000007a2","produced_quantity":9700,"rejected_quantity":0},
    {"product_id":"50000000-0000-0000-0000-0000000007a3","produced_quantity":10333,"rejected_quantity":0}]'::jsonb)$$,
  'تسجيل الإنتاج الفعلي');

create function pg_temp.allocation_string(p_product uuid) returns text
language sql as $$
  select string_agg(a.allocated_quantity::text, ',' order by o.idx)
  from public.production_allocations a
  join public.sales_order_lines l on l.id = a.order_line_id
  join pd_orders o on o.order_id = l.order_id
  where l.product_id = p_product;
$$;

select is(pg_temp.allocation_string('50000000-0000-0000-0000-0000000007a1'),
  '832,1560,2080,1248,936,2600,1144', 'زيادة 400 توزع بنسب المناديب (10400)');
select is(pg_temp.allocation_string('50000000-0000-0000-0000-0000000007a2'),
  '776,1455,1940,1164,873,2425,1067', 'نقص 300 يخصم بنسب المناديب (9700)');
select is(pg_temp.allocation_string('50000000-0000-0000-0000-0000000007a3'),
  '827,1550,2066,1240,930,2583,1137', 'الكسور توزع على أكبر البواقي (10333)');
select is(
  (select sum(a.allocated_quantity) from public.production_allocations a
   join public.sales_order_lines l on l.id = a.order_line_id
   where l.product_id = '50000000-0000-0000-0000-0000000007a3'),
  10333::bigint, 'مجموع التوزيع يساوي الإنتاج الفعلي تمامًا');
select is(
  (select a.allocated_quantity * l.unit_price
   from public.production_allocations a
   join public.sales_order_lines l on l.id = a.order_line_id
   join pd_orders o on o.order_id = l.order_id
   where o.idx = 1 and l.product_id = '50000000-0000-0000-0000-0000000007a1'),
  8320::numeric, 'السعر النهائي بعد التوزيع = 832 × 10');

create temporary table pd_lines as
select o.idx, l.id as line_id
from public.sales_order_lines l join pd_orders o on o.order_id = l.order_id
where l.product_id = '50000000-0000-0000-0000-0000000007a3';

select throws_ok($$select public.revise_production_distribution(
  (select id from pd_batch), '50000000-0000-0000-0000-0000000007a3',
  (select jsonb_agg(jsonb_build_object('order_line_id', line_id,
     'allocated_quantity', 100) order by idx) from pd_lines), 'سبب')$$,
  'P0001',
  'Adjusted quantities must be nonnegative and equal available production',
  'مجموع التعديل اليدوي يجب أن يساوي الإنتاج');

select lives_ok($$select public.revise_production_distribution(
  (select id from pd_batch), '50000000-0000-0000-0000-0000000007a3',
  (select jsonb_agg(jsonb_build_object('order_line_id', line_id,
     'allocated_quantity', case idx when 1 then 837 when 6 then 2573
       when 2 then 1550 when 3 then 2066 when 4 then 1240 when 5 then 930
       else 1137 end) order by idx) from pd_lines), 'تعديل إداري')$$,
  'تعديل يدوي بمجموع صحيح');
select is(
  (select count(*) from public.production_allocation_audit
   where reason = 'تعديل إداري'), 2::bigint, 'التعديل موثق لكل مندوب تغيّر');
select is(
  (select calculated_quantity from public.production_allocations
   where order_line_id = (select line_id from pd_lines where idx = 1)),
  827, 'الكمية المحسوبة تبقى محفوظة بعد التعديل');

select lives_ok($$select public.approve_production_distribution(
  (select id from pd_batch))$$, 'اعتماد التوزيع');
select lives_ok($$select public.revise_production_distribution(
  (select id from pd_batch), '50000000-0000-0000-0000-0000000007a3',
  (select jsonb_agg(jsonb_build_object('order_line_id', line_id,
     'allocated_quantity', case idx when 1 then 827 when 6 then 2583
       when 2 then 1550 when 3 then 2066 when 4 then 1240 when 5 then 930
       else 1137 end) order by idx) from pd_lines), 'تراجع')$$,
  'تعديل بعد الاعتماد');
select is(
  (select distribution_approved from public.production_batches
   where id = (select id from pd_batch)),
  false, 'التعديل بعد الاعتماد يُسقط الاعتماد ويلزم اعتمادًا جديدًا');

select * from finish();
rollback;
