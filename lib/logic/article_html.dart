import 'dart:convert';

import 'package:intl/intl.dart';

import '../data/models.dart';

const _esc = HtmlEscape();

String buildArticleHtml({required Article article, required String? imageBase64}) {
  final date = DateFormat('d MMMM yyyy').format(article.scannedAt.toLocal());
  final sections = StringBuffer();
  if (article.originalLang == 'en') {
    sections.write(_section('English', article.originalText));
  } else {
    final label = article.originalLang == 'hi' ? 'Hindi' : 'Marathi';
    sections.write(_section('Original text ($label)', article.originalText));
    final en = article.englishText;
    if (en != null && en.trim().isNotEmpty) sections.write(_section('English', en));
  }
  final image = imageBase64 == null
      ? ''
      : '<img src="data:image/jpeg;base64,$imageBase64">';
  return '''<!doctype html>
<html><head><meta charset="utf-8">
<style>
body{font-family:'Noto Sans Devanagari','Noto Sans',sans-serif;font-size:14px;line-height:1.5;margin:24px;}
h1{font-size:16px;color:#555;margin:0 0 12px}
h2{font-size:15px;margin:20px 0 6px;border-bottom:1px solid #ccc}
img{max-width:100%;max-height:420px;display:block;margin:8px 0}
.text{white-space:pre-wrap}
</style></head>
<body>
<h1>Scanned on $date</h1>
$image
$sections
</body></html>''';
}

String _section(String title, String text) =>
    '<h2>$title</h2><div class="text">${_esc.convert(text)}</div>';
