-- ============================================================================
--  IDENTIDAD DEL PROYECTO (nombre, descripción, logo)
--  Usa project_settings (keys: project_name, project_desc, project_logo).
--  ROBUSTO: crea la tabla si no existe, y si ya existía SIN llave primaria en
--  'key' (causa del error 42P10 "no unique constraint matching ON CONFLICT"),
--  la repara. Configura RLS (lectura pública, escritura admin) y siembra datos.
--  Idempotente. Supabase -> SQL Editor -> New query -> pegar todo -> Run.
-- ============================================================================

-- 1) Crear la tabla si no existe (con PK en key).
create table if not exists public.project_settings (
    key        text primary key,
    value      text,
    updated_at timestamptz not null default now()
);

-- 2) Asegurar columnas (por si la tabla existía con otra forma).
alter table public.project_settings add column if not exists value text;
alter table public.project_settings add column if not exists updated_at timestamptz not null default now();

-- 3) Asegurar una restricción única/PK en 'key' (necesaria para ON CONFLICT y upsert).
--    Si no hay ninguna, elimina posibles duplicados y la añade.
do $$
begin
  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'project_settings'
      and c.contype in ('p', 'u')
  ) then
    delete from public.project_settings a
    using public.project_settings b
    where a.ctid < b.ctid and a.key = b.key;

    alter table public.project_settings
      add constraint project_settings_key_key unique (key);
  end if;
end $$;

-- 4) RLS.
alter table public.project_settings enable row level security;

-- Lectura PÚBLICA (anon + autenticados) — personaliza login/favicon antes del login.
drop policy if exists project_settings_read on public.project_settings;
create policy project_settings_read on public.project_settings
    for select using (true);

-- Escritura solo administradores.
drop policy if exists project_settings_write on public.project_settings;
create policy project_settings_write on public.project_settings
    for all to authenticated
    using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
    with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

-- 5) Sembrar valores iniciales para I&I Realty si aún no existen.
insert into public.project_settings (key, value)
values
    ('project_name', 'I&I Realty'),
    ('project_desc', 'Clínica de Endocrinología · Santurce, Puerto Rico')
on conflict (key) do nothing;
