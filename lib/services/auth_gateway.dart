import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

class SignInCancelled implements Exception {}

abstract class AuthGateway {
  bool get hasSession;
  String? get userId;
  String? get email;
  Future<void> signInWithGoogle();
  Future<String?> bootstrapLibrary();
  Future<void> signOut();
}

class SupabaseAuth implements AuthGateway {
  final _client = Supabase.instance.client;
  final _google = GoogleSignIn(
    serverClientId: Config.googleWebClientId,
    scopes: const ['email'],
  );

  @override
  bool get hasSession => _client.auth.currentSession != null;
  @override
  String? get userId => _client.auth.currentUser?.id;
  @override
  String? get email => _client.auth.currentUser?.email;

  @override
  Future<void> signInWithGoogle() async {
    final account = await _google.signIn();
    if (account == null) throw SignInCancelled();
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) throw StateError('Google did not return an ID token');
    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: auth.accessToken,
    );
  }

  @override
  Future<String?> bootstrapLibrary() async {
    final res = await _client.rpc('bootstrap_library');
    return res as String?;
  }

  @override
  Future<void> signOut() async {
    await _google.signOut();
    await _client.auth.signOut();
  }
}
