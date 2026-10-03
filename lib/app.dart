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
        if (app.status == AuthStatus.ready) {
          return ServicesScope(child: child!);
        }
        return child!;
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
                  if (app.error != null) Text(app.error!),
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
