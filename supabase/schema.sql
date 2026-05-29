-- ============================================================================
--  CONTROL DE ACCESO MULTI-USUARIO CON PERMISOS POR ÁREA
--  Reporte de Equipo Médico - Puerto Rico
--
--  Cómo usarlo:
--    1. Supabase Dashboard -> SQL Editor -> New query
--    2. Pega TODO este archivo y pulsa "Run".
--  Es idempotente: puedes ejecutarlo varias veces sin romper nada.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) TABLAS
-- ----------------------------------------------------------------------------

-- Un perfil por cada usuario de Supabase Auth. Marca quién es administrador.
create table if not exists public.profiles (
    id          uuid primary key references auth.users(id) on delete cascade,
    email       text,
    full_name   text default '',
    is_admin    boolean not null default false,
    created_at  timestamptz not null default now()
);

-- Catálogo de áreas (secciones) del sitio.
-- Para añadir un área futura: simplemente inserta una fila aquí.
create table if not exists public.areas (
    key         text primary key,
    label       text not null,
    sort_order  int  not null default 0
);

-- Áreas sembradas con las secciones actuales del sitio.
insert into public.areas (key, label, sort_order) values
    ('catalogo',   'Catálogo General',                 1),
    ('analisis',   'Análisis FibroScan vs iLivTouch',  2),
    ('suplidores', 'Directorio de Suplidores',         3)
on conflict (key) do update set label = excluded.label, sort_order = excluded.sort_order;

-- Qué usuario puede acceder a qué área (relación muchos-a-muchos).
create table if not exists public.user_area_access (
    user_id   uuid not null references auth.users(id) on delete cascade,
    area_key  text not null references public.areas(key) on delete cascade,
    primary key (user_id, area_key)
);

-- ----------------------------------------------------------------------------
-- 2) FUNCIÓN AUXILIAR: ¿el usuario actual es administrador?
--    SECURITY DEFINER => evita recursión de RLS al consultar profiles.
-- ----------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
    select coalesce((select p.is_admin from public.profiles p where p.id = auth.uid()), false);
$$;

-- ----------------------------------------------------------------------------
-- 3) TRIGGER: crear un perfil automáticamente cuando nace un usuario de Auth
-- ----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (id, email, full_name)
    values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', ''))
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- Backfill: crea perfiles para usuarios que ya existieran antes de este script.
insert into public.profiles (id, email, full_name)
select u.id, u.email, coalesce(u.raw_user_meta_data->>'full_name', '')
from auth.users u
on conflict (id) do nothing;

-- ----------------------------------------------------------------------------
-- 4) ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------
alter table public.profiles          enable row level security;
alter table public.areas             enable row level security;
alter table public.user_area_access  enable row level security;

-- PROFILES ----------------------------------------------------------------
-- Cada quien lee su propio perfil; los admins leen todos.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
    for select using (id = auth.uid() or public.is_admin());

-- Solo los admins crean/editan/borran perfiles (incluido el flag is_admin).
drop policy if exists profiles_admin_write on public.profiles;
create policy profiles_admin_write on public.profiles
    for all using (public.is_admin()) with check (public.is_admin());

-- AREAS -------------------------------------------------------------------
-- Cualquier usuario autenticado puede leer la lista de áreas.
drop policy if exists areas_select on public.areas;
create policy areas_select on public.areas
    for select using (auth.uid() is not null);

-- Solo los admins gestionan el catálogo de áreas.
drop policy if exists areas_admin_write on public.areas;
create policy areas_admin_write on public.areas
    for all using (public.is_admin()) with check (public.is_admin());

-- USER_AREA_ACCESS --------------------------------------------------------
-- Cada quien ve sus propias áreas; los admins ven todas.
drop policy if exists uaa_select on public.user_area_access;
create policy uaa_select on public.user_area_access
    for select using (user_id = auth.uid() or public.is_admin());

-- Solo los admins asignan/revocan áreas.
drop policy if exists uaa_admin_write on public.user_area_access;
create policy uaa_admin_write on public.user_area_access
    for all using (public.is_admin()) with check (public.is_admin());

-- ----------------------------------------------------------------------------
-- 5) BLINDAR LA TABLA EXISTENTE app_state (datos de suplidores / equipos)
--    Antes era accesible con la llave anónima; ahora exige sesión.
-- ----------------------------------------------------------------------------
alter table public.app_state enable row level security;

-- Leer: cualquier usuario autenticado.
drop policy if exists app_state_select on public.app_state;
create policy app_state_select on public.app_state
    for select using (auth.uid() is not null);

-- Modificar: admins, o usuarios con acceso al área 'suplidores'.
drop policy if exists app_state_update on public.app_state;
create policy app_state_update on public.app_state
    for update using (
        public.is_admin() or exists (
            select 1 from public.user_area_access u
            where u.user_id = auth.uid() and u.area_key = 'suplidores'
        )
    ) with check (
        public.is_admin() or exists (
            select 1 from public.user_area_access u
            where u.user_id = auth.uid() and u.area_key = 'suplidores'
        )
    );

-- Insertar la fila inicial (id = 1) por si aún no existe.
drop policy if exists app_state_insert_admin on public.app_state;
create policy app_state_insert_admin on public.app_state
    for insert with check (public.is_admin());

-- ============================================================================
--  BOOTSTRAP DEL PRIMER ADMINISTRADOR
--  Después de crear tu usuario en Authentication -> Users, ejecuta (1 vez):
--
--    update public.profiles set is_admin = true
--    where email = 'TU-CORREO-ADMIN@ejemplo.com';
--
--  A partir de ahí ese usuario verá el panel de Admin y podrá crear el resto.
-- ============================================================================
