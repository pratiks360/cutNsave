import 'package:sqflite/sqflite.dart';

class LocalDb {
  static Future<Database> open(DatabaseFactory factory, String path) {
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE categories(
              id TEXT PRIMARY KEY,
              library_id TEXT NOT NULL,
              name TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              deleted INTEGER NOT NULL DEFAULT 0,
              dirty INTEGER NOT NULL DEFAULT 0
            )''');
          await db.execute('''
            CREATE TABLE articles(
              id TEXT PRIMARY KEY,
              library_id TEXT NOT NULL,
              category_id TEXT,
              image_path TEXT,
              original_text TEXT NOT NULL,
              original_lang TEXT NOT NULL,
              english_text TEXT,
              scanned_at TEXT NOT NULL,
              created_by TEXT,
              updated_at TEXT NOT NULL,
              deleted INTEGER NOT NULL DEFAULT 0,
              dirty INTEGER NOT NULL DEFAULT 0
            )''');
        },
      ),
    );
  }
}
