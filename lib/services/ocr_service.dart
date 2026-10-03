import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'cloud_api.dart';

enum CloudSkip { quota, offline, tooLong }

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

  // Cloud Vision is tried first (better accuracy, worth the quota cost for
  // this family's volume); on-device ML Kit is the fallback when Cloud
  // Vision can't be reached or the family's monthly quota is used up, so a
  // scan still produces something instead of failing outright.
  Future<OcrResult> recognize(String imagePath) async {
    CloudSkip? skip;
    try {
      final text = await cloud.ocr(await readBytes(imagePath));
      if (text.trim().isNotEmpty) return OcrResult(text, usedCloud: true);
      // Cloud succeeded but returned nothing usable -- fall through to
      // on-device without treating this as a quota/connectivity skip.
    } on QuotaExceeded {
      skip = CloudSkip.quota;
    } catch (_) {
      skip = CloudSkip.offline;
    }
    try {
      final local = await mlkit(imagePath);
      return OcrResult(local, skip: skip);
    } catch (_) {
      // ML Kit threw too (platform exception, decode failure, ...): fail
      // soft instead of propagating and hanging the caller's UI.
      return OcrResult('', skip: skip ?? CloudSkip.offline);
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
