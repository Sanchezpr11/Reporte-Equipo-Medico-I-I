// ============================================================================
//  Edge Function: smooth-responder  (gestión privilegiada de usuarios/clientes)
//  Usa la SERVICE ROLE KEY (secreta, solo del servidor). MULTI-CLIENTE.
//
//  Acciones (body.action):
//    - "create_client"  { name, admin_email, admin_password, admin_full_name, is_demo? }
//                       -> SOLO admin de plataforma. Crea un cliente + su 1er admin.
//    - "create"         { email, password, full_name, area_keys[], is_admin, client_id? }
//                       -> admin de cliente (en SU cliente) o plataforma (client_id).
//    - "set_password"   { user_id, password }
//    - "delete"         { user_id }
//
//  Desplegar: Supabase Dashboard -> Edge Functions -> smooth-responder ->
//  pega este archivo -> Deploy.  (Secretos SUPABASE_* ya están en el entorno.)
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

function slugify(s: string): string {
  return String(s ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40) || "cliente";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // 1) Identificar a quien llama (por su token de sesión)
    const authHeader = req.headers.get("Authorization") ?? "";
    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user: me }, error: meErr } = await caller.auth.getUser();
    if (meErr || !me) return json({ error: "No autenticado." }, 401);

    // 2) Cliente con privilegios (service role) para verificar y actuar
    const admin = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // 3) Perfil del que llama: rol + cliente
    const { data: meProfile } = await admin
      .from("profiles")
      .select("is_admin, is_platform_admin, client_id")
      .eq("id", me.id)
      .single();

    const isPlatform = meProfile?.is_platform_admin === true;
    const isClientAdmin = meProfile?.is_admin === true;
    if (!isPlatform && !isClientAdmin) {
      return json({ error: "Requiere permisos de administrador." }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const action = body.action as string;

    // ---- CREAR CLIENTE (+ su primer admin) — solo plataforma ----------------
    if (action === "create_client") {
      if (!isPlatform) {
        return json({ error: "Solo el administrador de plataforma puede crear clientes." }, 403);
      }
      const name = String(body.name ?? "").trim();
      const admin_email = String(body.admin_email ?? "").trim().toLowerCase();
      const admin_password = String(body.admin_password ?? "");
      const admin_full_name = String(body.admin_full_name ?? "");
      const is_demo = body.is_demo === true;

      if (!name) return json({ error: "El nombre del cliente es obligatorio." }, 400);
      if (!admin_email || admin_password.length < 6) {
        return json({ error: "Email y contraseña (mín. 6) del admin del cliente son obligatorios." }, 400);
      }

      // Crear el cliente (con reintento si el slug choca)
      let slug = slugify(body.slug ?? name);
      let { data: client, error: clErr } = await admin
        .from("clients").insert({ name, slug, is_demo }).select("id").single();
      if (clErr && /duplicate|unique/i.test(clErr.message ?? "")) {
        slug = slug + "-" + Math.random().toString(36).slice(2, 6);
        ({ data: client, error: clErr } = await admin
          .from("clients").insert({ name, slug, is_demo }).select("id").single());
      }
      if (clErr || !client) {
        return json({ error: clErr?.message ?? "No se pudo crear el cliente." }, 400);
      }

      // Crear el primer admin del cliente (confirmado, entra de inmediato)
      const { data: created, error: cErr } = await admin.auth.admin.createUser({
        email: admin_email,
        password: admin_password,
        email_confirm: true,
        user_metadata: { full_name: admin_full_name },
      });
      if (cErr || !created?.user) {
        return json({ error: "Cliente creado, pero falló su admin: " + (cErr?.message ?? "") , client_id: client.id }, 400);
      }
      await admin.from("profiles").upsert({
        id: created.user.id,
        email: admin_email,
        full_name: admin_full_name,
        is_admin: true,           // admin DE SU CLIENTE
        is_platform_admin: false,
        client_id: client.id,
      });

      return json({ ok: true, client_id: client.id, user_id: created.user.id });
    }

    // ---- CREAR USUARIO dentro de un cliente ---------------------------------
    if (action === "create") {
      const email = String(body.email ?? "").trim().toLowerCase();
      const password = String(body.password ?? "");
      const full_name = String(body.full_name ?? "");
      const is_admin = body.is_admin === true;
      const area_keys: string[] = Array.isArray(body.area_keys) ? body.area_keys : [];

      // Cliente destino: admin de cliente -> el suyo; plataforma -> el indicado
      const targetClient = isPlatform
        ? (body.client_id ?? meProfile?.client_id)
        : meProfile?.client_id;
      if (!targetClient) return json({ error: "No se pudo determinar el cliente destino." }, 400);

      if (!email || !password) return json({ error: "Email y contraseña son obligatorios." }, 400);
      if (password.length < 6) return json({ error: "La contraseña debe tener al menos 6 caracteres." }, 400);

      const { data: created, error: cErr } = await admin.auth.admin.createUser({
        email, password, email_confirm: true, user_metadata: { full_name },
      });
      if (cErr || !created?.user) {
        return json({ error: cErr?.message ?? "No se pudo crear el usuario." }, 400);
      }
      const newId = created.user.id;

      await admin.from("profiles").upsert({
        id: newId, email, full_name, is_admin, client_id: targetClient,
      });

      if (area_keys.length > 0) {
        await admin.from("user_area_access")
          .insert(area_keys.map((k) => ({ user_id: newId, area_key: k })));
      }

      return json({ ok: true, user_id: newId });
    }

    // ---- CAMBIAR CONTRASEÑA --------------------------------------------------
    if (action === "set_password") {
      const user_id = String(body.user_id ?? "");
      const password = String(body.password ?? "");
      if (!user_id || password.length < 6) {
        return json({ error: "Usuario y contraseña (mín. 6) son obligatorios." }, 400);
      }
      if (!isPlatform) {
        const { data: tgt } = await admin.from("profiles").select("client_id").eq("id", user_id).single();
        if (!tgt || tgt.client_id !== meProfile?.client_id) {
          return json({ error: "Ese usuario no pertenece a tu cliente." }, 403);
        }
      }
      const { error } = await admin.auth.admin.updateUserById(user_id, { password });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    // ---- ELIMINAR USUARIO ----------------------------------------------------
    if (action === "delete") {
      const user_id = String(body.user_id ?? "");
      if (!user_id) return json({ error: "Falta el usuario." }, 400);
      if (user_id === me.id) return json({ error: "No puedes eliminar tu propia cuenta." }, 400);
      if (!isPlatform) {
        const { data: tgt } = await admin.from("profiles").select("client_id").eq("id", user_id).single();
        if (!tgt || tgt.client_id !== meProfile?.client_id) {
          return json({ error: "Ese usuario no pertenece a tu cliente." }, 403);
        }
      }
      const { error } = await admin.auth.admin.deleteUser(user_id);
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    return json({ error: "Acción no reconocida." }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
