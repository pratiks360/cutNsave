import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';

class ArticleTile extends StatelessWidget {
  const ArticleTile({super.key, required this.article, required this.onTap, this.categoryName});
  final Article article;
  final String? categoryName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final path = article.imagePath;
    final snippet = article.originalText.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.all(10),
        leading: SizedBox(
          width: 64,
          height: 64,
          child: (path != null && File(path).existsSync())
              ? Image.file(File(path), fit: BoxFit.cover, cacheWidth: 200)
              : const Icon(Icons.article, size: 40),
        ),
        title: Text(snippet.isEmpty ? '—' : snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          DateFormat('d MMM yyyy').format(article.scannedAt.toLocal()),
          ?categoryName,
        ].join(' · ')),
        onTap: onTap,
      ),
    );
  }
}
