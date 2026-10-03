import 'package:cutnsave/logic/email.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes valid emails', () {
    expect(normalizeEmail('  Mom@Gmail.COM '), 'mom@gmail.com');
  });
  test('rejects invalid emails', () {
    expect(normalizeEmail('nope'), isNull);
    expect(normalizeEmail('a@b'), isNull);
    expect(normalizeEmail(''), isNull);
  });
}
