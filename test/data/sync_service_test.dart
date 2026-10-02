import 'dart:io';
import 'dart:typed_data';

import 'package:cutnsave/data/local_db.dart';
import 'package:cutnsave/data/models.dart';
import 'package:cutnsave/data/remote_store.dart';
import 'package:cutnsave/data/repository.dart';
import 'package:cutnsave/data/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeRemote implements RemoteStore {
  final cats = <Category>[];
  final arts = <Article>[];
  final uploaded = <String>[];
  final images = <String, Uint8List>{};
  DateTime? lastSince;
  DateTime? lastCategoriesSince;
  DateTime? lastArticlesSince;
  int categoriesSinceCalls = 0;
  int articlesSinceCalls = 0;
  int upsertCategoryCalls = 0;
  int upsertArticleCalls = 0;

  @override
  Future<void> upsertCategory(Category c) async {
    upsertCategoryCalls++;
    cats.add(c);
  }
  @override
  Future<void> upsertArticle(Article a) async {
    upsertArticleCalls++;
    arts.add(a);
  }
  @override
  Future<void> uploadImage(String remotePath, File file) async => uploaded.add(remotePath);
  @override
  Future<Uint8List> downloadImage(String remotePath) async =>
      images[remotePath] ?? (throw Exception('404'));
  @override
  Future<List<Category>> categoriesSince(DateTime? since) async {
    lastSince = since;
    lastCategoriesSince = since;
    categoriesSinceCalls++;
    return cats.where((c) => since == null || !c.updatedAt.isBefore(since)).toList();
  }
  @override
  Future<List<Article>> articlesSince(DateTime? since) async {
    lastArticlesSince = since;
    articlesSinceCalls++;
    return arts.where((a) => since == null || !a.updatedAt.isBefore(since)).toList();
  }
}

Article art(String id, {String text = 'x', DateTime? updated, String? image}) => Article(
      id: id,
      libraryId: 'lib',
      originalText: text,
      originalLang: 'mr',
      scannedAt: DateTime.utc(2026, 1, 1),
      updatedAt: updated ?? DateTime.utc(2026, 1, 1),
      imagePath: image,
    );

void main() {
  late Repository repo;
  late FakeRemote remote;
  late SyncService sync;
  late Directory dir;
  late SharedPreferences prefs;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('cns');
    repo = Repository(await LocalDb.open(databaseFactoryFfi, inMemoryDatabasePath));
    remote = FakeRemote();
    prefs = await SharedPreferences.getInstance();
    sync = SyncService(
      repo: repo,
      remote: remote,
      prefs: prefs,
      imageDir: dir.path,
    );
  });

  test('push uploads image, upserts rows and marks them clean', () async {
    final img = File('${dir.path}/a1.jpg')..writeAsBytesSync([1, 2, 3]);
    await repo.upsertCategory(Category(id: 'c1', libraryId: 'lib', name: 'Recipes'));
    await repo.upsertArticle(art('a1', image: img.path));
    await sync.sync();
    expect(remote.uploaded, ['lib/a1.jpg']);
    expect(remote.arts.single.id, 'a1');
    expect(remote.cats.single.id, 'c1');
    expect(await repo.dirtyArticles(), isEmpty);
    expect(await repo.dirtyCategories(), isEmpty);
  });

  test('pull applies remote rows and downloads missing images', () async {
    remote.arts.add(art('r1', text: 'remote', updated: DateTime.utc(2026, 5, 1)));
    remote.images['lib/r1.jpg'] = Uint8List.fromList([9, 9]);
    await sync.sync();
    final a = (await repo.article('r1'))!;
    expect(a.originalText, 'remote');
    expect(File(a.imagePath!).readAsBytesSync(), [9, 9]);
  });

  test('pull does not overwrite a dirty local row', () async {
    await repo.upsertArticle(art('a1', text: 'local'));
    // make push fail so row stays dirty, remote has a different version
    remote.arts.add(art('a1', text: 'remote', updated: DateTime.utc(2026, 5, 1)));
    await repo.applyRemoteArticle(remote.arts.first);
    expect((await repo.article('a1'))!.originalText, 'local');
  });

  test('articles pull cursor advances to the newest remote article updated_at', () async {
    remote.arts.add(art('r1', updated: DateTime.utc(2026, 5, 1)));
    await sync.sync();
    remote.lastArticlesSince = null;
    await sync.sync();
    expect(remote.lastArticlesSince, DateTime.utc(2026, 5, 1));
  });

  test('categories and articles track independent pull cursors', () async {
    final t1 = DateTime.utc(2026, 5, 1);
    final t2 = DateTime.utc(2026, 5, 10); // newer article
    remote.cats.add(Category(id: 'c1', libraryId: 'lib', name: 'C1', updatedAt: t1));
    remote.arts.add(art('a1', updated: t2));

    await sync.sync();
    // Articles cursor is newer than categories cursor after this first sync.
    expect(prefs.getString('last_pull_categories'), t1.toIso8601String());
    expect(prefs.getString('last_pull_articles'), t2.toIso8601String());

    // Another device inserts a category between t1 and t2 (the exact race
    // that used to be lost under a single shared cursor: a shared cursor
    // advanced to t2 by the article would have excluded this category
    // forever, since its timestamp t3 < t2).
    final t3 = DateTime.utc(2026, 5, 5);
    remote.cats.add(Category(id: 'c2', libraryId: 'lib', name: 'C2', updatedAt: t3));

    await sync.sync();

    // The categories fetch for this second sync must have used the
    // categories-only cursor (t1), not the articles cursor (t2).
    expect(remote.lastCategoriesSince, t1);
    // And the new category must actually have been pulled in.
    final ids = (await repo.categories()).map((c) => c.id).toSet();
    expect(ids.contains('c2'), isTrue);
    expect(prefs.getString('last_pull_categories'), t3.toIso8601String());
  });

  test('sync() is single-flight: overlapping calls only push/pull once', () async {
    await repo.upsertArticle(art('a1'));
    await repo.upsertCategory(Category(id: 'c1', libraryId: 'lib', name: 'Recipes'));

    final f1 = sync.sync();
    final f2 = sync.sync();
    await Future.wait([f1, f2]);

    expect(remote.upsertArticleCalls, 1);
    expect(remote.upsertCategoryCalls, 1);
    expect(remote.categoriesSinceCalls, 1);
    expect(remote.articlesSinceCalls, 1);

    // A sync started after the first completes is a new, independent run.
    await sync.sync();
    expect(remote.categoriesSinceCalls, 2);
  });

  test('trySync returns false instead of throwing when remote fails', () async {
    await repo.upsertArticle(art('a1'));
    final failing = SyncService(
      repo: repo,
      remote: _Throwing(),
      prefs: await SharedPreferences.getInstance(),
      imageDir: dir.path,
    );
    expect(await failing.trySync(), isFalse);
    expect((await repo.dirtyArticles()).length, 1);
  });
}

class _Throwing extends FakeRemote {
  @override
  Future<void> upsertArticle(Article a) async => throw Exception('offline');
}
