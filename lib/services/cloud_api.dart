import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

const _networkTimeout = Duration(seconds: 20);

class QuotaExceeded implements Exception {
  @override
  String toString() => 'QuotaExceeded';
}

abstract class CloudApi {
  Future<String> ocr(Uint8List jpeg);
  Future<String> translate(String text, String sourceLang);
}

class SupabaseCloudApi implements CloudApi {
  SupabaseCloudApi(this._client, this._libraryId);
  final SupabaseClient _client;
  final String _libraryId;

  @override
  Future<String> ocr(Uint8List jpeg) async {
    final res = await _invoke('ocr', {
      'image_base64': base64Encode(jpeg),
      'library_id': _libraryId,
    });
    return res['text'] as String;
  }

  @override
  Future<String> translate(String text, String sourceLang) async {
    final res = await _invoke('translate', {
      'text': text,
      'source': sourceLang,
      'library_id': _libraryId,
    });
    return res['text'] as String;
  }

  Future<Map<String, dynamic>> _invoke(String fn, Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(fn, body: body).timeout(
            _networkTimeout,
            onTimeout: () => throw TimeoutException('cloud_api.$fn timed out'),
          );
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      if (e.status == 429) throw QuotaExceeded();
      rethrow;
    }
  }
}
