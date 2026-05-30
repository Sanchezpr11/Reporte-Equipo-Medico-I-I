-- ============================================================================
--  DOCUMENTOS DEL BANCO POR MIEMBRO (Dra. Hernández y Dra. Arroyo)
--  Desdobla "Estado de condición financiera de los Miembros" en documentos
--  individuales por doctora: estado de condición financiera + planillas
--  personales (últimos 2 años).
--  Idempotente. Supabase -> SQL Editor -> New query -> pegar -> Run.
-- ============================================================================

-- 1) Añadir los 4 documentos por miembro (idempotente por doc_key)
insert into public.bank_documents (area_key, doc_key, name, description, ord)
select x.area_key, x.doc_key, x.name, x.description, x.ord
from (values
    ('financiamiento', 'estado_fin_hernandez', 'Estado de condición financiera — Dra. Hernández',
     'Estado reciente (incluye modelo a utilizar).', 40),
    ('financiamiento', 'planillas_hernandez',  'Planillas personales (últimos 2 años) — Dra. Hernández',
     'Últimas dos planillas de contribución sobre ingresos.', 41),
    ('financiamiento', 'estado_fin_arroyo',    'Estado de condición financiera — Dra. Arroyo',
     'Estado reciente (incluye modelo a utilizar).', 42),
    ('financiamiento', 'planillas_arroyo',     'Planillas personales (últimos 2 años) — Dra. Arroyo',
     'Últimas dos planillas de contribución sobre ingresos.', 43)
) as x(area_key, doc_key, name, description, ord)
where not exists (
    select 1 from public.bank_documents b
    where b.area_key = x.area_key and b.doc_key = x.doc_key
);

-- 2) Eliminar el documento genérico anterior (si nunca se le subieron archivos,
--    los archivos viven en Storage por id; este borrado solo quita el renglón).
delete from public.bank_documents
where area_key = 'financiamiento' and doc_key = 'estado_financiero';
