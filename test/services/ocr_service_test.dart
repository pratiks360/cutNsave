import 'dart:typed_data';

import 'package:cutnsave/services/cloud_api.dart';
import 'package:cutnsave/services/ocr_service.dart';
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
}
