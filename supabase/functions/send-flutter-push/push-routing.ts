export type FlutterPushPlatform = "android" | "ios";
export type PrivateFcmDevice = { uid: string; appId: string; platform: FlutterPushPlatform; token: string; tokenHash: string };
export const FLUTTER_FCM_APP_ID = "com.omnistudio.omnistudioFlutterPrototype";
export const isValidUid = (uid: unknown): uid is string =>
  typeof uid === "string" && uid.length > 0 && uid.length <= 128 && /^[A-Za-z0-9_-]+$/.test(uid);
export const isValidDevice = (row: unknown): row is PrivateFcmDevice => {
  if (!row || typeof row !== "object" || Array.isArray(row)) return false;
  const device = row as Record<string, unknown>;
  return isValidUid(device.uid) && device.appId === FLUTTER_FCM_APP_ID &&
    (device.platform === "android" || device.platform === "ios") &&
    typeof device.token === "string" && device.token.length > 0 && device.token.length <= 4096 &&
    typeof device.tokenHash === "string" && /^[a-f0-9]{64}$/.test(device.tokenHash);
};
export const isAllowedFlutterPushRecipient = (senderUid: string, recipientUid: unknown): recipientUid is string =>
  isValidUid(recipientUid) && senderUid === recipientUid;
