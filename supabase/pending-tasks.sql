-- ============================================================================
--  PENDIENTES — lista de tareas genérica del equipo (no atada a un área)
--  Muestra quién lo añadió y cuándo; se puede marcar como realizado.
--  Visible para todos los usuarios con sesión.
--  Idempotente. Supabase -> SQL Editor -> New query -> pegar -> Run.
-- ============================================================================

create table if not exists public.pending_tasks (
    id              uuid primary key default gen_random_uuid(),
    title           text not null,
    status          text not null default 'pendiente',   -- pendiente | hecho
    created_by      uuid references auth.users(id) on delete set null,
    created_by_name text default '',
    created_at      timestamptz not null default now(),
    done_at         timestamptz
);

alter table public.pending_tasks enable row level security;

-- Todos los usuarios con sesión ven la lista (es del equipo)
drop policy if exists pending_tasks_select on public.pending_tasks;
create policy pending_tasks_select on public.pending_tasks
    for select to authenticated using (true);

-- Cada quien crea sus propios pendientes (queda registrado quién)
drop policy if exists pending_tasks_insert on public.pending_tasks;
create policy pending_tasks_insert on public.pending_tasks
    for insert to authenticated with check (created_by = auth.uid());

-- Cualquiera del equipo puede marcar/desmarcar como realizado
drop policy if exists pending_tasks_update on public.pending_tasks;
create policy pending_tasks_update on public.pending_tasks
    for update to authenticated using (true) with check (true);

-- Eliminar: solo quien lo creó o un administrador
drop policy if exists pending_tasks_delete on public.pending_tasks;
create policy pending_tasks_delete on public.pending_tasks
    for delete to authenticated using (
        created_by = auth.uid()
        or exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
    );
