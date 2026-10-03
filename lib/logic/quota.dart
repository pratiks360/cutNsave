import 'dart:math';

class Quota {
  Quota({
    required this.ocrUsed,
    required this.ocrLimit,
    required this.translateUsed,
    required this.translateLimit,
    required this.month,
  });

  final int ocrUsed;
  final int ocrLimit;
  final int translateUsed;
  final int translateLimit;
  final DateTime month;

  factory Quota.fromRpc(Map<String, dynamic> m) => Quota(
        ocrUsed: m['ocr_used'] as int,
        ocrLimit: m['ocr_limit'] as int,
        translateUsed: m['translate_used'] as int,
        translateLimit: m['translate_limit'] as int,
        month: DateTime.parse(m['month'] as String),
      );

  Map<String, dynamic> toJson() => {
        'ocr_used': ocrUsed,
        'ocr_limit': ocrLimit,
        'translate_used': translateUsed,
        'translate_limit': translateLimit,
        'month': month.toIso8601String().substring(0, 10),
      };

  int get ocrLeft => max(0, ocrLimit - ocrUsed);
  int get translateLeft => max(0, translateLimit - translateUsed);
  DateTime get resetsOn => DateTime(month.year, month.month + 1, 1);
}
