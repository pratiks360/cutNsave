import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class NotMemberScreen extends StatelessWidget {
  const NotMemberScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(context.t('not_member_title'),
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              Text(context.t('not_member_body'), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => context.read<AppState>().retry(),
                child: Text(context.t('retry')),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.read<AppState>().signOut(),
                child: Text(context.t('sign_out')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
