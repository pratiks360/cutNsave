import 'package:cutnsave/services/auth_gateway.dart';
import 'package:cutnsave/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAuth implements AuthGateway {
  FakeAuth({this.session = true, this.library});
  bool session;
  String? library;
  int bootstrapCalls = 0;
  @override
  bool get hasSession => session;
  @override
  String? get userId => 'u1';
  @override
  String? get email => 'mom@example.com';
  @override
  Future<void> signInWithGoogle() async => session = true;
  @override
  Future<String?> bootstrapLibrary() async {
    bootstrapCalls++;
    return library;
  }
  @override
  Future<void> signOut() async => session = false;
}

Future<AppState> make(FakeAuth auth, [Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  return AppState(prefs: await SharedPreferences.getInstance(), auth: auth);
}

void main() {
  test('no session → signedOut, Marathi default', () async {
    final s = await make(FakeAuth(session: false));
    await s.boot();
    expect(s.status, AuthStatus.signedOut);
    expect(s.lang, 'mr');
  });

  test('session + bootstrap returns library → ready and cached', () async {
    final s = await make(FakeAuth(library: 'lib1'));
    await s.boot();
    expect(s.status, AuthStatus.ready);
    expect(s.libraryId, 'lib1');
    expect((await SharedPreferences.getInstance()).getString('library_id'), 'lib1');
  });

  test('session + bootstrap null → notMember', () async {
    final s = await make(FakeAuth(library: null));
    await s.boot();
    expect(s.status, AuthStatus.notMember);
  });

  test('cached library id lets app start offline without bootstrap call', () async {
    final auth = FakeAuth(library: null);
    final s = await make(auth, {'library_id': 'lib1'});
    await s.boot();
    expect(s.status, AuthStatus.ready);
    expect(auth.bootstrapCalls, 0);
  });

  test('signIn resolves library; signOut clears cache', () async {
    final auth = FakeAuth(session: false, library: 'lib1');
    final s = await make(auth);
    await s.boot();
    await s.signIn();
    expect(s.status, AuthStatus.ready);
    await s.signOut();
    expect(s.status, AuthStatus.signedOut);
    expect((await SharedPreferences.getInstance()).getString('library_id'), isNull);
  });

  test('setLang persists and t() follows', () async {
    final s = await make(FakeAuth(session: false));
    await s.boot();
    await s.setLang('en');
    expect(s.t('scan'), 'Scan article');
    expect((await SharedPreferences.getInstance()).getString('lang'), 'en');
  });
}
