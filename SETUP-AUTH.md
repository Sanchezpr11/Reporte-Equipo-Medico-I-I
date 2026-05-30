# Configuración del sistema multi-usuario

Esta guía activa el nuevo sistema de **usuarios con login real + permisos por área + panel de administración**. Hazla una sola vez. Tiempo estimado: ~15 minutos.

Todo se hace en tu panel de Supabase: <https://supabase.com/dashboard> → tu proyecto.

---

## Paso 1 — Crear las tablas y la seguridad (SQL)

1. En Supabase, ve a **SQL Editor** → **New query**.
2. Abre el archivo [`supabase/schema.sql`](supabase/schema.sql) de este repositorio, copia **todo** su contenido y pégalo.
3. Pulsa **Run**.

Esto crea las tablas `profiles`, `areas`, `user_area_access`, activa Row-Level Security y **blinda** la tabla `app_state` (suplidores) para que ya no sea accesible sin sesión. Es seguro ejecutarlo más de una vez.

---

## Paso 2 — Desplegar la función `admin-users`

Esta pequeña función es la que permite crear usuarios con contraseña temporal de forma segura (usa una llave privada que nunca debe estar en la página).

### Opción A — Desde el navegador (sin terminal) — recomendada
1. En Supabase, ve a **Edge Functions** → **Deploy a new function** (o **Create function**).
2. Nombre de la función: **`smooth-responder`** *(debe coincidir con la constante `EDGE_FUNCTION` en `index.html`)*.
3. Borra el contenido de ejemplo y pega **todo** el archivo [`supabase/functions/smooth-responder/index.ts`](supabase/functions/smooth-responder/index.ts).
4. **IMPORTANTE:** desactiva la opción **"Verify JWT"** / **"Enforce JWT verification"** (la verificación la hace la función por dentro; si la dejas activada, el navegador no podrá llamarla por CORS).
5. Pulsa **Deploy**.

### Opción B — Desde la terminal (CLI)
```bash
npm i -g supabase            # si no la tienes
supabase login
supabase functions deploy smooth-responder --project-ref rqqwrbmrzgxgcyijzytc --no-verify-jwt
```
> No necesitas configurar secretos: `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` ya existen en el entorno de la función.

---

## Paso 3 — Cerrar el registro público

Para que **solo un admin** pueda crear cuentas:

1. Ve a **Authentication** → **Sign In / Providers** (o **Settings**).
2. Asegúrate de que el proveedor **Email** está habilitado.
3. **Desactiva** "Allow new users to sign up" (Enable signups). *(El admin sigue pudiendo crear usuarios; esto solo bloquea el auto-registro público.)*

---

## Paso 4 — Crear tu primer administrador (bootstrap)

Todavía no hay ningún admin, así que el primero se crea a mano:

1. Ve a **Authentication** → **Users** → **Add user** → **Create new user**.
   - Escribe tu **correo** y una **contraseña**.
   - Marca **Auto Confirm User** (para poder entrar sin email de confirmación).
2. Ve a **SQL Editor** y ejecuta (cambia el correo por el tuyo):
   ```sql
   update public.profiles set is_admin = true
   where email = 'TU-CORREO-ADMIN@ejemplo.com';
   ```

¡Listo! Ese usuario ya es administrador.

---

## Paso 5 — Publicar el sitio y entrar

1. Fusiona el Pull Request de esta rama a `main` (o sube el `index.html` actualizado), para que el sitio en vivo use la nueva versión.
2. Abre el sitio, inicia sesión con tu correo y contraseña de admin.
3. Verás la pestaña **⚙️ Admin**. Desde ahí puedes:
   - **Crear usuarios** (correo + nombre + contraseña temporal + áreas).
   - **Marcar las áreas** que cada usuario puede ver (se guarda al instante).
   - **Restablecer contraseñas** o **eliminar** usuarios.

> Comparte cada contraseña temporal por un canal seguro. El usuario podrá entrar de inmediato.

---

## Cómo añadir un área NUEVA en el futuro

1. Crea la sección en `index.html`: un `<section id="sec-MICLAVE">…</section>` y su pestaña `<button id="tab-MICLAVE" onclick="window.switchTab('MICLAVE')" class="hidden …">…</button>`.
2. Regístrala en la base de datos (SQL Editor):
   ```sql
   insert into public.areas (key, label, sort_order)
   values ('MICLAVE', 'Nombre visible del área', 4);
   ```
3. Aparecerá automáticamente en el panel de Admin para asignarla a cada usuario. No hace falta tocar la lógica de acceso.

---

## Notas de seguridad

- Ahora la seguridad es **real y del lado del servidor**: las políticas RLS de Supabase deciden quién lee/escribe, no el navegador.
- La llave **anónima** que aparece en `index.html` es pública por diseño; no da acceso a nada sin una sesión válida.
- La llave **service_role** (la poderosa) solo vive dentro de la Edge Function, nunca en la página.
- Los administradores tienen acceso a todas las áreas automáticamente.
