import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../logic/quota.dart';

class QuotaService {
  QuotaService({required this.fetchRows, required this.prefs, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final Future<List<dynamic>> Function() fetchRows;
  final SharedPreferences prefs;
  final DateTime Function() _now;

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
        final q = Quota.fromRpc(Map<String, dynamic>.from(jsonDecode(cached) as Map));
        // The cache survives app restarts with no server round-trip, so a
        // quota cached in, say, September can still be sitting there on
        // October 2nd. Treat a stale month as a cache miss rather than
        // showing last month's numbers.
        final now = _now();
        if (q.month.year != now.year || q.month.month != now.month) return null;
        return q;
      } catch (_) {
        return null;
      }
    }
  }
}
