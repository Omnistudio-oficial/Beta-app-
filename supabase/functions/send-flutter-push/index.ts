const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
const FIREBASE_PROJECT_ID = "omnistudio-caaf5";
const FIREBASE_IDENTITY_LOOKUP_URL = "https://identitytoolkit.googleapis.com/v1/accounts:lookup";
const GOOGLE_OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token";
const GOOGLE_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
import { FLUTTER_FCM_APP_ID, isAllowedFlutterPushRecipient, isValidDevice } from "./push-routing.ts";
const APP_ID = FLUTTER_FCM_APP_ID;
const MAX_TOKEN_LENGTH = 4096;

type Identity = { uid: string; email: string };
type ServiceAccount = { client_email: string; private_key: string; project_id: string };
type PushRequest = { recipientUid?: unknown; title?: unknown; body?: unknown; data?: unknown };
type DeviceRow = { uid: string; fcm_token: string; platform: "android" | "ios"; token_hash: string };

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}
function text(value: unknown): string { return typeof value === "string" ? value.trim() : ""; }
function validUid(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= 128 && /^[A-Za-z0-9_-]+$/.test(value);
}
function safeData(value: unknown): Record<string, string> | null {
  if (value == null) return {};
  if (typeof value !== "object" || Array.isArray(value)) return null;
  const entries = Object.entries(value as Record<string, unknown>);
  if (entries.length > 20) return null;
  const result: Record<string, string> = {};
  for (const [key, raw] of entries) {
    if (!/^[A-Za-z][A-Za-z0-9_]{0,39}$/.test(key)) return null;
    if (typeof raw !== "string" || raw.length > 512) return null;
    result[key] = raw;
  }
  return result;
}
function decodePrivateKey(pem: string): ArrayBuffer {
  const clean = pem.replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "").replace(/\\n/g, "\n").replace(/\s/g, "");
  const raw = atob(clean);
  const buffer = new ArrayBuffer(raw.length);
  const bytes = new Uint8Array(buffer);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return buffer;
}
function b64url(bytes: Uint8Array): string {
  let raw = "";
  for (const byte of bytes) raw += String.fromCharCode(byte);
  return btoa(raw).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
async function googleAccessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = b64url(new TextEncoder().encode(JSON.stringify({
    iss: account.client_email, scope: GOOGLE_SCOPE, aud: GOOGLE_OAUTH_TOKEN_URL, iat: now, exp: now + 3600,
  })));
  const unsigned = `${header}.${claims}`;
  const key = await crypto.subtle.importKey("pkcs8", decodePrivateKey(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const response = await fetch(GOOGLE_OAUTH_TOKEN_URL, {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${b64url(signature)}` }),
  });
  if (!response.ok) throw new Error(`Google OAuth failed (${response.status})`);
  const json = await response.json() as { access_token?: string };
  if (!json.access_token) throw new Error("Google OAuth did not return an access token");
  return json.access_token;
}
async function firebaseIdentity(token: string, apiKey: string): Promise<Identity | null> {
  const response = await fetch(`${FIREBASE_IDENTITY_LOOKUP_URL}?key=${encodeURIComponent(apiKey)}`, {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ idToken: token }),
  });
  if (!response.ok) return null;
  const json = await response.json() as { users?: Array<{ localId?: string; email?: string; disabled?: boolean }> };
  const user = json.users?.length === 1 ? json.users[0] : undefined;
  const uid = text(user?.localId); const email = text(user?.email).toLowerCase();
  if (!validUid(uid) || !email || user?.disabled === true) return null;
  return { uid, email };
}
async function supabaseDevices(url: string, key: string, uid: string): Promise<DeviceRow[]> {
  const query = new URLSearchParams({
    select: "uid,fcm_token,platform,token_hash", uid: `eq.${uid}`, app_id: `eq.${APP_ID}`,
  });
  const response = await fetch(`${url.replace(/\/$/, "")}/rest/v1/fcm_device_tokens?${query}`, {
    headers: { apikey: key, authorization: `Bearer ${key}`, accept: "application/json" },
  });
  if (!response.ok) throw new Error(`Private FCM registry read failed (${response.status})`);
  const rows = await response.json() as DeviceRow[];
  return rows.flatMap((row) => {
    const candidate = { uid: row.uid, appId: APP_ID, platform: row.platform, token: row.fcm_token, tokenHash: row.token_hash };
    return isValidDevice(candidate) ? [row] : [];
  });
}
async function deleteStaleDevice(url: string, key: string, row: DeviceRow): Promise<void> {
  const query = new URLSearchParams({
    uid: `eq.${row.uid}`, app_id: `eq.${APP_ID}`, platform: `eq.${row.platform}`, token_hash: `eq.${row.token_hash}`,
  });
  const response = await fetch(`${url.replace(/\/$/, "")}/rest/v1/fcm_device_tokens?${query}`, {
    method: "DELETE", headers: { apikey: key, authorization: `Bearer ${key}` },
  });
  if (!response.ok) console.warn("Could not remove stale Flutter FCM device", { status: response.status });
}
async function send(token: string, platform: "android" | "ios", title: string, body: string, data: Record<string, string>, accessToken: string): Promise<Response> {
  return await fetch(`https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`, {
    method: "POST", headers: { authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        data,
        ...(platform === "android" ? { android: { priority: "HIGH" } } : {
          apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default" } } },
        }),
      },
    }),
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);
  const idToken = /^Bearer\s+(\S+)$/i.exec(request.headers.get("authorization") ?? "")?.[1] ?? "";
  if (!idToken || idToken.length > 4096) return jsonResponse({ error: "Firebase authentication required" }, 401);
  const apiKey = Deno.env.get("FIREBASE_WEB_API_KEY");
  const serviceJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!apiKey || !serviceJson || !supabaseUrl || !supabaseKey) return jsonResponse({ error: "Push sender is not configured" }, 503);
  const identity = await firebaseIdentity(idToken, apiKey).catch(() => null);
  if (!identity) return jsonResponse({ error: "Firebase token verification failed" }, 401);
  let input: PushRequest;
  try { input = await request.json() as PushRequest; } catch { return jsonResponse({ error: "Invalid JSON body" }, 400); }
  const recipientUid = text(input.recipientUid);
  const title = text(input.title);
  const body = text(input.body);
  const data = safeData(input.data);
  if (!validUid(recipientUid) || !title || title.length > 120 || !body || body.length > 500 || data == null) {
    return jsonResponse({ error: "Invalid notification request" }, 400);
  }
  if (!isAllowedFlutterPushRecipient(identity.uid, recipientUid)) {
    return jsonResponse({ error: "Only self-test delivery is enabled in this phase" }, 403);
  }
  let serviceAccount: ServiceAccount;
  try { serviceAccount = JSON.parse(serviceJson) as ServiceAccount; }
  catch { return jsonResponse({ error: "Push service credentials are invalid" }, 503); }
  if (serviceAccount.project_id !== FIREBASE_PROJECT_ID || !serviceAccount.client_email || !serviceAccount.private_key) {
    return jsonResponse({ error: "Push credentials do not match Firebase project" }, 503);
  }
  try {
    const [devices, accessToken] = await Promise.all([
      supabaseDevices(supabaseUrl, supabaseKey, recipientUid), googleAccessToken(serviceAccount),
    ]);
    let sent = 0;
    for (const device of devices) {
      const response = await send(device.fcm_token, device.platform, title, body, data, accessToken);
      if (response.ok) {
        sent++;
        continue;
      }
      const errorBody = await response.json().catch(() => ({})) as { error?: { details?: Array<{ errorCode?: string }> } };
      const codes = errorBody.error?.details?.map((detail) => detail.errorCode) ?? [];
      if (codes.includes("UNREGISTERED") || response.status === 404) {
        await deleteStaleDevice(supabaseUrl, supabaseKey, device);
      } else {
        console.warn("FCM sender rejected device", { platform: device.platform, status: response.status });
      }
    }
    return jsonResponse({ accepted: true, sent, deviceCount: devices.length });
  } catch (error) {
    console.error("Flutter FCM send failed", { message: error instanceof Error ? error.message : "Unknown error" });
    return jsonResponse({ error: "Push send failed" }, 502);
  }
});
