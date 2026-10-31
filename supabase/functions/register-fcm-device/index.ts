import { validateFcmDeviceRequest, validateFirebaseIdToken, validFirebaseUid } from "./authorization.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
const FIREBASE_IDENTITY_LOOKUP_URL = "https://identitytoolkit.googleapis.com/v1/accounts:lookup";

type FirebaseIdentity = { uid: string; email?: string };
function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

async function verifyFirebaseIdToken(idToken: string, apiKey: string): Promise<FirebaseIdentity | null> {
  const response = await fetch(`${FIREBASE_IDENTITY_LOOKUP_URL}?key=${encodeURIComponent(apiKey)}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ idToken }),
  });
  if (!response.ok) return null;
  const payload = await response.json() as {
    users?: Array<{ localId?: string; email?: string; disabled?: boolean }>;
  };
  const user = payload.users?.length === 1 ? payload.users[0] : undefined;
  const uid = text(user?.localId);
  if (!validFirebaseUid(uid) || user?.disabled === true) return null;
  return { uid, email: text(user?.email).toLowerCase() };
}

async function sha256(value: string): Promise<string> {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function serviceRequest(
  url: string,
  secret: string,
  method: string,
  path: string,
  body?: Record<string, unknown>,
  prefer?: string,
): Promise<Response> {
  const headers: Record<string, string> = {
    apikey: secret,
    authorization: `Bearer ${secret}`,
    accept: "application/json",
  };
  if (body) headers["content-type"] = "application/json";
  if (prefer) headers.prefer = prefer;
  return await fetch(`${url.replace(/\/$/, "")}/rest/v1/${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const bearer = /^Bearer\s+(\S+)$/i.exec(request.headers.get("authorization") ?? "")?.[1] ?? "";
  if (!validateFirebaseIdToken(bearer)) return jsonResponse({ error: "Firebase authentication required" }, 401);
  const apiKey = Deno.env.get("FIREBASE_WEB_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!apiKey || !supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: "Device registry is not configured" }, 503);
  }
  const identity = await verifyFirebaseIdToken(bearer, apiKey).catch(() => null);
  if (!identity) return jsonResponse({ error: "Firebase token verification failed" }, 401);

  let rawBody: unknown;
  try {
    rawBody = await request.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }
  const device = validateFcmDeviceRequest(rawBody);
  if (!device) return jsonResponse({ error: "Invalid Flutter device registration" }, 400);

  const tokenHash = await sha256(device.token);
  const filters = new URLSearchParams({
    uid: `eq.${identity.uid}`,
    app_id: `eq.${device.appId}`,
    platform: `eq.${device.platform}`,
    token_hash: `eq.${tokenHash}`,
  }).toString();
  try {
    if (device.action === "register") {
      const result = await serviceRequest(
        supabaseUrl,
        serviceRoleKey,
        "POST",
        "fcm_device_tokens?on_conflict=uid,app_id,platform,token_hash",
        {
          uid: identity.uid,
          app_id: device.appId,
          platform: device.platform,
          token_hash: tokenHash,
          fcm_token: device.token,
          updated_at: new Date().toISOString(),
        },
        "resolution=merge-duplicates,return=minimal",
      );
      if (!result.ok) {
        console.error("FCM token register request failed", { status: result.status });
        return jsonResponse({ error: "Could not register this device" }, 502);
      }
    } else {
      const result = await serviceRequest(
        supabaseUrl,
        serviceRoleKey,
        "DELETE",
        `fcm_device_tokens?${filters}`,
      );
      if (!result.ok) {
        console.error("FCM token unregister request failed", { status: result.status });
        return jsonResponse({ error: "Could not unregister this device" }, 502);
      }
    }
    return jsonResponse({ registered: device.action === "register" });
  } catch {
    return jsonResponse({ error: "Device registry unavailable" }, 502);
  }
});
