import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final error = context.watch<AppState>().error;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.content_cut, size: 96),
              const SizedBox(height: 12),
              const Text('cutNsave',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
              const SizedBox(height: 48),
              FilledButton.icon(
                icon: const Icon(Icons.login),
                label: Text(context.t('sign_in')),
                onPressed: () => context.read<AppState>().signIn(),
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
