import 'dart:io';

import 'package:cutnsave/data/local_db.dart';
import 'package:cutnsave/data/models.dart';
import 'package:cutnsave/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Article art(String id,
        {String text = 'x', String? en, String? cat, DateTime? scanned, String lang = 'mr'}) =>
    Article(
      id: id,
      libraryId: 'lib',
      categoryId: cat,
      originalText: text,
      originalLang: lang,
      englishText: en,
      scannedAt: scanned ?? DateTime.utc(2026, 1, 1),
    );

void main() {
  late Repository repo;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    final db = await LocalDb.open(databaseFactoryFfi, inMemoryDatabasePath);
    repo = Repository(db);
  });

  test('upsert and read back an article', () async {
    await repo.upsertArticle(art('a1', text: 'नमस्कार', en: 'Hello'));
    final a = await repo.article('a1');
    expect(a!.originalText, 'नमस्कार');
    expect(a.englishText, 'Hello');
  });

  test('articles are newest-scanned first and exclude deleted', () async {
    await repo.upsertArticle(art('old', scanned: DateTime.utc(2026, 1, 1)));
    await repo.upsertArticle(art('new', scanned: DateTime.utc(2026, 2, 1)));
    await repo.upsertArticle(art('gone', scanned: DateTime.utc(2026, 3, 1)));
    await repo.softDeleteArticle('gone');
    expect((await repo.articles()).map((a) => a.id), ['new', 'old']);
  });

  test('search matches Marathi original and English text', () async {
    await repo.upsertArticle(art('a1', text: 'आजची पाककृती', en: 'Todays recipe'));
    await repo.upsertArticle(art('a2', text: 'बातमी', en: 'News'));
    expect((await repo.articles(query: 'पाककृती')).map((a) => a.id), ['a1']);
    expect((await repo.articles(query: 'news')).map((a) => a.id), ['a2']);
    expect(await repo.articles(query: 'zzz'), isEmpty);
  });

  test('search treats % and _ literally', () async {
    await repo.upsertArticle(art('a1', text: '100% sure'));
    await repo.upsertArticle(art('a2', text: 'other'));
    expect((await repo.articles(query: '%')).map((a) => a.id), ['a1']);
  });

  test('category filter works', () async {
    await repo.upsertArticle(art('a1', cat: 'c1'));
    await repo.upsertArticle(art('a2', cat: 'c2'));
    expect((await repo.articles(categoryId: 'c1')).map((a) => a.id), ['a1']);
  });

  test('createCategory reuses an existing name case-insensitively', () async {
    final c1 = await repo.createCategory('lib', 'Recipes');
    final c2 = await repo.createCategory('lib', '  recipes ');
    expect(c2.id, c1.id);
    expect((await repo.categories()).length, 1);
  });

  test('dirty rows are listed until marked clean', () async {
    final a = art('a1');
    await repo.upsertArticle(a);
    expect((await repo.dirtyArticles()).map((x) => x.id), ['a1']);
    await repo.markClean('articles', 'a1', a.updatedAt);
    expect(await repo.dirtyArticles(), isEmpty);
  });

  test('markClean ignores a row edited after the snapshot', () async {
    final a = art('a1');
    await repo.upsertArticle(a);
    await repo.upsertArticle(a.copyWith(updatedAt: DateTime.utc(2030, 1, 1)));
    await repo.markClean('articles', 'a1', a.updatedAt);
    expect((await repo.dirtyArticles()).length, 1);
  });

  test('applyRemoteArticle skips a dirty local row', () async {
    await repo.upsertArticle(art('a1', text: 'local edit'));
    await repo.applyRemoteArticle(art('a1', text: 'remote'));
    expect((await repo.article('a1'))!.originalText, 'local edit');
  });

  test('applyRemoteArticle overwrites a clean row and keeps image path', () async {
    final a = art('a1', text: 'old').copyWith(imagePath: '/img/a1.jpg');
    await repo.upsertArticle(a, dirty: false);
    await repo.applyRemoteArticle(art('a1', text: 'new'));
    final got = (await repo.article('a1'))!;
    expect(got.originalText, 'new');
    expect(got.imagePath, '/img/a1.jpg');
  });

  test('articlesNeedingImage and setImagePath', () async {
    await repo.upsertArticle(art('a1'), dirty: false);
    expect((await repo.articlesNeedingImage()).map((a) => a.id), ['a1']);
    await repo.setImagePath('a1', '/img/a1.jpg');
    expect(await repo.articlesNeedingImage(), isEmpty);
    expect(await repo.dirtyArticles(), isEmpty);
  });

  test('articlesNeedingImage backs off a recently-failed download', () async {
    await repo.upsertArticle(art('a1'), dirty: false);
    await repo.markImageDownloadFailed('a1', DateTime.utc(2026, 1, 1, 12, 0));
    // A retry cutoff before the failure: still within backoff, skipped.
    expect(
      await repo.articlesNeedingImage(retryNotBefore: DateTime.utc(2026, 1, 1, 11, 0)),
      isEmpty,
    );
    // A retry cutoff after the failure: backoff has elapsed, eligible again.
    expect(
      (await repo.articlesNeedingImage(retryNotBefore: DateTime.utc(2026, 1, 1, 13, 0)))
          .map((a) => a.id),
      ['a1'],
    );
  });

  test('applyRemoteArticle deletes the local image file on a remote soft-delete', () async {
    final dir = Directory.systemTemp.createTempSync('repo_img');
    final img = File('${dir.path}/a1.jpg')..writeAsBytesSync([1, 2, 3]);
    await repo.upsertArticle(art('a1').copyWith(imagePath: img.path), dirty: false);

    await repo.applyRemoteArticle(art('a1').copyWith(deleted: true, updatedAt: DateTime.utc(2030, 1, 1)));

    expect(img.existsSync(), isFalse);
    expect((await repo.article('a1'))!.imagePath, isNull);
    dir.deleteSync(recursive: true);
  });
}
