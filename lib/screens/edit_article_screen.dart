import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../logic/article_saver.dart';
import '../services/lang_id.dart';
import '../services/ocr_service.dart';
import '../services/services.dart';
import '../state/app_state.dart';
import '../widgets/new_category_dialog.dart';

class EditArticleScreen extends StatefulWidget {
  const EditArticleScreen.scan({super.key, required String this.imagePath}) : article = null;
  const EditArticleScreen.existing(Article this.article, {super.key}) : imagePath = null;

  final String? imagePath;
  final Article? article;

  @override
  State<EditArticleScreen> createState() => _EditArticleScreenState();
}

class _EditArticleScreenState extends State<EditArticleScreen> {
  late final Services _s = context.read<Services>();
  final _text = TextEditingController();
  String _lang = 'mr';
  String? _categoryId;
  bool _translate = true;
  List<Category> _categories = [];
  String? _busy;
  String? _note;

  bool get _isNew => widget.article == null;

  @override
  void initState() {
    super.initState();
    final a = widget.article;
    if (a != null) {
      _text.text = a.originalText;
      _lang = a.originalLang;
      _categoryId = a.categoryId;
    }
    unawaited(_loadCategories());
    if (_isNew) WidgetsBinding.instance.addPostFrameCallback((_) => _runOcr());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final list = await _s.repo.categories();
    if (mounted) setState(() => _categories = list);
  }

  Future<void> _runOcr() async {
    setState(() => _busy = context.tr('scanning'));
    final result = await _s.ocr.recognize(widget.imagePath!);
    final lang = await identifyLanguage(result.text);
    if (!mounted) return;
    String? note;
    if (result.skip == CloudSkip.quota) {
      final q = await _s.quota.fetch();
      if (!mounted) return;
      note = context.tr('cloud_limit', {
        'date': q == null ? '' : DateFormat('d MMM').format(q.resetsOn),
      });
    } else if (result.skip == CloudSkip.offline) {
      note = context.tr('cloud_offline');
    }
    if (result.text.trim().isEmpty) note = context.tr('ocr_empty');
    setState(() {
      _text.text = result.text;
      _lang = lang;
      _translate = lang != 'en';
      _note = note;
      _busy = null;
    });
  }

  Future<void> _newCategory() async {
    final c = await showNewCategoryDialog(context);
    if (c == null) return;
    await _loadCategories();
    setState(() => _categoryId = c.id);
  }

  Future<void> _save() async {
    final willTranslate = _translate && _lang != 'en';
    setState(() => _busy = context.tr(willTranslate ? 'translating' : 'save'));
    try {
      final SaveOutcome outcome;
      final existing = widget.article;
      if (existing == null) {
        outcome = await _s.saver.saveNew(
          tempImagePath: widget.imagePath!,
          text: _text.text,
          lang: _lang,
          categoryId: _categoryId,
          translate: willTranslate,
        );
      } else {
        outcome = await _s.saver.updateExisting(
          existing,
          text: _text.text,
          lang: _lang,
          categoryId: _categoryId,
          translate: willTranslate,
        );
      }
      unawaited(_s.sync.trySync());
      if (!mounted) return;
      if (outcome.translationPending) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.tr('translate_later'))));
      }
      if (_isNew) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr('error_generic'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t(_isNew ? 'scan' : 'edit'))),
      body: _busy != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [const CircularProgressIndicator(), const SizedBox(height: 16), Text(_busy!)],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.imagePath != null)
                  SizedBox(height: 160, child: Image.file(File(widget.imagePath!))),
                if (_note != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_note!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _text,
                  minLines: 8,
                  maxLines: null,
                  decoration: InputDecoration(
                    labelText: context.t('original_text'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _lang,
                  decoration: InputDecoration(labelText: context.t('language')),
                  items: [
                    for (final l in ['mr', 'hi', 'en'])
                      DropdownMenuItem(value: l, child: Text(context.t('lang_$l'))),
                  ],
                  onChanged: (v) => setState(() {
                    _lang = v!;
                    _translate = v != 'en';
                  }),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                  decoration: InputDecoration(labelText: context.t('category')),
                  items: [
                    for (final c in _categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(context.t('new_category')),
                  onPressed: _newCategory,
                ),
                if (_lang != 'en')
                  SwitchListTile(
                    title: Text(context.t('translate_toggle')),
                    value: _translate,
                    onChanged: (v) => setState(() => _translate = v),
                  ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _save, child: Text(context.t('save'))),
              ],
            ),
    );
  }
}
