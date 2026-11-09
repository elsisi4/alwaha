-- دفعة المنفذ الخارجي للمصنع: مبلغ مجمّع عن كل عملاء المنفذ، وتُخصم من رصيد
-- المنفذ لدى المصنع (outlet_account_balances) دون المساس بحسابات المناديب.
create function public.record_outlet_payment(
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
  if auth.uid() is null
    or public.current_user_role() not in ('admin', 'accountant') then
    raise exception 'Only administration or accounting can record outlet payments';
  end if;
  if p_amount is null or p_amount <= 0 or p_paid_at is null then
    raise exception 'A positive payment amount and date are required';
  end if;
  if not exists (
    select 1 from public.external_outlets outlet
    where outlet.id = p_external_outlet_id
  ) then
    raise exception 'The outlet does not exist';
  end if;
  insert into public.outlet_payments (
    external_outlet_id, amount, paid_at, created_by
  ) values (
    p_external_outlet_id, p_amount, p_paid_at, auth.uid()
  ) returning id into payment_id;
  return payment_id;
end;
$$;

revoke all on function public.record_outlet_payment(uuid, numeric, timestamptz)
  from public, anon;
grant execute on function public.record_outlet_payment(uuid, numeric, timestamptz)
  to authenticated;
