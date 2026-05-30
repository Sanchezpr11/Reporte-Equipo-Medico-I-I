-- ============================================================================
--  DEMO + CONMUTADOR DE CLIENTE  (multi-tenant — switcher para super-admin)
--
--  PARTE A: Conmutador de cliente
--    - profiles.active_client_id: el cliente "activo" del super-admin.
--    - current_client_id() = coalesce(active_client_id, client_id).
--    - set_active_client(uuid): el super-admin cambia su cliente activo.
--    - RLS de datos: cada quien (incl. super-admin) ve SOLO su cliente activo,
--      evitando que el super-admin vea I&I y Demo mezclados. El poder de
--      plataforma (gestionar clientes/usuarios) se mantiene aparte.
--
--  PARTE B: Datos de ejemplo en el cliente Demo (clínica genérica).
--
--  Idempotente. Supabase -> SQL Editor -> pega TODO -> Run.
-- ============================================================================

-- ════════════════════════════════════════════════════════════════════════
--  PARTE A — CONMUTADOR
-- ════════════════════════════════════════════════════════════════════════

alter table public.profiles add column if not exists active_client_id uuid references public.clients(id);

-- current_client_id ahora respeta el cliente activo (si lo hay)
create or replace function public.current_client_id()
returns uuid language sql security definer set search_path = public stable as $$
    select coalesce(active_client_id, client_id) from public.profiles where id = auth.uid();
$$;

