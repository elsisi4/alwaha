-- المحاسب والمدير يملكان قرار اعتماد طلب المندوب أو رفضه.
-- الرفض يتطلب سببًا يُحفظ في status_reason ويظهر للمندوب عبر role_orders.
-- الإلغاء بعد الاعتماد يبقى للمدير فقط. الصلاحيات الممنوحة للدالة لا تتغير.
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
    or (
      public.current_user_role() = 'accountant'
      and p_decision in ('in_review', 'approved', 'rejected')
    )
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
