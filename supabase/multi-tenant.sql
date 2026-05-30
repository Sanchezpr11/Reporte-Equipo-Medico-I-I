-- ============================================================================
--  PLATAFORMA MULTI-CLIENTE (multi-tenant) — PASO 1: FUNDACIÓN
--  Convierte la app de "un solo proyecto" a "varios clientes aislados".
--
--  Propiedades:
--    • IDEMPOTENTE: puedes correrlo varias veces sin romper nada.
--    • RETROCOMPATIBLE: al aplicarlo, la app actual de I&I sigue funcionando
--      igual (su data queda asignada al cliente "I&I Realty"), pero ya aislada
--      por cliente vía RLS.
--
--  ⚠️ ANTES DE CORRER:
--    1) Supabase Dashboard -> Database -> Backups: confirma que tienes un
--       respaldo reciente (o crea uno). Este script cambia llaves primarias
--       de 3 tablas de config (irreversible).
--    2) SQL Editor -> New query -> pega TODO -> Run.
--    3) Si algo falla, copia el error y mándamelo; el script es re-ejecutable.
-- ============================================================================

-- UUIDs fijos de los clientes semilla:
--   I&I Realty : 00000000-0000-0000-0000-000000000001
--   Demo       : 00000000-0000-0000-0000-0000000000de

-- ----------------------------------------------------------------------------
-- 1) TABLA DE CLIENTES (inquilinos de la plataforma)
-- ----------------------------------------------------------------------------
create table if not exists public.clients (
    id          uuid primary key default gen_random_uuid(),
    name        text not null,
    slug        text unique,
    status      text not null default 'active',     -- 'active' | 'suspended'
    is_demo     boolean not null default false,
    created_at  timestamptz not null default now()
);
alter table public.clients enable row level security;

-- Semilla: cliente real (I&I) + cliente Demo
insert into public.clients (id, name, slug, is_demo, status) values
    ('00000000-0000-0000-0000-000000000001', 'I&I Realty', 'ii-realty', false, 'active')
on conflict (id) do nothing;
insert into public.clients (id, name, slug, is_demo, status) values
    ('00000000-0000-0000-0000-0000000000de', 'Demo (datos de ejemplo)', 'demo', true, 'active')
on conflict (id) do nothing;

-- ----------------------------------------------------------------------------
-- 2) PROFILES: a qué cliente pertenece cada usuario + flag de super-admin
-- ----------------------------------------------------------------------------
alter table public.profiles add column if not exists client_id uuid references public.clients(id);
alter table public.profiles add column if not exists is_platform_admin boolean not null default false;

-- Usuarios existentes -> I&I (retrocompatibilidad)
update public.profiles set client_id = '00000000-0000-0000-0000-000000000001' where client_id is null;

-- Tu cuenta = Administrador de Plataforma (super-admin por encima de los clientes)
update public.profiles set is_platform_admin = true where lower(email) = 'sanchez.pr@gmail.com';

-- ----------------------------------------------------------------------------
-- 3) FUNCIONES AUXILIARES (SECURITY DEFINER evita recursión de RLS)
-- ----------------------------------------------------------------------------
create or replace function public.current_client_id()
returns uuid language sql security definer set search_path = public stable as $$
    select client_id from public.profiles where id = auth.uid();
$$;

create or replace function public.is_platform_admin()
returns boolean language sql security definer set search_path = public stable as $$
    select coalesce((select is_platform_admin from public.profiles where id = auth.uid()), false);
$$;

-- Estampa client_id en cada INSERT (la app NO necesita enviar client_id)
create or replace function public.stamp_client_id()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    if new.client_id is null then
        new.client_id := public.current_client_id();
    end if;
    return new;
end; $$;

-- ----------------------------------------------------------------------------
-- 4) AÑADIR client_id + TRIGGER + RLS A CADA TABLA DE DATOS
--    Regla RLS de datos:
--      (es super-admin de plataforma)  OR
--      (client_id = mi cliente  AND  tengo acceso al área)
-- ----------------------------------------------------------------------------
do $$
declare
    t text;
    ii constant text := '00000000-0000-0000-0000-000000000001';
    -- Tablas CON area_key  -> aislamiento por cliente + acceso por área
    area_tables text[] := array[
        'tasks','positions','permits','stages','contractors','office_info',
        'office_equipment','office_rooms','bank_product','bank_contacts',
        'bank_documents','finance_estimates','brand_info','purchase_equipment',
        'equipment_items','equipment_quotes'
    ];
    -- Tablas SIN area_key -> aislamiento solo por cliente (todos los del cliente)
    plain_tables text[] := array['pending_tasks','project_settings'];
