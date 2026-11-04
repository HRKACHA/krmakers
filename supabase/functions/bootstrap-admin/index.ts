import { createClient } from "npm:@supabase/supabase-js@2.118.0";

const ALLOWED_ORIGINS = new Set([
  "https://kr-makers-invoice.vercel.app",
  "https://kr-makers-invoice-dehniybv4-hemanshukacha983-1529s-projects.vercel.app",
]);
const corsHeaders = (origin: string) => ({
  "Access-Control-Allow-Origin": ALLOWED_ORIGINS.has(origin) ? origin : "https://kr-makers-invoice.vercel.app",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin") || "";
  const headers = corsHeaders(origin);
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return Response.json({ error: "Method not allowed" }, { status: 405, headers });

  try {
    const body = await req.json();
    const setupCode = String(body.setupCode || "");
    const email = String(body.email || "").trim().toLowerCase();
    const password = String(body.password || "");
    const displayName = String(body.displayName || "").trim().slice(0, 80);

    if (!setupCode || setupCode.length < 20) {
      return Response.json({ error: "Enter the one-time owner setup code." }, { status: 400, headers });
    }
    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return Response.json({ error: "Enter a valid administrator email address." }, { status: 400, headers });
    }
    if (password.length < 10) {
      return Response.json({ error: "Use a password with at least 10 characters." }, { status: 400, headers });
    }
    if (!displayName) {
      return Response.json({ error: "Enter the owner's name." }, { status: 400, headers });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) throw new Error("Owner setup service is not configured.");

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const created = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { display_name: displayName },
    });
    if (created.error || !created.data.user) {
      return Response.json({ error: created.error?.message || "Could not create the owner account." }, { status: 400, headers });
    }

    const claim = await admin.rpc("claim_bootstrap_admin", {
      p_code_hash: await sha256(setupCode),
      p_user_id: created.data.user.id,
      p_display_name: displayName,
    });
    if (claim.error) {
      await admin.auth.admin.deleteUser(created.data.user.id);
      return Response.json({ error: "The setup code is invalid or has already been used. No account was created." }, { status: 403, headers });
    }

    return Response.json({ ok: true, message: "Owner account created. Sign in with your email and password." }, { status: 200, headers });
  } catch (error) {
    console.error("bootstrap-admin error:", error);
    return Response.json({ error: "Owner setup could not be completed. Please try again." }, { status: 500, headers });
  }
});
