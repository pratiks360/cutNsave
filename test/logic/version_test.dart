import 'package:cutnsave/logic/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('newer tag detected', () {
    expect(isNewer('v1.2.0', '1.1.9'), isTrue);
    expect(isNewer('v2.0.0', '1.9.9+4'), isTrue);
  });
  test('same or older is not newer', () {
    expect(isNewer('v1.2.0', '1.2.0'), isFalse);
    expect(isNewer('v1.0.0', '1.2.0'), isFalse);
  });
  test('missing components treated as zero', () {
    expect(isNewer('v1.2', '1.2.0'), isFalse);
    expect(isNewer('v1.3', '1.2.9'), isTrue);
  });
}
