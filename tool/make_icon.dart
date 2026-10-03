import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  const size = 1024;
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(0x03, 0x69, 0xA1)); // AppColors.primary

  // White newspaper-clipping card, centered.
  const cardW = 620, cardH = 460;
  final cx = (size - cardW) ~/ 2;
  final cy = (size - cardH) ~/ 2;
  final white = img.ColorRgb8(0xFF, 0xFF, 0xFF);
  img.fillRect(image, x1: cx, y1: cy, x2: cx + cardW, y2: cy + cardH, color: white);

  // A few "text line" bars on the card.
  final lineColor = img.ColorRgb8(0x03, 0x69, 0xA1);
  for (final dy in [110, 190, 270, 350]) {
    img.fillRect(
      image,
      x1: cx + 50,
      y1: cy + dy,
      x2: cx + cardW - 50,
      y2: cy + dy + 30,
      color: lineColor,
    );
  }

  // Accent-green cut corner, top-right of the card.
  final accent = img.ColorRgb8(0x16, 0xA3, 0x4A); // AppColors.accent
  img.fillPolygon(
    image,
    vertices: [
      img.Point(cx + cardW - 140, cy),
      img.Point(cx + cardW, cy),
      img.Point(cx + cardW, cy + 140),
    ],
    color: accent,
  );

  final file = File('assets/icon/icon.png');
  file.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
  // ignore: avoid_print
  print('wrote ${file.path}');
}
