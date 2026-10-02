import 'package:cutnsave/data/local_db.dart';
import 'package:cutnsave/data/models.dart';
import 'package:cutnsave/data/repository.dart';
import 'package:cutnsave/logic/home_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Article art(String id, String text, String? cat) => Article(
      id: id,
      libraryId: 'lib',
      categoryId: cat,
      originalText: text,
      originalLang: 'mr',
      scannedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  late Repository repo;
  late HomeController c;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    repo = Repository(await LocalDb.open(databaseFactoryFfi, inMemoryDatabasePath));
    await repo.upsertCategory(Category(id: 'c1', libraryId: 'lib', name: 'Recipes'));
    await repo.upsertArticle(art('a1', 'पाककृती', 'c1'));
    await repo.upsertArticle(art('a2', 'बातमी', null));
    c = HomeController(repo);
  });

  test('reload loads categories and all articles', () async {
    await c.reload();
    expect(c.categories.single.id, 'c1');
    expect(c.articles.length, 2);
  });

  test('setCategory filters, null shows all', () async {
    await c.setCategory('c1');
    expect(c.articles.map((a) => a.id), ['a1']);
    await c.setCategory(null);
    expect(c.articles.length, 2);
  });

  test('setQuery filters by text and combines with category', () async {
    await c.setQuery('बातमी');
    expect(c.articles.map((a) => a.id), ['a2']);
    await c.setCategory('c1');
    expect(c.articles, isEmpty);
  });

  test('notifies listeners on reload', () async {
    var n = 0;
    c.addListener(() => n++);
    await c.reload();
    expect(n, 1);
  });
}
