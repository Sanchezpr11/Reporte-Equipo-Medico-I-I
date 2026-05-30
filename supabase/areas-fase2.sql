-- ============================================================================
--  ÁREAS: Financiamiento, Personal, Permisos y Marca
--    funding_sources + expenses (Financiamiento)
--    positions (Personal) | permits (Permisos) | brand_info (Marca)
--    Marca reutiliza la tabla 'tasks' (checklist) y el bucket de media.
--  Idempotente. Supabase -> SQL Editor -> New query -> pegar todo -> Run.
-- ============================================================================

-- ---------- FINANCIAMIENTO: fuentes de fondos ----------
create table if not exists public.funding_sources (
    id         uuid primary key default gen_random_uuid(),
    area_key   text not null default 'financiamiento' references public.areas(key) on delete cascade,
    name       text not null,
    type       text not null default 'otro',        -- prestamo | inversion | ahorro | otro
    amount     numeric,
    status     text not null default 'proyectado',  -- proyectado | confirmado | recibido
    notes      text default '',
    created_at timestamptz not null default now()
);
create index if not exists funding_area_idx on public.funding_sources(area_key);
alter table public.funding_sources enable row level security;
drop policy if exists funding_rw on public.funding_sources;
create policy funding_rw on public.funding_sources for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

-- ---------- FINANCIAMIENTO: gastos ----------
create table if not exists public.expenses (
    id         uuid primary key default gen_random_uuid(),
    area_key   text not null default 'financiamiento' references public.areas(key) on delete cascade,
    concept    text not null,
    category   text default '',
    estimated  numeric,
    actual     numeric,
    status     text not null default 'pendiente',   -- pendiente | pagado
    notes      text default '',
    created_at timestamptz not null default now()
);
create index if not exists expenses_area_idx on public.expenses(area_key);
alter table public.expenses enable row level security;
drop policy if exists expenses_rw on public.expenses;
create policy expenses_rw on public.expenses for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

-- ---------- PERSONAL: puestos ----------
create table if not exists public.positions (
    id         uuid primary key default gen_random_uuid(),
    area_key   text not null default 'personal' references public.areas(key) on delete cascade,
    title      text not null,
    status     text not null default 'por_abrir',   -- por_abrir | abierto | entrevistando | contratado
    candidate  text default '',
    salary     numeric,
    start_date date,
    notes      text default '',
    created_at timestamptz not null default now()
);
create index if not exists positions_area_idx on public.positions(area_key);
alter table public.positions enable row level security;
drop policy if exists positions_rw on public.positions;
create policy positions_rw on public.positions for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

-- ---------- PERMISOS: licencias y credenciales ----------
create table if not exists public.permits (
    id          uuid primary key default gen_random_uuid(),
    area_key    text not null default 'permisos' references public.areas(key) on delete cascade,
    name        text not null,
    type        text default '',
    status      text not null default 'pendiente',  -- pendiente | en_tramite | obtenido | vencido
    issued_date date,
    expiry_date date,
    responsible text default '',
    notes       text default '',
    created_at  timestamptz not null default now()
);
create index if not exists permits_area_idx on public.permits(area_key);
alter table public.permits enable row level security;
drop policy if exists permits_rw on public.permits;
create policy permits_rw on public.permits for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

-- ---------- MARCA: identidad (una fila) ----------
create table if not exists public.brand_info (
    area_key   text primary key references public.areas(key) on delete cascade,
    name       text default '',
    slogan     text default '',
    colors     text default '',
    website    text default '',
    social     text default '',
    notes      text default '',
    updated_at timestamptz not null default now()
);
alter table public.brand_info enable row level security;
drop policy if exists brand_info_rw on public.brand_info;
create policy brand_info_rw on public.brand_info for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));
