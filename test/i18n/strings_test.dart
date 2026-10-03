import 'package:cutnsave/i18n/strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns Marathi and English', () {
    expect(Tr.of('mr', 'scan'), 'लेख स्कॅन करा');
    expect(Tr.of('en', 'scan'), 'Scan article');
  });
  test('unknown key returns the key', () {
    expect(Tr.of('mr', 'does_not_exist'), 'does_not_exist');
  });
  test('substitutes placeholders', () {
    expect(Tr.of('en', 'update_available', {'version': '1.2.0'}),
        'New version 1.2.0 is available');
  });
  test('every English key has a Marathi twin', () {
    expect(Tr.missingMarathiKeys(), isEmpty);
  });
}