begin
    -- ---- Tablas con área ----
    foreach t in array area_tables loop
        execute format('alter table public.%I add column if not exists client_id uuid references public.clients(id) default %L', t, ii);
        execute format('update public.%I set client_id = %L where client_id is null', t, ii);
        execute format('drop trigger if exists trg_stamp_client on public.%I', t);
        execute format('create trigger trg_stamp_client before insert on public.%I for each row execute function public.stamp_client_id()', t);
        execute format('drop policy if exists %I on public.%I', t || '_rw', t);
        execute format(
            'create policy %I on public.%I for all '
            || 'using ( public.is_platform_admin() or (client_id = public.current_client_id() and public.has_area(area_key)) ) '
            || 'with check ( public.is_platform_admin() or (client_id = public.current_client_id() and public.has_area(area_key)) )',
            t || '_rw', t);
    end loop;

    -- ---- Tablas sin área (config / global del cliente) ----
    foreach t in array plain_tables loop
        execute format('alter table public.%I add column if not exists client_id uuid references public.clients(id) default %L', t, ii);
        execute format('update public.%I set client_id = %L where client_id is null', t, ii);
        execute format('drop trigger if exists trg_stamp_client on public.%I', t);
        execute format('create trigger trg_stamp_client before insert on public.%I for each row execute function public.stamp_client_id()', t);
        -- quitar políticas previas conocidas (nombres varían) y poner una uniforme
        execute format('drop policy if exists %I on public.%I', t || '_rw', t);
        execute format('drop policy if exists %I on public.%I', t || '_read', t);
        execute format('drop policy if exists %I on public.%I', t || '_write', t);
        execute format('drop policy if exists %I on public.%I', t || '_select', t);
        execute format('drop policy if exists %I on public.%I', t || '_all', t);
        execute format(
            'create policy %I on public.%I for all '
            || 'using ( public.is_platform_admin() or client_id = public.current_client_id() ) '
            || 'with check ( public.is_platform_admin() or client_id = public.current_client_id() )',
            t || '_rw', t);
    end loop;
end $$;

-- ----------------------------------------------------------------------------
-- 5) TABLAS DE CONFIG CON area_key COMO PK -> PK COMPUESTA (client_id, area_key)
--    Necesario para que cada cliente tenga su propia fila por área.
-- ----------------------------------------------------------------------------
do $$
declare t text;
begin
    foreach t in array array['office_info','bank_product','brand_info'] loop
        execute format('alter table public.%I alter column client_id set not null', t);
        execute format('alter table public.%I drop constraint if exists %I', t, t || '_pkey');
        execute format('alter table public.%I add constraint %I primary key (client_id, area_key)', t, t || '_pkey');
    end loop;
end $$;

-- project_settings: PK (key) -> (client_id, key)  (cada cliente su propia config)
alter table public.project_settings alter column client_id set not null;
alter table public.project_settings drop constraint if exists project_settings_pkey;
alter table public.project_settings add constraint project_settings_pkey primary key (client_id, key);

-- ----------------------------------------------------------------------------
-- 5b) app_state (suplidores/equipos legacy, fila única id=1) -> aislar por cliente
-- ----------------------------------------------------------------------------
alter table public.app_state add column if not exists client_id uuid references public.clients(id) default '00000000-0000-0000-0000-000000000001';
update public.app_state set client_id = '00000000-0000-0000-0000-000000000001' where client_id is null;
create unique index if not exists app_state_client_uidx on public.app_state(client_id);
drop trigger if exists trg_stamp_client on public.app_state;
create trigger trg_stamp_client before insert on public.app_state for each row execute function public.stamp_client_id();
drop policy if exists app_state_select on public.app_state;
drop policy if exists app_state_update on public.app_state;
drop policy if exists app_state_insert_admin on public.app_state;
drop policy if exists app_state_rw on public.app_state;
create policy app_state_rw on public.app_state for all
    using ( public.is_platform_admin() or client_id = public.current_client_id() )
    with check ( public.is_platform_admin() or client_id = public.current_client_id() );

-- ----------------------------------------------------------------------------
-- 6) RLS DE LAS TABLAS DE PLATAFORMA / ACCESO
-- ----------------------------------------------------------------------------
-- CLIENTS: el super-admin gestiona todo; cada usuario ve su propio cliente.
drop policy if exists clients_platform_all on public.clients;
create policy clients_platform_all on public.clients
    for all using (public.is_platform_admin()) with check (public.is_platform_admin());

drop policy if exists clients_self_select on public.clients;
create policy clients_self_select on public.clients
    for select using (id = public.current_client_id());

-- PROFILES: cada quien su perfil; admin de cliente ve los de SU cliente;
--           super-admin ve todos.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
    for select using (
        id = auth.uid()
        or public.is_platform_admin()
        or (public.is_admin() and client_id = public.current_client_id())
    );

drop policy if exists profiles_admin_write on public.profiles;
create policy profiles_admin_write on public.profiles
    for all using (
        public.is_platform_admin()
        or (public.is_admin() and client_id = public.current_client_id())
    ) with check (
        public.is_platform_admin()
        or (public.is_admin() and client_id = public.current_client_id())
    );

-- USER_AREA_ACCESS: cada quien ve lo suyo; admin de cliente gestiona su cliente.
drop policy if exists uaa_select on public.user_area_access;
create policy uaa_select on public.user_area_access
    for select using (
        user_id = auth.uid()
        or public.is_platform_admin()
        or (public.is_admin() and exists (
            select 1 from public.profiles p
            where p.id = public.user_area_access.user_id
              and p.client_id = public.current_client_id()))
    );

drop policy if exists uaa_admin_write on public.user_area_access;
create policy uaa_admin_write on public.user_area_access
    for all using (
        public.is_platform_admin()
        or (public.is_admin() and exists (
            select 1 from public.profiles p
            where p.id = public.user_area_access.user_id
              and p.client_id = public.current_client_id()))
    ) with check (
        public.is_platform_admin()
        or (public.is_admin() and exists (
            select 1 from public.profiles p
            where p.id = public.user_area_access.user_id
              and p.client_id = public.current_client_id()))
    );

-- ============================================================================
--  LISTO. Verificación rápida (corre estos SELECT después):
--    select id, name, is_demo from public.clients;
--    select email, is_admin, is_platform_admin, client_id from public.profiles;
--    -- Entra a la app como I&I: debe verse IGUAL que antes (ya aislado).
--  Siguiente: 2) actualizar la Edge Function y 3) publicar la app.
-- ============================================================================
