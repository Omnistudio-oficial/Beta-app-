import 'chat_attachment.dart';

Map<String, Object?> betaChatAttachmentMessage({required String messageId, required String channelId, required String senderId, required String senderName, required String senderEmail, required String caption, required int timestamp, required ChatAttachment attachment, required String mediaUrl}) {
  if (mediaUrl.isEmpty) throw ArgumentError('La URL multimedia es obligatoria.');
  return {
    'firestoreId': messageId,
    'channelId': channelId,
    'senderId': senderId,
    'senderName': senderName,
    'senderEmail': senderEmail,
    'text': caption.trim().isNotEmpty ? caption.trim() : _defaultText(attachment),
    'timestamp': timestamp,
    'mediaType': attachment.mediaType,
    'mediaUrl': mediaUrl,
    'mediaThumbnail': attachment.isImage ? mediaUrl : '',
    'mediaMimeType': attachment.mimeType,
    'mediaFileName': attachment.name,
    'reactions': '',
    'deliveryStatus': 'enviado',
    'sentTimestamp': timestamp,
  };
}

String _defaultText(ChatAttachment attachment) => switch (attachment.mediaType) {
  'image' => '📷 Foto adjunta', 'gif' => '🎭 GIF adjunto', 'video' => '🎥 Video adjunto', _ => '📎 ${attachment.name}',
};

class ChatMessage {
  const ChatMessage({required this.id, required this.senderName, required this.senderEmail, required this.text, required this.timestamp, this.senderId = '', this.mediaType = '', this.mediaUrl, this.mediaThumbnail, this.mediaMimeType = '', this.mediaFileName = ''});
  final String id, senderName, senderEmail, text, senderId, mediaType, mediaMimeType, mediaFileName;
  final int timestamp;
  final String? mediaUrl, mediaThumbnail;
  factory ChatMessage.fromMap(String id, String channelId, Map<Object?, Object?> data) => ChatMessage(
    id: id, senderId: '${data['senderId'] ?? ''}', senderName: '${data['senderName'] ?? 'Usuario'}', senderEmail: '${data['senderEmail'] ?? ''}', text: '${data['text'] ?? ''}', timestamp: (data['timestamp'] as num?)?.toInt() ?? 0,
    mediaType: '${data['mediaType'] ?? ''}', mediaUrl: data['mediaUrl'] as String?, mediaThumbnail: data['mediaThumbnail'] as String?, mediaMimeType: '${data['mediaMimeType'] ?? ''}', mediaFileName: '${data['mediaFileName'] ?? ''}',
  );
}
