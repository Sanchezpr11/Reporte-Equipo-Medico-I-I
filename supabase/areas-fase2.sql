-- ============================================================================
--  ÁREAS: Financiamiento, Personal, Permisos y Marca
--    Financiamiento (banco): bank_product + bank_contacts + bank_documents
--                            + finance_estimates (ajustes del total a solicitar)
--    Personal: positions (salary = compensación ANUAL)
--    Permisos: permits (incluye costo, para nutrir el total a solicitar)
--    Marca: brand_info  (+ reutiliza 'tasks' y el bucket de media)
--  Idempotente. Supabase -> SQL Editor -> New query -> pegar todo -> Run.
-- ============================================================================

-- ---------- FINANCIAMIENTO: producto financiero del banco (una fila) ----------
create table if not exists public.bank_product (
    area_key   text primary key references public.areas(key) on delete cascade,
    bank       text default '',
    product    text default '',
    rate       text default '',
    term       text default '',
    notes      text default '',
    updated_at timestamptz not null default now()
);
alter table public.bank_product enable row level security;
drop policy if exists bank_product_rw on public.bank_product;
create policy bank_product_rw on public.bank_product for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

-- ---------- FINANCIAMIENTO: contactos del banco ----------
create table if not exists public.bank_contacts (
    id         uuid primary key default gen_random_uuid(),
    area_key   text not null default 'financiamiento' references public.areas(key) on delete cascade,
    name       text not null,
    phone      text default '',
    email      text default '',
    notes      text default '',
    created_at timestamptz not null default now()
);
create index if not exists bank_contacts_area_idx on public.bank_contacts(area_key);
alter table public.bank_contacts enable row level security;
drop policy if exists bank_contacts_rw on public.bank_contacts;
create policy bank_contacts_rw on public.bank_contacts for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

-- ---------- FINANCIAMIENTO: documentos solicitados (con archivos adjuntos) ----------
create table if not exists public.bank_documents (
    id          uuid primary key default gen_random_uuid(),
    area_key    text not null default 'financiamiento' references public.areas(key) on delete cascade,
    doc_key     text,                                 -- clave de doc predefinido (null = personalizado)
    name        text not null,
    description text default '',
    status      text not null default 'pendiente',   -- pendiente | entregado
    notes       text default '',
    ord         int  not null default 100,
    created_at  timestamptz not null default now()
);
create index if not exists bank_documents_area_idx on public.bank_documents(area_key);
alter table public.bank_documents enable row level security;
drop policy if exists bank_documents_rw on public.bank_documents;
create policy bank_documents_rw on public.bank_documents for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

-- Documentos que solicita el banco (predefinidos, idempotente por doc_key)
insert into public.bank_documents (area_key, doc_key, name, description, ord)
select x.area_key, x.doc_key, x.name, x.description, x.ord
from (values
    ('financiamiento', 'costo_total',       'Costo total del proyecto',
     'Cotizaciones, facturas u otros documentos que sustenten el monto del financiamiento. Se nutre de Equipos y Remodelación.', 1),
    ('financiamiento', 'proyecciones',      '3 años de proyecciones con supuestos',
     'Del Real Estate company y de la operación.', 2),
    ('financiamiento', 'business_plan',     'Business plan',
     '', 3),
    ('financiamiento', 'estado_financiero', 'Estado de condición financiera de los Miembros',
     'Estado reciente (incluye modelo a utilizar) + últimas dos planillas de contribución sobre ingresos.', 4),
    ('financiamiento', 'contrato_opcion',   'Copia del Contrato de Opción Compraventa firmado',
     'Una vez esté disponible.', 5)
) as x(area_key, doc_key, name, description, ord)
where not exists (
    select 1 from public.bank_documents b
    where b.area_key = x.area_key and b.doc_key = x.doc_key
);

-- ---------- FINANCIAMIENTO: ajustes manuales del total a solicitar ----------
-- (Si un renglón no tiene ajuste, se usa el estimado calculado desde su área.)
create table if not exists public.finance_estimates (
    area_key text not null default 'financiamiento' references public.areas(key) on delete cascade,
    item_key text not null,                          -- local | remodelacion | equipos | permisos | nomina | operacional
    amount   numeric,
    primary key (area_key, item_key)
);
alter table public.finance_estimates enable row level security;
drop policy if exists finance_estimates_rw on public.finance_estimates;
create policy finance_estimates_rw on public.finance_estimates for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

-- ---------- PERSONAL: puestos (salary = compensación anual) ----------
create table if not exists public.positions (
    id         uuid primary key default gen_random_uuid(),
    area_key   text not null default 'personal' references public.areas(key) on delete cascade,
    title      text not null,
    status     text not null default 'por_abrir',   -- por_abrir | abierto | entrevistando | contratado
    candidate  text default '',
    salary     numeric,                              -- compensación ANUAL
    start_date date,
    notes      text default '',
    created_at timestamptz not null default now()
);
create index if not exists positions_area_idx on public.positions(area_key);
alter table public.positions enable row level security;
drop policy if exists positions_rw on public.positions;
create policy positions_rw on public.positions for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

-- ---------- PERMISOS: licencias y credenciales (con costo) ----------
create table if not exists public.permits (
    id          uuid primary key default gen_random_uuid(),
    area_key    text not null default 'permisos' references public.areas(key) on delete cascade,
    name        text not null,
    type        text default '',
    status      text not null default 'pendiente',  -- pendiente | en_tramite | obtenido | vencido
    cost        numeric,
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
    area_key         text primary key references public.areas(key) on delete cascade,
    name             text default '',
    slogan           text default '',
    colors           text default '',
    website          text default '',
    social           text default '',
    marketing_budget numeric,                       -- presupuesto de mercadeo (va al financiamiento)
    notes            text default '',
    updated_at       timestamptz not null default now()
);
alter table public.brand_info enable row level security;
drop policy if exists brand_info_rw on public.brand_info;
create policy brand_info_rw on public.brand_info for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

-- ---------- EQUIPOS: lista de equipos escogidos para comprar ----------
create table if not exists public.purchase_equipment (
    id         uuid primary key default gen_random_uuid(),
    area_key   text not null default 'equipos' references public.areas(key) on delete cascade,
    name       text not null,
    price      numeric,
    quantity   int not null default 1,
    notes      text default '',
    created_at timestamptz not null default now()
);
create index if not exists purchase_equipment_area_idx on public.purchase_equipment(area_key);
alter table public.purchase_equipment enable row level security;
drop policy if exists purchase_equipment_rw on public.purchase_equipment;
create policy purchase_equipment_rw on public.purchase_equipment for all
    using (public.has_area(area_key)) with check (public.has_area(area_key));

-- ---------- LOCAL: precio de compra del local (numérico, va al financiamiento) ----------
-- (office_info se creó en area-local.sql; aquí solo añadimos la columna.)
alter table public.office_info add column if not exists purchase_price numeric;
