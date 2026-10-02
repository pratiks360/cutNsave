import 'package:cutnsave/logic/ocr_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty or very short text needs cloud', () {
    expect(needsCloud(''), isTrue);
    expect(needsCloud('अ ब क'), isTrue);
  });
  test('clean Marathi paragraph does not need cloud', () {
    expect(needsCloud('तो घरी आहे आणि काम करत आहे कारण आज रविवार आहे आणि सुट्टी आहे'), isFalse);
  });
  test('garbage symbols need cloud', () {
    expect(needsCloud('@#\$%^&*()' * 10), isTrue);
  });
}