-- Cambiar de cliente activo (solo super-admin). null = volver a su cliente base.
create or replace function public.set_active_client(target uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
    if not public.is_platform_admin() then
        raise exception 'Solo el administrador de plataforma puede cambiar de cliente.';
    end if;
    if target is not null and not exists (select 1 from public.clients where id = target) then
        raise exception 'Cliente inexistente.';
    end if;
    update public.profiles set active_client_id = target where id = auth.uid();
end; $$;

-- RLS de DATOS: scoped al cliente activo (super-admin incluido).
--   - Tablas con área: cliente activo + (super-admin ve todas las áreas, o has_area).
--   - Tablas sin área: cliente activo.
do $$
declare
    t text;
    area_tables text[] := array[
        'tasks','positions','permits','stages','contractors','office_info',
        'office_equipment','office_rooms','bank_product','bank_contacts',
        'bank_documents','finance_estimates','brand_info','purchase_equipment',
        'equipment_items','equipment_quotes'
    ];
    plain_tables text[] := array['pending_tasks','project_settings'];
begin
    foreach t in array area_tables loop
        execute format('drop policy if exists %I on public.%I', t || '_rw', t);
        execute format(
            'create policy %I on public.%I for all '
            || 'using ( client_id = public.current_client_id() and ( public.is_platform_admin() or public.has_area(area_key) ) ) '
            || 'with check ( client_id = public.current_client_id() and ( public.is_platform_admin() or public.has_area(area_key) ) )',
            t || '_rw', t);
    end loop;
    foreach t in array plain_tables loop
        execute format('drop policy if exists %I on public.%I', t || '_rw', t);
        execute format(
            'create policy %I on public.%I for all '
            || 'using ( client_id = public.current_client_id() ) '
            || 'with check ( client_id = public.current_client_id() )',
            t || '_rw', t);
    end loop;
end $$;

-- app_state igual (scoped al cliente activo)
drop policy if exists app_state_rw on public.app_state;
create policy app_state_rw on public.app_state for all
    using ( client_id = public.current_client_id() )
    with check ( client_id = public.current_client_id() );

-- ════════════════════════════════════════════════════════════════════════
--  PARTE B — SEED DEL CLIENTE DEMO
--    Demo client_id = 00000000-0000-0000-0000-0000000000de
--    Re-ejecutable: borra lo previo del Demo y reinserta.
-- ════════════════════════════════════════════════════════════════════════
do $$
declare d constant uuid := '00000000-0000-0000-0000-0000000000de';
begin
    -- Limpieza previa (solo filas del Demo)
    delete from public.tasks               where client_id = d;
    delete from public.positions           where client_id = d;
    delete from public.permits             where client_id = d;
    delete from public.stages              where client_id = d;
    delete from public.contractors         where client_id = d;
    delete from public.office_equipment    where client_id = d;
    delete from public.office_rooms        where client_id = d;
    delete from public.bank_contacts       where client_id = d;
    delete from public.bank_documents      where client_id = d;
    delete from public.finance_estimates   where client_id = d;
    delete from public.purchase_equipment  where client_id = d;
    delete from public.pending_tasks       where client_id = d;
    delete from public.office_info         where client_id = d;
    delete from public.bank_product        where client_id = d;
    delete from public.brand_info          where client_id = d;
    delete from public.project_settings    where client_id = d;

    -- Apertura (countdown)
    insert into public.project_settings (client_id, key, value)
        values (d, 'opening_date', to_char(now() + interval '120 days', 'YYYY-MM-DD'));

    -- LOCAL: info + contratistas + etapas de obra
    insert into public.office_info (client_id, area_key, address, size, price, status, notes)
        values (d, 'local', 'Av. Principal 123, Ciudad Demo', '1,800 pies²', '450000', 'Opción de compra realizada', 'Local en zona comercial céntrica.');
    insert into public.contractors (client_id, area_key, name, quote_amount, contact, lead_time, status, notes) values
        (d, 'local', 'Constructora Demo A', 78000, '(000) 111-2222', '8 semanas', 'seleccionado', 'Mejor propuesta integral.'),
        (d, 'local', 'Remodelaciones Demo B', 92000, '(000) 333-4444', '6 semanas', 'cotizado', ''),
        (d, 'local', 'Acabados Demo C', 65000, '(000) 555-6666', '10 semanas', 'descartado', 'Sin disponibilidad inmediata.');
    insert into public.stages (client_id, area_key, name, status, progress, sort_order) values
        (d, 'local', 'Demolición y preparación', 'hecho', 100, 1),
        (d, 'local', 'Plomería e instalaciones', 'en_progreso', 80, 2),
        (d, 'local', 'Sistema eléctrico', 'en_progreso', 45, 3),
        (d, 'local', 'Pintura y acabados', 'pendiente', 10, 4),
        (d, 'local', 'Pisos y mobiliario fijo', 'pendiente', 0, 5);

    -- PERSONAL: puestos
    insert into public.positions (client_id, area_key, title, status, candidate, salary) values
        (d, 'personal', 'Médico/a principal',  'contratado',   'Dra. Ejemplo',      180000),
        (d, 'personal', 'Recepcionista',        'contratado',   'Sr. Ejemplo',        32000),
        (d, 'personal', 'Enfermero/a',          'entrevistando','—',                  48000),
        (d, 'personal', 'Asistente médico',     'abierto',      '',                   38000),
        (d, 'personal', 'Facturación / seguros','abierto',      '',                   40000),
        (d, 'personal', 'Conserjería',          'por_abrir',    '',                   24000);

    -- PERMISOS
    insert into public.permits (client_id, area_key, name, type, status, cost, responsible) values
        (d, 'permisos', 'Licencia sanitaria',        'Salud',        'obtenido',  1200, 'Administración'),
        (d, 'permisos', 'Registro de comercio',      'Municipal',    'obtenido',   450, 'Administración'),
        (d, 'permisos', 'Permiso de uso',            'Permisos',     'en_tramite', 800, 'Gestoría'),
        (d, 'permisos', 'Inspección de bomberos',    'Seguridad',    'en_tramite', 300, 'Gestoría'),
        (d, 'permisos', 'Patente municipal',         'Municipal',    'pendiente',  600, 'Administración'),
        (d, 'permisos', 'Registro de residuos',      'Ambiental',    'pendiente',  350, 'Gestoría'),
        (d, 'permisos', 'Seguro de responsabilidad', 'Seguros',      'pendiente', 2500, 'Administración');

    -- FINANCIAMIENTO: producto + contactos + documentos + estimados
    insert into public.bank_product (client_id, area_key, bank, product, rate, term, notes)
        values (d, 'financiamiento', 'Banco Demo', 'Préstamo comercial', '7.5%', '10 años', 'Pre-aprobación en proceso.');
    insert into public.bank_contacts (client_id, area_key, name, phone, email) values
        (d, 'financiamiento', 'Oficial Demo', '(000) 777-8888', 'oficial@bancodemo.example');
    insert into public.bank_documents (client_id, area_key, doc_key, name, description, status, ord) values
        (d, 'financiamiento', 'costo_total',   'Costo total del proyecto', 'Cotizaciones y facturas.', 'entregado', 1),
        (d, 'financiamiento', 'proyecciones',  '3 años de proyecciones',   'Con supuestos.',           'entregado', 2),
        (d, 'financiamiento', 'business_plan', 'Business plan',            '',                          'entregado', 3),
        (d, 'financiamiento', 'estados_fin',   'Estados financieros',      'Personales recientes.',    'pendiente', 4),
        (d, 'financiamiento', 'contrato',      'Contrato de opción',       'Firmado.',                 'pendiente', 5);
    insert into public.finance_estimates (client_id, area_key, item_key, amount) values
        (d, 'financiamiento', 'local',        450000),
        (d, 'financiamiento', 'remodelacion',  78000),
        (d, 'financiamiento', 'equipos',      140000),
        (d, 'financiamiento', 'nomina',       180000),
        (d, 'financiamiento', 'permisos',       6200),
        (d, 'financiamiento', 'operacional',   30000);

    -- MARCA
    insert into public.brand_info (client_id, area_key, name, slogan, colors, website, marketing_budget)
        values (d, 'equipos', 'Clínica Demo', 'Tu salud, nuestra prioridad', 'Verde azulado / blanco', 'www.clinicademo.example', 25000);

    -- EQUIPOS DE OFICINA: cuartos + equipos
    insert into public.office_rooms (client_id, area_key, name, sort_order) values
        (d, 'equipos_oficina', 'Recepción',     1),
        (d, 'equipos_oficina', 'Consultorio 1', 2),
        (d, 'equipos_oficina', 'Consultorio 2', 3),
        (d, 'equipos_oficina', 'Laboratorio',   4),
        (d, 'equipos_oficina', 'Sala de espera',5);
    -- equipos asignados por nombre de cuarto
    insert into public.office_equipment (client_id, area_key, name, quantity, unit_price, status, room_id)
    select d, 'equipos_oficina', e.name, e.qty, e.price, e.status, r.id
    from (values
        ('Escritorio recepción', 1, 650,  'comprado',  'Recepción'),
        ('Computadora recepción',1, 900,  'comprado',  'Recepción'),
        ('Sillas de espera',     8, 120,  'comprado',  'Sala de espera'),
        ('Mesa de centro',       1, 180,  'comprado',  'Sala de espera'),
        ('Camilla de examen',    1, 1400, 'comprado',  'Consultorio 1'),
        ('Escritorio médico',    1, 700,  'comprado',  'Consultorio 1'),
        ('Computadora consult.1',1, 950,  'comprado',  'Consultorio 1'),
        ('Camilla de examen',    1, 1400, 'comprado',  'Consultorio 2'),
        ('Escritorio médico',    1, 700,  'pendiente', 'Consultorio 2'),
        ('Computadora consult.2',1, 950,  'pendiente', 'Consultorio 2'),
        ('Microscopio',          1, 2200, 'pendiente', 'Laboratorio'),
        ('Centrífuga',           1, 1800, 'comprado',  'Laboratorio'),
        ('Refrigerador muestras',1, 1300, 'pendiente', 'Laboratorio'),
        ('Impresora multifunc.', 1, 400,  'comprado',  'Recepción')
    ) as e(name, qty, price, status, room_name)
    join public.office_rooms r on r.client_id = d and r.name = e.room_name;

    -- EQUIPOS MÉDICOS: lista de compra + tareas (para % del área)
    insert into public.purchase_equipment (client_id, area_key, name, price, quantity) values
        (d, 'equipos', 'Equipo de ultrasonido', 35000, 1),
        (d, 'equipos', 'Monitor de signos vitales', 2500, 2),
        (d, 'equipos', 'Báscula clínica', 450, 2);
    insert into public.tasks (client_id, area_key, title, status, sort_order) values
        (d, 'equipos', 'Comparar proveedores de ultrasonido', 'hecho', 1),
        (d, 'equipos', 'Solicitar cotizaciones', 'hecho', 2),
        (d, 'equipos', 'Decidir financiamiento de equipos', 'en_progreso', 3),
        (d, 'equipos', 'Orden de compra', 'pendiente', 4);

    -- PENDIENTES (to-do del equipo)
    insert into public.pending_tasks (client_id, title, status, created_by_name, done_at) values
        (d, 'Confirmar fecha de inspección de bomberos', 'pendiente', 'Equipo Demo', null),
        (d, 'Enviar estados financieros al banco',       'pendiente', 'Equipo Demo', null),
        (d, 'Publicar vacante de enfermería',            'pendiente', 'Equipo Demo', null),
        (d, 'Cotizar rótulo exterior',                   'pendiente', 'Equipo Demo', null),
        (d, 'Firmar opción de compra del local',         'hecho',     'Equipo Demo', now() - interval '5 days'),
        (d, 'Abrir cuenta comercial',                    'hecho',     'Equipo Demo', now() - interval '2 days');
end $$;

-- ============================================================================
--  LISTO. Verificación:
--    select name, status from public.clients;
--    -- En la app: como super-admin, usa el conmutador para entrar al Demo
--    --            y verás el Resumen lleno de datos de ejemplo.
-- ============================================================================
