import 'package:cutnsave/data/models.dart';
import 'package:cutnsave/data/remote_store.dart';
import 'package:flutter_test/flutter_test.dart';

// SupabaseRemoteStore sends article params as PostgREST *named* RPC
// arguments, so a param-name typo doesn't fail to compile -- it silently
// breaks every article sync in production (PostgREST can't match the
// function overload). This pins the sent keys against the real
// upsert_article(...) signature in
// supabase/migrations/20261008000000_articles_translation_declined.sql, so a
// renamed/misspelled key here is caught locally instead of in production.
const _upsertArticleSqlParams = {
  'p_id',
  'p_library_id',
  'p_category_id',
  'p_image_path',
  'p_original_text',
  'p_original_lang',
  'p_english_text',
  'p_scanned_at',
  'p_created_by',
  'p_deleted_at',
  'p_client_updated_at',
  'p_translation_declined',
};

void main() {
  test('article RPC params match the real upsert_article SQL signature', () {
    final a = Article(
      id: 'a1',
      libraryId: 'lib1',
      originalText: 'text',
      originalLang: 'mr',
      scannedAt: DateTime.utc(2026, 1, 1),
    );
    final params = SupabaseRemoteStore.articleParamsForTesting(a);
    expect(params.keys.toSet(), _upsertArticleSqlParams);
  });
}
