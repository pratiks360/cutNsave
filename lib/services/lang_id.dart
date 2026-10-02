import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';

import '../logic/lang.dart';

Future<String> identifyLanguage(String text) async {
  if (text.trim().isEmpty) return 'mr';
  final id = LanguageIdentifier(confidenceThreshold: 0.4);
  try {
    final code = await id.identifyLanguage(text);
    return detectLang(text, mlkitCode: code);
  } catch (_) {
    return detectLang(text);
  } finally {
    await id.close();
  }
}
