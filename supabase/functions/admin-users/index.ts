// ============================================================================
//  Edge Function: admin-users
//  Operaciones privilegiadas de gestión de usuarios. Usa la SERVICE ROLE KEY
//  (secreta, solo del lado del servidor) y SOLO la ejecuta un administrador.
//
//  Acciones (body.action):
//    - "create"        { email, password, full_name, area_keys[], is_admin }
//    - "set_password"  { user_id, password }
//    - "delete"        { user_id }
//
//  Desplegar:
//    Opción A (sin terminal): Supabase Dashboard -> Edge Functions -> Deploy a
//    new function -> nombre "admin-users" -> pega este archivo -> Deploy.
//    Opción B (CLI): supabase functions deploy admin-users
//
//  No requiere configurar secretos: SUPABASE_URL, SUPABASE_ANON_KEY y
//  SUPABASE_SERVICE_ROLE_KEY ya están disponibles en el entorno de la función.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  // Preflight CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // --- 1) Identificar a quien llama, a partir de su token de sesión ---
    const authHeader = req.headers.get("Authorization") ?? "";
    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user: me },
      error: meErr,
    } = await caller.auth.getUser();
    if (meErr || !me) return json({ error: "No autenticado." }, 401);

    // --- 2) Cliente con privilegios (service role) para verificar y actuar ---
    const admin = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // --- 3) Verificar que quien llama es administrador ---
    const { data: meProfile } = await admin
      .from("profiles")
      .select("is_admin")
      .eq("id", me.id)
      .single();
    if (!meProfile?.is_admin) {
      return json({ error: "Requiere permisos de administrador." }, 403);
    }

    // --- 4) Procesar la acción ---
    const body = await req.json().catch(() => ({}));
    const action = body.action as string;

    if (action === "create") {
      const email = String(body.email ?? "").trim().toLowerCase();
      const password = String(body.password ?? "");
      const full_name = String(body.full_name ?? "");
      const is_admin = body.is_admin === true;
      const area_keys: string[] = Array.isArray(body.area_keys)
        ? body.area_keys
        : [];

      if (!email || !password) {
        return json({ error: "Email y contraseña son obligatorios." }, 400);
      }
      if (password.length < 6) {
        return json({ error: "La contraseña debe tener al menos 6 caracteres." }, 400);
      }

      // Crear el usuario YA confirmado para que pueda entrar de inmediato.
      const { data: created, error: cErr } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { full_name },
      });
      if (cErr || !created?.user) {
        return json({ error: cErr?.message ?? "No se pudo crear el usuario." }, 400);
      }
      const newId = created.user.id;

      // El trigger ya creó el perfil base; fijamos nombre y rol admin.
      await admin.from("profiles").upsert({
        id: newId,
        email,
        full_name,
        is_admin,
      });

      // Asignar áreas seleccionadas.
      if (area_keys.length > 0) {
        await admin
          .from("user_area_access")
          .insert(area_keys.map((k) => ({ user_id: newId, area_key: k })));
      }

      return json({ ok: true, user_id: newId });
    }

    if (action === "set_password") {
      const user_id = String(body.user_id ?? "");
      const password = String(body.password ?? "");
      if (!user_id || password.length < 6) {
        return json({ error: "Usuario y contraseña (mín. 6) son obligatorios." }, 400);
      }
      const { error } = await admin.auth.admin.updateUserById(user_id, { password });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    if (action === "delete") {
      const user_id = String(body.user_id ?? "");
      if (!user_id) return json({ error: "Falta el usuario." }, 400);
      if (user_id === me.id) {
        return json({ error: "No puedes eliminar tu propia cuenta." }, 400);
      }
      const { error } = await admin.auth.admin.deleteUser(user_id);
      if (error) return json({ error: error.message }, 400);
      // profiles y user_area_access se borran en cascada (ON DELETE CASCADE).
      return json({ ok: true });
    }

    return json({ error: "Acción no reconocida." }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
