import 'dart:io';

import 'package:image/image.dart' as img;

/// Draws a simple cutNsave mark (pure Dart, no Flutter engine dependency):
/// a primary-blue square with a dashed white "cut" line and a green "save"
/// accent dot, and writes it to assets/icon/icon.png at 1024x1024.
void main() {
  const size = 1024;
  final primary = img.ColorRgb8(0x03, 0x69, 0xA1); // #0369A1
  final accent = img.ColorRgb8(0x16, 0xA3, 0x4A); // #16A34A
  final white = img.ColorRgb8(0xFF, 0xFF, 0xFF);

  final image = img.Image(width: size, height: size, numChannels: 3);

  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: size - 1,
    y2: size - 1,
    color: primary,
  );

  // Dashed white diagonal line representing the "cut".
  const lineStart = 220.0;
  const lineEnd = 680.0;
  const dashLength = 70.0;
  const gapLength = 46.0;
  const thickness = 48.0;
  final diagonalLength = (lineEnd - lineStart) * 1.4142135623730951;
  var travelled = 0.0;
  while (travelled < diagonalLength) {
    final t0 = travelled / diagonalLength;
    final t1 = ((travelled + dashLength) / diagonalLength).clamp(0.0, 1.0);
    img.drawLine(
      image,
      x1: (lineStart + (lineEnd - lineStart) * t0).round(),
      y1: (lineStart + (lineEnd - lineStart) * t0).round(),
      x2: (lineStart + (lineEnd - lineStart) * t1).round(),
      y2: (lineStart + (lineEnd - lineStart) * t1).round(),
      color: white,
      thickness: thickness,
      antialias: true,
    );
    travelled += dashLength + gapLength;
  }

  // Green "save" accent dot with a white highlight, clear of the edges.
  img.fillCircle(
    image,
    x: 760,
    y: 760,
    radius: 90,
    color: accent,
    antialias: true,
  );
  img.fillCircle(
    image,
    x: 760,
    y: 760,
    radius: 38,
    color: white,
    antialias: true,
  );

  final file = File('assets/icon/icon.png');
  file.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
  // ignore: avoid_print
  print('wrote ${file.path}');
}
