import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/strings.dart';
import '../services/auth_gateway.dart';

enum AuthStatus { loading, signedOut, notMember, ready, error }

class AppState extends ChangeNotifier {
  AppState({required this.prefs, required this.auth}) : lang = prefs.getString('lang') ?? 'mr';

  final SharedPreferences prefs;
  final AuthGateway auth;

  AuthStatus status = AuthStatus.loading;
  String lang;
  String? libraryId;
  String? error;

  String get userId => auth.userId ?? '';

  String t(String key, [Map<String, String> args = const {}]) => Tr.of(lang, key, args);

  Future<void> boot() async {
    if (!auth.hasSession) {
      status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    final cached = prefs.getString('library_id');
    if (cached != null) {
      libraryId = cached;
      status = AuthStatus.ready;
      notifyListeners();
      return;
    }
    await _resolveLibrary();
  }

  Future<void> signIn() async {
    error = null;
    try {
      await auth.signInWithGoogle();
    } on SignInCancelled {
      status = AuthStatus.signedOut;
      notifyListeners();
      return;
    } catch (e) {
      error = '$e';
      status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    await _resolveLibrary();
  }

  Future<void> retry() => _resolveLibrary();

  Future<void> _resolveLibrary() async {
    status = AuthStatus.loading;
    notifyListeners();
    try {
      final id = await auth.bootstrapLibrary();
      if (id == null) {
        status = AuthStatus.notMember;
      } else {
        libraryId = id;
        await prefs.setString('library_id', id);
        status = AuthStatus.ready;
      }
    } catch (e) {
      error = '$e';
      status = AuthStatus.error;
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    await auth.signOut();
    await prefs.remove('library_id');
    libraryId = null;
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<void> setLang(String value) async {
    lang = value;
    await prefs.setString('lang', value);
    notifyListeners();
  }
}

extension BuildContextT on BuildContext {
  /// Watches AppState: use inside build().
  String t(String key, [Map<String, String> args = const {}]) =>
      watch<AppState>().t(key, args);

  /// Reads AppState without listening: use inside callbacks / after awaits.
  String tr(String key, [Map<String, String> args = const {}]) =>
      read<AppState>().t(key, args);
}
