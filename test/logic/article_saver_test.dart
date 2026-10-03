import 'dart:io';
import 'dart:typed_data';

import 'package:cutnsave/data/local_db.dart';
import 'package:cutnsave/data/repository.dart';
import 'package:cutnsave/logic/article_saver.dart';
import 'package:cutnsave/services/cloud_api.dart';
import 'package:cutnsave/services/ocr_service.dart' show CloudSkip;
import 'package:cutnsave/services/translate_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Cloud implements CloudApi {
  @override
  Future<String> ocr(Uint8List jpeg) async => '';
  @override
  Future<String> translate(String text, String sourceLang) async => '';
}

class _TooLongCloud implements CloudApi {
  @override
  Future<String> ocr(Uint8List jpeg) async => '';
  @override
  Future<String> translate(String text, String sourceLang) async => throw TextTooLong();
}

void main() {
  late Repository repo;
  late Directory dir;
  late File photo;
  var translateCalls = 0;

  ArticleSaver saver({String? result = 'Hello'}) => ArticleSaver(
        repo: repo,
        translator: TranslateService(
          mlkit: (t, l) async {
            translateCalls++;
            if (result == null) throw Exception('fail');
            return result;
          },
          cloud: _Cloud(), // returns '' so fallback yields pending
        ),
        libraryId: 'lib',
        userId: 'u1',
        imageDir: '${dir.path}/images',
        now: () => DateTime.utc(2026, 10, 2),
        newId: () => 'id1',
      );

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    translateCalls = 0;
    dir = Directory.systemTemp.createTempSync('saver');
    photo = File('${dir.path}/tmp.jpg')..writeAsBytesSync([1, 2, 3]);
    repo = Repository(await LocalDb.open(databaseFactoryFfi, inMemoryDatabasePath));
  });

  test('saveNew copies image, translates Marathi, stores dirty row', () async {
    final out = await saver().saveNew(
        tempImagePath: photo.path, text: 'नमस्कार', lang: 'mr', categoryId: 'c1', translate: true);
    expect(out.translationPending, isFalse);
    expect(out.article.englishText, 'Hello');
    expect(File(out.article.imagePath!).readAsBytesSync(), [1, 2, 3]);
    expect(out.article.imagePath, endsWith('id1.jpg'));
    expect((await repo.dirtyArticles()).single.id, 'id1');
    expect(out.article.createdBy, 'u1');
    expect(out.article.scannedAt, DateTime.utc(2026, 10, 2));
  });

  test('English article stores same text as English, no translation call', () async {
    final out = await saver().saveNew(
        tempImagePath: photo.path, text: 'Hi there', lang: 'en', translate: true);
    expect(out.article.englishText, 'Hi there');
    expect(translateCalls, 0);
  });

  test('translate off leaves English empty and not pending', () async {
    final out = await saver().saveNew(
        tempImagePath: photo.path, text: 'नमस्कार', lang: 'mr', translate: false);
    expect(out.article.englishText, isNull);
    expect(out.translationPending, isFalse);
  });

  test('translation failure saves anyway and flags pending', () async {
    final out = await saver(result: null).saveNew(
        tempImagePath: photo.path, text: 'नमस्कार', lang: 'mr', translate: true);
    expect(out.translationPending, isTrue);
    expect(out.article.englishText, isNull);
    expect(await repo.article('id1'), isNotNull);
  });

  test('updateExisting re-translates only when text changed', () async {
    final s = saver();
    final first = await s.saveNew(
        tempImagePath: photo.path, text: 'नमस्कार', lang: 'mr', translate: true);
    expect(translateCalls, 1);
    await s.updateExisting(first.article,
        text: 'नमस्कार', lang: 'mr', categoryId: 'c2', translate: true);
    expect(translateCalls, 1);
    final changed = await s.updateExisting(first.article,
        text: 'धन्यवाद', lang: 'mr', categoryId: 'c2', translate: true);
    expect(translateCalls, 2);
    expect(changed.article.originalText, 'धन्यवाद');
    expect(changed.article.categoryId, 'c2');
  });

  test('updateExisting with translate off clears stale English on text change', () async {
    final s = saver();
    final first = await s.saveNew(
        tempImagePath: photo.path, text: 'नमस्कार', lang: 'mr', translate: true);
    final out = await s.updateExisting(first.article,
        text: 'धन्यवाद', lang: 'mr', translate: false);
    expect(out.article.englishText, isNull);
  });

  test('retranslate fills in English text and persists it, no longer pending', () async {
    final pending = await saver(result: null).saveNew(
        tempImagePath: photo.path, text: 'नमस्कार', lang: 'mr', translate: true);
    expect(pending.translationPending, isTrue);

    final out = await saver().retranslate(pending.article);
    expect(out.translationPending, isFalse);
    expect(out.article.englishText, 'Hello');
    expect((await repo.article('id1'))!.englishText, 'Hello');
    expect((await repo.dirtyArticles()).single.id, 'id1');
  });

  test('retranslate that fails again leaves English pending', () async {
    final pending = await saver(result: null).saveNew(
        tempImagePath: photo.path, text: 'नमस्कार', lang: 'mr', translate: true);

    final out = await saver(result: null).retranslate(pending.article);
    expect(out.translationPending, isTrue);
    expect(out.article.englishText, isNull);
  });

  test('saveNew surfaces a tooLong translationSkip distinct from offline', () async {
    final s = ArticleSaver(
      repo: repo,
      translator: TranslateService(
        mlkit: (t, l) async => throw Exception('fail'),
        cloud: _TooLongCloud(),
      ),
      libraryId: 'lib',
      userId: 'u1',
      imageDir: '${dir.path}/images',
      now: () => DateTime.utc(2026, 10, 2),
      newId: () => 'id1',
    );
    final out = await s.saveNew(
        tempImagePath: photo.path, text: 'नमस्कार', lang: 'mr', translate: true);
    expect(out.translationPending, isTrue);
    expect(out.translationSkip, CloudSkip.tooLong);
  });

  test('retranslate on an English article is a no-op passthrough', () async {
    final out = await saver().saveNew(
        tempImagePath: photo.path, text: 'Hi there', lang: 'en', translate: true);
    final retried = await saver().retranslate(out.article);
    expect(retried.translationPending, isFalse);
    expect(retried.article.englishText, 'Hi there');
  });
}
