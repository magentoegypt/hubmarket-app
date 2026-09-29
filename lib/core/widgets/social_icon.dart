import 'package:flutter/material.dart';

/// Material icon proxy for a social-network key. Instagram/TikTok/Pinterest/X
/// have no native Material glyph, so the closest available icon is used — X
/// (formerly Twitter) shows the Material `close` glyph, which reads as its "✕".
/// Instagram is the exception: prefer [socialIconWidget], which draws a real
/// Instagram mark instead of the camera stand-in below.
IconData socialIconFor(String key) => switch (key) {
  'facebook' => Icons.facebook,
  'instagram' => Icons.camera_alt_outlined,
  'youtube' => Icons.smart_display_outlined,
  'tiktok' => Icons.music_note,
  'pinterest' => Icons.push_pin_outlined,
  'twitter' => Icons.close,
  _ => Icons.public,
};

/// A rendered social icon for [key] at [size] in [color]. Returns the drawn
/// Instagram mark (rounded camera body + lens + flash dot) for `instagram`,
/// where Material has no brand glyph; every other key falls back to its
/// [socialIconFor] Material icon. Prefer this over `Icon(socialIconFor(...))`.
Widget socialIconWidget(
  String key, {
  required double size,
  required Color color,
}) {
  if (key == 'instagram') return _InstagramIcon(size: size, color: color);
  return Icon(socialIconFor(key), size: size, color: color);
}

/// The Instagram glyph drawn to match a monochrome line icon at any [size].
class _InstagramIcon extends StatelessWidget {
  const _InstagramIcon({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _InstagramPainter(color),
  );
}

class _InstagramPainter extends CustomPainter {
  const _InstagramPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.09
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;

    // Camera body (rounded square).
    final inset = s * 0.125;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, s - 2 * inset, s - 2 * inset),
      Radius.circular(s * 0.235),
    );
    canvas.drawRRect(body, stroke);
    // Lens.
    canvas.drawCircle(Offset(s / 2, s / 2), s * 0.18, stroke);
    // Flash dot.
    canvas.drawCircle(Offset(s * 0.70, s * 0.30), s * 0.052, fill);
  }

  @override
  bool shouldRepaint(_InstagramPainter old) => old.color != color;
}
