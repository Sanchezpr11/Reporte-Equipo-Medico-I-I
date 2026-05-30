-- ============================================================================
--  REVERTIR MULTI-CLIENTE  (volver a un solo proyecto)
--  Deshace los cambios de multi-client.sql en la base de datos:
--   - quita la restricción única (client_id, key)
--   - deduplica project_settings por 'key'
--   - elimina la columna client_id
--   - restaura la PRIMARY KEY en 'key' (para que el guardado por key funcione)
--   - elimina la tabla clients
--  Idempotente y seguro. Supabase -> SQL Editor -> New query -> pegar TODO -> Run.
-- ============================================================================

-- 1) Quitar la restricción compuesta de multi-cliente (si existe).
alter table public.project_settings drop constraint if exists project_settings_client_key cascade;

-- 2) Deduplicar por 'key' (conserva una fila por clave; red de seguridad).
delete from public.project_settings a
using public.project_settings b
where a.ctid < b.ctid and a.key = b.key;

-- 3) Eliminar la columna client_id (ya no se usa).
alter table public.project_settings drop column if exists client_id;

-- 4) Garantizar una llave única/PK en 'key' (necesaria para upsert onConflict:'key').
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
    alter table public.project_settings add constraint project_settings_pkey primary key (key);
  end if;
end $$;

-- 5) Eliminar la tabla clients (descartamos el multi-cliente).
drop table if exists public.clients cascade;
