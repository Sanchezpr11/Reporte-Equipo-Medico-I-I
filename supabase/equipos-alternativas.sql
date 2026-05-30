-- ============================================================================
--  EQUIPOS: alternativas de suplidores + equipo de oficina
--    equipment_items   -> equipos médicos a comprar (alimenta el financiamiento)
--    equipment_quotes  -> 2-3 alternativas por equipo; se elige una
--    office_equipment  -> equipo de oficina (escritorios, sillas, supplies, etc.)
--  Idempotente. Supabase -> SQL Editor -> New query -> pegar -> Run.
-- ============================================================================

-- Equipos médicos a comprar
create table if not exists public.equipment_items (
    id         uuid primary key default gen_random_uuid(),
    area_key   text not null default 'equipos' references public.areas(key) on delete cascade,
    name       text not null,
    item_key   text,                                 -- clave para equipos del análisis (fibroscan/iliv)
    quantity   int not null default 1,
    notes      text default '',
    created_at timestamptz not null default now()
);
create index if not exists equipment_items_area_idx on public.equipment_items(area_key);
alter table public.equipment_items enable row level security;
drop policy if exists equipment_items_rw on public.equipment_items;
create policy equipment_items_rw on public.equipment_items for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

-- Alternativas de costo (por tienda/suplidor) para cada equipo
create table if not exists public.equipment_quotes (
    id         uuid primary key default gen_random_uuid(),
    area_key   text not null default 'equipos' references public.areas(key) on delete cascade,
    item_id    uuid not null references public.equipment_items(id) on delete cascade,
    supplier   text default '',
    price      numeric,
    notes      text default '',
    selected   boolean not null default false,
    created_at timestamptz not null default now()
);
create index if not exists equipment_quotes_item_idx on public.equipment_quotes(item_id);
alter table public.equipment_quotes enable row level security;
drop policy if exists equipment_quotes_rw on public.equipment_quotes;
create policy equipment_quotes_rw on public.equipment_quotes for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

-- Equipo de oficina (mobiliario, enseres, supplies)
create table if not exists public.office_equipment (
    id         uuid primary key default gen_random_uuid(),
    area_key   text not null default 'equipos' references public.areas(key) on delete cascade,
    name       text not null,
    category   text default '',
    quantity   int not null default 1,
    unit_price numeric,
    status     text not null default 'pendiente',   -- pendiente | comprado
    notes      text default '',
    created_at timestamptz not null default now()
);
create index if not exists office_equipment_area_idx on public.office_equipment(area_key);
alter table public.office_equipment enable row level security;
drop policy if exists office_equipment_rw on public.office_equipment;
create policy office_equipment_rw on public.office_equipment for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

-- Migrar la lista de compra anterior (purchase_equipment) al nuevo modelo
do $$
begin
  if to_regclass('public.purchase_equipment') is not null then
    insert into public.equipment_items (area_key, name, quantity, notes, created_at)
    select pe.area_key, pe.name, pe.quantity, pe.notes, pe.created_at
    from public.purchase_equipment pe
    where not exists (
        select 1 from public.equipment_items ei
        where ei.area_key = pe.area_key and ei.name = pe.name
    );
    insert into public.equipment_quotes (area_key, item_id, supplier, price, selected)
    select ei.area_key, ei.id, 'Estimado', pe.price, true
    from public.equipment_items ei
    join public.purchase_equipment pe
      on pe.area_key = ei.area_key and pe.name = ei.name
    where pe.price is not null
      and not exists (select 1 from public.equipment_quotes q where q.item_id = ei.id);
  end if;
end $$;

-- Equipo de oficina sugerido para empezar (idempotente por nombre)
insert into public.office_equipment (area_key, name, category)
select 'equipos', x.name, x.category
from (values
    ('Escritorios', 'Mobiliario'),
    ('Sillas de oficina', 'Mobiliario'),
    ('Sillas de sala de espera', 'Sala de espera'),
    ('Nevera personal', 'Cocina / break room'),
    ('Lockers (vestidor)', 'Locker room'),
    ('Supplies de oficina', 'Suministros')
) as x(name, category)
where not exists (
    select 1 from public.office_equipment oe
    where oe.area_key = 'equipos' and oe.name = x.name
);
