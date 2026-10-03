import 'package:cutnsave/app.dart';
import 'package:cutnsave/services/auth_gateway.dart';
import 'package:cutnsave/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedOut implements AuthGateway {
  @override
  bool get hasSession => false;
  @override
  String? get userId => null;
  @override
  String? get email => null;
  @override
  Future<void> signInWithGoogle() async {}
  @override
  Future<String?> bootstrapLibrary() async => null;
  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets('signed-out user sees Marathi sign-in button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(prefs: await SharedPreferences.getInstance(), auth: _SignedOut());
    await app.boot();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: app,
      child: const CutNSaveApp(),
    ));
    expect(find.text('Google ने साइन इन करा'), findsOneWidget);
    await app.setLang('en');
    await tester.pump();
    expect(find.text('Sign in with Google'), findsOneWidget);
  });
}
