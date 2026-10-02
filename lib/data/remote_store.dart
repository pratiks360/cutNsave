import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

abstract class RemoteStore {
  Future<void> upsertCategory(Category c);
  Future<void> upsertArticle(Article a);
  Future<void> uploadImage(String remotePath, File file);
  Future<Uint8List> downloadImage(String remotePath);
  Future<List<Category>> categoriesSince(DateTime? since);
  Future<List<Article>> articlesSince(DateTime? since);
}

class SupabaseRemoteStore implements RemoteStore {
  SupabaseRemoteStore(this._client);
  final SupabaseClient _client;

  @override
  Future<void> upsertCategory(Category c) =>
      _client.from('categories').upsert(c.toRemote());

  @override
  Future<void> upsertArticle(Article a) => _client.from('articles').upsert(a.toRemote());

  @override
  Future<void> uploadImage(String remotePath, File file) async {
    await _client.storage.from('articles').upload(
          remotePath,
          file,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
  }

  @override
  Future<Uint8List> downloadImage(String remotePath) =>
      _client.storage.from('articles').download(remotePath);

  @override
  Future<List<Category>> categoriesSince(DateTime? since) async {
    var q = _client.from('categories').select();
    if (since != null) q = q.gte('updated_at', since.toUtc().toIso8601String());
    final rows = await q.order('updated_at');
    return rows.map((r) => Category.fromRemote(Map<String, dynamic>.from(r))).toList();
  }

  @override
  Future<List<Article>> articlesSince(DateTime? since) async {
    var q = _client.from('articles').select();
    if (since != null) q = q.gte('updated_at', since.toUtc().toIso8601String());
    final rows = await q.order('updated_at');
    return rows.map((r) => Article.fromRemote(Map<String, dynamic>.from(r))).toList();
  }
}
