import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/not_member_screen.dart';
import 'services/services_scope.dart';
import 'state/app_state.dart';
import 'theme.dart';

class CutNSaveApp extends StatelessWidget {
  const CutNSaveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'cutNsave',
      theme: buildTheme(),
      builder: (context, child) {
        final app = context.watch<AppState>();
        // Android 15+ (targetSdk 35+) enforces edge-to-edge rendering: the
        // system no longer reserves space for the gesture/button nav bar, so
        // bottom-aligned content (a button at the end of a ListView, not a
        // FloatingActionButton -- Scaffold already insets those itself) gets
        // drawn underneath it unless explicitly padded. SafeArea here is
        // app-wide so no individual screen has to remember to add it;
        // nesting it inside a screen that already wraps its own body in
        // SafeArea (login_screen, not_member_screen) is harmless -- the
        // inner one just sees zero additional padding to consume.
        final safe = SafeArea(child: child!);
        if (app.status == AuthStatus.ready) {
          return ServicesScope(child: safe);
        }
        return safe;
      },
      home: const Gate(),
    );
  }
}

class Gate extends StatelessWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    switch (app.status) {
      case AuthStatus.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.signedOut:
        return const LoginScreen();
      case AuthStatus.notMember:
        return const NotMemberScreen();
      case AuthStatus.error:
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(app.t('error_generic')),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: app.retry, child: Text(app.t('retry'))),
                ],
              ),
            ),
          ),
        );
      case AuthStatus.ready:
        return const HomeScreen();
    }
  }
}
