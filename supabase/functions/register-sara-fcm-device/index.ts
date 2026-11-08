const PROJECT_ID = "omnistudio-caaf5";
const ANDROID_APP_ID = "com.omnistudio.omnistudioFlutterPrototype";
const IOS_APP_ID = "com.omnistudio.omnistudioF";
const MAX_TOKEN_LENGTH = 4096;
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: cors });
}
function text(value: unknown): string { return typeof value === "string" ? value.trim() : ""; }
function validUid(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= 128 && /^[A-Za-z0-9_-]+$/.test(value);
}
function bearer(request: Request): string | null {
  const match = /^Bearer\s+(\S+)$/i.exec(request.headers.get("authorization") ?? "");
  return match && match[1].length <= MAX_TOKEN_LENGTH ? match[1] : null;
}
async function verifyIdToken(idToken: string, apiKey: string) {
  const response = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(apiKey)}`, {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ idToken }),
  });
  if (!response.ok) return null;
  const payload = await response.json() as { users?: Array<{ localId?: string; disabled?: boolean }> };
  const user = payload.users?.length === 1 ? payload.users[0] : undefined;
  return user && validUid(user.localId) && user.disabled !== true ? { uid: user.localId } : null;
}
async function sha256(value: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  return [...digest].map(byte => byte.toString(16).padStart(2, "0")).join("");
}
Deno.serve(async request => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const idToken = bearer(request);
  if (!idToken) return json({ error: "firebase_auth_required" }, 401);
  const apiKey = Deno.env.get("FIREBASE_WEB_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!apiKey || !supabaseUrl || !serviceKey) return json({ error: "device_registry_not_configured" }, 503);

  let body: { action?: unknown; token?: unknown; platform?: unknown; appId?: unknown };
  try { body = await request.json(); } catch { return json({ error: "invalid_json" }, 400); }
  const platform = text(body.platform);
  const expectedAppId = platform === "android" ? ANDROID_APP_ID : platform === "ios" ? IOS_APP_ID : "";
  const action = text(body.action);
  const token = text(body.token);
  if (!expectedAppId || text(body.appId) !== expectedAppId || (action !== "register" && action !== "unregister")) {
    return json({ error: "unsupported_app_platform_or_action" }, 400);
  }
  if (token.length < 100 || token.length > MAX_TOKEN_LENGTH || /\s/.test(token)) {
    return json({ error: "invalid_fcm_token" }, 400);
  }

  try {
    const identity = await verifyIdToken(idToken, apiKey);
    if (!identity) return json({ error: "firebase_token_invalid" }, 401);
    const tokenHash = await sha256(token);
    const base = supabaseUrl.replace(/\/$/, "");
    const filters = new URLSearchParams({
      uid: `eq.${identity.uid}`,
      app_id: `eq.${expectedAppId}`,
      platform: `eq.${platform}`,
      token_hash: `eq.${tokenHash}`,
    });
    const headers = {
      apikey: serviceKey,
      authorization: `Bearer ${serviceKey}`,
      "content-type": "application/json",
      accept: "application/json",
    };
    let response: Response;
    if (action === "register") {
      response = await fetch(`${base}/rest/v1/fcm_device_tokens?on_conflict=uid,app_id,platform,token_hash`, {
        method: "POST",
        headers: { ...headers, prefer: "resolution=merge-duplicates,return=minimal" },
        body: JSON.stringify({
          uid: identity.uid,
          app_id: expectedAppId,
          platform,
          token_hash: tokenHash,
          fcm_token: token,
          updated_at: new Date().toISOString(),
        }),
      });
    } else {
      response = await fetch(`${base}/rest/v1/fcm_device_tokens?${filters.toString()}`, {
        method: "DELETE", headers,
      });
    }
    if (!response.ok) {
      console.error("Sara FCM device registry request failed", { action, status: response.status });
      return json({ error: "device_registry_request_failed" }, 502);
    }
    return json({ ok: true, registered: action === "register" }, action === "register" ? 201 : 200);
  } catch {
    return json({ error: "device_registry_unavailable" }, 502);
  }
});
