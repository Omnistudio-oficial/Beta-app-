import {
  callSignalPath,
  chatFlutterRecipientUids,
  pushEnvironmentForPackage,
  selectRecipientDevices,
  uidForRecipientEmail,
} from "./push-routing.ts";

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${message}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

const NOW = 2_000_000_000_000;
const WEEK = 7 * 24 * 60 * 60 * 1000;
const oldToken = {
  appId: "com.aistudio.omnistudio.wkspea",
  fcmToken: "prod-old",
  email: "ana@example.com",
  lastActiveAt: NOW - WEEK,
};
const recentBetaToken = {
  appId: "com.aistudio.omnistudio.wkspea.test",
  fcmToken: "beta-new",
  email: "ana@example.com",
  lastActiveAt: NOW - 1000,
};

Deno.test("chat and call routing chooses the most recently active supported recipient package", () => {
  const users = {
    uidAna: {
      uid: "uidAna",
      email: "ana@example.com",
      fcmTokens: {
        production: oldToken,
        beta: recentBetaToken,
        betaSecondDevice: { ...recentBetaToken, fcmToken: "beta-second", lastActiveAt: NOW - 2000 },
      },
    },
  };
  const devices = selectRecipientDevices(users, ["ANA@example.com"], NOW);
  assertEquals(devices.map((device) => device.token).sort(), ["beta-new", "beta-second"], "selected tokens");
  assert(devices.every((device) => device.uid === "uidAna"), "recipient UID must accompany each registration");
  assert(devices.every((device) => device.pushEnvironment === "test"), "FCM environment must match the selected receiver app");
  assert(devices.every((device) => device.androidPackage === "com.aistudio.omnistudio.wkspea.test"), "sender package must not control routing");
});

Deno.test("each recipient can independently receive pushes in their own most-recent app", () => {
  const users = {
    uidAna: { email: "ana@example.com", fcmTokens: { a: recentBetaToken } },
    uidLuis: {
      email: "luis@example.com",
      fcmTokens: {
        production: { ...oldToken, email: "luis@example.com", fcmToken: "luis-prod", lastActiveAt: NOW - 1000 },
        beta: { ...recentBetaToken, email: "luis@example.com", fcmToken: "luis-beta", lastActiveAt: NOW - WEEK },
      },
    },
  };
  const devices = selectRecipientDevices(users, ["ana@example.com", "luis@example.com"], NOW);
  assertEquals(
    devices.map(({ email, pushEnvironment }) => [email, pushEnvironment]).sort(),
    [["ana@example.com", "test"], ["luis@example.com", "production"]],
    "independent recipient environments",
  );
});

Deno.test("invalid, disabled, stale, future, and mismatched registrations are excluded", () => {
  const users = {
    uidAna: {
      email: "ana@example.com",
      fcmTokens: {
        unsupported: { ...recentBetaToken, appId: "com.other.app", fcmToken: "unsupported" },
        disabled: { ...recentBetaToken, fcmToken: "disabled", notificationsEnabled: false },
        stale: { ...recentBetaToken, fcmToken: "stale", lastActiveAt: NOW - 271 * 24 * 60 * 60 * 1000 },
        future: { ...recentBetaToken, fcmToken: "future", lastActiveAt: NOW + 60 * 60 * 1000 },
        backgroundRefreshOnly: {
          appId: recentBetaToken.appId,
          fcmToken: "background-only",
          email: "ana@example.com",
          lastTokenRefresh: NOW - 500,
          activityTrackingEnabled: true,
        },
        mismatchedEmail: { ...recentBetaToken, fcmToken: "mismatch", email: "other@example.com" },
        fallback: { ...recentBetaToken, fcmToken: "refresh-fallback", lastActiveAt: undefined, lastTokenRefresh: NOW - 10_000 },
      },
    },
  };
  const devices = selectRecipientDevices(users, ["ana@example.com"], NOW);
  assertEquals(devices.map((device) => device.token), ["refresh-fallback"], "only fresh valid token remains");
});

Deno.test("valid package mapping and private calls are build-independent", () => {
  assertEquals(pushEnvironmentForPackage("com.aistudio.omnistudio.wkspea"), "production", "main package");
  assertEquals(pushEnvironmentForPackage("com.aistudio.omnistudio.wkspea.test"), "test", "Beta package");
  assertEquals(pushEnvironmentForPackage("com.other.app"), null, "unknown package");
  assertEquals(callSignalPath("call-1"), "calls/call-1", "shared call path");
  assertEquals(callSignalPath("call-2"), "calls/call-2", "shared path regardless of originating app");
});

Deno.test("recipient email must resolve to one UID before creating a private call", () => {
  assertEquals(
    uidForRecipientEmail({ uidAna: { uid: "uidAna", email: "ana@example.com" } }, "ANA@example.com"),
    "uidAna",
    "unique account mapping",
  );
  const ambiguousUsers = {
    a: { uid: "uidA", email: "ana@example.com", fcmTokens: { a: recentBetaToken } },
    b: { uid: "uidB", email: "ana@example.com", fcmTokens: { b: { ...recentBetaToken, fcmToken: "other-token" } } },
  };
  assertEquals(
    uidForRecipientEmail(ambiguousUsers, "ana@example.com"),
    null,
    "ambiguous account mapping",
  );
  assertEquals(selectRecipientDevices(ambiguousUsers, ["ana@example.com"], NOW), [], "ambiguous push target must be rejected");
});

Deno.test("Flutter chat recipients must be unique resolved chat members, excluding sender", () => {
  const users = {
    senderUid: { uid: "senderUid", email: "sender@example.com" },
    peerUid: { uid: "peerUid", email: "peer@example.com" },
    outsiderUid: { uid: "outsiderUid", email: "outsider@example.com" },
  };
  assertEquals(
    chatFlutterRecipientUids(users, ["sender@example.com", "peer@example.com"], "sender@example.com", ["peer@example.com", "outsider@example.com", "sender@example.com"]),
    ["peerUid"],
    "only member UID is returned",
  );
  assertEquals(chatFlutterRecipientUids(users, ["peer@example.com"], "sender@example.com", ["peer@example.com"]), [], "non-member sender cannot route chat notification");
});
