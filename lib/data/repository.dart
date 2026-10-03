import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

class Repository {
  Repository(this._db);
  final Database _db;

  // ---- categories ----
  Future<void> upsertCategory(Category c, {bool dirty = true}) =>
      _db.insert('categories', c.toLocal(dirty: dirty),
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Category>> categories() async {
    final rows = await _db.query('categories',
        where: 'deleted = 0', orderBy: 'name COLLATE NOCASE');
    return rows.map(Category.fromLocal).toList();
  }

  Future<Category> createCategory(String libraryId, String name) async {
    final clean = name.trim();
    final existing = (await categories())
        .where((c) => c.name.toLowerCase() == clean.toLowerCase());
    if (existing.isNotEmpty) return existing.first;
    final c = Category(id: const Uuid().v4(), libraryId: libraryId, name: clean);
    await upsertCategory(c);
    return c;
  }

  Future<List<Category>> dirtyCategories() async =>
      (await _db.query('categories', where: 'dirty = 1'))
          .map(Category.fromLocal)
          .toList();

  /// Reconciles a category id this device pushed with the surviving id the
  /// server's dedup-on-sync merged it into (see upsert_category in
  /// 20261005000000_category_dedup.sql: two offline devices independently
  /// creating a same-named category each push their own id, and the server
  /// keeps only one). Drops the local row for [oldId] - it was never
  /// actually accepted on the server - and repoints any local articles that
  /// referenced it to [newId]. The next pull picks up [newId]'s category
  /// row itself (its client_updated_at just advanced on the server).
  Future<void> mergeCategoryId(String oldId, String newId) async {
    if (oldId == newId) return;
    await _db.transaction((txn) async {
      await txn.update('articles', {'category_id': newId},
          where: 'category_id = ?', whereArgs: [oldId]);
      await txn.delete('categories', where: 'id = ?', whereArgs: [oldId]);
    });
  }

  Future<void> applyRemoteCategory(Category c) async {
    final rows = await _db.query('categories',
        columns: ['dirty'], where: 'id = ?', whereArgs: [c.id]);
    if (rows.isNotEmpty && rows.first['dirty'] == 1) return;
    await upsertCategory(c, dirty: false);
  }

  // ---- articles ----
  Future<void> upsertArticle(Article a, {bool dirty = true}) =>
      _db.insert('articles', a.toLocal(dirty: dirty),
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<Article?> article(String id) async {
    final rows = await _db.query('articles', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Article.fromLocal(rows.first);
  }

  Future<List<Article>> articles({String? categoryId, String query = ''}) async {
    final where = <String>['deleted = 0'];
    final args = <Object?>[];
    if (categoryId != null) {
      where.add('category_id = ?');
      args.add(categoryId);
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      final like = '%${q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      where.add(r"(original_text LIKE ? ESCAPE '\' OR english_text LIKE ? ESCAPE '\')");
      args..add(like)..add(like);
    }
    final rows = await _db.query('articles',
        where: where.join(' AND '), whereArgs: args, orderBy: 'scanned_at DESC');
    return rows.map(Article.fromLocal).toList();
  }

  Future<void> softDeleteArticle(String id) => _db.update(
        'articles',
        {
          'deleted': 1,
          'dirty': 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<List<Article>> dirtyArticles() async =>
      (await _db.query('articles', where: 'dirty = 1'))
          .map(Article.fromLocal)
          .toList();

  Future<void> applyRemoteArticle(Article a) async {
    final rows = await _db.query('articles',
        columns: ['dirty', 'image_path'], where: 'id = ?', whereArgs: [a.id]);
    if (rows.isNotEmpty && rows.first['dirty'] == 1) return;
    final existingPath = rows.isEmpty ? null : rows.first['image_path'] as String?;
    await upsertArticle(a.copyWith(imagePath: existingPath), dirty: false);
    if (a.deleted && existingPath != null) {
      // The remote soft-delete is authoritative and this row is clean (just
      // confirmed above), so the local JPEG is now unreachable dead weight;
      // clear the path and remove the file. Best-effort: if the delete
      // fails, the path has already been cleared so we won't retry it
      // forever, and a stray file left on disk is harmless.
      await _db.update('articles', {'image_path': null}, where: 'id = ?', whereArgs: [a.id]);
      try {
        final f = File(existingPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Articles with no local image yet. When [retryNotBefore] is given, an
  /// article whose last download attempt failed more recently than that is
  /// skipped, so sync doesn't hammer a download that just failed (e.g. the
  /// image was never uploaded) on every single sync pass.
  Future<List<Article>> articlesNeedingImage({DateTime? retryNotBefore}) async {
    final where = StringBuffer('image_path IS NULL AND deleted = 0');
    final args = <Object?>[];
    if (retryNotBefore != null) {
      where.write(' AND (image_download_failed_at IS NULL OR image_download_failed_at <= ?)');
      args.add(retryNotBefore.toUtc().toIso8601String());
    }
    return (await _db.query('articles', where: where.toString(), whereArgs: args))
        .map(Article.fromLocal)
        .toList();
  }

  Future<void> setImagePath(String id, String path) => _db.update(
        'articles',
        {'image_path': path, 'image_download_failed_at': null},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> markImageDownloadFailed(String id, DateTime at) => _db.update(
        'articles',
        {'image_download_failed_at': at.toUtc().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );

  // ---- sync bookkeeping ----
  Future<void> markClean(String table, String id, DateTime updatedAt) => _db.update(
        table,
        {'dirty': 0},
        where: 'id = ? AND updated_at = ?',
        whereArgs: [id, updatedAt.toUtc().toIso8601String()],
      );
}
