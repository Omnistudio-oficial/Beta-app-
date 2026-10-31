import { sendFlutterPushToUids } from "../_shared/flutter-fcm.ts";
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const FIREBASE_PROJECT_ID = "omnistudio-caaf5";
const FIREBASE_DATABASE_URL = "https://omnistudio-caaf5-default-rtdb.firebaseio.com";
const TEST_ANDROID_PACKAGE = "com.aistudio.omnistudio.wkspea.test";
const GOOGLE_OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token";
const FIREBASE_IDENTITY_LOOKUP_URL = "https://identitytoolkit.googleapis.com/v1/accounts:lookup";
const GOOGLE_SCOPE = [
  "https://www.googleapis.com/auth/userinfo.email",
  "https://www.googleapis.com/auth/firebase.database",
  "https://www.googleapis.com/auth/firebase.messaging",
].join(" ");
const MAX_ID_LENGTH = 256;
const MAX_ID_TOKEN_LENGTH = 4096;

type DataMap = Record<string, unknown>;
type FirebaseIdentity = { uid: string; email: string };
type ServiceAccount = { client_email: string; private_key: string; project_id: string };
type DeviceToken = { token: string; tokenId: string };

type SocialEvent = {
  eventType?: unknown;
  socialType?: unknown;
  targetUid?: unknown;
  postId?: unknown;
  storyId?: unknown;
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function isValidKey(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= MAX_ID_LENGTH && /^[A-Za-z0-9_.-]+$/.test(value);
}

function asMap(value: unknown): DataMap | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as DataMap : null;
}

function extractBearerToken(request: Request): string | null {
  const match = /^Bearer\s+(\S+)$/i.exec(request.headers.get("authorization") ?? "");
  if (!match || match[1].length > MAX_ID_TOKEN_LENGTH) return null;
  return match[1];
}

async function verifyFirebaseIdToken(idToken: string, apiKey: string): Promise<FirebaseIdentity | null> {
  const response = await fetch(`${FIREBASE_IDENTITY_LOOKUP_URL}?key=${encodeURIComponent(apiKey)}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ idToken }),
  });
  if (!response.ok) return null;
  const payload = await response.json() as { users?: Array<{ localId?: string; email?: string; disabled?: boolean }> };
  const user = payload.users?.length === 1 ? payload.users[0] : undefined;
  const uid = text(user?.localId);
  if (!uid || user?.disabled === true) return null;
  return { uid, email: text(user?.email).toLowerCase() };
}

function decodePrivateKey(pem: string): ArrayBuffer {
  const clean = pem.replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\\n/g, "\n")
    .replace(/\s/g, "");
  const binary = atob(clean);
  const result = new ArrayBuffer(binary.length);
  const bytes = new Uint8Array(result);
  for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
  return result;
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function getGoogleAccessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = base64Url(new TextEncoder().encode(JSON.stringify({
    iss: account.client_email,
    scope: GOOGLE_SCOPE,
    aud: GOOGLE_OAUTH_TOKEN_URL,
    iat: now,
    exp: now + 3600,
  })));
  const unsignedJwt = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    decodePrivateKey(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsignedJwt),
  ));
  const response = await fetch(GOOGLE_OAUTH_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsignedJwt}.${base64Url(signature)}`,
    }),
  });
  if (!response.ok) throw new Error(`Google OAuth token request failed (${response.status})`);
  const result = await response.json() as { access_token?: string };
  if (!result.access_token) throw new Error("Google OAuth response had no access token");
  return result.access_token;
}

async function firebaseGet(path: string, accessToken: string): Promise<unknown> {
  const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  const response = await fetch(`${FIREBASE_DATABASE_URL}/${encodedPath}.json`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok) throw new Error(`Firebase read failed (${response.status})`);
  return await response.json();
}

async function firebasePut(path: string, value: unknown, accessToken: string): Promise<void> {
  const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  const response = await fetch(`${FIREBASE_DATABASE_URL}/${encodedPath}.json`, {
    method: "PUT",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    body: JSON.stringify(value),
  });
  if (!response.ok) throw new Error(`Firebase write failed (${response.status})`);
}

