import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_store.dart';
import 'repository.dart';

class SyncService extends ChangeNotifier {
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

  static const _categoriesCursorKey = 'last_pull_categories';
  static const _articlesCursorKey = 'last_pull_articles';

  Future<void>? _inFlight;

  /// True once a `trySync()` attempt has failed and no later attempt has
  /// yet succeeded. The UI (see HomeScreen) surfaces this as a small
  /// persistent indicator so a silently-failed sync doesn't leave the user
  /// believing their edits reached the shared backend.
  bool hasPendingFailure = false;

  Future<bool> trySync() async {
    try {
      await sync();
      _setPendingFailure(false);
      return true;
    } catch (_) {
      _setPendingFailure(true);
      return false;
    }
  }

  void _setPendingFailure(bool value) {
    if (hasPendingFailure == value) return;
    hasPendingFailure = value;
    notifyListeners();
  }

  /// Single-flight: if a sync is already running, callers share its Future
  /// instead of starting a second overlapping push/pull (e.g. a save-triggered
  /// sync racing a navigation-triggered refresh).
  Future<void> sync() {
    return _inFlight ??= _doSync().whenComplete(() => _inFlight = null);
  }

  Future<void> _doSync() async {
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
    final catsSince = _cursor(_categoriesCursorKey);
    final cats = await remote.categoriesSince(catsSince);
    for (final c in cats) {
      await repo.applyRemoteCategory(c);
    }
    await _advanceCursor(_categoriesCursorKey, cats.map((c) => c.updatedAt));

    final artsSince = _cursor(_articlesCursorKey);
    final arts = await remote.articlesSince(artsSince);
    for (final a in arts) {
      await repo.applyRemoteArticle(a);
    }
    await _advanceCursor(_articlesCursorKey, arts.map((a) => a.updatedAt));

    await _downloadMissingImages();
  }

  DateTime? _cursor(String key) {
    final raw = prefs.getString(key);
    return raw == null ? null : DateTime.parse(raw);
  }

  Future<void> _advanceCursor(String key, Iterable<DateTime> stamps) async {
    if (stamps.isEmpty) return;
    final newest = stamps.reduce((a, b) => a.isAfter(b) ? a : b);
    await prefs.setString(key, newest.toIso8601String());
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
