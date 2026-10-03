import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../state/app_state.dart';
import 'services.dart';

class ServicesScope extends StatefulWidget {
  const ServicesScope({super.key, required this.child});
  final Widget child;

  @override
  State<ServicesScope> createState() => _ServicesScopeState();
}

class _ServicesScopeState extends State<ServicesScope> {
  late Future<Services> _future;

  @override
  void initState() {
    super.initState();
    _future = _create();
  }

  Future<Services> _create() {
    final app = context.read<AppState>();
    return Services.create(
      libraryId: app.libraryId!,
      userId: app.userId,
      db: context.read<Database>(),
      client: Supabase.instance.client,
      prefs: context.read<SharedPreferences>(),
    );
  }

  void _retry() => setState(() => _future = _create());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Services>(
      future: _future,
      builder: (context, snap) {
        // Mirrors Gate's AuthStatus.error handling in app.dart: a generic
        // message plus a retry button instead of hanging on a spinner
        // forever when Services.create() fails (e.g. a DB/open error).
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(context.tr('error_generic')),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _retry, child: Text(context.tr('retry'))),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return Provider<Services>.value(value: snap.data!, child: widget.child);
      },
    );
  }
}
