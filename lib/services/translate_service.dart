import 'dart:async';

import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'cloud_api.dart';
import 'ocr_service.dart' show CloudSkip;

// Model files are up to ~30MB; bound the download generously so it can't
// hang forever on a weak/captive-portal connection, while still allowing
// time for a large transfer on a slow link.
const _modelDownloadTimeout = Duration(seconds: 60);

class TranslateResult {
  const TranslateResult(this.text, {this.usedCloud = false, this.skip});
  final String? text; // null => translation pending
  final bool usedCloud;
  final CloudSkip? skip;
}

class TranslateService {
  TranslateService({required this.mlkit, required this.cloud});
  final Future<String> Function(String text, String sourceLang) mlkit;
  final CloudApi cloud;

  Future<TranslateResult> toEnglish(String text, String sourceLang) async {
    if (sourceLang == 'en') return TranslateResult(text);
    try {
      final local = await mlkit(text, sourceLang);
      if (local.trim().isNotEmpty) return TranslateResult(local);
    } catch (_) {
      // model missing / offline / ML Kit error: try cloud
    }
    try {
      final remote = await cloud.translate(text, sourceLang);
      if (remote.trim().isNotEmpty) return TranslateResult(remote, usedCloud: true);
      return const TranslateResult(null);
    } on QuotaExceeded {
      return const TranslateResult(null, skip: CloudSkip.quota);
    } on TextTooLong {
      return const TranslateResult(null, skip: CloudSkip.tooLong);
    } catch (_) {
      return const TranslateResult(null, skip: CloudSkip.offline);
    }
  }
}

/// Default on-device translator. Downloads language models on first use (needs network).
Future<String> mlkitTranslate(String text, String sourceLang) async {
  final from = sourceLang == 'hi' ? TranslateLanguage.hindi : TranslateLanguage.marathi;
  final manager = OnDeviceTranslatorModelManager();
  for (final lang in [from, TranslateLanguage.english]) {
    if (!await manager.isModelDownloaded(lang.bcpCode)) {
      // isWifiRequired stays false: requiring Wi-Fi for the download is a
      // product decision (confirm-before-downloading-on-cellular UX) that's
      // explicitly out of scope here; this only bounds how long we'll wait.
      final ok = await manager.downloadModel(lang.bcpCode, isWifiRequired: false).timeout(
            _modelDownloadTimeout,
            onTimeout: () => throw TimeoutException('model download timed out: ${lang.bcpCode}'),
          );
      if (!ok) throw StateError('model download failed: ${lang.bcpCode}');
    }
  }
  final translator = OnDeviceTranslator(
    sourceLanguage: from,
    targetLanguage: TranslateLanguage.english,
  );
  try {
    return await translator.translateText(text);
  } finally {
    await translator.close();
  }
}
