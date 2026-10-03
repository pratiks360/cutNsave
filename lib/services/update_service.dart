import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../logic/version.dart';

class UpdateInfo {
  const UpdateInfo(this.tag, this.apkUrl);
  final String tag;
  final Uri apkUrl;
}

class UpdateService {
  UpdateService({
    required this.client,
    required this.repoSlug,
    required this.installedVersion,
    this.timeout = const Duration(seconds: 20),
  });

  final http.Client client;
  final String repoSlug;
  final String installedVersion;

  /// Bound on each individual network call below. Overridable for tests so
  /// they don't have to wait out a real-world timeout.
  final Duration timeout;

  Future<UpdateInfo?> latestIfNewer() async {
    final res = await client
        .get(
          Uri.parse('https://api.github.com/repos/$repoSlug/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(timeout, onTimeout: () => throw TimeoutException('update check timed out'));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw Exception('GitHub returned ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = json['tag_name'] as String;
    if (!isNewer(tag, installedVersion)) return null;
    final assets = (json['assets'] as List).cast<Map<String, dynamic>>();
    final apk = assets.where((a) => (a['name'] as String).endsWith('.apk')).firstOrNull;
    if (apk == null) return null;
    return UpdateInfo(tag, Uri.parse(apk['browser_download_url'] as String));
  }

  Future<File> download(UpdateInfo info, {void Function(double)? onProgress}) async {
    // Network call first, so a hang/timeout surfaces before we ever touch
    // the filesystem (also keeps the timeout bound testable without a real
    // path_provider platform binding).
    final res = await client
        .send(http.Request('GET', info.apkUrl))
        .timeout(timeout, onTimeout: () => throw TimeoutException('update download timed out'));
    if (res.statusCode != 200) throw Exception('Download failed (${res.statusCode})');
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'cutnsave-${info.tag}.apk'));
    final total = res.contentLength ?? 0;
    var received = 0;
    final sink = file.openWrite();
    await for (final chunk in res.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total);
    }
    await sink.close();
    return file;
  }

  Future<void> install(File apk) async {
    await OpenFilex.open(apk.path, type: 'application/vnd.android.package-archive');
  }
}
