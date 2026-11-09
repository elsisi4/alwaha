alter table public.products
  add column if not exists category text not null default 'غير مصنف',
  add column if not exists quality text not null default 'غير محدد',
  add column if not exists sales_unit text not null default 'علبة',
  add column if not exists description text,
  add column if not exists image_url text;

alter table public.products
  add constraint products_category_check check (length(trim(category)) > 0),
  add constraint products_quality_check check (length(trim(quality)) > 0),
  add constraint products_sales_unit_check check (length(trim(sales_unit)) > 0),
  add constraint products_image_url_check
  check (image_url is null or image_url ~* '^https?://');

create table public.raw_materials (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  unit text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  check (length(trim(code)) > 0),
  check (length(trim(name)) > 0),
  check (length(trim(unit)) > 0)
);

create table public.product_recipe_versions (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id),
  version_number integer not null check (version_number > 0),
  starts_at timestamptz not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (product_id, version_number),
  unique (product_id, starts_at)
);

create index product_recipe_versions_effective_idx
  on public.product_recipe_versions(product_id, starts_at desc);

create table public.product_recipe_lines (
  version_id uuid not null
    references public.product_recipe_versions(id) on delete restrict,
  raw_material_id uuid not null
    references public.raw_materials(id) on delete restrict,
  quantity_per_sales_unit numeric(14, 4) not null
    check (quantity_per_sales_unit > 0),
  waste_percent numeric(6, 3) not null default 0
    check (waste_percent >= 0 and waste_percent <= 100),
  primary key (version_id, raw_material_id)
);

create table public.crate_types (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  capacity integer not null default 75 check (capacity > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  check (length(trim(code)) > 0),
  check (length(trim(name)) > 0)
);

create table public.product_crate_types (
  product_id uuid not null references public.products(id) on delete cascade,
  crate_type_id uuid not null references public.crate_types(id) on delete restrict,
  primary key (product_id, crate_type_id)
);

insert into public.crate_types (code, name, capacity)
values ('standard', 'برنيكة قياسية', 75)
on conflict (code) do nothing;

create function public.reject_recipe_history_change()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  raise exception 'Recipe history is immutable; create a new version instead';
end;
$$;

create trigger product_recipe_versions_immutable
before update or delete on public.product_recipe_versions
for each row execute function public.reject_recipe_history_change();

create trigger product_recipe_lines_immutable
before update or delete on public.product_recipe_lines
for each row execute function public.reject_recipe_history_change();

create function public.save_product_recipe(
  p_product_id uuid,
  p_starts_at timestamptz,
  p_lines jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  recipe_version_id uuid;
  next_version integer;
  line record;
begin
  if auth.uid() is null or not public.is_pricing_admin() then
    raise exception 'Only an administrator can save a product recipe';
  end if;
  if p_starts_at is null then
    raise exception 'Recipe effective date is required';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) = 0 then
    raise exception 'At least one recipe ingredient is required';
  end if;
  if not exists (
    select 1 from public.products product
    where product.id = p_product_id
  ) then
    raise exception 'Product was not found';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_lines) as item(
      raw_material_id uuid, quantity_per_sales_unit numeric, waste_percent numeric
    )
    group by raw_material_id
    having count(*) > 1
  ) then
    raise exception 'A raw material may appear only once in a recipe';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_product_id::text));
  select coalesce(max(version_number), 0) + 1
  into next_version
  from public.product_recipe_versions
  where product_id = p_product_id;

  insert into public.product_recipe_versions (
    product_id, version_number, starts_at, created_by
  ) values (
    p_product_id, next_version, p_starts_at, auth.uid()
  ) returning id into recipe_version_id;

  for line in
    select * from jsonb_to_recordset(p_lines) as item(
      raw_material_id uuid,
      quantity_per_sales_unit numeric,
      waste_percent numeric
    )
  loop
    if line.raw_material_id is null
      or line.quantity_per_sales_unit is null
      or line.quantity_per_sales_unit <= 0
      or coalesce(line.waste_percent, 0) < 0
      or coalesce(line.waste_percent, 0) > 100 then
      raise exception 'Recipe lines require a raw material, positive amount, and valid waste percent';
    end if;
    if not exists (
      select 1 from public.raw_materials material
      where material.id = line.raw_material_id and material.is_active
    ) then
      raise exception 'The raw material is inactive or does not exist';
    end if;
    insert into public.product_recipe_lines (
      version_id, raw_material_id, quantity_per_sales_unit, waste_percent
    ) values (
      recipe_version_id,
      line.raw_material_id,
      line.quantity_per_sales_unit,
      coalesce(line.waste_percent, 0)
    );
  end loop;
  return recipe_version_id;
end;
$$;

alter table public.raw_materials enable row level security;
alter table public.product_recipe_versions enable row level security;
alter table public.product_recipe_lines enable row level security;
alter table public.crate_types enable row level security;
alter table public.product_crate_types enable row level security;

create policy "administrators manage raw materials"
  on public.raw_materials for all to authenticated
  using (public.is_pricing_admin())
  with check (public.is_pricing_admin());
create policy "operations and accountants read raw materials"
  on public.raw_materials for select to authenticated
  using (
    public.current_user_role() in (
      'accountant', 'production_manager', 'factory_outlet_manager'
    )
    and (is_active or public.is_pricing_admin())
  );

create policy "administrators manage recipe versions"
  on public.product_recipe_versions for all to authenticated
  using (public.is_pricing_admin())
  with check (public.is_pricing_admin());
create policy "operations and accountants read recipe versions"
  on public.product_recipe_versions for select to authenticated
  using (
    public.current_user_role() in (
      'admin', 'accountant', 'production_manager', 'factory_outlet_manager'
    )
  );
create policy "administrators manage recipe lines"
  on public.product_recipe_lines for all to authenticated
  using (public.is_pricing_admin())
  with check (public.is_pricing_admin());
create policy "operations and accountants read recipe lines"
  on public.product_recipe_lines for select to authenticated
  using (
    public.current_user_role() in (
      'admin', 'accountant', 'production_manager', 'factory_outlet_manager'
    )
  );

create policy "administrators manage crate types"
  on public.crate_types for all to authenticated
  using (public.is_pricing_admin())
  with check (public.is_pricing_admin());
create policy "authorized users read crate types"
  on public.crate_types for select to authenticated
  using (
    public.current_user_role() in (
      'admin', 'accountant', 'production_manager', 'factory_outlet_manager',
      'outlet_manager', 'collector', 'distributor'
    )
    and (is_active or public.is_pricing_admin())
  );

create policy "administrators manage product crate types"
  on public.product_crate_types for all to authenticated
  using (public.is_pricing_admin())
  with check (public.is_pricing_admin());
create policy "authorized users read product crate types"
  on public.product_crate_types for select to authenticated
  using (
    public.current_user_role() in (
      'admin', 'accountant', 'production_manager', 'factory_outlet_manager',
      'outlet_manager', 'collector', 'distributor'
    )
  );

grant select, insert, update, delete on
  public.raw_materials, public.product_recipe_versions,
  public.product_recipe_lines, public.crate_types, public.product_crate_types
to authenticated;
grant execute on function public.save_product_recipe(uuid, timestamptz, jsonb)
  to authenticated;

revoke all on function public.reject_recipe_history_change() from public;
revoke all on function public.save_product_recipe(uuid, timestamptz, jsonb)
  from public;
