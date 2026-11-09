-- بيانات البداية: المنافذ الثلاثة ونوع عميل افتراضي. آمن لإعادة التشغيل.
insert into public.pickup_locations (name)
values ('المصنع'), ('أم بيومي'), ('بهتيم')
on conflict (name) do nothing;

insert into public.external_outlets (name, pickup_location_id, outlet_type)
select 'منفذ المصنع', location.id, 'factory_pickup'
from public.pickup_locations location where location.name = 'المصنع'
on conflict (name) do nothing;
insert into public.external_outlets (name, pickup_location_id, outlet_type)
select 'منفذ أم بيومي', location.id, 'external'
from public.pickup_locations location where location.name = 'أم بيومي'
on conflict (name) do nothing;
insert into public.external_outlets (name, pickup_location_id, outlet_type)
select 'منفذ بهتيم', location.id, 'external'
from public.pickup_locations location where location.name = 'بهتيم'
on conflict (name) do nothing;

insert into public.customer_types (name)
values ('مندوب مستقل')
on conflict (name) do nothing;
