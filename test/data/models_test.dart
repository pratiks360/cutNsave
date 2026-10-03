import 'package:cutnsave/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

Article _article({
  String lang = 'mr',
  String? en,
  bool declined = false,
}) =>
    Article(
      id: 'a1',
      libraryId: 'lib',
      originalText: 'x',
      originalLang: lang,
      englishText: en,
      englishDeclined: declined,
      scannedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('needsTranslatePrompt', () {
    test('true when English is missing and not declined (pending/failed)', () {
      expect(_article(en: null, declined: false).needsTranslatePrompt, isTrue);
    });

    test('false when English is missing but deliberately declined', () {
      expect(_article(en: null, declined: true).needsTranslatePrompt, isFalse);
    });

    test('false once English text is present, declined or not', () {
      expect(_article(en: 'Hello', declined: false).needsTranslatePrompt, isFalse);
      expect(_article(en: 'Hello', declined: true).needsTranslatePrompt, isFalse);
    });

    test('false for an article already in English', () {
      expect(_article(lang: 'en', en: null, declined: false).needsTranslatePrompt, isFalse);
    });
  });

  test('englishDeclined round-trips through toLocal/fromLocal', () {
    final a = _article(en: null, declined: true);
    final back = Article.fromLocal(a.toLocal(dirty: false));
    expect(back.englishDeclined, isTrue);
  });

  // fromRemote parses rows as they come back from the `articles` table
  // (via articlesSince), which uses 'updated_at' (server-trigger-maintained)
  // rather than the 'client_updated_at' that toRemote() sends as an RPC
  // param - the two are not inverses of each other, so build a representative
  // server row directly instead of round-tripping through toRemote().
  Map<String, dynamic> _remoteRow({bool? englishDeclined}) => {
        'id': 'a1',
        'library_id': 'lib',
        'category_id': null,
        'original_text': 'x',
        'original_lang': 'mr',
        'english_text': null,
        if (englishDeclined != null) 'english_declined': englishDeclined,
        'scanned_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        'created_by': null,
        'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        'deleted_at': null,
      };

  test('fromLocal defaults englishDeclined to false when the column is absent', () {
    final a = _article(en: null, declined: true);
    final row = a.toLocal(dirty: false)..remove('english_declined');
    expect(Article.fromLocal(row).englishDeclined, isFalse);
  });

  test('fromRemote reads an explicit englishDeclined value', () {
    expect(Article.fromRemote(_remoteRow(englishDeclined: true)).englishDeclined, isTrue);
    expect(Article.fromRemote(_remoteRow(englishDeclined: false)).englishDeclined, isFalse);
  });

  test('fromRemote defaults englishDeclined to false when the field is absent', () {
    expect(Article.fromRemote(_remoteRow()).englishDeclined, isFalse);
  });
}
