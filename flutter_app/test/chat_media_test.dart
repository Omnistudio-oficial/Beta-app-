import 'dart:io';
import 'package:beta_app/screens/chat_attachment.dart';
import 'package:beta_app/screens/chat_media_upload.dart';
import 'package:beta_app/screens/chat_message_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('supports only deployed backend MIME allowlist and categorizes GIF/file correctly', () {
    expect(chatMediaTypeForMime('image/gif'), 'gif');
    expect(chatMediaTypeForMime('video/quicktime'), 'video');
    expect(chatMediaTypeForMime('audio/ogg'), 'audio');
    expect(chatMediaTypeForMime('audio/mp4'), 'audio');
    expect(chatMediaTypeForMime('application/pdf'), 'document');
    expect(() => chatMediaTypeForMime('application/octet-stream'), throwsFormatException);
    expect(supportedChatMediaMimeExtensions.length, 30);
  });
  test('maps attachment to the existing RTDB media schema with metadata', () {
    const attachment = ChatAttachment(path: '/tmp/demo.pdf', name: 'demo.pdf', mimeType: 'application/pdf', mediaType: 'document');
    final message = betaChatAttachmentMessage(messageId: 'm1', channelId: 'room', senderId: 'uid', senderName: 'Cris', senderEmail: 'c@example.test', caption: '', timestamp: 12, attachment: attachment, mediaUrl: 'https://example.test/demo.pdf');
    expect(message['mediaType'], 'document'); expect(message['mediaFileName'], 'demo.pdf'); expect(message['mediaMimeType'], 'application/pdf'); expect(message['senderId'], 'uid');
    final parsed = ChatMessage.fromMap('m1', 'room', message);
    expect(parsed.mediaUrl, 'https://example.test/demo.pdf'); expect(parsed.mediaFileName, 'demo.pdf');
  });
  test('upload-then-message fake cleans uploaded object after write error', () async {
    final f = File('${Directory.systemTemp.path}/chat-media-fake-${DateTime.now().microsecondsSinceEpoch}.jpg')..writeAsBytesSync([1, 2, 3]);
    final attachment = ChatAttachment(path: f.path, name: 'x.jpg', mimeType: 'image/jpeg', mediaType: 'image');
    var uploads = 0, writes = 0, cleanups = 0;
    await expectLater(uploadThenSendChatMedia(attachment: attachment, caption: 'caption', upload: (_) async { uploads++; return const UploadedChatMedia(storagePath: 'users/u/media/p/file.jpg', publicUrl: 'https://public.test/x.jpg'); }, writeMessage: (_, __, ___) async { writes++; throw StateError('offline'); }, cleanup: (_) async { cleanups++; }), throwsStateError);
    expect([uploads, writes, cleanups], [1, 1, 1]);
    await f.delete();
  });
  test('upload failure never attempts message write or cleanup', () async {
    const attachment = ChatAttachment(path: 'mock.jpg', name: 'x.jpg', mimeType: 'image/jpeg', mediaType: 'image');
    var writes = 0, cleanups = 0;
    await expectLater(uploadThenSendChatMedia(attachment: attachment, caption: '', upload: (_) async => throw StateError('upload failed'), writeMessage: (_, __, ___) async { writes++; }, cleanup: (_) async { cleanups++; }), throwsStateError);
    expect(writes, 0); expect(cleanups, 0);
  });
}
