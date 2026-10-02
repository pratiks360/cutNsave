import 'package:cutnsave/logic/lang.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Marathi markers', () {
    expect(detectLang('तो घरी आहे आणि काम करत आहे'), 'mr');
    expect(detectLang('पाणी ळ'), 'mr');
  });
  test('Hindi markers', () {
    expect(detectLang('वह घर पर है और काम कर रहा है'), 'hi');
  });
  test('English', () {
    expect(detectLang('The quick brown fox jumps over the lazy dog'), 'en');
  });
  test('ambiguous Devanagari follows ML Kit code, defaults to Marathi', () {
    expect(detectLang('राम सीता', mlkitCode: 'hi'), 'hi');
    expect(detectLang('राम सीता', mlkitCode: 'mr'), 'mr');
    expect(detectLang('राम सीता'), 'mr');
  });
  test('empty text defaults to Marathi unless ML Kit says otherwise', () {
    expect(detectLang(''), 'mr');
    expect(detectLang('', mlkitCode: 'hi'), 'hi');
  });
}
