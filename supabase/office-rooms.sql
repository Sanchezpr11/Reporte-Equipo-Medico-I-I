-- ============================================================================
--  EQUIPOS DE OFICINA POR CUARTO (a partir del plano)
--    office_rooms        -> cuartos del plano (Recepción, Consultorio 1, ...)
--    office_equipment.room_id -> a qué cuarto pertenece cada artículo
--  El plano (imagen) se sube al bucket de media bajo la carpeta equipos_oficina/.
--  Idempotente. Supabase -> SQL Editor -> New query -> pegar -> Run.
-- ============================================================================

create table if not exists public.office_rooms (
    id         uuid primary key default gen_random_uuid(),
    area_key   text not null default 'equipos_oficina' references public.areas(key) on delete cascade,
    name       text not null,
    sort_order int  not null default 0,
    notes      text default '',
    created_at timestamptz not null default now()
);
create index if not exists office_rooms_area_idx on public.office_rooms(area_key);
alter table public.office_rooms enable row level security;
drop policy if exists office_rooms_rw on public.office_rooms;
create policy office_rooms_rw on public.office_rooms for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

-- Asociar cada artículo a un cuarto (si se borra el cuarto, queda sin asignar)
alter table public.office_equipment
    add column if not exists room_id uuid references public.office_rooms(id) on delete set null;

-- ----------------------------------------------------------------------------
-- Ajustes del proyecto (clave/valor) — p.ej. fecha de apertura (countdown)
-- ----------------------------------------------------------------------------
create table if not exists public.project_settings (
    key        text primary key,
    value      text,
    updated_at timestamptz not null default now()
);
alter table public.project_settings enable row level security;
drop policy if exists project_settings_read on public.project_settings;
create policy project_settings_read on public.project_settings
    for select to authenticated using (true);
drop policy if exists project_settings_write on public.project_settings;
create policy project_settings_write on public.project_settings
    for all to authenticated
    using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
    with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

-- ----------------------------------------------------------------------------
-- Posición / cargo en los contactos del banco
-- ----------------------------------------------------------------------------
alter table public.bank_contacts add column if not exists position text default '';
