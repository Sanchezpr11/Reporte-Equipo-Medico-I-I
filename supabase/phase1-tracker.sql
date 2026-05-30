-- ============================================================================
--  FASE 1 — CIMIENTOS DEL SEGUIMIENTO DE PROYECTO
--  Añade las áreas del proyecto y una tabla genérica de TAREAS (checklist)
--  reutilizable por cualquier área. Versión "simple": título, estado,
--  responsable y notas. (Presupuesto y documentos se añadirán después.)
--
--  Cómo usarlo: Supabase -> SQL Editor -> New query -> pegar todo -> Run.
--  Es idempotente (se puede correr varias veces).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) NUEVAS ÁREAS DEL PROYECTO  (+ reordenar las de equipos médicos)
-- ----------------------------------------------------------------------------
insert into public.areas (key, label, sort_order) values
    ('resumen',        'Resumen',                 0),
    ('local',          'Local / Oficina',        10),
    ('remodelacion',   'Remodelación',           20),
    ('financiamiento', 'Financiamiento',         30),
    ('personal',       'Personal',               50),
    ('marca',          'Marca',                  60),
    ('permisos',       'Permisos y Credenciales',70)
on conflict (key) do update set label = excluded.label, sort_order = excluded.sort_order;

-- Reordenar las áreas de equipos para que queden en medio del flujo.
update public.areas set sort_order = 40 where key = 'catalogo';
update public.areas set sort_order = 41 where key = 'analisis';
update public.areas set sort_order = 42 where key = 'suplidores';

-- ----------------------------------------------------------------------------
-- 2) TABLA GENÉRICA DE TAREAS (una fila por tarea, etiquetada por área)
-- ----------------------------------------------------------------------------
create table if not exists public.tasks (
    id          uuid primary key default gen_random_uuid(),
    area_key    text not null references public.areas(key) on delete cascade,
    title       text not null,
    status      text not null default 'pendiente',   -- pendiente | en_progreso | hecho
    assignee    text default '',
    notes       text default '',
    sort_order  int  not null default 0,
    created_at  timestamptz not null default now()
);

create index if not exists tasks_area_idx on public.tasks (area_key);

-- ----------------------------------------------------------------------------
-- 3) ¿El usuario actual tiene acceso a un área? (admin o acceso concedido)
--    SECURITY DEFINER para evitar problemas de RLS al consultar.
-- ----------------------------------------------------------------------------
create or replace function public.has_area(area text)
returns boolean
language sql
security definer
set search_path = public
as $$
    select public.is_admin() or exists (
        select 1 from public.user_area_access u
        where u.user_id = auth.uid() and u.area_key = area
    );
$$;

-- ----------------------------------------------------------------------------
-- 4) RLS: puedes ver y gestionar las tareas de las áreas a las que tienes acceso
-- ----------------------------------------------------------------------------
alter table public.tasks enable row level security;

drop policy if exists tasks_rw on public.tasks;
create policy tasks_rw on public.tasks
    for all
    using (public.has_area(area_key))
    with check (public.has_area(area_key));
