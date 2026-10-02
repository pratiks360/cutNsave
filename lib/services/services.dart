import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../data/remote_store.dart';
import '../data/repository.dart';
import '../data/sync_service.dart';
import '../logic/article_saver.dart';
import 'cloud_api.dart';
import 'members_service.dart';
import 'ocr_service.dart';
import 'pdf_service.dart';
import 'quota_service.dart';
import 'translate_service.dart';
import 'update_service.dart';

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
    required this.saver,
    required this.pdf,
    required this.updater,
    required this.members,
  });

  final String libraryId;
  final String userId;
  final String imageDir;
  final Repository repo;
  final SyncService sync;
  final OcrService ocr;
  final TranslateService translate;
  final QuotaService quota;
  final ArticleSaver saver;
  final PdfService pdf;
  final UpdateService updater;
  final MembersService members;

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
    final translate = TranslateService(mlkit: mlkitTranslate, cloud: cloud);
    final info = await PackageInfo.fromPlatform();
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
      translate: translate,
      quota: QuotaService(
        fetchRows: () async =>
            await client.rpc('get_quota', params: {'lib': libraryId}) as List<dynamic>,
        prefs: prefs,
      ),
      saver: ArticleSaver(
        repo: repo,
        translator: translate,
        libraryId: libraryId,
        userId: userId,
        imageDir: imageDir,
      ),
      pdf: PdfService(),
      updater: UpdateService(
        client: http.Client(),
        repoSlug: Config.githubRepo,
        installedVersion: info.version,
      ),
      members: MembersService(client, libraryId, client.auth.currentUser?.email),
    );
  }
}
