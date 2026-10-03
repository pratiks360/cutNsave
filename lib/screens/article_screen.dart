import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../services/services.dart';
import '../state/app_state.dart';
import 'edit_article_screen.dart';

class ArticleScreen extends StatefulWidget {
  const ArticleScreen({super.key, required this.articleId});
  final String articleId;

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  late final Services _s = context.read<Services>();
  Article? _article;
  String? _categoryName;
  bool _sharing = false;
  bool _retranslating = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final a = await _s.repo.article(widget.articleId);
    final cats = await _s.repo.categories();
    if (!mounted) return;
    setState(() {
      _article = a;
      _categoryName = cats.where((c) => c.id == a?.categoryId).map((c) => c.name).firstOrNull;
    });
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      await _s.pdf.share(_article!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${context.tr('error_generic')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _retranslate() async {
    setState(() => _retranslating = true);
    try {
      final outcome = await _s.saver.retranslate(_article!);
      unawaited(_s.sync.trySync());
      if (!mounted) return;
      setState(() => _article = outcome.article);
      if (outcome.translationPending) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.tr('translate_later'))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.tr('error_generic'))));
      }
    } finally {
      if (mounted) setState(() => _retranslating = false);
    }
  }

  Future<void> _edit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EditArticleScreen.existing(_article!)),
    );
    if (changed == true) await _load();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(ctx.tr('delete_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await _s.repo.softDeleteArticle(widget.articleId);
    unawaited(_s.sync.trySync());
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final a = _article;
    if (a == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final path = a.imagePath;
    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('d MMM yyyy').format(a.scannedAt.toLocal())),
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: _edit),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_categoryName != null) Chip(label: Text(_categoryName!)),
          if (path != null && File(path).existsSync())
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(),
                      body: InteractiveViewer(child: Center(child: Image.file(File(path)))),
                    ),
                  ),
                ),
                child: Image.file(File(path)),
              ),
            ),
          Text(context.t('original_text'), style: Theme.of(context).textTheme.titleMedium),
          SelectableText(a.originalText),
          if (a.englishText != null && a.originalLang != 'en') ...[
            const SizedBox(height: 16),
            Text(context.t('english_text'), style: Theme.of(context).textTheme.titleMedium),
            SelectableText(a.englishText!),
          ] else if (a.originalLang != 'en') ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.translate),
              label: Text(context.t(_retranslating ? 'translating' : 'retry_translation')),
              onPressed: _retranslating ? null : _retranslate,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.share),
            label: Text(context.t(_sharing ? 'preparing_pdf' : 'share_pdf')),
            onPressed: _sharing ? null : _share,
          ),
        ],
      ),
    );
  }
}
