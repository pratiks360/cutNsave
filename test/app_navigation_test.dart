// Regression test for the "Services provider is invisible to every pushed
// screen" bug: ServicesScope used to wrap only the Gate's `ready` case
// (i.e. only HomeScreen, the Navigator's first route). Any screen pushed on
// top of HomeScreen was a sibling of it in the Overlay, not a descendant, so
// `context.read<Services>()` there threw ProviderNotFoundException and
// crashed the app on every navigation away from Home.
//
// The fix moves the Services provider into MaterialApp's `builder`, which
// wraps the already-built Navigator, making it an ancestor of every pushed
// route at any depth.
//
// Test environment notes (see the final report for full detail):
//  - The whole pumpWidget/push/settle sequence runs inside `tester.runAsync`.
//    `Supabase.initialize` performs real asynchronous platform/socket setup
//    that never completes under the fake-async zone `testWidgets` normally
//    runs in; `runAsync` switches to the real event loop for that work.
//  - `databaseFactoryFfiNoIsolate` is used instead of `databaseFactoryFfi`:
//    the isolate-based factory talks to a background isolate over a
//    ReceivePort, which (like Supabase.initialize) never gets a chance to
//    respond under the fake-async zone and hangs the test; the no-isolate
//    factory does the same work in-process and is unaffected.
//  - Supabase auth is configured with `persistSession: false` and an
//    in-memory `pkceAsyncStorage` so `Supabase.initialize` never touches the
//    `shared_preferences` method channel while running inside `runAsync`
//    (platform-channel mocks set up by `SharedPreferences.setMockInitialValues`
//    don't apply inside `runAsync`'s real zone, so a real channel call there
//    throws `MissingPluginException`).
//  - `detectSessionInUri`/`autoRefreshToken` are disabled so no background
//    deep-link or token-refresh machinery is left running past the test.
import 'dart:io';

import 'package:cutnsave/app.dart';
import 'package:cutnsave/data/local_db.dart';
import 'package:cutnsave/services/auth_gateway.dart';
import 'package:cutnsave/services/services.dart';
import 'package:cutnsave/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _ReadyAuth implements AuthGateway {
  @override
  bool get hasSession => true;
  @override
  String? get userId => 'u1';
  @override
  String? get email => 'mom@example.com';
  @override
  Future<void> signInWithGoogle() async {}
  @override
  Future<String?> bootstrapLibrary() async => 'lib1';
  @override
  Future<void> signOut() async {}
}

/// Minimal fake so `Services.create`'s `getApplicationDocumentsDirectory()`
/// call doesn't hit a real platform channel in the test environment.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._dir);
  final Directory _dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir.path;
}

/// In-memory PKCE storage so Supabase.initialize (called from inside
/// tester.runAsync, see file header) never touches the shared_preferences
/// platform channel.
class _InMemoryPkceStorage extends GotrueAsyncStorage {
  final _map = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _map[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _map[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _map.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cns_nav_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    PackageInfo.setMockInitialValues(
      appName: 'cutNsave',
      packageName: 'com.example.cutnsave',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  testWidgets(
      'Services provider is visible after a Navigator.push '
      '(regression for ProviderNotFoundException)', (tester) async {
    SharedPreferences.setMockInitialValues({'library_id': 'lib1'});
    final prefs = await SharedPreferences.getInstance();
    // See file header: the isolate-based factory hangs under testWidgets'
    // fake-async zone, so the in-process factory is used here instead.
    final db =
        await LocalDb.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);

    final app = AppState(prefs: prefs, auth: _ReadyAuth());
    await app.boot();
    expect(app.status, AuthStatus.ready);

    late BuildContext pushedContext;

    await tester.runAsync(() async {
      // No real backend is reachable in a widget test; Services.create only
      // needs a SupabaseClient object to exist (it doesn't make eager
      // network calls), so a local, never-dialled URL is enough.
      await Supabase.initialize(
        url: 'http://localhost:54321',
        publishableKey: 'test-anon-key',
        authOptions: FlutterAuthClientOptions(
          detectSessionInUri: false,
          autoRefreshToken: false,
          persistSession: false,
          pkceAsyncStorage: _InMemoryPkceStorage(),
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: app),
            Provider<Database>.value(value: db),
            Provider<SharedPreferences>.value(value: prefs),
          ],
          child: const CutNSaveApp(),
        ),
      );
      // Let ServicesScope's FutureBuilder resolve Services.create(...).
      await tester.pumpAndSettle();

      // Push a second route the way the real app does (HomeScreen pushing
      // ScanScreen/EditArticleScreen/etc. via Navigator.push), and confirm
      // the Services provider is visible there too. Before the fix, this
      // threw ProviderNotFoundException because the pushed route's context
      // was a sibling of HomeScreen in the Navigator's Overlay, not its
      // descendant.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(MaterialPageRoute(builder: (ctx) {
        pushedContext = ctx;
        return const Scaffold(body: Text('pushed'));
      }));
      await tester.pumpAndSettle();
    });

    expect(() => pushedContext.read<Services>(), returnsNormally);
    expect(pushedContext.read<Services>().libraryId, 'lib1');
  });
}
