import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  flutterFcmAppId,
  validateFirebaseIdToken,
  validateFcmDeviceRequest,
  validFirebaseUid,
} from "./authorization.ts";

Deno.test("accepts bounded Firebase ID tokens only", () => {
  assertEquals(validateFirebaseIdToken("valid-id-token"), true);
  assertEquals(validateFirebaseIdToken(""), false);
  assertEquals(validateFirebaseIdToken("x".repeat(4097)), false);
  assertEquals(validateFirebaseIdToken(null), false);
});

Deno.test("accepts only the Flutter app device registration shape", () => {
  assertEquals(validateFcmDeviceRequest({
    action: "register", appId: flutterFcmAppId, platform: "ios", token: "opaque-fcm-token",
  }), { action: "register", appId: flutterFcmAppId, platform: "ios", token: "opaque-fcm-token" });
  assertEquals(validateFcmDeviceRequest({
    action: "unregister", appId: flutterFcmAppId, platform: "android", token: "opaque-fcm-token",
  })?.action, "unregister");
  assertEquals(validateFcmDeviceRequest({ action: "register", appId: "other", platform: "ios", token: "x" }), null);
  assertEquals(validateFcmDeviceRequest({ action: "register", appId: flutterFcmAppId, platform: "web", token: "x" }), null);
  assertEquals(validateFcmDeviceRequest({ action: "register", appId: flutterFcmAppId, platform: "ios", token: "" }), null);
  assertEquals(validateFcmDeviceRequest([]), null);
});

Deno.test("restricts Firebase UID filter input", () => {
  assertEquals(validFirebaseUid("firebaseUid_123-"), true);
  assertEquals(validFirebaseUid("bad/uid"), false);
  assertEquals(validFirebaseUid(""), false);
  assertEquals(validFirebaseUid("u".repeat(129)), false);
});