async function hashKey(value: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  return [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function userTokens(uid: string, accessToken: string): Promise<DeviceToken[]> {
  const value = asMap(await firebaseGet(`users/${uid}/fcmTokens`, accessToken));
  if (!value) return [];
  const unique = new Map<string, string>();
  for (const [tokenId, raw] of Object.entries(value)) {
    const item = asMap(raw);
    const token = text(item?.fcmToken);
    if (!token || text(item?.appId) !== TEST_ANDROID_PACKAGE || item?.notificationsEnabled === false) continue;
    unique.set(token, tokenId);
  }
  return [...unique].map(([token, tokenId]) => ({ token, tokenId }));
}

async function removeStaleToken(uid: string, tokenId: string, accessToken: string): Promise<void> {
  const encodedPath = `users/${uid}/fcmTokens/${tokenId}`.split("/").map(encodeURIComponent).join("/");
  const response = await fetch(`${FIREBASE_DATABASE_URL}/${encodedPath}.json`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok && response.status !== 404) console.warn("Could not remove a stale Social FCM token", response.status);
}

async function sendFcm(token: string, data: Record<string, string>, accessToken: string): Promise<Response> {
  return await fetch(`https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        token,
        data,
        android: { priority: "HIGH" },
      },
    }),
  });
}

function acceptedFollowerUids(value: unknown): string[] {
  const map = asMap(value);
  if (!map) return [];
  return Object.entries(map).flatMap(([uid, raw]) => {
    const relation = asMap(raw);
    return relation?.status === "accepted" && uid ? [uid] : [];
  });
}

async function deliverToUser(
  recipientUid: string,
  actorUid: string,
  socialType: string,
  actorName: string,
  actorUsername: string,
  objectId: string,
  eventKey: string,
  accessToken: string,
  account: ServiceAccount,
): Promise<{ sent: number; devices: number }> {
  if (!recipientUid || recipientUid === actorUid) return { sent: 0, devices: 0 };
  const dedupeKey = await hashKey(`${eventKey}:${recipientUid}`);
  const logPath = `social_test/pushDispatch/${dedupeKey}`;
  if (await firebaseGet(logPath, accessToken)) return { sent: 0, devices: 0 };

  const devices = await userTokens(recipientUid, accessToken);
  let sent = 0;
  for (const device of devices) {
    const payload: Record<string, string> = {
      eventType: "social",
      socialType,
      actorName: actorName || "Alguien",
      actorUsername,
      eventId: dedupeKey,
      pushEnvironment: "test",
    };
    if (socialType === "like" || socialType === "new_post") payload.postId = objectId;
    if (socialType === "new_story") payload.storyId = objectId;
    const response = await sendFcm(device.token, payload, accessToken);
    if (response.ok) {
      sent++;
    } else {
      const errorBody = await response.json().catch(() => ({})) as { error?: { details?: Array<{ errorCode?: string }> } };
      const errorCodes = errorBody.error?.details?.map((item) => item.errorCode) ?? [];
      if (response.status === 404 || errorCodes.includes("UNREGISTERED")) {
        await removeStaleToken(recipientUid, device.tokenId, accessToken);
      } else {
        console.warn("FCM rejected a Social notification", { socialType, status: response.status });
      }
    }
  }
  const titleByType: Record<string, string> = {
    like: `${actorName || "Alguien"} indicó que le gusta tu publicación`,
    follow_request: `${actorName || "Alguien"} quiere seguirte`,
    new_follower: `${actorName || "Alguien"} empezó a seguirte`,
    follow_accepted: `${actorName || "Alguien"} aceptó tu solicitud`,
    new_post: `${actorName || "Alguien"} publicó en Social`,
    new_story: `${actorName || "Alguien"} compartió una historia`,
  };
  const flutter = await sendFlutterPushToUids({
    uids: [recipientUid],
    title: titleByType[socialType] || "Nueva actividad en Social",
    body: "Toca para abrir OmniStudio",
    data: { eventType: "social", socialType, actorName: actorName || "Alguien", actorUsername, eventId: dedupeKey, ...(socialType === "like" || socialType === "new_post" ? { postId: objectId } : {}), ...(socialType === "new_story" ? { storyId: objectId } : {}) },
    account,
  });
  sent += flutter.sent;
  if (sent > 0) await firebasePut(logPath, { sentAt: Date.now(), socialType }, accessToken);
  return { sent, devices: devices.length + flutter.devices };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const idToken = extractBearerToken(request);
  if (!idToken) return jsonResponse({ error: "Firebase authentication required" }, 401);
  const apiKey = Deno.env.get("FIREBASE_WEB_API_KEY");
  const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!apiKey || !serviceAccountJson) return jsonResponse({ error: "Social push is not configured" }, 503);

  let body: SocialEvent;
  try {
    body = await request.json() as SocialEvent;
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }
  if (text(body.eventType) !== "social") return jsonResponse({ error: "Unsupported event type" }, 400);
  const requestedType = text(body.socialType);
  if (!["like", "follow", "follow_accepted", "new_post", "new_story"].includes(requestedType)) {
    return jsonResponse({ error: "Unsupported Social notification" }, 400);
  }
  if (body.targetUid != null && !isValidKey(body.targetUid)) return jsonResponse({ error: "Invalid target UID" }, 400);
  if (body.postId != null && !isValidKey(body.postId)) return jsonResponse({ error: "Invalid post ID" }, 400);
  if (body.storyId != null && !isValidKey(body.storyId)) return jsonResponse({ error: "Invalid story ID" }, 400);

  const identity = await verifyFirebaseIdToken(idToken, apiKey).catch(() => null);
  if (!identity) return jsonResponse({ error: "Firebase token verification failed" }, 401);
  let account: ServiceAccount;
  try {
    account = JSON.parse(serviceAccountJson) as ServiceAccount;
  } catch {
    return jsonResponse({ error: "Firebase server credentials are invalid" }, 503);
  }
  if (!account.client_email || !account.private_key || account.project_id !== FIREBASE_PROJECT_ID) {
    return jsonResponse({ error: "Firebase credentials do not match this project" }, 503);
  }

  try {
    const accessToken = await getGoogleAccessToken(account);
    const senderUid = identity.uid;
    const senderProfile = asMap(await firebaseGet(`social_test/profiles/${senderUid}`, accessToken));
    const actorName = text(senderProfile?.displayName) || identity.email || "Alguien";
    const actorUsername = text(senderProfile?.username);
    const recipients: string[] = [];
    let actualType = requestedType;
    let objectId = "";
    let eventKey = "";

    if (requestedType === "like") {
      const targetUid = text(body.targetUid);
      const postId = text(body.postId);
      if (!targetUid || !postId || targetUid === senderUid) return jsonResponse({ accepted: true, sent: 0 }, 200);
      const [like, post] = await Promise.all([
        firebaseGet(`social_test/likes/${targetUid}/${postId}/${senderUid}`, accessToken),
        firebaseGet(`social_test/postsByUser/${targetUid}/${postId}`, accessToken),
      ]);
      const postMap = asMap(post);
      if (like !== true || !postMap || text(postMap.ownerUid) !== targetUid) {
        return jsonResponse({ error: "Like does not match a Social post" }, 403);
      }
      recipients.push(targetUid);
      objectId = postId;
      eventKey = `like:${senderUid}:${targetUid}:${postId}`;
    } else if (requestedType === "follow") {
      const targetUid = text(body.targetUid);
      if (!targetUid || targetUid === senderUid) return jsonResponse({ accepted: true, sent: 0 }, 200);
      const [following, request, follower, targetProfile] = await Promise.all([
        firebaseGet(`social_test/following/${senderUid}/${targetUid}`, accessToken),
        firebaseGet(`social_test/followRequests/${targetUid}/${senderUid}`, accessToken),
        firebaseGet(`social_test/followers/${targetUid}/${senderUid}`, accessToken),
        firebaseGet(`social_test/profiles/${targetUid}`, accessToken),
      ]);
      const relation = asMap(following);
      const followRequest = asMap(request);
      const followerRecord = asMap(follower);
      const profile = asMap(targetProfile);
      if (relation?.status === "pending" && followRequest?.status === "pending") {
        actualType = "follow_request";
        recipients.push(targetUid);
        eventKey = `follow-request:${senderUid}:${targetUid}:${String(followRequest.createdAt ?? "")}`;
      } else if (relation?.status === "accepted" && followerRecord?.status === "accepted" && profile?.visibility === "public") {
        actualType = "new_follower";
        recipients.push(targetUid);
        eventKey = `follow:${senderUid}:${targetUid}:${String(relation.createdAt ?? "")}`;
      } else {
        return jsonResponse({ accepted: true, sent: 0 }, 200);
      }
    } else if (requestedType === "follow_accepted") {
      const requesterUid = text(body.targetUid);
      if (!requesterUid || requesterUid === senderUid) return jsonResponse({ accepted: true, sent: 0 }, 200);
      const [request, follower] = await Promise.all([
        firebaseGet(`social_test/followRequests/${senderUid}/${requesterUid}`, accessToken),
        firebaseGet(`social_test/followers/${senderUid}/${requesterUid}`, accessToken),
      ]);
      const followRequest = asMap(request);
      const followerRecord = asMap(follower);
      if (followRequest?.status !== "accepted" || followerRecord?.status !== "accepted") {
        return jsonResponse({ error: "Follow acceptance was not found" }, 403);
      }
      recipients.push(requesterUid);
      eventKey = `follow-accepted:${senderUid}:${requesterUid}:${String(followRequest.createdAt ?? "")}`;
    } else if (requestedType === "new_post") {
      const postId = text(body.postId);
      if (!postId) return jsonResponse({ error: "Post ID required" }, 400);
      const post = asMap(await firebaseGet(`social_test/postsByUser/${senderUid}/${postId}`, accessToken));
      if (!post || text(post.ownerUid) !== senderUid) return jsonResponse({ error: "Social post not found" }, 404);
      recipients.push(...acceptedFollowerUids(await firebaseGet(`social_test/followers/${senderUid}`, accessToken)));
      objectId = postId;
      eventKey = `new-post:${senderUid}:${postId}`;
    } else if (requestedType === "new_story") {
      const storyId = text(body.storyId);
      if (!storyId) return jsonResponse({ error: "Story ID required" }, 400);
      const story = asMap(await firebaseGet(`social_test/storiesByUser/${senderUid}/${storyId}`, accessToken));
      if (!story || text(story.ownerUid) !== senderUid) return jsonResponse({ error: "Social story not found" }, 404);
      const expiresAt = Number(story.expiresAt);
      if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) return jsonResponse({ accepted: true, sent: 0 }, 200);
      recipients.push(...acceptedFollowerUids(await firebaseGet(`social_test/followers/${senderUid}`, accessToken)));
      objectId = storyId;
      eventKey = `new-story:${senderUid}:${storyId}`;
    }

    const uniqueRecipients = [...new Set(recipients)].filter((uid) => uid && uid !== senderUid);
    let sent = 0;
    let devices = 0;
    for (const recipientUid of uniqueRecipients) {
      const result = await deliverToUser(
        recipientUid,
        senderUid,
        actualType,
        actorName,
        actorUsername,
        objectId,
        eventKey,
        accessToken,
        account,
      );
      sent += result.sent;
      devices += result.devices;
    }
    return jsonResponse({ accepted: true, socialType: actualType, recipientCount: uniqueRecipients.length, deviceCount: devices, sent }, 200);
  } catch (error) {
    console.error("Social push delivery failed", error instanceof Error ? error.message : "Unknown error");
    return jsonResponse({ error: "Social notification delivery failed" }, 502);
  }
});
