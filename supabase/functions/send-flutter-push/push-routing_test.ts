import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FLUTTER_FCM_APP_ID, isAllowedFlutterPushRecipient, isValidDevice, isValidUid } from "./push-routing.ts";
Deno.test("accepts only private Flutter Android/iOS device rows", () => {
  const base = { uid: "uid_1", appId: FLUTTER_FCM_APP_ID, platform: "ios", token: "opaque", tokenHash: "a".repeat(64) };
  assertEquals(isValidDevice(base), true);
  assertEquals(isValidDevice({ ...base, platform: "web" }), false);
  assertEquals(isValidDevice({ ...base, appId: "com.aistudio.omnistudio.wkspea" }), false);
  assertEquals(isValidDevice({ ...base, token: "x".repeat(4097) }), false);
});
Deno.test("restricts this sender to authenticated self-test", () => {
  assertEquals(isAllowedFlutterPushRecipient("uid_1", "uid_1"), true);
  assertEquals(isAllowedFlutterPushRecipient("uid_1", "uid_2"), false);
});
Deno.test("validates user IDs", () => {
  assertEquals(isValidUid("uid_123"), true);
  assertEquals(isValidUid("uid/123"), false);
});
