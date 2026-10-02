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
  }

  Future<List<Article>> articlesNeedingImage() async =>
      (await _db.query('articles', where: 'image_path IS NULL AND deleted = 0'))
          .map(Article.fromLocal)
          .toList();

  Future<void> setImagePath(String id, String path) => _db.update(
        'articles',
        {'image_path': path},
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
