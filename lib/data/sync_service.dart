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

  // How long to wait before retrying a missing-image download that just
  // failed (e.g. the image was never uploaded, or the device is offline),
  // instead of re-attempting it on every single sync.
  static const _imageRetryBackoff = Duration(minutes: 15);

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
    var anyFailed = false;
    for (final c in await repo.dirtyCategories()) {
      try {
        final survivorId = await remote.upsertCategory(c);
        if (survivorId == c.id) {
          await repo.markClean('categories', c.id, c.updatedAt);
        } else {
          // Server-side dedup merged this category into an existing one with
          // the same name (see mergeCategoryId doc comment); c.id never
          // actually landed server-side, so there's nothing to mark clean -
          // drop it locally and repoint any articles that used it.
          await repo.mergeCategoryId(c.id, survivorId);
        }
      } on Exception catch (e) {
        // Don't let one stuck category (e.g. a rename collision nothing
        // auto-resolves) block every other unrelated dirty row in this
        // pass. Leave it dirty and keep going; trySync() still surfaces
        // the overall failure via hasPendingFailure below. Catching only
        // Exception (not Error) so a genuine programming bug -- a
        // TypeError, a failed assertion -- propagates loudly instead of
        // being silently logged and treated like a transient network blip.
        anyFailed = true;
        debugPrint('SyncService: failed to push category ${c.id}: $e');
      }
    }
    for (final a in await repo.dirtyArticles()) {
      try {
        final path = a.imagePath;
        if (path != null && !a.deleted && File(path).existsSync()) {
          await remote.uploadImage(a.remoteImagePath, File(path));
        }
        await remote.upsertArticle(a);
        await repo.markClean('articles', a.id, a.updatedAt);
      } on Exception catch (e) {
        // Same isolation as above: a single bad article row (e.g. one
        // referencing a category that failed to push, or a transient
        // network blip) must not stop the rest of the queue. Same
        // Exception-only scoping as above, for the same reason.
        anyFailed = true;
        debugPrint('SyncService: failed to push article ${a.id}: $e');
      }
    }
    if (anyFailed) {
      throw Exception('_push: one or more rows failed to push');
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
    final retryNotBefore = DateTime.now().toUtc().subtract(_imageRetryBackoff);
    for (final a in await repo.articlesNeedingImage(retryNotBefore: retryNotBefore)) {
      try {
        final bytes = await remote.downloadImage(a.remoteImagePath);
        final file = File(p.join(imageDir, '${a.id}.jpg'));
        await file.writeAsBytes(bytes);
        await repo.setImagePath(a.id, file.path);
      } catch (_) {
        // image not uploaded yet or offline; back off and retry later
        // (see _imageRetryBackoff) instead of hammering this on every sync.
        await repo.markImageDownloadFailed(a.id, DateTime.now().toUtc());
      }
    }
  }
}
