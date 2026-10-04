import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../logic/article_html.dart';

// convertHtml renders via a hidden platform WebView; a bound here guards
// against that render never completing (seen on some devices/HTML inputs).
const _renderTimeout = Duration(seconds: 20);

// share_plus's shareXFiles() future only resolves once the OS reports back
// which app the user picked, via a broadcast the share sheet sends after a
// choice is made. Some OEM Android skins' custom share sheets never send
// that broadcast, so the future can hang indefinitely even though the share
// sheet opened and did its job -- the app doesn't actually need to know
// which app was picked, so bound the wait and treat a timeout as a
// non-error rather than leaving the UI's busy spinner stuck forever.
const _shareResultTimeout = Duration(seconds: 10);

enum ShareOutcome {
  /// The proper PDF (image + original text + English text) was shared.
  pdf,

  /// PDF generation failed (e.g. the platform WebView never completed --
  /// seen on at least one real device/Android build, not just a theoretical
  /// risk) and the original photo was shared instead, so sharing still
  /// produces *something* rather than a dead end.
  photoFallback,
}

class PdfService {
  /// Renders via the platform WebView so Devanagari conjuncts shape correctly
  /// (the pure-Dart `pdf` package cannot shape Indic scripts).
  Future<File> buildFile(Article a) async {
    final path = a.imagePath;
    final image = (path != null && File(path).existsSync())
        ? base64Encode(await File(path).readAsBytes())
        : null;
    final html = buildArticleHtml(article: a, imageBase64: image);
    // printing 5.15.1 deprecated convertHtml with no replacement that still
    // renders via a platform WebView (needed for Devanagari conjunct
    // shaping — the pure-Dart `pdf` package can't do that). Deliberate,
    // documented choice; suppressed rather than worked around.
    // ignore: deprecated_member_use
    final bytes = await Printing.convertHtml(format: PdfPageFormat.a4, html: html)
        .timeout(_renderTimeout, onTimeout: () => throw TimeoutException('PDF render timed out'));
    final dir = await getTemporaryDirectory();
    final day = DateFormat('yyyy-MM-dd').format(a.scannedAt.toLocal());
    final file = File(p.join(dir.path, 'cutnsave-$day-${a.id.substring(0, 6)}.pdf'));
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<ShareOutcome> share(Article a) async {
    try {
      final file = await buildFile(a);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')])
          .timeout(_shareResultTimeout, onTimeout: () => ShareResult.unavailable);
      return ShareOutcome.pdf;
    } catch (_) {
      await _sharePhotoFallback(a);
      return ShareOutcome.photoFallback;
    }
  }

  Future<void> _sharePhotoFallback(Article a) async {
    final text = [
      a.originalText,
      if (a.englishText != null && a.englishText!.trim().isNotEmpty) a.englishText!,
    ].join('\n\n');
    final path = a.imagePath;
    final share = (path != null && File(path).existsSync())
        ? Share.shareXFiles([XFile(path, mimeType: 'image/jpeg')], text: text)
        : Share.share(text);
    await share.timeout(_shareResultTimeout, onTimeout: () => ShareResult.unavailable);
  }
}
