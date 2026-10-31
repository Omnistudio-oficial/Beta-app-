import { sendFlutterPushToUids } from "../_shared/flutter-fcm.ts";
import { callSignalPath, chatFlutterRecipientUids, selectRecipientDevices, uidForRecipientEmail } from "./push-routing.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const FIREBASE_PROJECT_ID = "omnistudio-caaf5";
const FIREBASE_DATABASE_URL = "https://omnistudio-caaf5-default-rtdb.firebaseio.com";
const MAX_ID_TOKEN_LENGTH = 4096;
const MAX_ID_LENGTH = 256;
const GOOGLE_OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token";
const FIREBASE_IDENTITY_LOOKUP_URL = "https://identitytoolkit.googleapis.com/v1/accounts:lookup";
const GOOGLE_SCOPE = [
  "https://www.googleapis.com/auth/userinfo.email",
  "https://www.googleapis.com/auth/firebase.database",
  "https://www.googleapis.com/auth/datastore",
  "https://www.googleapis.com/auth/firebase.messaging",
].join(" ");

type FirebaseIdentity = {
  uid: string;
  email: string;
};

type ServiceAccount = {
  client_email: string;
  private_key: string;
  project_id: string;
};

type DataMap = Record<string, unknown>;

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function normalizeEmail(value: unknown): string {
  return text(value).toLowerCase();
}

function extractBearerToken(request: Request): string | null {
  const match = /^Bearer\s+(\S+)$/i.exec(request.headers.get("authorization") ?? "");
  if (!match || match[1].length > MAX_ID_TOKEN_LENGTH) return null;
  return match[1];
}

function isValidDatabaseKey(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= MAX_ID_LENGTH && /^[A-Za-z0-9_.-]+$/.test(value);
}

function asMembers(value: unknown): DataMap[] {
  if (Array.isArray(value)) {
    return value.filter((item): item is DataMap => !!item && typeof item === "object");
  }
  if (value && typeof value === "object") {
    return Object.values(value as Record<string, unknown>)
      .filter((item): item is DataMap => !!item && typeof item === "object");
  }
  return [];
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
  const email = normalizeEmail(user?.email);
  if (!uid || !email || user?.disabled === true) return null;
  return { uid, email };
}

function decodePrivateKey(pem: string): ArrayBuffer {
  const clean = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\\n/g, "\n")
    .replace(/\s/g, "");
  const binary = atob(clean);
  const buffer = new ArrayBuffer(binary.length);
  const bytes = new Uint8Array(buffer);
  for (let index = 0; index < binary.length; index++) {
    bytes[index] = binary.charCodeAt(index);
  }
  return buffer;
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function getGoogleAccessToken(serviceAccount: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = base64Url(new TextEncoder().encode(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: GOOGLE_SCOPE,
    aud: GOOGLE_OAUTH_TOKEN_URL,
    iat: now,
    exp: now + 3600,
  })));
  const unsignedJwt = `${header}.${claims}`;
  const privateKey = serviceAccount.private_key.replace(/\\n/g, "\n");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    decodePrivateKey(privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsignedJwt),
  ));
  const assertion = `${unsignedJwt}.${base64Url(signature)}`;
  const response = await fetch(GOOGLE_OAUTH_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) throw new Error(`Google OAuth token request failed (${response.status})`);
  const tokenBody = await response.json() as { access_token?: string };
  if (!tokenBody.access_token) throw new Error("Google OAuth response had no access token");
  return tokenBody.access_token;
}

async function firebaseGet(path: string, accessToken: string): Promise<unknown> {
  const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  const response = await fetch(`${FIREBASE_DATABASE_URL}/${encodedPath}.json`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok) throw new Error(`Firebase Database read failed (${response.status})`);
  return await response.json();
}

function findDeviceTokens(
  usersValue: unknown,
  emails: string[],
): Array<{ uid: string; token: string; documentName: string; pushEnvironment: "test" | "production" }> {
  return selectRecipientDevices(usersValue, emails).map(({ uid, token, documentName, pushEnvironment }) => ({
    uid,
    token,
    documentName,
    pushEnvironment,
  }));
}

function messagePreview(message: DataMap): string {
  const body = text(message.text);
  if (body) return body.slice(0, 600);
  const mediaType = text(message.mediaType).toLowerCase();
  if (mediaType === "image" || mediaType === "photo") return "Te enviaron una imagen";
  if (mediaType === "video") return "Te enviaron un video";
  if (mediaType === "audio" || mediaType === "voice") return "Te enviaron un audio";
  if (mediaType === "file" || mediaType === "document") return "Te enviaron un archivo";
  return "Nuevo mensaje";
}

