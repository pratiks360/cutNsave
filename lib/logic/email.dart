String? normalizeEmail(String input) {
  final e = input.trim().toLowerCase();
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e) ? e : null;
}
