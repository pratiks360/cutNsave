import 'dart:typed_data';

import 'package:cutnsave/services/cloud_api.dart';
import 'package:cutnsave/services/ocr_service.dart';
import 'package:cutnsave/services/translate_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCloud implements CloudApi {
  FakeCloud({this.result = 'cloud en', this.error});
  final String result;
  final Object? error;
  int calls = 0;
  @override
  Future<String> ocr(Uint8List jpeg) async => throw UnimplementedError();
  @override
  Future<String> translate(String text, String sourceLang) async {
    calls++;
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  test('English input is returned unchanged, no engines called', () async {
    final cloud = FakeCloud();
    final s = TranslateService(mlkit: (_, _) async => fail('no'), cloud: cloud);
    final r = await s.toEnglish('hello', 'en');
    expect(r.text, 'hello');
    expect(cloud.calls, 0);
  });

  test('ML Kit result used first', () async {
    final cloud = FakeCloud();
    final s = TranslateService(mlkit: (t, l) async => 'local en', cloud: cloud);
    final r = await s.toEnglish('नमस्कार', 'mr');
    expect(r.text, 'local en');
    expect(r.usedCloud, isFalse);
    expect(cloud.calls, 0);
  });

  test('ML Kit failure falls back to cloud', () async {
    final s = TranslateService(
        mlkit: (_, _) async => throw Exception('no model'), cloud: FakeCloud());
    final r = await s.toEnglish('नमस्कार', 'mr');
    expect(r.text, 'cloud en');
    expect(r.usedCloud, isTrue);
  });

  test('empty ML Kit output falls back to cloud', () async {
    final s = TranslateService(mlkit: (_, _) async => ' ', cloud: FakeCloud());
    expect((await s.toEnglish('नमस्कार', 'hi')).text, 'cloud en');
  });

  test('both fail → pending (null text); quota reported', () async {
    final s = TranslateService(
        mlkit: (_, _) async => throw Exception('x'),
        cloud: FakeCloud(error: QuotaExceeded()));
    final r = await s.toEnglish('नमस्कार', 'mr');
    expect(r.text, isNull);
    expect(r.skip, CloudSkip.quota);
  });

  test('both fail offline → pending with offline skip', () async {
    final s = TranslateService(
        mlkit: (_, _) async => throw Exception('x'),
        cloud: FakeCloud(error: Exception('socket')));
    final r = await s.toEnglish('नमस्कार', 'mr');
    expect(r.text, isNull);
    expect(r.skip, CloudSkip.offline);
  });
}
