import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class ChatTranslationResult {
  const ChatTranslationResult({required this.sourceLanguage, required this.translatedText, required this.targetLanguage, this.sameLanguage = false});
  final String sourceLanguage;
  final String translatedText;
  final String targetLanguage;
  final bool sameLanguage;
}

abstract interface class ChatTranslationService {
  Future<ChatTranslationResult> translate(String text, String targetLanguage);
  void close();
}

class MlKitChatTranslationService implements ChatTranslationService {
  final LanguageIdentifier _identifier = LanguageIdentifier(confidenceThreshold: 0.5);
  final OnDeviceTranslatorModelManager _models = OnDeviceTranslatorModelManager();
  final Map<String, OnDeviceTranslator> _translators = {};

  static const languages = <String, String>{
    'es': 'Español', 'en': 'English', 'fr': 'Français', 'de': 'Deutsch',
    'it': 'Italiano', 'pt': 'Português', 'ru': 'Русский', 'ja': '日本語',
    'zh': '中文', 'ar': 'العربية', 'ko': '한국어', 'hi': 'हिन्दी',
  };

  static TranslateLanguage? languageForCode(String code) => switch (code.toLowerCase()) {
    'es' => TranslateLanguage.spanish, 'en' => TranslateLanguage.english,
    'fr' => TranslateLanguage.french, 'de' => TranslateLanguage.german,
    'it' => TranslateLanguage.italian, 'pt' => TranslateLanguage.portuguese,
    'ru' => TranslateLanguage.russian, 'ja' => TranslateLanguage.japanese,
    'zh' => TranslateLanguage.chinese, 'ar' => TranslateLanguage.arabic,
    'ko' => TranslateLanguage.korean, 'hi' => TranslateLanguage.hindi,
    _ => null,
  };

  @override
  Future<ChatTranslationResult> translate(String text, String targetLanguage) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw ArgumentError('No hay texto para traducir.');
    final target = languageForCode(targetLanguage);
    if (target == null) throw ArgumentError('Idioma de destino no admitido.');
    final sourceCode = await _identifier.identifyLanguage(trimmed);
    final source = languageForCode(sourceCode);
    if (sourceCode == 'und' || source == null) throw StateError('No pude detectar el idioma del mensaje.');
    if (source == target) return ChatTranslationResult(sourceLanguage: sourceCode, translatedText: trimmed, targetLanguage: targetLanguage, sameLanguage: true);
    for (final language in [source, target]) {
      if (!await _models.isModelDownloaded(language.bcpCode)) {
        await _models.downloadModel(language.bcpCode, isWifiRequired: true);
      }
    }
    final key = '$sourceCode>$targetLanguage';
    final translator = _translators.putIfAbsent(key, () => OnDeviceTranslator(sourceLanguage: source, targetLanguage: target));
    final translated = await translator.translateText(trimmed);
    return ChatTranslationResult(sourceLanguage: sourceCode, translatedText: translated, targetLanguage: targetLanguage);
  }

  @override
  void close() {
    _identifier.close();
    for (final translator in _translators.values) {
      translator.close();
    }
    _translators.clear();
  }
}


class ChatTranslationLanguage {
  const ChatTranslationLanguage(this.code, this.name);
  final String code;
  final String name;
}

class ChatTranslationLanguages {
  static const items = <ChatTranslationLanguage>[
    ChatTranslationLanguage('es', 'Español'),
    ChatTranslationLanguage('en', 'English'),
    ChatTranslationLanguage('fr', 'Français'),
    ChatTranslationLanguage('de', 'Deutsch'),
    ChatTranslationLanguage('it', 'Italiano'),
    ChatTranslationLanguage('pt', 'Português'),
    ChatTranslationLanguage('ru', 'Русский'),
    ChatTranslationLanguage('ja', '日本語'),
    ChatTranslationLanguage('zh', '中文'),
    ChatTranslationLanguage('ar', 'العربية'),
    ChatTranslationLanguage('ko', '한국어'),
    ChatTranslationLanguage('hi', 'हिन्दी'),
  ];
}
