import 'package:flutter/foundation.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class TranslationResult {
  final String text;
  final String source;
  final String target;
  const TranslationResult(this.text, this.source, this.target);
  bool get sameLanguage => source == target;
}

class TranslationService {
  static final instance = TranslationService();
  final _cache = <String, TranslationResult>{};
  final _pending = <String, Future<TranslationResult>>{};
  void clear() => _cache.clear();

  Future<TranslationResult> translate(String text, String target) async {
    final key = '$target\u0000$text';
    if (_cache.containsKey(key)) return _cache[key]!;
    if (_pending.containsKey(key)) return _pending[key]!;
    final task = _translate(text, target);
    _pending[key] = task;
    try {
      final result = await task;
      if (_cache.length >= 200) _cache.remove(_cache.keys.first);
      _cache[key] = result;
      return result;
    } finally {
      _pending.remove(key);
    }
  }

  Future<TranslationResult> _translate(String text, String targetCode) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw StateError(
        'Dịch tin nhắn hiện hỗ trợ trên điện thoại Android/iOS.',
      );
    }
    if (text.trim().isEmpty || text.length > 10000) {
      throw StateError('Tin nhắn cần có nội dung và không quá 10.000 ký tự.');
    }
    final identifier = LanguageIdentifier(confidenceThreshold: 0.4);
    late String sourceCode;
    try {
      sourceCode = await identifier.identifyLanguage(text);
    } finally {
      await identifier.close();
    }
    final source = TranslateLanguage.values
        .where((v) => v.bcpCode == sourceCode)
        .firstOrNull;
    final target = TranslateLanguage.values
        .where((v) => v.bcpCode == targetCode)
        .firstOrNull;
    if (source == null || target == null) {
      throw StateError(
        'Chưa nhận diện được ngôn ngữ hoặc ngôn ngữ chưa được hỗ trợ.',
      );
    }
    if (source == target) {
      return TranslationResult(text, sourceCode, targetCode);
    }
    final translator = OnDeviceTranslator(
      sourceLanguage: source,
      targetLanguage: target,
    );
    try {
      // The native ML Kit SDK downloads missing models, then translates locally.
      final translated = await translator.translateText(text);
      return TranslationResult(translated, sourceCode, targetCode);
    } catch (_) {
      throw StateError(
        'Không dịch được. Lần đầu cần mạng để tải mô hình dịch; hãy thử lại.',
      );
    } finally {
      await translator.close();
    }
  }
}
