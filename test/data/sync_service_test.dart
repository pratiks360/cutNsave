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

  @override
  Future<void> upsertCategory(Category c) async => cats.add(c);
  @override
  Future<void> upsertArticle(Article a) async => arts.add(a);
  @override
  Future<void> uploadImage(String remotePath, File file) async => uploaded.add(remotePath);
  @override
  Future<Uint8List> downloadImage(String remotePath) async =>
      images[remotePath] ?? (throw Exception('404'));
  @override
  Future<List<Category>> categoriesSince(DateTime? since) async {
    lastSince = since;
    return cats.where((c) => since == null || !c.updatedAt.isBefore(since)).toList();
  }
  @override
  Future<List<Article>> articlesSince(DateTime? since) async =>
      arts.where((a) => since == null || !a.updatedAt.isBefore(since)).toList();
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

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('cns');
    repo = Repository(await LocalDb.open(databaseFactoryFfi, inMemoryDatabasePath));
    remote = FakeRemote();
    sync = SyncService(
      repo: repo,
      remote: remote,
      prefs: await SharedPreferences.getInstance(),
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

  test('pull cursor advances to the newest remote updated_at', () async {
    remote.arts.add(art('r1', updated: DateTime.utc(2026, 5, 1)));
    await sync.sync();
    remote.lastSince = null;
    await sync.sync();
    expect(remote.lastSince, DateTime.utc(2026, 5, 1));
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
