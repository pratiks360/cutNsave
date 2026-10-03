import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

const _networkTimeout = Duration(seconds: 20);
// Larger payloads (image upload/download) get a longer bound.
const _transferTimeout = Duration(seconds: 60);

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
  Future<void> upsertCategory(Category c) => _client
      .rpc('upsert_category', params: _categoryParams(c))
      .timeout(_networkTimeout, onTimeout: () => throw TimeoutException('upsertCategory timed out'));

  @override
  Future<void> upsertArticle(Article a) => _client
      .rpc('upsert_article', params: _articleParams(a))
      .timeout(_networkTimeout, onTimeout: () => throw TimeoutException('upsertArticle timed out'));

  @override
  Future<void> uploadImage(String remotePath, File file) async {
    await _client.storage
        .from('articles')
        .upload(
          remotePath,
          file,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        )
        .timeout(_transferTimeout, onTimeout: () => throw TimeoutException('uploadImage timed out'));
  }

  @override
  Future<Uint8List> downloadImage(String remotePath) => _client.storage
      .from('articles')
      .download(remotePath)
      .timeout(_transferTimeout, onTimeout: () => throw TimeoutException('downloadImage timed out'));

  @override
  Future<List<Category>> categoriesSince(DateTime? since) async {
    var q = _client.from('categories').select();
    if (since != null) q = q.gt('updated_at', since.toUtc().toIso8601String());
    final rows = await q.order('updated_at').timeout(
          _networkTimeout,
          onTimeout: () => throw TimeoutException('categoriesSince timed out'),
        );
    return rows.map((r) => Category.fromRemote(Map<String, dynamic>.from(r))).toList();
  }

  @override
  Future<List<Article>> articlesSince(DateTime? since) async {
    var q = _client.from('articles').select();
    if (since != null) q = q.gt('updated_at', since.toUtc().toIso8601String());
    final rows = await q.order('updated_at').timeout(
          _networkTimeout,
          onTimeout: () => throw TimeoutException('articlesSince timed out'),
        );
    return rows.map((r) => Article.fromRemote(Map<String, dynamic>.from(r))).toList();
  }

  Map<String, dynamic> _categoryParams(Category c) {
    final m = c.toRemote();
    return {
      'p_id': m['id'],
      'p_library_id': m['library_id'],
      'p_name': m['name'],
      'p_deleted_at': m['deleted_at'],
      'p_client_updated_at': m['client_updated_at'],
    };
  }

  Map<String, dynamic> _articleParams(Article a) {
    final m = a.toRemote();
    return {
      'p_id': m['id'],
      'p_library_id': m['library_id'],
      'p_category_id': m['category_id'],
      'p_image_path': m['image_path'],
      'p_original_text': m['original_text'],
      'p_original_lang': m['original_lang'],
      'p_english_text': m['english_text'],
      'p_scanned_at': m['scanned_at'],
      'p_created_by': m['created_by'],
      'p_deleted_at': m['deleted_at'],
      'p_client_updated_at': m['client_updated_at'],
    };
  }
}