async function sendFcm(token: string, payload: Record<string, string>, accessToken: string): Promise<Response> {
  return await fetch(`https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      message: {
        token,
        data: payload,
        android: {
          priority: "HIGH",
          collapseKey: payload.eventType === "call"
            ? `call_${payload.callId || payload.channelId}`.slice(0, 64)
            : `chat_${payload.channelId}`.slice(0, 64),
        },
      },
    }),
  });
}

async function removeStaleToken(documentPath: string, accessToken: string): Promise<void> {
  const encodedPath = documentPath.split("/").map(encodeURIComponent).join("/");
  const response = await fetch(`${FIREBASE_DATABASE_URL}/${encodedPath}.json`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok && response.status !== 404) {
    console.warn("Could not remove a stale device token", { status: response.status });
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const idToken = extractBearerToken(request);
  if (!idToken) return jsonResponse({ error: "Firebase authentication required" }, 401);

  const firebaseWebApiKey = Deno.env.get("FIREBASE_WEB_API_KEY");
  const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!firebaseWebApiKey || !serviceAccountJson) {
    return jsonResponse({ error: "Chat notifications are not configured" }, 503);
  }

  let payload: { eventType?: unknown; channelId?: unknown; messageId?: unknown; callId?: unknown };
  try {
    payload = await request.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }
  const eventType = payload.eventType == null ? "message" : text(payload.eventType);
  if (eventType !== "message" && eventType !== "call") {
    return jsonResponse({ error: "Unsupported notification event" }, 400);
  }
  if (!isValidDatabaseKey(payload.channelId)) {
    return jsonResponse({ error: "Invalid chat identifier" }, 400);
  }
  if (eventType === "message" && !isValidDatabaseKey(payload.messageId)) {
    return jsonResponse({ error: "Invalid message identifier" }, 400);
  }
  if (eventType === "call" && !isValidDatabaseKey(payload.callId)) {
    return jsonResponse({ error: "Invalid call identifier" }, 400);
  }
  let identity: FirebaseIdentity | null;
  try {
    identity = await verifyFirebaseIdToken(idToken, firebaseWebApiKey);
  } catch {
    return jsonResponse({ error: "Firebase token verification failed" }, 401);
  }
  if (!identity) return jsonResponse({ error: "Firebase token verification failed" }, 401);

  let serviceAccount: ServiceAccount;
  try {
    serviceAccount = JSON.parse(serviceAccountJson) as ServiceAccount;
  } catch {
    return jsonResponse({ error: "Firebase server credentials are invalid" }, 503);
  }
  if (!serviceAccount.client_email || !serviceAccount.private_key || serviceAccount.project_id !== FIREBASE_PROJECT_ID) {
    return jsonResponse({ error: "Firebase server credentials do not match this project" }, 503);
  }

  try {
    const channelId = payload.channelId;
    const accessToken = await getGoogleAccessToken(serviceAccount);
    const eventPath = eventType === "call"
      ? callSignalPath(payload.callId as string)
      : `chats/${channelId}/messages/${payload.messageId as string}`;
    const [channelValue, eventValue, usersValue] = await Promise.all([
      firebaseGet(`chats/${channelId}`, accessToken),
      firebaseGet(eventPath, accessToken),
      firebaseGet("users", accessToken),
    ]);
    const channel = channelValue && typeof channelValue === "object" ? channelValue as DataMap : null;
    const event = eventValue && typeof eventValue === "object" ? eventValue as DataMap : null;
    if (!channel || !event) return jsonResponse({ error: "Chat event not found" }, 404);

    if (eventType === "message") {
      if (text(event.senderId) !== identity.uid || normalizeEmail(event.senderEmail) !== identity.email) {
        return jsonResponse({ error: "Message sender does not match the authenticated account" }, 403);
      }
    } else {
      if (text(event.callId) !== payload.callId || text(event.channelId) !== channelId) {
        return jsonResponse({ error: "Call identifiers do not match" }, 403);
      }
      if (text(event.status) !== "RINGING") return jsonResponse({ accepted: true, sent: 0 }, 200);
      if (text(event.callerUid) !== identity.uid || normalizeEmail(event.callerEmail) !== identity.email) {
        return jsonResponse({ error: "Call sender does not match the authenticated account" }, 403);
      }
    }

    const members = asMembers(channel.members);
    const memberEmails = [...new Set(members.map((member) => normalizeEmail(member.email)).filter(Boolean))];
    if (!memberEmails.includes(identity.email)) return jsonResponse({ error: "Sender is not a chat member" }, 403);
    const isGroup = channel.isGroup === true;
    let recipientEmails = memberEmails.filter((email) => email !== identity.email);

    if (eventType === "call") {
      if (isGroup || channel.isDirect !== true) {
        return jsonResponse({ error: "Call notifications are restricted to one-to-one private chats" }, 403);
      }
      const peerEmail = normalizeEmail(event.peerEmail);
      const peerUid = uidForRecipientEmail(usersValue, peerEmail);
      if (
        !peerEmail || peerEmail === identity.email || !memberEmails.includes(peerEmail) ||
        !peerUid || text(event.peerUid) !== peerUid
      ) {
        return jsonResponse({ error: "Call recipient is not a verified member of the private chat" }, 403);
      }
      recipientEmails = [peerEmail];
    }

    if (recipientEmails.length === 0) {
      console.info("Push notification has no recipients", { eventType, isGroup, memberCount: members.length });
      return jsonResponse({ accepted: true, sent: 0, recipientCount: 0, deviceCount: 0 }, 200);
    }

    const devices = findDeviceTokens(usersValue, recipientEmails);
    // UIDs are resolved from the server-read Firebase directory using the
    // already-authorized chat member emails; never accept recipient UIDs from client input.
    const flutterRecipientUids = chatFlutterRecipientUids(
      usersValue, memberEmails, identity.email, recipientEmails,
    );
    if (devices.length === 0 && flutterRecipientUids.length === 0) {
      console.info("Push notification has no eligible devices", {
        eventType, isGroup, memberCount: members.length, recipientCount: recipientEmails.length,
      });
      return jsonResponse({ accepted: true, sent: 0, recipientCount: recipientEmails.length, deviceCount: 0 }, 200);
    }

    const fcmPayload: Record<string, string> = eventType === "call"
      ? {
        eventType: "call",
        callId: text(event.callId),
        channelId,
        channelName: text(channel.name) || "Chat",
        callerName: text(event.callerName) || identity.email,
        callerEmail: identity.email,
        groupName: isGroup ? (text(channel.name) || text(event.groupName)) : "",
        isVideo: String(event.isVideo === true),
        isGroup: String(isGroup),
        timeoutMinutes: "5",
      }
      : {
        eventType: "message",
        channelId,
        channelName: text(channel.name) || "Chat",
        senderName: text(event.senderName) || identity.email,
        senderEmail: identity.email,
        text: messagePreview(event),
        isGroup: String(isGroup),
        messageId: text(event.messageId) || (payload.messageId as string),
      };

    let sent = 0;
    for (const device of devices) {
      const recipientPayload = {
        ...fcmPayload,
        recipientUid: device.uid,
        pushEnvironment: device.pushEnvironment,
      };
      const response = await sendFcm(device.token, recipientPayload, accessToken);
      if (response.ok) {
        sent++;
      } else {
        const errorBody = await response.json().catch(() => ({})) as { error?: { details?: Array<{ errorCode?: string }> } };
        const errorCodes = errorBody.error?.details?.map((detail) => detail.errorCode) ?? [];
        if (response.status === 404 || errorCodes.includes("UNREGISTERED")) {
          await removeStaleToken(device.documentName, accessToken);
        } else {
          console.warn("FCM rejected a notification", { eventType, status: response.status });
        }
      }
    }

    const flutterResult = await sendFlutterPushToUids({
      uids: flutterRecipientUids,
      title: eventType === "call"
        ? `${text(event.callerName) || identity.email} te está llamando`
        : `${text(event.senderName) || identity.email} te envió un mensaje`,
      body: eventType === "call" ? "Toca para abrir OmniStudio" : messagePreview(event),
      data: { ...fcmPayload, isFlutterPush: "true" },
      account: serviceAccount,
    });
    const totalDevices = devices.length + flutterResult.devices;
    sent += flutterResult.sent;
    console.info("Push notification delivery result", {
      eventType, isGroup, memberCount: members.length, recipientCount: recipientEmails.length,
      deviceCount: totalDevices, sent,
    });
    return jsonResponse({
      accepted: true,
      sent,
      recipientCount: recipientEmails.length,
      deviceCount: totalDevices,
    }, 200);
  } catch (error) {
    console.error("Push notification request failed", {
      message: error instanceof Error ? error.message : "Unknown server error",
    });
    return jsonResponse({ error: "Chat notification delivery failed" }, 502);
  }
});
