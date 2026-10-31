export const flutterFcmAppId = "com.omnistudio.omnistudioFlutterPrototype";
export const maxFirebaseIdTokenLength = 4096;
export const maxFcmTokenLength = 4096;
export const maxFirebaseUidLength = 128;

export type FcmPlatform = "android" | "ios";
export type FcmDeviceAction = "register" | "unregister";

export function validateFirebaseIdToken(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= maxFirebaseIdTokenLength;
}

export function validateFcmDeviceRequest(value: unknown): {
  action: FcmDeviceAction;
  appId: typeof flutterFcmAppId;
  platform: FcmPlatform;
  token: string;
} | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const body = value as Record<string, unknown>;
  const action = body.action;
  const appId = body.appId;
  const platform = body.platform;
  const token = body.token;
  if (action !== "register" && action !== "unregister") return null;
  if (appId !== flutterFcmAppId) return null;
  if (platform !== "android" && platform !== "ios") return null;
  if (typeof token !== "string" || token.length < 1 || token.length > maxFcmTokenLength) return null;
  return { action, appId, platform, token };
}

export function validFirebaseUid(uid: unknown): uid is string {
  return typeof uid === "string" && uid.length > 0 && uid.length <= maxFirebaseUidLength && /^[A-Za-z0-9_-]+$/.test(uid);
}
