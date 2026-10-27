import { assertEquals, assertNotEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  createStoragePath,
  extractBearerToken,
  MAX_UPLOAD_BYTES,
  parseUploadRequest,
} from "./validation.ts";

Deno.test("accepts only a bounded Firebase Bearer token", () => {
  assertEquals(extractBearerToken("Bearer firebase-id-token"), "firebase-id-token");
  assertEquals(extractBearerToken("Basic firebase-id-token"), null);
  assertEquals(extractBearerToken(`Bearer ${"x".repeat(4097)}`), null);
  assertEquals(extractBearerToken(null), null);
});

Deno.test("whitelists supported image, video, audio, and document MIME types", () => {
  assertEquals(parseUploadRequest({ mediaType: "image", mimeType: "IMAGE/JPEG", sizeBytes: 1 })?.mimeType, "image/jpeg");
  assertEquals(parseUploadRequest({ mediaType: "video", mimeType: "video/mp4", sizeBytes: 1 })?.mimeType, "video/mp4");
  assertEquals(parseUploadRequest({ mediaType: "audio", mimeType: "audio/ogg", sizeBytes: 1 })?.mimeType, "audio/ogg");
  assertEquals(parseUploadRequest({ mediaType: "audio", mimeType: "audio/mp4", sizeBytes: 1 })?.mimeType, "audio/mp4");
  assertEquals(parseUploadRequest({ mediaType: "document", mimeType: "application/pdf", sizeBytes: 1 })?.mimeType, "application/pdf");
  assertEquals(parseUploadRequest({ mediaType: "gif", mimeType: "image/gif", sizeBytes: 1 })?.mediaType, "gif");
  assertEquals(parseUploadRequest({ mediaType: "image", mimeType: "application/pdf", sizeBytes: 1 }), null);
  assertEquals(parseUploadRequest({ mediaType: "video", mimeType: "image/jpeg", sizeBytes: 1 }), null);
  assertEquals(parseUploadRequest({ mediaType: "image", mimeType: "application/octet-stream", sizeBytes: 1 }), null);
  assertEquals(parseUploadRequest({ mediaType: "document", mimeType: "application/x-msdownload", sizeBytes: 1 }), null);
});

Deno.test("rejects client-selected paths, UIDs, extra input, and out-of-limit sizes", () => {
  assertEquals(parseUploadRequest({ mediaType: "image", mimeType: "image/png", sizeBytes: 1, storagePath: "users/other" }), null);
  assertEquals(parseUploadRequest({ mediaType: "image", mimeType: "image/png", sizeBytes: 1, uid: "other-user" }), null);
  assertEquals(parseUploadRequest({ mediaType: "image", mimeType: "image/png", sizeBytes: 1, fileName: "chosen.png" }), null);
  assertEquals(parseUploadRequest({ mediaType: "image", mimeType: "image/png", sizeBytes: 0 }), null);
  assertEquals(parseUploadRequest({ mediaType: "image", mimeType: "image/png", sizeBytes: MAX_UPLOAD_BYTES + 1 }), null);
  assertEquals(parseUploadRequest({ mediaType: "image", mimeType: "image/png", sizeBytes: 1.5 }), null);
  assertEquals(parseUploadRequest({ mediaType: "image", mimeType: "image/png", sizeBytes: "1" }), null);
  assertEquals(parseUploadRequest({ mediaType: "image", mimeType: "image/png", sizeBytes: MAX_UPLOAD_BYTES })?.sizeBytes, MAX_UPLOAD_BYTES);
});

Deno.test("server-generated storage path is unique and scoped to the verified UID", () => {
  const first = createStoragePath("firebaseUid_123", "image/jpeg");
  const second = createStoragePath("firebaseUid_123", "image/jpeg");
  assertEquals(first.startsWith("users/firebaseUid_123/media/"), true);
  assertEquals(first.split("/").length, 5);
  assertEquals(first.endsWith(".jpg"), true);
  assertNotEquals(first, second);
  try {
    createStoragePath("bad/uid", "image/jpeg");
    throw new Error("Expected invalid UID to be rejected");
  } catch (error) {
    assertEquals(error instanceof TypeError, true);
  }
});
