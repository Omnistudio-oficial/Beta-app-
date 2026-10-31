import { FLUTTER_FCM_APP_ID, selectFlutterDevices } from "./flutter-fcm.ts";
function eq(actual: unknown, expected: unknown, label: string) { if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error(`${label}: ${JSON.stringify(actual)}`); }
Deno.test("Flutter token lookup is restricted to server-selected UIDs and supported app/platform", () => {
  const base = { uid: "uid_1", app_id: FLUTTER_FCM_APP_ID, platform: "android", fcm_token: "opaque-token", token_hash: "a".repeat(64) };
  const rows = [base, { ...base, platform: "ios" }, { ...base, uid: "other", platform: "android" }, { ...base, app_id: "legacy", platform: "android" }, { ...base, platform: "web" }, { ...base, token_hash: "bad" }];
  eq(selectFlutterDevices(["uid_1"], rows).map((d) => d.platform), ["android", "ios"], "eligible platform list");
  eq(selectFlutterDevices(["other"], rows).length, 0, "unselected UID cannot be routed");
  eq(selectFlutterDevices([], rows).length, 0, "no recipients means no devices");
});
