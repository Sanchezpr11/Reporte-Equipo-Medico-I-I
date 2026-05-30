-- ============================================================================
--  ÁREA LOCAL / OFICINA — por fases
--    Información de la oficina | Fase 1: contratistas | Fase 2: etapas de obra
--    + elimina el área 'remodelacion' (ahora todo vive en 'local')
--  Idempotente. Supabase -> SQL Editor -> New query -> pegar todo -> Run.
-- ============================================================================

-- 1) Información de la oficina (una fila por área)
create table if not exists public.office_info (
    area_key   text primary key references public.areas(key) on delete cascade,
    address    text default '',
    size       text default '',
    price      text default '',
    status     text default '',
    notes      text default '',
    updated_at timestamptz not null default now()
);
alter table public.office_info enable row level security;
drop policy if exists office_info_rw on public.office_info;
create policy office_info_rw on public.office_info for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

insert into public.office_info (area_key, status)
values ('local', 'Opción de compra realizada')
on conflict (area_key) do nothing;

-- 2) Fase 1: contratistas y cotizaciones
create table if not exists public.contractors (
    id           uuid primary key default gen_random_uuid(),
    area_key     text not null default 'local' references public.areas(key) on delete cascade,
    name         text not null,
    quote_amount numeric,
    contact      text default '',
    lead_time    text default '',
    status       text not null default 'pendiente',  -- pendiente | cotizado | seleccionado | descartado
    notes        text default '',
    created_at   timestamptz not null default now()
);
create index if not exists contractors_area_idx on public.contractors(area_key);
alter table public.contractors enable row level security;
drop policy if exists contractors_rw on public.contractors;
create policy contractors_rw on public.contractors for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

-- 3) Fase 2: etapas de obra
create table if not exists public.stages (
    id          uuid primary key default gen_random_uuid(),
    area_key    text not null default 'local' references public.areas(key) on delete cascade,
    name        text not null,
    status      text not null default 'pendiente',  -- pendiente | en_progreso | hecho
    progress    int  not null default 0,            -- 0..100
    start_date  date,
    end_date    date,
    sort_order  int  not null default 0,
    notes       text default '',
    created_at  timestamptz not null default now()
);
create index if not exists stages_area_idx on public.stages(area_key);
alter table public.stages enable row level security;
drop policy if exists stages_rw on public.stages;
create policy stages_rw on public.stages for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

-- 4) Quitar el área 'remodelacion' (fusionada en 'local')
delete from public.areas where key = 'remodelacion';
