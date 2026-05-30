-- ============================================================================
--  REORGANIZACIÓN DE ÁREAS
--    - Separa "Equipos de Oficina" como su propia área (key: equipos_oficina)
--    - Elimina el área "Marca"
--    - Reordena el menú: Financiamiento, Local, Equipos Médicos,
--      Equipos de Oficina, Personal, Permisos
--  Idempotente. Supabase -> SQL Editor -> New query -> pegar todo -> Run.
-- ============================================================================

-- 1) Nueva área: Equipos de Oficina (debe existir antes de mover sus filas)
insert into public.areas (key, label, sort_order)
values ('equipos_oficina', 'Equipos de Oficina', 35)
on conflict (key) do update set label = excluded.label, sort_order = excluded.sort_order;

-- 2) Mover el equipo de oficina de "Equipos Médicos" a su nueva área
update public.office_equipment set area_key = 'equipos_oficina' where area_key = 'equipos';

-- 3) Quien tenga acceso a Equipos Médicos, también a Equipos de Oficina
insert into public.user_area_access (user_id, area_key)
select distinct user_id, 'equipos_oficina'
from public.user_area_access
where area_key = 'equipos'
on conflict do nothing;

-- 4) Reordenar el menú (sort_order define el orden en el panel de administración)
update public.areas set sort_order = 0  where key = 'resumen';
update public.areas set sort_order = 10 where key = 'financiamiento';
update public.areas set sort_order = 20 where key = 'local';
update public.areas set sort_order = 30 where key = 'equipos';
update public.areas set sort_order = 35 where key = 'equipos_oficina';
update public.areas set sort_order = 40 where key = 'personal';
update public.areas set sort_order = 50 where key = 'permisos';

-- 5) Eliminar el área "Marca" (el borrado arrastra brand_info y las tareas de
--    marca por las llaves foráneas on delete cascade).
delete from public.areas where key = 'marca';
