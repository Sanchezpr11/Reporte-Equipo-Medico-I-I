-- ============================================================================
--  IDENTIDAD DEL PROYECTO (nombre, descripción, logo)
--  Usa project_settings (keys: project_name, project_desc, project_logo).
--  Autosuficiente: crea la tabla si no existe, configura RLS (lectura pública,
--  escritura solo-admin) y siembra los valores de I&I Realty.
--  Idempotente. Supabase -> SQL Editor -> New query -> pegar todo -> Run.
-- ============================================================================

-- 1) Tabla (clave/valor). La PRIMARY KEY en 'key' es lo que necesita ON CONFLICT.
create table if not exists public.project_settings (
    key        text primary key,
    value      text,
    updated_at timestamptz not null default now()
);

alter table public.project_settings enable row level security;

-- 2) Lectura PÚBLICA (anon + autenticados) — para personalizar el login/favicon
--    antes de iniciar sesión.
drop policy if exists project_settings_read on public.project_settings;
create policy project_settings_read on public.project_settings
    for select using (true);

-- 3) Escritura solo para administradores.
drop policy if exists project_settings_write on public.project_settings;
create policy project_settings_write on public.project_settings
    for all to authenticated
    using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
    with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

-- 4) Sembrar valores iniciales para I&I Realty si aún no existen.
insert into public.project_settings (key, value)
values
    ('project_name', 'I&I Realty'),
    ('project_desc', 'Clínica de Endocrinología · Santurce, Puerto Rico')
on conflict (key) do nothing;
