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
  late final Future<Services> _future;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _future = Services.create(
      libraryId: app.libraryId!,
      userId: app.userId,
      db: context.read<Database>(),
      client: Supabase.instance.client,
      prefs: context.read<SharedPreferences>(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Services>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return Provider<Services>.value(value: snap.data!, child: widget.child);
      },
    );
  }
}
