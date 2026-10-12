import 'package:flutter/material.dart';

/// Distinct jewelry silhouettes. Color comes from the icon theme.
enum JewelryKind { ring, earrings, necklace, pendant, coin, bullion }

class JewelryGlyph extends StatelessWidget {
  const JewelryGlyph(this.kind, {super.key, this.size = 28});

  final JewelryKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color =
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _JewelryPainter(kind, color),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _JewelryPainter extends CustomPainter {
  const _JewelryPainter(this.kind, this.color);

  final JewelryKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;
    switch (kind) {
      case JewelryKind.ring:
        canvas.drawCircle(Offset(w * 0.5, h * 0.58), w * 0.28, paint);
        _diamond(canvas, fill, Offset(w * 0.5, h * 0.22), w * 0.16);
      case JewelryKind.earrings:
        _drop(canvas, paint, Offset(w * 0.32, h * 0.58), w * 0.16);
        _drop(canvas, paint, Offset(w * 0.68, h * 0.58), w * 0.16);
        canvas.drawCircle(Offset(w * 0.32, h * 0.22), w * 0.06, fill);
        canvas.drawCircle(Offset(w * 0.68, h * 0.22), w * 0.06, fill);
      case JewelryKind.necklace:
        final chain = Path()
          ..moveTo(w * 0.12, h * 0.28)
          ..quadraticBezierTo(w * 0.5, h * 0.95, w * 0.88, h * 0.28);
        canvas.drawPath(chain, paint);
        canvas.drawCircle(Offset(w * 0.5, h * 0.72), w * 0.08, fill);
      case JewelryKind.pendant:
        canvas.drawLine(
          Offset(w * 0.5, h * 0.08),
          Offset(w * 0.5, h * 0.34),
          paint,
        );
        _diamond(canvas, paint, Offset(w * 0.5, h * 0.62), w * 0.28);
      case JewelryKind.coin:
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.38, paint);
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.22, paint);
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.05, fill);
      case JewelryKind.bullion:
        final back = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.18, h * 0.18, w * 0.64, h * 0.28),
          Radius.circular(w * 0.06),
        );
        final front = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.1, h * 0.4, w * 0.8, h * 0.36),
          Radius.circular(w * 0.08),
        );
        canvas.drawRRect(back, paint);
        canvas.drawRRect(front, paint);
        canvas.drawLine(
          Offset(w * 0.22, h * 0.58),
          Offset(w * 0.78, h * 0.58),
          paint,
        );
    }
  }

  void _diamond(Canvas canvas, Paint paint, Offset center, double radius) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx + radius * 0.75, center.dy)
      ..lineTo(center.dx, center.dy + radius)
      ..lineTo(center.dx - radius * 0.75, center.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drop(Canvas canvas, Paint paint, Offset center, double radius) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(
        center.dx + radius,
        center.dy,
        center.dx,
        center.dy + radius * 1.35,
      )
      ..quadraticBezierTo(
        center.dx - radius,
        center.dy,
        center.dx,
        center.dy - radius,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _JewelryPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
