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
  Future<String> upsertCategory(Category c) async {
    upsertCategoryCalls++;
    // Mimics the server's dedup-on-sync: a live category with the same
    // name under a different id already "exists" -> merge into it instead
    // of adding a duplicate.
    final dup = cats.where((o) => o.id != c.id && o.name.toLowerCase() == c.name.toLowerCase());
    if (dup.isNotEmpty) return dup.first.id;
    cats.add(c);
    return c.id;
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

  test('trySync sets hasPendingFailure on failure and notifies listeners', () async {
    await repo.upsertArticle(art('a1'));
    final failing = SyncService(
      repo: repo,
      remote: _Throwing(),
      prefs: await SharedPreferences.getInstance(),
      imageDir: dir.path,
    );
    var notified = 0;
    failing.addListener(() => notified++);
    expect(failing.hasPendingFailure, isFalse);
    await failing.trySync();
    expect(failing.hasPendingFailure, isTrue);
    expect(notified, 1);
    // A second failed attempt is not newly actionable: no extra notification.
    await failing.trySync();
    expect(notified, 1);
  });

  test('a category name collision on push merges into the existing remote '
      'category and repoints local articles', () async {
    // Another device already synced a category with this name under a
    // different id.
    remote.cats.add(Category(id: 'server-cat', libraryId: 'lib', name: 'Recipes'));
    // This device independently created its own (case-insensitively
    // duplicate) category offline, and an article already filed under it.
    await repo.upsertCategory(Category(id: 'local-cat', libraryId: 'lib', name: 'RECIPES'));
    await repo.upsertArticle(Article(
      id: 'a1',
      libraryId: 'lib',
      categoryId: 'local-cat',
      originalText: 'x',
      originalLang: 'mr',
      scannedAt: DateTime.utc(2026, 1, 1),
    ));

    await sync.sync();

    // local-cat never actually landed server-side (the push was merged into
    // server-cat instead), so it must not linger locally either.
    expect((await repo.categories()).map((c) => c.id), isNot(contains('local-cat')));
    // The article that referenced it now points at the surviving id.
    expect((await repo.article('a1'))!.categoryId, 'server-cat');
    expect(await repo.dirtyCategories(), isEmpty);
    expect(await repo.dirtyArticles(), isEmpty);
  });

  test('a failing image download is backed off, not retried every sync', () async {
    // Local-only article with no image yet (never synced its image, or the
    // remote image was never uploaded) and a remote that always 404s.
    await repo.upsertArticle(art('a1'), dirty: false);
    final failingDownload = _FailingDownloadRemote();
    final s = SyncService(repo: repo, remote: failingDownload, prefs: prefs, imageDir: dir.path);

    await s.sync();
    expect(failingDownload.downloadCalls, 1);

    // A second sync run immediately after must not retry: the backoff
    // window (_imageRetryBackoff) hasn't elapsed yet.
    await s.sync();
    expect(failingDownload.downloadCalls, 1);
  });

  test('a single bad row does not block the rest of the dirty queue', () async {
    // Three dirty articles; the middle one always fails to push (e.g. a
    // permanently-stuck row). The other two must still be pushed and
    // marked clean, the bad one must stay dirty, and the overall sync
    // must still be reported as a failure via hasPendingFailure.
    await repo.upsertArticle(art('a1'));
    await repo.upsertArticle(art('a2'));
    await repo.upsertArticle(art('a3'));
    final partiallyFailing = _FailsOnOneArticle('a2');
    final flaky = SyncService(
      repo: repo,
      remote: partiallyFailing,
      prefs: await SharedPreferences.getInstance(),
      imageDir: dir.path,
    );

    expect(await flaky.trySync(), isFalse);
    expect(flaky.hasPendingFailure, isTrue);

    final dirtyIds = (await repo.dirtyArticles()).map((a) => a.id).toSet();
    expect(dirtyIds, {'a2'});
    expect(partiallyFailing.arts.map((a) => a.id).toSet(), {'a1', 'a3'});
  });

  test('hasPendingFailure clears on the next successful trySync', () async {
    await repo.upsertArticle(art('a1'));
    final remoteThatFailsOnce = _FailsOnceThenWorks();
    final flaky = SyncService(
      repo: repo,
      remote: remoteThatFailsOnce,
      prefs: await SharedPreferences.getInstance(),
      imageDir: dir.path,
    );
    expect(await flaky.trySync(), isFalse);
    expect(flaky.hasPendingFailure, isTrue);
    expect(await flaky.trySync(), isTrue);
    expect(flaky.hasPendingFailure, isFalse);
  });
}

class _Throwing extends FakeRemote {
  @override
  Future<void> upsertArticle(Article a) async => throw Exception('offline');
}

class _FailingDownloadRemote extends FakeRemote {
  int downloadCalls = 0;
  @override
  Future<Uint8List> downloadImage(String remotePath) async {
    downloadCalls++;
    throw Exception('404');
  }
}

class _FailsOnOneArticle extends FakeRemote {
  _FailsOnOneArticle(this.badId);
  final String badId;

  @override
  Future<void> upsertArticle(Article a) async {
    if (a.id == badId) throw Exception('stuck row');
    await super.upsertArticle(a);
  }
}

class _FailsOnceThenWorks extends FakeRemote {
  bool _failed = false;
  @override
  Future<void> upsertArticle(Article a) async {
    if (!_failed) {
      _failed = true;
      throw Exception('offline');
    }
    await super.upsertArticle(a);
  }
}
