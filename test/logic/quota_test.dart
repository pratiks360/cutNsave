import 'package:cutnsave/logic/quota.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final q = Quota.fromRpc({
    'month': '2026-10-01',
    'ocr_used': 640,
    'ocr_limit': 1000,
    'translate_used': 120000,
    'translate_limit': 500000,
  });
  test('computes remaining', () {
    expect(q.ocrLeft, 360);
    expect(q.translateLeft, 380000);
  });
  test('remaining never negative', () {
    final over = Quota.fromRpc({
      'month': '2026-10-01', 'ocr_used': 1200, 'ocr_limit': 1000,
      'translate_used': 0, 'translate_limit': 500000,
    });
    expect(over.ocrLeft, 0);
  });
  test('resets on first of next month, incl. December rollover', () {
    expect(q.resetsOn, DateTime(2026, 11, 1));
    final dec = Quota.fromRpc({
      'month': '2026-12-01', 'ocr_used': 0, 'ocr_limit': 1000,
      'translate_used': 0, 'translate_limit': 500000,
    });
    expect(dec.resetsOn, DateTime(2027, 1, 1));
  });
  test('json round trip', () {
    expect(Quota.fromRpc(q.toJson()).ocrLeft, 360);
  });
}
