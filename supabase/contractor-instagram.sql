-- Instagram del contratista (Local · Fase 1)
-- Idempotente. Supabase -> SQL Editor -> New query -> pegar -> Run.
alter table public.contractors add column if not exists instagram text default '';
