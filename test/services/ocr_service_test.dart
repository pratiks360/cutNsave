import 'package:cutnsave/services/cloud_api.dart';
import 'package:cutnsave/services/ocr_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCloud implements CloudApi {
  FakeCloud({this.ocrText = 'cloud text', this.error});
  final String ocrText;
  final Object? error;
  int ocrCalls = 0;
  @override
  Future<String> ocr(Uint8List jpeg) async {
    ocrCalls++;
    if (error != null) throw error!;
    return ocrText;
  }
  @override
  Future<String> translate(String text, String sourceLang) async => throw UnimplementedError();
}

OcrService svc(String local, FakeCloud cloud) => OcrService(
      mlkit: (_) async => local,
      cloud: cloud,
      readBytes: (_) async => Uint8List(1),
    );

void main() {
  test('cloud OCR is tried first and used when it succeeds', () async {
    final cloud = FakeCloud(ocrText: 'cloud result');
    final r = await svc('local result', cloud).recognize('p.jpg');
    expect(r.text, 'cloud result');
    expect(r.usedCloud, isTrue);
    expect(r.skip, isNull);
    expect(cloud.ocrCalls, 1);
  });

  test('cloud returning only whitespace falls back to ML Kit without a skip reason', () async {
    final r = await svc('local result', FakeCloud(ocrText: '  ')).recognize('p.jpg');
    expect(r.text, 'local result');
    expect(r.usedCloud, isFalse);
    expect(r.skip, isNull);
  });

  test('quota exceeded falls back to ML Kit and reports skip', () async {
    final r = await svc('local result', FakeCloud(error: QuotaExceeded())).recognize('p.jpg');
    expect(r.text, 'local result');
    expect(r.usedCloud, isFalse);
    expect(r.skip, CloudSkip.quota);
  });

  test('network error falls back to ML Kit and reports offline', () async {
    final r = await svc('local result', FakeCloud(error: Exception('socket'))).recognize('p.jpg');
    expect(r.text, 'local result');
    expect(r.usedCloud, isFalse);
    expect(r.skip, CloudSkip.offline);
  });

  test('both cloud and ML Kit failing returns empty text with a skip reason', () async {
    final service = OcrService(
      mlkit: (_) async => throw PlatformException(code: 'decode_failed'),
      cloud: FakeCloud(error: Exception('socket')),
      readBytes: (_) async => Uint8List(1),
    );
    // Must not throw: the caller's try/catch around recognize() should never
    // even be needed, but a bug here used to leave edit_article_screen stuck
    // on a spinner.
    final r = await service.recognize('p.jpg');
    expect(r.text, '');
    expect(r.skip, CloudSkip.offline);
  });

  test('ML Kit throwing after a cloud failure still reports the cloud skip reason', () async {
    final service = OcrService(
      mlkit: (_) async => throw PlatformException(code: 'decode_failed'),
      cloud: FakeCloud(error: QuotaExceeded()),
      readBytes: (_) async => Uint8List(1),
    );
    final r = await service.recognize('p.jpg');
    expect(r.text, '');
    expect(r.skip, CloudSkip.quota);
  });
}
