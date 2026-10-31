/** Server-only routing for Flutter FCM devices. Call only with UIDs already
 * derived from the authenticated event's server-validated recipient set. */
export const FLUTTER_FCM_APP_ID = "com.omnistudio.omnistudioFlutterPrototype";
export type FlutterPlatform = "android" | "ios";
export type FlutterDevice = { uid: string; fcm_token: string; platform: FlutterPlatform; token_hash: string };
type ServiceAccount = { client_email: string; private_key: string; project_id: string };
const PROJECT = "omnistudio-caaf5";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const validUid = (uid: unknown): uid is string => typeof uid === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(uid);

export function selectFlutterDevices(uids: string[], rows: unknown): FlutterDevice[] {
  const allowed = new Set(uids.filter(validUid));
  if (!Array.isArray(rows) || !allowed.size) return [];
  const seen = new Set<string>();
  return rows.flatMap((raw) => {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return [];
    const row = raw as Record<string, unknown>;
    if (!validUid(row.uid) || !allowed.has(row.uid) || row.app_id !== FLUTTER_FCM_APP_ID ||
      (row.platform !== "android" && row.platform !== "ios") || typeof row.fcm_token !== "string" ||
      !row.fcm_token || row.fcm_token.length > 4096 || typeof row.token_hash !== "string" ||
      !/^[a-f0-9]{64}$/.test(row.token_hash)) return [];
    const key = `${row.uid}\0${row.platform}\0${row.token_hash}`;
    if (seen.has(key)) return [];
    seen.add(key);
    return [{ uid: row.uid, fcm_token: row.fcm_token, platform: row.platform, token_hash: row.token_hash } as FlutterDevice];
  });
}

function b64url(bytes: Uint8Array): string {
  let value = "";
  for (const byte of bytes) value += String.fromCharCode(byte);
  return btoa(value).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
function decodeKey(pem: string): ArrayBuffer {
  const raw = atob(pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----/g, "").replace(/\\n/g, "\n").replace(/\s/g, ""));
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out.buffer;
}
async function accessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = b64url(new TextEncoder().encode(JSON.stringify({ iss: account.client_email, scope: SCOPE, aud: TOKEN_URL, iat: now, exp: now + 3600 })));
  const unsigned = `${header}.${claims}`;
  const key = await crypto.subtle.importKey("pkcs8", decodeKey(account.private_key), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const response = await fetch(TOKEN_URL, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${b64url(signature)}` }) });
  if (!response.ok) throw new Error(`FCM authorization failed (${response.status})`);
  const result = await response.json() as { access_token?: string };
  if (!result.access_token) throw new Error("FCM authorization response missing access token");
  return result.access_token;
}
async function fetchDevices(url: string, key: string, uids: string[]): Promise<FlutterDevice[]> {
  const unique = [...new Set(uids.filter(validUid))].slice(0, 100);
  if (!unique.length) return [];
  const params = new URLSearchParams({ select: "uid,app_id,fcm_token,platform,token_hash", uid: `in.(${unique.join(",")})`, app_id: `eq.${FLUTTER_FCM_APP_ID}`, limit: "500" });
  const response = await fetch(`${url.replace(/\/$/, "")}/rest/v1/fcm_device_tokens?${params}`, { headers: { apikey: key, authorization: `Bearer ${key}`, accept: "application/json" } });
  if (!response.ok) throw new Error(`Private Flutter device lookup failed (${response.status})`);
  return selectFlutterDevices(unique, await response.json());
}
async function removeStale(url: string, key: string, device: FlutterDevice): Promise<void> {
  const params = new URLSearchParams({ uid: `eq.${device.uid}`, app_id: `eq.${FLUTTER_FCM_APP_ID}`, platform: `eq.${device.platform}`, token_hash: `eq.${device.token_hash}` });
  const response = await fetch(`${url.replace(/\/$/, "")}/rest/v1/fcm_device_tokens?${params}`, { method: "DELETE", headers: { apikey: key, authorization: `Bearer ${key}` } });
  if (!response.ok) console.warn("Could not remove stale Flutter push registration", { platform: device.platform, status: response.status });
}
/** Limit lookup and delivery to 100 distinct server-selected users and 500 devices. */
export async function sendFlutterPushToUids(args: {
  uids: string[]; title: string; body: string; data: Record<string, string>; account: ServiceAccount;
}): Promise<{ sent: number; devices: number }> {
  const url = Deno.env.get("SUPABASE_URL"), key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Private Flutter token registry is not configured");
  const selectedUids = [...new Set(args.uids.filter(validUid))].slice(0, 1000);
  const devices: FlutterDevice[] = [];
  for (let offset = 0; offset < selectedUids.length && devices.length < 500; offset += 100) {
    devices.push(...(await fetchDevices(url, key, selectedUids.slice(offset, offset + 100))).slice(0, 500 - devices.length));
  }
  if (!devices.length) return { sent: 0, devices: 0 };
  const bearer = await accessToken(args.account);
  let sent = 0;
  for (const device of devices) {
    const options = device.platform === "android"
      ? { android: { priority: "HIGH" } }
      : { apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default" } } } };
    const response = await fetch(`https://fcm.googleapis.com/v1/projects/${PROJECT}/messages:send`, {
      method: "POST", headers: { authorization: `Bearer ${bearer}`, "content-type": "application/json" },
      body: JSON.stringify({ message: { token: device.fcm_token, notification: { title: args.title.slice(0, 120), body: args.body.slice(0, 500) }, data: args.data, ...options } }),
    });
    if (response.ok) { sent++; continue; }
    const result = await response.json().catch(() => ({})) as { error?: { details?: Array<{ errorCode?: string }> } };
    const codes = result.error?.details?.map((item) => item.errorCode) ?? [];
    if (response.status === 404 || codes.includes("UNREGISTERED")) await removeStale(url, key, device);
    else console.warn("FCM rejected Flutter device", { platform: device.platform, status: response.status });
  }
  return { sent, devices: devices.length };
}
