import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/remote_store.dart';
import '../data/repository.dart';
import '../data/sync_service.dart';
import 'cloud_api.dart';
import 'ocr_service.dart';
import 'quota_service.dart';
import 'translate_service.dart';

class Services {
  Services({
    required this.libraryId,
    required this.userId,
    required this.imageDir,
    required this.repo,
    required this.sync,
    required this.ocr,
    required this.translate,
    required this.quota,
  });

  final String libraryId;
  final String userId;
  final String imageDir;
  final Repository repo;
  final SyncService sync;
  final OcrService ocr;
  final TranslateService translate;
  final QuotaService quota;

  static Future<Services> create({
    required String libraryId,
    required String userId,
    required Database db,
    required SupabaseClient client,
    required SharedPreferences prefs,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final imageDir = p.join(docs.path, 'images');
    final repo = Repository(db);
    final cloud = SupabaseCloudApi(client, libraryId);
    return Services(
      libraryId: libraryId,
      userId: userId,
      imageDir: imageDir,
      repo: repo,
      sync: SyncService(
        repo: repo,
        remote: SupabaseRemoteStore(client),
        prefs: prefs,
        imageDir: imageDir,
      ),
      ocr: OcrService(mlkit: mlkitRecognize, cloud: cloud),
      translate: TranslateService(mlkit: mlkitTranslate, cloud: cloud),
      quota: QuotaService(
        fetchRows: () async =>
            await client.rpc('get_quota', params: {'lib': libraryId}) as List<dynamic>,
        prefs: prefs,
      ),
    );
  }
}
