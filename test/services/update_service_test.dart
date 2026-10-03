import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cutnsave/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Minimal fake so `UpdateService.download`'s `getTemporaryDirectory()` call
/// doesn't hit a real platform channel in the test environment.
class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this._dir);
  final Directory _dir;

  @override
  Future<String?> getTemporaryPath() async => _dir.path;
}

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

  test('latestIfNewer throws within a bounded time when the request hangs', () async {
    final hanging = MockClient((_) => Completer<http.Response>().future);
    final service = UpdateService(
      client: hanging,
      repoSlug: 'me/cutNsave',
      installedVersion: '1.0.0',
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(
      service.latestIfNewer().timeout(const Duration(seconds: 5)),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('download throws within a bounded time when the request hangs', () async {
    final hanging = MockClient.streaming((_, bodyStream) => Completer<http.StreamedResponse>().future);
    final service = UpdateService(
      client: hanging,
      repoSlug: 'me/cutNsave',
      installedVersion: '1.0.0',
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(
      service.download(UpdateInfo('v1.1.0', Uri.parse('https://x/cutnsave.apk'))).timeout(
            const Duration(seconds: 5),
          ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('download throws when the body stream stalls mid-transfer', () async {
    final tempDir = Directory.systemTemp.createTempSync('cns_update_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final stalling = MockClient.streaming((_, bodyStream) async {
      final controller = StreamController<List<int>>();
      controller.add('partial chunk, then silence'.codeUnits);
      // never add another chunk, never close -- simulates a dropped
      // connection after headers arrived
      return http.StreamedResponse(controller.stream, 200);
    });
    final service = UpdateService(
      client: stalling,
      repoSlug: 'me/cutNsave',
      installedVersion: '1.0.0',
      streamStallTimeout: const Duration(milliseconds: 50),
    );
    await expectLater(
      service.download(UpdateInfo('v1.1.0', Uri.parse('https://x/cutnsave.apk'))).timeout(
            const Duration(seconds: 5),
          ),
      throwsA(isA<TimeoutException>()),
    );
  });
}
