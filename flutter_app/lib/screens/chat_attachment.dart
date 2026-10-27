import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import 'chat_media_upload.dart';

class ChatAttachment {
  const ChatAttachment({required this.path, required this.name, required this.mimeType, required this.mediaType});
  final String path;
  final String name;
  final String mimeType;
  final String mediaType;
  bool get isImage => mediaType == 'image' || mediaType == 'gif';
}

abstract interface class ChatAttachmentPicker {
  Future<ChatAttachment?> pickImage();
  Future<ChatAttachment?> pickVideo();
  Future<ChatAttachment?> pickFile();
}

class DeviceChatAttachmentPicker implements ChatAttachmentPicker {
  DeviceChatAttachmentPicker({ImagePicker? imagePicker, FilePicker? filePicker}) : _imagePicker = imagePicker ?? ImagePicker(), _filePicker = filePicker ?? FilePicker.platform;
  final ImagePicker _imagePicker;
  final FilePicker _filePicker;

  @override
  Future<ChatAttachment?> pickImage() async {
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    return file == null ? null : _fromFile(file.path, file.name, file.mimeType);
  }
  @override
  Future<ChatAttachment?> pickVideo() async {
    final file = await _imagePicker.pickVideo(source: ImageSource.gallery);
    return file == null ? null : _fromFile(file.path, file.name, file.mimeType);
  }
  @override
  Future<ChatAttachment?> pickFile() async {
    final result = await _filePicker.pickFiles(type: FileType.custom, allowedExtensions: supportedChatMediaMimeExtensions.values.toSet().toList(), allowMultiple: false, withData: false);
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    if (file.path == null) return null;
    return _fromFile(file.path!, file.name, lookupMimeType(file.name));
  }

  ChatAttachment _fromFile(String path, String name, String? suppliedMime) {
    final mime = (suppliedMime ?? lookupMimeType(name) ?? '').split(';').first.trim().toLowerCase();
    if (!supportedChatMediaMimeExtensions.containsKey(mime)) throw FormatException('Formato no admitido: ${mime.isEmpty ? name : mime}.');
    final type = chatMediaTypeForMime(mime);
    final size = File(path).lengthSync();
    if (size <= 0 || size > maxChatMediaBytes) throw const FormatException('El archivo debe tener entre 1 byte y 50 MiB.');
    return ChatAttachment(path: path, name: name, mimeType: mime, mediaType: type);
  }
}

typedef ChatMediaUpload = Future<UploadedChatMedia> Function(ChatAttachment attachment);
typedef ChatMediaMessageWrite = Future<void> Function(ChatAttachment attachment, UploadedChatMedia uploaded, String caption);
typedef ChatMediaCleanup = Future<void> Function(String storagePath);

/// Shared transactional boundary used by app and offline fakes. Failed message
/// writes trigger a best-effort delete through the authenticated cleanup function.
Future<void> uploadThenSendChatMedia({required ChatAttachment attachment, required String caption, required ChatMediaUpload upload, required ChatMediaMessageWrite writeMessage, required ChatMediaCleanup cleanup}) async {
  final uploaded = await upload(attachment);
  try {
    await writeMessage(attachment, uploaded, caption);
  } catch (_) {
    try { await cleanup(uploaded.storagePath); } catch (_) { /* Preserve the message error. */ }
    rethrow;
  }
}
