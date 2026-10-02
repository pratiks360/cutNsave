import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_store.dart';
import 'repository.dart';

class SyncService {
  SyncService({
    required this.repo,
    required this.remote,
    required this.prefs,
    required this.imageDir,
  });

  final Repository repo;
  final RemoteStore remote;
  final SharedPreferences prefs;
  final String imageDir;

  static const _cursorKey = 'last_pull';

  Future<bool> trySync() async {
    try {
      await sync();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> sync() async {
    await _push();
    await _pull();
  }

  Future<void> _push() async {
    for (final c in await repo.dirtyCategories()) {
      await remote.upsertCategory(c);
      await repo.markClean('categories', c.id, c.updatedAt);
    }
    for (final a in await repo.dirtyArticles()) {
      final path = a.imagePath;
      if (path != null && !a.deleted && File(path).existsSync()) {
        await remote.uploadImage(a.remoteImagePath, File(path));
      }
      await remote.upsertArticle(a);
      await repo.markClean('articles', a.id, a.updatedAt);
    }
  }

  Future<void> _pull() async {
    final raw = prefs.getString(_cursorKey);
    final since = raw == null ? null : DateTime.parse(raw);

    final cats = await remote.categoriesSince(since);
    for (final c in cats) {
      await repo.applyRemoteCategory(c);
    }
    final arts = await remote.articlesSince(since);
    for (final a in arts) {
      await repo.applyRemoteArticle(a);
    }
    await _downloadMissingImages();

    final stamps = [...cats.map((c) => c.updatedAt), ...arts.map((a) => a.updatedAt)];
    if (stamps.isNotEmpty) {
      final newest = stamps.reduce((a, b) => a.isAfter(b) ? a : b);
      await prefs.setString(_cursorKey, newest.toIso8601String());
    }
  }

  Future<void> _downloadMissingImages() async {
    await Directory(imageDir).create(recursive: true);
    for (final a in await repo.articlesNeedingImage()) {
      try {
        final bytes = await remote.downloadImage(a.remoteImagePath);
        final file = File(p.join(imageDir, '${a.id}.jpg'));
        await file.writeAsBytes(bytes);
        await repo.setImagePath(a.id, file.path);
      } catch (_) {
        // image not uploaded yet or offline; retried on next sync
      }
    }
  }
}
