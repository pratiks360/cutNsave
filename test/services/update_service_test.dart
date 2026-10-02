import 'dart:convert';

import 'package:cutnsave/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Client client(int status, Object body) =>
    MockClient((_) async => http.Response(jsonEncode(body), status));

Map<String, Object> release(String tag) => {
      'tag_name': tag,
      'assets': [
        {'name': 'notes.txt', 'browser_download_url': 'https://x/notes.txt'},
        {'name': 'cutnsave.apk', 'browser_download_url': 'https://x/cutnsave.apk'},
      ],
    };

UpdateService svc(http.Client c, {String installed = '1.0.0'}) =>
    UpdateService(client: c, repoSlug: 'me/cutNsave', installedVersion: installed);

void main() {
  test('returns info when latest release is newer', () async {
    final info = await svc(client(200, release('v1.1.0'))).latestIfNewer();
    expect(info!.tag, 'v1.1.0');
    expect(info.apkUrl, Uri.parse('https://x/cutnsave.apk'));
  });

  test('returns null when already up to date', () async {
    expect(await svc(client(200, release('v1.0.0'))).latestIfNewer(), isNull);
  });

  test('returns null when no release exists (404)', () async {
    expect(await svc(client(404, {'message': 'Not Found'})).latestIfNewer(), isNull);
  });

  test('returns null when release has no apk asset', () async {
    final body = {'tag_name': 'v2.0.0', 'assets': []};
    expect(await svc(client(200, body)).latestIfNewer(), isNull);
  });

  test('throws on server error', () async {
    expect(() => svc(client(500, {})).latestIfNewer(), throwsException);
  });
}
