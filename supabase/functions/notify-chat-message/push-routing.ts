export type PushEnvironment = "test" | "production";

const TEST_ANDROID_PACKAGE = "com.aistudio.omnistudio.wkspea.test";
const PRODUCTION_ANDROID_PACKAGE = "com.aistudio.omnistudio.wkspea";
const DEFAULT_MAX_ACTIVE_AGE_MS = 270 * 24 * 60 * 60 * 1000;
const MAX_FUTURE_CLOCK_SKEW_MS = 5 * 60 * 1000;

type DataMap = Record<string, unknown>;

export type RecipientDevice = {
  uid: string;
  email: string;
  token: string;
  documentName: string;
  androidPackage: string;
  pushEnvironment: PushEnvironment;
  lastActiveAt: number;
};

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function normalizeEmail(value: unknown): string {
  return text(value).toLowerCase();
}

function asMap(value: unknown): DataMap | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as DataMap
    : null;
}

function timestamp(value: unknown): number | null {
  const parsed = typeof value === "number"
    ? value
    : typeof value === "string" && value.trim() !== ""
    ? Number(value)
    : Number.NaN;
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

export function pushEnvironmentForPackage(value: unknown): PushEnvironment | null {
  const androidPackage = text(value);
  if (androidPackage === TEST_ANDROID_PACKAGE) return "test";
  if (androidPackage === PRODUCTION_ANDROID_PACKAGE) return "production";
  return null;
}

/** All supported clients use the same private, participant-protected call namespace. */
export function callSignalPath(callId: string): string {
  return `calls/${callId}`;
}

/**
 * Resolve an email to exactly one UID from the server-read user directory. Both
 * UID-keyed token records and email-keyed legacy profile records may be present.
 * Ambiguous identities are deliberately rejected rather than guessed.
 */
export function uidForRecipientEmail(usersValue: unknown, email: string): string | null {
  const requestedEmail = normalizeEmail(email);
  const users = asMap(usersValue);
  if (!requestedEmail || !users) return null;

  const matches = new Set<string>();
  for (const [key, userValue] of Object.entries(users)) {
    const user = asMap(userValue);
    if (!user || normalizeEmail(user.email) !== requestedEmail) continue;
    const uid = text(user.uid) || key;
    if (uid) matches.add(uid);
  }
  return matches.size === 1 ? [...matches][0] : null;
}

/** Resolve Flutter recipients only from verified chat-member emails and the
 * server-read Firebase user directory. The authenticated sender is excluded. */
export function chatFlutterRecipientUids(
  usersValue: unknown,
  memberEmails: string[],
  senderEmail: string,
  requestedEmails: string[],
): string[] {
  const members = new Set(memberEmails.map(normalizeEmail).filter(Boolean));
  const sender = normalizeEmail(senderEmail);
  if (!sender || !members.has(sender)) return [];
  return [...new Set(requestedEmails.map(normalizeEmail)
    .filter((email) => email && email !== sender && members.has(email))
    .map((email) => uidForRecipientEmail(usersValue, email))
    .filter((uid): uid is string => Boolean(uid)))];
}

/**
 * Select active, valid FCM registrations per recipient. A recipient is routed
 * only to the app package with the newest foreground activity; all eligible
 * tokens for that winning package are retained. Only registrations active
 * within FCM's 270-day Android token-validity window are considered. Older
 * clients fall back to lastTokenRefresh until they start writing lastActiveAt.
 */
export function selectRecipientDevices(
  usersValue: unknown,
  requestedEmails: string[],
  now = Date.now(),
  maxActiveAgeMs = DEFAULT_MAX_ACTIVE_AGE_MS,
): RecipientDevice[] {
  const users = asMap(usersValue);
  if (!users || !Number.isFinite(now) || maxActiveAgeMs <= 0) return [];
  const requested = new Set(requestedEmails.map(normalizeEmail).filter(Boolean));
  if (requested.size === 0) return [];

  const uidByEmail = new Map<string, string | null>();
  for (const [key, userValue] of Object.entries(users)) {
    const user = asMap(userValue);
    if (!user) continue;
    const email = normalizeEmail(user.email);
    if (!requested.has(email)) continue;
    const uid = text(user.uid) || key;
    if (!uid) continue;
    const existing = uidByEmail.get(email);
    uidByEmail.set(email, existing === undefined || existing === uid ? uid : null);
  }

  const candidates: RecipientDevice[] = [];
  for (const [key, userValue] of Object.entries(users)) {
    const user = asMap(userValue);
    if (!user) continue;
    const email = normalizeEmail(user.email);
    if (!requested.has(email)) continue;
    const uid = text(user.uid) || key;
    if (!uid || uidByEmail.get(email) !== uid) continue;
    const tokenEntries = asMap(user.fcmTokens);
    if (!tokenEntries) continue;

    for (const [tokenId, deviceValue] of Object.entries(tokenEntries)) {
      const device = asMap(deviceValue);
      if (!device || device.notificationsEnabled === false) continue;
      const deviceEmail = normalizeEmail(device.email);
      if (deviceEmail && deviceEmail !== email) continue;
      const androidPackage = text(device.appId);
      const pushEnvironment = pushEnvironmentForPackage(androidPackage);
      if (!pushEnvironment) continue;
      const token = text(device.fcmToken);
      if (!token || token.length > 4096) continue;

      const lastActiveAt = timestamp(device.lastActiveAt) ?? (
        device.activityTrackingEnabled === true ? 0 : timestamp(device.lastTokenRefresh) ?? 0
      );
      if (
        lastActiveAt <= 0 ||
        lastActiveAt < now - maxActiveAgeMs ||
        lastActiveAt > now + MAX_FUTURE_CLOCK_SKEW_MS
      ) continue;

      candidates.push({
        uid,
        email,
        token,
        documentName: `users/${uid}/fcmTokens/${tokenId}`,
        androidPackage,
        pushEnvironment,
        lastActiveAt,
      });
    }
  }

  const latestByEmail = new Map<string, RecipientDevice>();
  for (const candidate of candidates) {
    const latest = latestByEmail.get(candidate.email);
    if (
      !latest ||
      candidate.lastActiveAt > latest.lastActiveAt ||
      (candidate.lastActiveAt === latest.lastActiveAt && candidate.androidPackage < latest.androidPackage)
    ) latestByEmail.set(candidate.email, candidate);
  }

  const winningPackageByEmail = new Map(
    [...latestByEmail].map(([email, device]) => [email, device.androidPackage]),
  );
  const uniqueTokens = new Map<string, RecipientDevice>();
  for (const candidate of candidates) {
    if (winningPackageByEmail.get(candidate.email) !== candidate.androidPackage) continue;
    const uniqueKey = `${candidate.uid}\u0000${candidate.token}`;
    const existing = uniqueTokens.get(uniqueKey);
    if (!existing || candidate.lastActiveAt > existing.lastActiveAt) {
      uniqueTokens.set(uniqueKey, candidate);
    }
  }
  return [...uniqueTokens.values()];
}
