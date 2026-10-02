import 'package:cutnsave/data/models.dart';
import 'package:cutnsave/logic/article_html.dart';
import 'package:flutter_test/flutter_test.dart';

Article art({String lang = 'mr', String text = 'नमस्कार', String? en = 'Hello'}) => Article(
      id: 'a1',
      libraryId: 'lib',
      originalText: text,
      originalLang: lang,
      englishText: en,
      scannedAt: DateTime.utc(2026, 10, 2, 12),
    );

void main() {
  test('contains date, image, original then English', () {
    final html = buildArticleHtml(article: art(), imageBase64: 'AAAA');
    expect(html, contains('2 October 2026'));
    expect(html, contains('data:image/jpeg;base64,AAAA'));
    expect(html, contains('Marathi'));
    expect(html.indexOf('नमस्कार'), lessThan(html.indexOf('Hello')));
  });

  test('omits image tag when no image', () {
    expect(buildArticleHtml(article: art(), imageBase64: null), isNot(contains('<img')));
  });

  test('escapes HTML in text', () {
    final html = buildArticleHtml(article: art(text: '<b>x</b> & y', en: null), imageBase64: null);
    expect(html, contains('&lt;b&gt;x&lt;&#47;b&gt; &amp; y'));
    expect(html, isNot(contains('<b>x')));
  });

  test('omits English section when no English text', () {
    final html = buildArticleHtml(article: art(en: null), imageBase64: null);
    expect(html, isNot(contains('<h2>English</h2>')));
  });

  test('English article shows a single English section', () {
    final html = buildArticleHtml(article: art(lang: 'en', text: 'Hi', en: 'Hi'), imageBase64: null);
    expect('<h2>English</h2>'.allMatches(html).length, 1);
  });
}
