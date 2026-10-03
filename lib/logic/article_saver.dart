import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/ocr_service.dart' show CloudSkip;
import '../services/translate_service.dart';

class SaveOutcome {
  const SaveOutcome(this.article, this.translationPending, {this.translationSkip});
  final Article article;
  final bool translationPending;
  // Why translation didn't complete when [translationPending] is true (quota,
  // offline, or text too long for the cloud translator), so the UI can show
  // a message specific to the reason instead of one generic "pending" note.
  final CloudSkip? translationSkip;
}

class _English {
  const _English(this.text, this.pending, [this.skip]);
  final String? text;
  final bool pending;
  final CloudSkip? skip;
}

class ArticleSaver {
  ArticleSaver({
    required this.repo,
    required this.translator,
    required this.libraryId,
    required this.userId,
    required this.imageDir,
    DateTime Function()? now,
    String Function()? newId,
  })  : _now = now ?? (() => DateTime.now().toUtc()),
        _newId = newId ?? (() => const Uuid().v4());

  final Repository repo;
  final TranslateService translator;
  final String libraryId;
  final String userId;
  final String imageDir;
  final DateTime Function() _now;
  final String Function() _newId;

  Future<SaveOutcome> saveNew({
    required String tempImagePath,
    required String text,
    required String lang,
    String? categoryId,
    required bool translate,
  }) async {
    final id = _newId();
    await Directory(imageDir).create(recursive: true);
    final dest = p.join(imageDir, '$id.jpg');
    await File(tempImagePath).copy(dest);
    final en = await _english(text, lang, translate);
    final now = _now();
    final article = Article(
      id: id,
      libraryId: libraryId,
      categoryId: categoryId,
      imagePath: dest,
      originalText: text,
      originalLang: lang,
      englishText: en.text,
      scannedAt: now,
      createdBy: userId,
      updatedAt: now,
    );
    await repo.upsertArticle(article);
    return SaveOutcome(article, en.pending, translationSkip: en.skip);
  }

  Future<SaveOutcome> updateExisting(
    Article old, {
    required String text,
    required String lang,
    String? categoryId,
    required bool translate,
  }) async {
    final changed = text != old.originalText || lang != old.originalLang;
    _English en;
    if (translate && (changed || old.englishText == null)) {
      en = await _english(text, lang, true);
    } else {
      en = _English(changed ? null : old.englishText, false);
    }
    final article = old.copyWith(
      originalText: text,
      originalLang: lang,
      categoryId: categoryId,
      englishText: en.text,
      clearEnglish: en.text == null,
      updatedAt: _now(),
    );
    await repo.upsertArticle(article);
    return SaveOutcome(article, en.pending, translationSkip: en.skip);
  }

  /// Re-runs translation for an article whose English text is still
  /// pending (both ML Kit and cloud translate failed earlier, e.g. quota or
  /// offline) and stores the result locally, dirty, for the next sync.
  Future<SaveOutcome> retranslate(Article article) async {
    final en = await _english(article.originalText, article.originalLang, true);
    final updated = article.copyWith(
      englishText: en.text,
      clearEnglish: en.text == null,
      updatedAt: _now(),
    );
    await repo.upsertArticle(updated);
    return SaveOutcome(updated, en.pending, translationSkip: en.skip);
  }

  Future<_English> _english(String text, String lang, bool translate) async {
    if (lang == 'en') return _English(text, false);
    if (!translate) return const _English(null, false);
    final r = await translator.toEnglish(text, lang);
    return _English(r.text, r.text == null, r.skip);
  }
}
