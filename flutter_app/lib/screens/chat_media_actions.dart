import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Downloads only the URL attached to the message the user tapped, then opens
/// the native share sheet with a temporary local copy. The receiving app (for
/// example Files) decides where to save it; this does not claim gallery saving.
class ChatMediaActions {
  ChatMediaActions({
    Future<http.Response> Function(Uri uri)? get,
    Future<Directory> Function()? temporaryDirectory,
    Future<void> Function(String path, String name, String mimeType)? share,
  })  : _get = get ?? _httpGet,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
        _share = share ?? _shareFile;

  final Future<http.Response> Function(Uri uri) _get;
  final Future<Directory> Function() _temporaryDirectory;
  final Future<void> Function(String path, String name, String mimeType) _share;

  static Future<http.Response> _httpGet(Uri uri) => http.get(uri);

  static Future<void> _shareFile(String path, String name, String mimeType) async {
    await Share.shareXFiles([XFile(path, mimeType: mimeType, name: name)], text: name);
  }

  Future<void> downloadAndShare({required String url, required String fileName, required String mimeType}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) {
      throw const FormatException('El enlace del archivo no es válido.');
    }
    final response = await _get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('El servidor respondió ${response.statusCode}.');
    }
    if (response.bodyBytes.isEmpty) throw const FormatException('El archivo descargado está vacío.');
    if (response.bodyBytes.length > 50 * 1024 * 1024) throw const FormatException('El archivo supera el límite de 50 MiB.');
    final safeName = _safeFileName(fileName);
    final directory = await _temporaryDirectory();
    final file = File('${directory.path}/chat-${DateTime.now().microsecondsSinceEpoch}-$safeName');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    await _share(file.path, safeName, mimeType.isEmpty ? 'application/octet-stream' : mimeType);
  }

  String _safeFileName(String value) {
    final leaf = value.replaceAll('\\', '/').split('/').last.trim();
    final clean = leaf.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    return clean.isEmpty || clean == '.' || clean == '..' ? 'chat-attachment' : clean;
  }
}
