import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local-only persistence for unsent text. Drafts never enter the chat backend.
abstract interface class ChatDraftStorage {
  Future<String?> read({required String uid, required String channelId});
  Future<void> write({required String uid, required String channelId, required String text});
  Future<void> clear({required String uid, required String channelId});
}

class SharedPreferencesChatDraftStorage implements ChatDraftStorage {
  static const _prefix = 'omnistudio.flutter.chat_draft.v1';

  static String keyFor({required String uid, required String channelId}) =>
      '$_prefix.${base64UrlEncode(utf8.encode(uid))}.${base64UrlEncode(utf8.encode(channelId))}';

  @override
  Future<String?> read({required String uid, required String channelId}) async =>
      (await SharedPreferences.getInstance()).getString(keyFor(uid: uid, channelId: channelId));

  @override
  Future<void> write({required String uid, required String channelId, required String text}) async {
    final preferences = await SharedPreferences.getInstance();
    final key = keyFor(uid: uid, channelId: channelId);
    if (text.isEmpty) {
      await clear(uid: uid, channelId: channelId);
      return;
    }
    if (!await preferences.setString(key, text)) {
      throw StateError('No se pudo guardar el borrador en este dispositivo.');
    }
  }

  @override
  Future<void> clear({required String uid, required String channelId}) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.remove(keyFor(uid: uid, channelId: channelId))) {
      throw StateError('No se pudo limpiar el borrador en este dispositivo.');
    }
  }
}
