-- ============================================================================
--  AGRUPAR "EQUIPOS MÉDICOS"
--  Une Catálogo, Análisis y Suplidores en una sola área: "Equipos Médicos"
--  (key: equipos). Migra los accesos existentes y elimina las 3 áreas sueltas.
--  Idempotente.
--
--  Supabase -> SQL Editor -> New query -> pegar todo -> Run.
-- ============================================================================

-- 1) Crear el área agrupada
insert into public.areas (key, label, sort_order)
values ('equipos', 'Equipos Médicos', 40)
on conflict (key) do update set label = excluded.label, sort_order = excluded.sort_order;

-- 2) Migrar accesos: quien tuviera acceso a cualquiera de las 3 áreas viejas
--    ahora tiene acceso a 'equipos'.
insert into public.user_area_access (user_id, area_key)
select distinct user_id, 'equipos'
from public.user_area_access
where area_key in ('catalogo', 'analisis', 'suplidores')
on conflict do nothing;

-- 3) Eliminar las 3 áreas sueltas (el borrado arrastra sus accesos por cascade).
delete from public.areas where key in ('catalogo', 'analisis', 'suplidores');
