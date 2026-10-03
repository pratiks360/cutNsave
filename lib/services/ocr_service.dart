import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../logic/ocr_policy.dart';
import 'cloud_api.dart';

enum CloudSkip { quota, offline }

class OcrResult {
  const OcrResult(this.text, {this.usedCloud = false, this.skip});
  final String text;
  final bool usedCloud;
  final CloudSkip? skip;
}

class OcrService {
  OcrService({
    required this.mlkit,
    required this.cloud,
    Future<Uint8List> Function(String path)? readBytes,
  }) : readBytes = readBytes ?? ((p) => File(p).readAsBytes());

  final Future<String> Function(String path) mlkit;
  final CloudApi cloud;
  final Future<Uint8List> Function(String path) readBytes;

  Future<OcrResult> recognize(String imagePath) async {
    String local;
    try {
      local = await mlkit(imagePath);
    } catch (_) {
      // ML Kit threw (platform exception, decode failure, ...). This points at
      // a bad/unsupported image rather than a network issue, so cloud OCR is
      // unlikely to help either; fail soft instead of propagating and hanging
      // the caller's UI.
      return const OcrResult('', skip: CloudSkip.offline);
    }
    if (!needsCloud(local)) return OcrResult(local);
    try {
      final text = await cloud.ocr(await readBytes(imagePath));
      if (text.trim().isEmpty) return OcrResult(local);
      return OcrResult(text, usedCloud: true);
    } on QuotaExceeded {
      return OcrResult(local, skip: CloudSkip.quota);
    } catch (_) {
      return OcrResult(local, skip: CloudSkip.offline);
    }
  }
}

/// Default on-device recognizer: Devanagari model also reads Latin text.
Future<String> mlkitRecognize(String imagePath) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.devanagiri);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
    return result.text.trim();
  } finally {
    await recognizer.close();
  }
}
