import 'package:cutnsave/services/quota_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const row = {
  'month': '2026-10-01',
  'ocr_used': 40,
  'ocr_limit': 1000,
  'translate_used': 5000,
  'translate_limit': 500000,
};

void main() {
  test('fetch returns fresh quota and caches it', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final q = await QuotaService(fetchRows: () async => [row], prefs: prefs).fetch();
    expect(q!.ocrLeft, 960);
    expect(prefs.getString('quota_cache'), isNotNull);
  });

  test('offline falls back to cached quota', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await QuotaService(fetchRows: () async => [row], prefs: prefs).fetch();
    final q = await QuotaService(
      fetchRows: () async => throw Exception('offline'),
      prefs: prefs,
    ).fetch();
    expect(q!.translateLeft, 495000);
  });

  test('offline with empty cache returns null', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final q = await QuotaService(
      fetchRows: () async => throw Exception('offline'),
      prefs: prefs,
    ).fetch();
    expect(q, isNull);
  });

  test('offline with corrupted cache returns null instead of throwing', () async {
    SharedPreferences.setMockInitialValues({'quota_cache': 'not valid json'});
    final prefs = await SharedPreferences.getInstance();
    final q = await QuotaService(
      fetchRows: () async => throw Exception('offline'),
      prefs: prefs,
    ).fetch();
    expect(q, isNull);
  });
}
