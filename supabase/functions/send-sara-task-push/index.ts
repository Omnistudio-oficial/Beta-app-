const PROJECT_ID = "omnistudio-caaf5";
const DATABASE_URL = "https://omnistudio-caaf5-default-rtdb.firebaseio.com";
const ANDROID_APP_ID = "com.omnistudio.omnistudioFlutterPrototype";
const IOS_APP_ID = "com.omnistudio.omnistudioF";
const MAX_SKEW_SECONDS = 300;
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "apikey, content-type, x-sara-timestamp, x-sara-request-id, x-sara-signature",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
function json(body: Record<string, unknown>, status = 200) { return new Response(JSON.stringify(body), { status, headers: cors }); }
function text(value: unknown) { return typeof value === "string" ? value.trim() : ""; }
function b64url(bytes: Uint8Array) {
  let binary = ""; for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
async function googleAccessToken(account: { client_email: string; private_key: string; project_id: string }) {
  const tokenUrl = "https://oauth2.googleapis.com/token"; const now = Math.floor(Date.now() / 1000);
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = b64url(new TextEncoder().encode(JSON.stringify({ iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.database https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUrl, iat: now, exp: now + 3600 })));
  const unsigned = header + "." + claims;
  const pem = account.private_key.replace(/\\n/g, "\n").replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  const raw = Uint8Array.from(atob(pem), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", raw, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const assertion = unsigned + "." + b64url(sig);
  const response = await fetch(tokenUrl, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }) });
  if (!response.ok) throw new Error("google_oauth_failed");
  const result = await response.json() as { access_token?: string };
  if (!result.access_token) throw new Error("google_access_token_missing");
  return result.access_token;
}
async function verifyHmac(secret: string, timestamp: string, requestId: string, rawBody: string, signature: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  const normalized = signature.toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(normalized)) return false;
  const bytes = new Uint8Array(normalized.match(/.{2}/g)!.map(v => parseInt(v, 16)));
  return await crypto.subtle.verify("HMAC", key, bytes, new TextEncoder().encode(timestamp + "." + requestId + "." + rawBody));
}
async function claimNonce(requestId: string, serviceKey: string, supabaseUrl: string) {
  const base = supabaseUrl.replace(/\/$/, "");
  await fetch(base + "/rest/v1/sara_push_request_nonces?expires_at=lt." + encodeURIComponent(new Date().toISOString()), {
    method: "DELETE", headers: { apikey: serviceKey, authorization: "Bearer " + serviceKey },
  });
  const response = await fetch(base + "/rest/v1/sara_push_request_nonces", {
    method: "POST", headers: { apikey: serviceKey, authorization: "Bearer " + serviceKey,
      "content-type": "application/json", prefer: "return=minimal" },
    body: JSON.stringify({ request_id: requestId, expires_at: new Date(Date.now() + 10 * 60_000).toISOString() }),
  });
  return response.status === 201 || response.status === 204;
}
Deno.serve(async request => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const secret = Deno.env.get("SARA_PUSH_SHARED_SECRET");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const accountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!secret || secret.length < 32 || !serviceKey || !supabaseUrl || !accountJson) return json({ error: "push_bridge_not_configured" }, 503);
  const timestamp = request.headers.get("x-sara-timestamp") ?? "";
  const requestId = request.headers.get("x-sara-request-id") ?? "";
  const signature = request.headers.get("x-sara-signature") ?? "";
  const seconds = Number(timestamp);
  if (!/^\d{10}$/.test(timestamp) || !Number.isFinite(seconds) || Math.abs(Date.now() / 1000 - seconds) > MAX_SKEW_SECONDS ||
      !/^[0-9a-f-]{36}$/i.test(requestId)) return json({ error: "invalid_or_expired_signature" }, 401);
  const rawBody = await request.text();
  if (rawBody.length > 2048 || !await verifyHmac(secret, timestamp, requestId, rawBody, signature)) return json({ error: "invalid_signature" }, 401);
  let body: { userId?: unknown; taskId?: unknown; status?: unknown };
  try { body = JSON.parse(rawBody); } catch { return json({ error: "invalid_json" }, 400); }
  const userId = text(body.userId); const taskId = text(body.taskId); const status = text(body.status);
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(userId) || !/^[0-9a-f-]{36}$/i.test(taskId) ||
      (status !== "completed" && status !== "failed")) return json({ error: "invalid_task_notification" }, 400);
  try {
    if (!await claimNonce(requestId, serviceKey, supabaseUrl)) return json({ error: "request_replayed" }, 409);
    const account = JSON.parse(accountJson) as { client_email: string; private_key: string; project_id: string };
    if (account.project_id !== PROJECT_ID || !account.client_email || !account.private_key) return json({ error: "firebase_service_account_invalid" }, 503);
    const accessToken = await googleAccessToken(account);
    const userUrl = DATABASE_URL + "/users/" + encodeURIComponent(userId) + "/fcmTokens.json";
    const devicesResponse = await fetch(userUrl, { headers: { authorization: "Bearer " + accessToken } });
    if (!devicesResponse.ok) return json({ error: "firebase_device_lookup_failed" }, 502);
    const devices = await devicesResponse.json() as Record<string, { fcmToken?: string; appId?: string; notificationsEnabled?: boolean } | null> | null;
    const candidates = Object.entries(devices ?? {}).filter(([, device]) =>
      !!device && device.notificationsEnabled !== false &&
      (device.appId === ANDROID_APP_ID || device.appId === IOS_APP_ID) &&
      typeof device.fcmToken === "string" && device.fcmToken.length >= 100 && device.fcmToken.length <= 4096
    );
    const title = status === "completed" ? "Sara completó tu tarea" : "Sara no pudo completar tu tarea";
    const messageBody = status === "completed" ? "Tu tarea ha finalizado. Abre Sara para ver el resultado." : "Hubo un problema con tu tarea. Abre Sara para consultar los detalles.";
    let sent = 0; let disabled = 0;
    for (const [tokenId, device] of candidates) {
      const response = await fetch("https://fcm.googleapis.com/v1/projects/" + PROJECT_ID + "/messages:send", {
        method: "POST", headers: { authorization: "Bearer " + accessToken, "content-type": "application/json" },
        body: JSON.stringify({ message: {
          token: device!.fcmToken,
          notification: { title, body: messageBody },
          data: { eventType: "sara_task", taskId, taskStatus: status },
          android: { priority: "HIGH" },
          apns: { payload: { aps: { sound: "default" } } },
        } }),
      });
      if (response.ok) sent++;
      else {
        const error = await response.json().catch(() => ({})) as { error?: { details?: Array<{ errorCode?: string }> } };
        const codes = error.error?.details?.map(item => item.errorCode) ?? [];
        if (response.status === 404 || codes.includes("UNREGISTERED")) {
          const deleteResponse = await fetch(DATABASE_URL + "/users/" + encodeURIComponent(userId) + "/fcmTokens/" + encodeURIComponent(tokenId) + ".json", {
            method: "DELETE", headers: { authorization: "Bearer " + accessToken },
          });
          if (deleteResponse.ok || deleteResponse.status === 404) disabled++;
        }
      }
    }
    return json({ accepted: true, attempted: candidates.length, sent, disabled });
  } catch {
    return json({ error: "push_delivery_unavailable" }, 502);
  }
});
