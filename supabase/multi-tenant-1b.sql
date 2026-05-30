-- ============================================================================
--  PASO 1b — Arreglo: finance_estimates debe incluir client_id en su PK
--  (En el paso 1 quedó con PK (area_key, item_key); sin client_id, dos clientes
--   colisionarían en la misma estimación. Esto lo corrige.)
--  Idempotente. Corre en: Supabase -> SQL Editor -> pega -> Run.
-- ============================================================================

alter table public.finance_estimates alter column client_id set not null;
alter table public.finance_estimates drop constraint if exists finance_estimates_pkey;
alter table public.finance_estimates add constraint finance_estimates_pkey
    primary key (client_id, area_key, item_key);

-- Verifica:  select conname from pg_constraint where conrelid = 'public.finance_estimates'::regclass;
