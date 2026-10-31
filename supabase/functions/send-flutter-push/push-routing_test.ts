import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FLUTTER_FCM_APP_ID, isAllowedFlutterPushRecipient, isValidDevice } from "./push-routing.ts";
Deno.test("valid Flutter Android and iOS devices only", () => {
  const valid = { uid: "uid-1", appId: FLUTTER_FCM_APP_ID, platform: "ios", token: "opaque-token", tokenHash: "a".repeat(64) };
  assertEquals(isValidDevice(valid), true);
  assertEquals(isValidDevice({ ...valid, appId: "com.aistudio.omnistudio.wkspea" }), false);
  assertEquals(isValidDevice({ ...valid, platform: "web" }), false);
  assertEquals(isValidDevice({ ...valid, token: "x".repeat(4097) }), false);
});
Deno.test("sender only permits authenticated self-test", () => {
  assertEquals(isAllowedFlutterPushRecipient("uid-1", "uid-1"), true);
  assertEquals(isAllowedFlutterPushRecipient("uid-1", "uid-2"), false);
});
