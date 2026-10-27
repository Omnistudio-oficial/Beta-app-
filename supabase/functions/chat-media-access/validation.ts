export const MAX_UPLOAD_BYTES = 50 * 1024 * 1024;
export const MAX_ID_TOKEN_LENGTH = 4096;

export type SupportedMedia = {
  extension: string;
  category: "image" | "video" | "audio" | "document";
};

// Allow only formats currently used by chat's image/video/audio/document picker.
// Generic binary MIME types, executable formats, and unknown extensions are rejected.
export const SUPPORTED_MEDIA: Readonly<Record<string, SupportedMedia>> = {
  "image/jpeg": { extension: "jpg", category: "image" },
  "image/png": { extension: "png", category: "image" },
  "image/webp": { extension: "webp", category: "image" },
  "image/gif": { extension: "gif", category: "image" },
  "image/bmp": { extension: "bmp", category: "image" },
  "image/heic": { extension: "heic", category: "image" },
  "image/heif": { extension: "heif", category: "image" },
  "video/mp4": { extension: "mp4", category: "video" },
  "video/quicktime": { extension: "mov", category: "video" },
  "video/webm": { extension: "webm", category: "video" },
  "video/3gpp": { extension: "3gp", category: "video" },
  "video/x-m4v": { extension: "m4v", category: "video" },
  "video/x-matroska": { extension: "mkv", category: "video" },
  "video/x-msvideo": { extension: "avi", category: "video" },
  "video/x-flv": { extension: "flv", category: "video" },
  "video/x-ms-wmv": { extension: "wmv", category: "video" },
  "audio/mpeg": { extension: "mp3", category: "audio" },
  "audio/wav": { extension: "wav", category: "audio" },
  "audio/x-wav": { extension: "wav", category: "audio" },
  "audio/mp4": { extension: "m4a", category: "audio" },
  "audio/aac": { extension: "aac", category: "audio" },
  "audio/ogg": { extension: "ogg", category: "audio" },
  "audio/mp4": { extension: "m4a", category: "audio" },
  "audio/flac": { extension: "flac", category: "audio" },
  "audio/opus": { extension: "opus", category: "audio" },
  "application/pdf": { extension: "pdf", category: "document" },
  "application/msword": { extension: "doc", category: "document" },
  "application/rtf": { extension: "rtf", category: "document" },
  "application/json": { extension: "json", category: "document" },
  "application/zip": { extension: "zip", category: "document" },
  "application/vnd.ms-excel": { extension: "xls", category: "document" },
  "application/vnd.ms-powerpoint": { extension: "ppt", category: "document" },
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document": {
    extension: "docx",
    category: "document",
  },
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": {
    extension: "xlsx",
    category: "document",
  },
  "application/vnd.openxmlformats-officedocument.presentationml.presentation": {
    extension: "pptx",
    category: "document",
  },
  "text/plain": { extension: "txt", category: "document" },
  "text/csv": { extension: "csv", category: "document" },
};

export type UploadRequest = {
  mediaType: "image" | "video" | "audio" | "gif" | "sticker" | "document";
  mimeType: string;
  sizeBytes: number;
};

export function extractBearerToken(header: string | null): string | null {
  const match = /^Bearer\s+(\S+)$/i.exec(header ?? "");
  if (!match || match[1].length > MAX_ID_TOKEN_LENGTH) return null;
  return match[1];
}

export function parseUploadRequest(input: unknown): UploadRequest | null {
  if (input === null || typeof input !== "object" || Array.isArray(input)) return null;
  const value = input as Record<string, unknown>;
  const keys = Object.keys(value).sort();
  if (keys.length !== 3 || keys[0] !== "mediaType" || keys[1] !== "mimeType" || keys[2] !== "sizeBytes") return null;
  if (typeof value.mediaType !== "string" || typeof value.mimeType !== "string") return null;
  if (typeof value.sizeBytes !== "number" || !Number.isSafeInteger(value.sizeBytes)) return null;
  if (value.sizeBytes < 1 || value.sizeBytes > MAX_UPLOAD_BYTES) return null;

  const mediaType = value.mediaType;
  if (!(mediaType === "image" || mediaType === "video" || mediaType === "audio" || mediaType === "gif" || mediaType === "sticker" || mediaType === "document")) return null;
  const mimeType = value.mimeType.toLowerCase().split(";", 1)[0].trim();
  const media = SUPPORTED_MEDIA[mimeType];
  if (!media) return null;
  const expectedCategory = mediaType === "gif" || mediaType === "sticker" ? "image" : mediaType;
  if (media.category !== expectedCategory) return null;
  return { mediaType, mimeType, sizeBytes: value.sizeBytes };
}

export function createStoragePath(uid: string, mimeType: string, id = crypto.randomUUID()): string {
  const media = SUPPORTED_MEDIA[mimeType];
  if (!media || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) {
    throw new TypeError("Invalid authenticated upload identity or media type");
  }
  // The filename and both random path components are generated on the server.
  return `users/${uid}/media/${id}/${crypto.randomUUID()}.${media.extension}`;
}
