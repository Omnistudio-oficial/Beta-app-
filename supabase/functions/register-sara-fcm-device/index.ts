const PROJECT_ID = "omnistudio-caaf5";
const DATABASE_URL = "https://omnistudio-caaf5-default-rtdb.firebaseio.com";
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
function text(value: unknown) { return typeof value === "string" ? value.trim() : ""; }
function bearer(request: Request) {
  const match = /^Bearer\s+(\S+)$/i.exec(request.headers.get("authorization") ?? "");
  return match && match[1].length <= MAX_TOKEN_LENGTH ? match[1] : null;
}
async function verifyIdToken(idToken: string, apiKey: string) {
  const response = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(apiKey)}`, {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ idToken }),
  });
  if (!response.ok) return null;
  const body = await response.json() as { users?: Array<{ localId?: string; email?: string; disabled?: boolean }> };
  const user = body.users?.length === 1 ? body.users[0] : undefined;
  if (!user?.localId || user.disabled === true) return null;
  return { uid: user.localId, email: text(user.email).toLowerCase() };
}
function b64url(bytes: Uint8Array) {
  let binary = ""; for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
async function googleAccessToken(account: { client_email: string; private_key: string; project_id: string }) {
  const tokenUrl = "https://oauth2.googleapis.com/token";
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = b64url(new TextEncoder().encode(JSON.stringify({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.database https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUrl, iat: now, exp: now + 3600,
  })));
  const unsigned = header + "." + claims;
  const pem = account.private_key.replace(/\\n/g, "\n").replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  const raw = Uint8Array.from(atob(pem), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", raw, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const assertion = unsigned + "." + b64url(sig);
  const response = await fetch(tokenUrl, {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!response.ok) throw new Error("google_oauth_failed");
  const data = await response.json() as { access_token?: string };
  if (!data.access_token) throw new Error("google_access_token_missing");
  return data.access_token;
}
async function digestHex(value: string) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  return [...digest].map(b => b.toString(16).padStart(2, "0")).join("");
}
Deno.serve(async request => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const idToken = bearer(request);
  if (!idToken) return json({ error: "firebase_auth_required" }, 401);
  const apiKey = Deno.env.get("FIREBASE_WEB_API_KEY");
  const accountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!apiKey || !accountJson) return json({ error: "firebase_server_not_configured" }, 503);
  let body: { token?: unknown; platform?: unknown; appId?: unknown };
  try { body = await request.json(); } catch { return json({ error: "invalid_json" }, 400); }
  const token = text(body.token);
  const platform = text(body.platform);
  const expectedAppId = platform === "android" ? ANDROID_APP_ID : platform === "ios" ? IOS_APP_ID : "";
  if (!expectedAppId || text(body.appId) !== expectedAppId) return json({ error: "unsupported_app_platform" }, 400);
  if (token.length < 100 || token.length > MAX_TOKEN_LENGTH || /\s/.test(token)) return json({ error: "invalid_fcm_token" }, 400);
  try {
    const identity = await verifyIdToken(idToken, apiKey);
    if (!identity) return json({ error: "firebase_token_invalid" }, 401);
    const account = JSON.parse(accountJson) as { client_email: string; private_key: string; project_id: string };
    if (account.project_id !== PROJECT_ID || !account.client_email || !account.private_key) return json({ error: "firebase_service_account_invalid" }, 503);
    const accessToken = await googleAccessToken(account);
    const tokenId = await digestHex(token);
    const record = {
      email: identity.email,
      appId: expectedAppId,
      fcmToken: token,
      lastTokenRefresh: Date.now(),
      lastActiveAt: Date.now(),
      activityTrackingEnabled: true,
      notificationsEnabled: true,
      platform,
    };
    const response = await fetch(`${DATABASE_URL}/users/${encodeURIComponent(identity.uid)}/fcmTokens/${tokenId}.json`, {
      method: "PUT",
      headers: { authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
      body: JSON.stringify(record),
    });
    if (!response.ok) return json({ error: "firebase_device_registration_failed" }, 502);
    return json({ ok: true, registered: true }, 201);
  } catch {
    return json({ error: "device_registration_unavailable" }, 502);
  }
});
