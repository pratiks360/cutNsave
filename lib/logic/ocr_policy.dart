/// True when on-device OCR output looks empty/unusable and Cloud Vision is worth a call.
bool needsCloud(String text) {
  final nonSpace = text.replaceAll(RegExp(r'\s'), '');
  if (nonSpace.length < 30) return true;
  final good = RegExp(r'[ऀ-ॿA-Za-z0-9]').allMatches(nonSpace).length;
  return good / nonSpace.length < 0.7;
}
