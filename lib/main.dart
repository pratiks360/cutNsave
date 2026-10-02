import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config.dart';
import 'data/local_db.dart';
import 'services/auth_gateway.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // `anonKey` is deprecated in supabase_flutter 2.18 in favor of
  // `publishableKey` (same value, new name); Config.supabaseAnonKey keeps
  // its name since that's what the Supabase dashboard / --dart-define calls it.
  await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseAnonKey);
  final prefs = await SharedPreferences.getInstance();
  final docs = await getApplicationDocumentsDirectory();
  final db = await LocalDb.open(databaseFactory, p.join(docs.path, 'cutnsave.db'));
  final app = AppState(prefs: prefs, auth: SupabaseAuth())..boot();
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: app),
      Provider<Database>.value(value: db),
      Provider<SharedPreferences>.value(value: prefs),
    ],
    child: const CutNSaveApp(),
  ));
}
