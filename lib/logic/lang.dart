const _marathiWords = {'आहे', 'आणि', 'नाही', 'होते', 'आहेत', 'तो', 'ती', 'काय', 'या', 'हा'};
const _hindiWords = {'है', 'और', 'नहीं', 'हैं', 'था', 'थी', 'वह', 'यह', 'को', 'का'};

String detectLang(String text, {String? mlkitCode}) {
  final dev = RegExp(r'[ऀ-ॿ]').allMatches(text).length;
  final latin = RegExp(r'[A-Za-z]').allMatches(text).length;
  final hint = (mlkitCode == 'hi' || mlkitCode == 'mr') ? mlkitCode! : null;
  if (dev + latin == 0) return hint ?? 'mr';
  if (dev < latin) return 'en';

  final tokens = text.split(RegExp(r'[\s,.;:!?()"\-–—।]+'));
  var mr = 'ळ'.allMatches(text).length;
  var hi = 0;
  for (final t in tokens) {
    if (_marathiWords.contains(t)) mr++;
    if (_hindiWords.contains(t)) hi++;
  }
  if (mr != hi) return mr > hi ? 'mr' : 'hi';
  return hint ?? 'mr';
}
