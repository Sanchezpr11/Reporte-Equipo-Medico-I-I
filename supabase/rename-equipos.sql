-- ============================================================================
--  RENOMBRAR ÁREA: "Equipos Médicos" -> "Equipos Especializados"
--  El nombre que se muestra en el Resumen (tarjetas) viene de la tabla areas.
--  Idempotente. Supabase -> SQL Editor -> New query -> pegar -> Run.
-- ============================================================================

update public.areas
   set label = 'Equipos Especializados'
 where key = 'equipos';
