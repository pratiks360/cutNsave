import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../logic/quota.dart';

class QuotaService {
  QuotaService({required this.fetchRows, required this.prefs});

  final Future<List<dynamic>> Function() fetchRows;
  final SharedPreferences prefs;

  static const _cacheKey = 'quota_cache';

  Future<Quota?> fetch() async {
    try {
      final rows = await fetchRows();
      final q = Quota.fromRpc(Map<String, dynamic>.from(rows.first as Map));
      await prefs.setString(_cacheKey, jsonEncode(q.toJson()));
      return q;
    } catch (_) {
      try {
        final cached = prefs.getString(_cacheKey);
        if (cached == null) return null;
        return Quota.fromRpc(Map<String, dynamic>.from(jsonDecode(cached) as Map));
      } catch (_) {
        return null;
      }
    }
  }
}
