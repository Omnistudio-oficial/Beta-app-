const PROJECT_ID = "omnistudio-caaf5";
const DATABASE_URL = "https://omnistudio-caaf5-default-rtdb.firebaseio.com";
const ANDROID_APP_ID = "com.omnistudio.omnistudioFlutterPrototypelutterPrototype";
const IOS_APP_ID = "com.omnistudio.omnistudioF";
const MAX_SKEW_SECONDS = 300;
const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
const GOOGLE_SCOPE = "https://www.googleapis.com/auth/firebase.database https://www.googleapis.com/auth/firebase.messaging";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "apikey, content-type, x-sara-timestamp, x-sara-request-id, x-sara-signature",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
type ServiceAccount = { client_email: string; private_key: string; project_id: string };
type Device = { tokenId: string; token: string; appId: string; platform: "android" | "ios" };
function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: cors });
}
function text(value: unknown): string { return typeof value === "string" ? value.trim() : ""; }
function validUid(value: string): boolean {
  return value.length > 0 && value.length <= 128 && /^[A-Za-z0-9_-]+$/.test(value);
}
function b64url(bytes: Uint8Array): string {
  let binary = ""; for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
async function googleAccessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = b64url(new TextEncoder().encode(JSON.stringify({
    iss: account.client_email, scope: GOOGLE_SCOPE, aud: GOOGLE_TOKEN_URL, iat: now, exp: now + 3600,
  })));
  const unsigned = header + "." + claims;
  const pem = account.private_key.replace(/\\n/g, "\\n").replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  const raw = Uint8Array.from(atob(pem), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", raw, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const response = await fetch(GOOGLE_TOKEN_URL, {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: unsigned + "." + b64url(signature),
    }),
  });
  if (!response.ok) throw new Error("google_oauth_failed");
  const result = await response.json() as { access_token?: string };
  if (!result.access_token) throw new Error("google_access_token_missing");
  return result.access_token;
}
async function verifyHmac(secret: string, timestamp: string, requestId: string, rawBody: string, signature: string) {
  if (!/^[a-f0-9]{64}$/i.test(signature)) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  const bytes = new Uint8Array(signature.match(/.{2}/g)!.map(value => parseInt(value, 16)));
  return crypto.subtle.verify("HMAC", key, bytes, new TextEncoder().encode(timestamp + "." + requestId + "." + rawBody));
}
async function claimNonce(requestId: string, serviceKey: string, supabaseUrl: string) {
  const base = supabaseUrl.replace(/\/$/, "");
  await fetch(base + "/rest/v1/sara_push_request_nonces?expires_at=lt." + encodeURIComponent(new Date().toISOString()), {
    method: "DELETE", headers: { apikey: serviceKey, authorization: "Bearer " + serviceKey },
  });
  const response = await fetch(base + "/rest/v1/sara_push_request_nonces", {
    method: "POST",
    headers: { apikey: serviceKey, authorization: "Bearer " + serviceKey, "content-type": "application/json", prefer: "return=minimal" },
    body: JSON.stringify({ request_id: requestId, expires_at: new Date(Date.now() + 10 * 60_000).toISOString() }),
  });
  return response.status === 201 || response.status === 204;
}
function databasePath(path: string): string {
  return path.split("/").map(encodeURIComponent).join("/");
}
async function firebaseGet(path: string, accessToken: string): Promise<unknown> {
  const response = await fetch(`${DATABASE_URL}/${databasePath(path)}.json`, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok) throw new Error("firebase_database_read_failed");
  return response.json();
}
async function firebaseDelete(path: string, accessToken: string): Promise<void> {
  const response = await fetch(`${DATABASE_URL}/${databasePath(path)}.json`, {
    method: "DELETE", headers: { authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok && response.status !== 404) throw new Error("firebase_database_delete_failed");
}
async function readDevices(uid: string, accessToken: string): Promise<Device[]> {
  const value = await firebaseGet(`users/${uid}/fcmTokens`, accessToken);
  if (!value || typeof value !== "object" || Array.isArray(value)) return [];
  const devices: Device[] = [];
  for (const [tokenId, raw] of Object.entries(value as Record<string, unknown>)) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) continue;
    const row = raw as Record<string, unknown>;
    const appId = text(row.appId);
    const token = text(row.fcmToken);
    const platform = appId === ANDROID_APP_ID ? "android" : appId === IOS_APP_ID ? "ios" : "";
    if (!platform || !token || token.length > 4096 || row.notificationsEnabled === false) continue;
    devices.push({ tokenId, token, appId, platform });
  }
  return devices;
}
async function sendFcm(device: Device, taskId: string, status: "completed" | "failed", accessToken: string) {
  const title = status === "completed" ? "Sara completó tu tarea" : "Sara no pudo completar tu tarea";
  const messageBody = status === "completed"
    ? "Tu tarea ha finalizado. Abre Sara para ver el resultado."
    : "Hubo un problema con tu tarea. Abre Sara para consultar los detalles.";
  return fetch("https://fcm.googleapis.com/v1/projects/" + PROJECT_ID + "/messages:send", {
    method: "POST",
    headers: { authorization: "Bearer " + accessToken, "content-type": "application/json" },
    body: JSON.stringify({ message: {
      token: device.token,
      notification: { title, body: messageBody },
      data: { eventType: "sara_task", taskId, taskStatus: status },
      ...(device.platform === "android"
        ? { android: { priority: "HIGH" } }
        : { apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default" } } } }),
    } }),
  });
}
Deno.serve(async request => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const secret = Deno.env.get("SARA_PUSH_SHARED_SECRET");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const accountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!secret || secret.length < 32 || !serviceKey || !supabaseUrl || !accountJson) {
    return json({ error: "push_bridge_not_configured" }, 503);
  }
  const timestamp = request.headers.get("x-sara-timestamp") ?? "";
  const requestId = request.headers.get("x-sara-request-id") ?? "";
  const signature = request.headers.get("x-sara-signature") ?? "";
  const seconds = Number(timestamp);
  if (!/^\d{10}$/.test(timestamp) || !Number.isFinite(seconds) ||
      Math.abs(Date.now() / 1000 - seconds) > MAX_SKEW_SECONDS ||
      !/^[0-9a-f-]{36}$/i.test(requestId)) return json({ error: "invalid_or_expired_signature" }, 401);
  const rawBody = await request.text();
  if (rawBody.length > 2048 || !await verifyHmac(secret, timestamp, requestId, rawBody, signature)) {
    return json({ error: "invalid_signature" }, 401);
  }
  let body: { userId?: unknown; taskId?: unknown; status?: unknown };
  try { body = JSON.parse(rawBody); } catch { return json({ error: "invalid_json" }, 400); }
  const userId = text(body.userId);
  const taskId = text(body.taskId);
  const status = text(body.status);
  if (!validUid(userId) || !/^[0-9a-f-]{36}$/i.test(taskId) ||
      (status !== "completed" && status !== "failed")) return json({ error: "invalid_task_notification" }, 400);

  try {
    if (!await claimNonce(requestId, serviceKey, supabaseUrl)) return json({ error: "request_replayed" }, 409);
    const account = JSON.parse(accountJson) as ServiceAccount;
    if (account.project_id !== PROJECT_ID || !account.client_email || !account.private_key) {
      return json({ error: "firebase_service_account_invalid" }, 503);
    }
    const accessToken = await googleAccessToken(account);
    const devices = await readDevices(userId, accessToken);
    let sent = 0;
    let disabled = 0;
    for (const device of devices) {
      const response = await sendFcm(device, taskId, status, accessToken);
      if (response.ok) sent++;
      else {
        const error = await response.json().catch(() => ({})) as { error?: { details?: Array<{ errorCode?: string }> } };
        const codes = error.error?.details?.map(item => item.errorCode) ?? [];
        if (response.status === 404 || codes.includes("UNREGISTERED")) {
          await firebaseDelete(`users/${userId}/fcmTokens/${device.tokenId}`, accessToken);
          disabled++;
        } else {
          console.warn("FCM rejected a Sara task notification", { platform: device.platform, status: response.status });
        }
      }
    }
    return json({ accepted: true, attempted: devices.length, sent, disabled });
  } catch (error) {
    console.error("Sara push delivery failed", { message: error instanceof Error ? error.message : "unknown" });
    return json({ error: "push_delivery_unavailable" }, 502);
  }
});
