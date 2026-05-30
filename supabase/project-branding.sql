-- ============================================================================
--  IDENTIDAD DEL PROYECTO (nombre, descripción, logo)
--  Usa project_settings (keys: project_name, project_desc, project_logo).
--  A PRUEBA DE 42P10: el seed NO usa ON CONFLICT (no depende de restricciones).
--  Aun así repara/garantiza la restricción única en 'key' que necesita el
--  guardado (upsert) desde el panel de Admin.
--  Idempotente. Supabase -> SQL Editor -> New query -> pegar TODO -> Run.
-- ============================================================================

-- 1) Crear la tabla si no existe.
create table if not exists public.project_settings (
    key        text primary key,
    value      text,
    updated_at timestamptz not null default now()
);

-- 2) Asegurar columnas (por si la tabla existía con otra forma).
alter table public.project_settings add column if not exists value text;
alter table public.project_settings add column if not exists updated_at timestamptz not null default now();

-- 3) Garantizar restricción única en 'key' (para que el upsert de Admin funcione).
--    Si no hay PK ni UNIQUE, deduplica y la añade.
do $$
begin
  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public' and t.relname = 'project_settings'
      and c.contype in ('p','u')
  ) then
    delete from public.project_settings a
    using public.project_settings b
    where a.ctid < b.ctid and a.key = b.key;

    alter table public.project_settings
      add constraint project_settings_key_key unique (key);
  end if;
end $$;

-- 4) RLS: lectura pública, escritura solo-admin.
alter table public.project_settings enable row level security;

drop policy if exists project_settings_read on public.project_settings;
create policy project_settings_read on public.project_settings
    for select using (true);

drop policy if exists project_settings_write on public.project_settings;
create policy project_settings_write on public.project_settings
    for all to authenticated
    using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
    with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

-- 5) Sembrar valores de I&I Realty SIN ON CONFLICT (no requiere restricción).
insert into public.project_settings (key, value)
select 'project_name', 'I&I Realty'
where not exists (select 1 from public.project_settings where key = 'project_name');

insert into public.project_settings (key, value)
select 'project_desc', 'Clínica de Endocrinología · Santurce, Puerto Rico'
where not exists (select 1 from public.project_settings where key = 'project_desc');
