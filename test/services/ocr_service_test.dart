import 'package:cutnsave/services/cloud_api.dart';
import 'package:cutnsave/services/ocr_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const good = 'तो घरी आहे आणि काम करत आहे कारण आज रविवार आहे आणि सुट्टी आहे';

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
  test('good ML Kit result never calls cloud', () async {
    final cloud = FakeCloud();
    final r = await svc(good, cloud).recognize('p.jpg');
    expect(r.text, good);
    expect(r.usedCloud, isFalse);
    expect(cloud.ocrCalls, 0);
  });

  test('poor ML Kit result falls back to cloud', () async {
    final cloud = FakeCloud(ocrText: good);
    final r = await svc('', cloud).recognize('p.jpg');
    expect(r.text, good);
    expect(r.usedCloud, isTrue);
  });

  test('quota exceeded keeps local text and reports skip', () async {
    final r = await svc('abc', FakeCloud(error: QuotaExceeded())).recognize('p.jpg');
    expect(r.text, 'abc');
    expect(r.skip, CloudSkip.quota);
  });

  test('network error keeps local text and reports offline', () async {
    final r = await svc('abc', FakeCloud(error: Exception('socket'))).recognize('p.jpg');
    expect(r.text, 'abc');
    expect(r.skip, CloudSkip.offline);
  });

  test('cloud returning empty keeps local text', () async {
    final r = await svc('abc', FakeCloud(ocrText: '  ')).recognize('p.jpg');
    expect(r.text, 'abc');
    expect(r.usedCloud, isFalse);
  });

  test('ML Kit throwing does not propagate and returns a safe result', () async {
    final cloud = FakeCloud(ocrText: good);
    final service = OcrService(
      mlkit: (_) async => throw PlatformException(code: 'decode_failed'),
      cloud: cloud,
      readBytes: (_) async => Uint8List(1),
    );
    // Must not throw: this is the regression case for the OCR hang (the
    // caller's try/catch around recognize() should never even be needed,
    // but a bug here used to leave edit_article_screen stuck on a spinner).
    final r = await service.recognize('p.jpg');
    expect(r.text, '');
    expect(r.skip, CloudSkip.offline);
    // Cloud OCR was deliberately not attempted: an ML Kit exception points at
    // a bad/unsupported image, not a connectivity problem.
    expect(cloud.ocrCalls, 0);
  });
}
