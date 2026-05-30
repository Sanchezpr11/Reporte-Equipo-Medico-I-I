-- ============================================================================
--  IDENTIDAD DEL PROYECTO (nombre, descripción, logo)
--  Reutiliza project_settings (keys: project_name, project_desc, project_logo).
--  Hace la lectura PÚBLICA para que el nombre/descr./favicon se apliquen
--  también en la pantalla de login (antes de iniciar sesión).
--  La escritura sigue siendo solo de administradores.
--  Idempotente. Supabase -> SQL Editor -> New query -> pegar -> Run.
-- ============================================================================

-- Lectura pública (anon + autenticados)
drop policy if exists project_settings_read on public.project_settings;
create policy project_settings_read on public.project_settings
    for select using (true);

-- (La escritura solo-admin ya existe como project_settings_write; no se toca.)

-- Sembrar valores iniciales para I&I Realty si aún no existen
insert into public.project_settings (key, value)
values
    ('project_name', 'I&I Realty'),
    ('project_desc', 'Clínica de Endocrinología · Santurce, Puerto Rico')
on conflict (key) do nothing;
