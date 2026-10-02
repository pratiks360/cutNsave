import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/translate_service.dart';

class SaveOutcome {
  const SaveOutcome(this.article, this.translationPending);
  final Article article;
  final bool translationPending;
}

class _English {
  const _English(this.text, this.pending);
  final String? text;
  final bool pending;
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
    return SaveOutcome(article, en.pending);
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
    return SaveOutcome(article, en.pending);
  }

  Future<_English> _english(String text, String lang, bool translate) async {
    if (lang == 'en') return _English(text, false);
    if (!translate) return const _English(null, false);
    final r = await translator.toEnglish(text, lang);
    return _English(r.text, r.text == null);
  }
}
