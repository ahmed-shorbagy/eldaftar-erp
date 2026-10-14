import 'package:flutter/material.dart';

// WhatsApp glyph from Font Awesome Free 6.7.2, Copyright 2024 Fonticons, Inc.
// CC BY 4.0: https://fontawesome.com/license/free
// Geometry preserved from svgs/brands/whatsapp.svg; uses the existing theme color.
class CustomerWhatsappIcon extends StatelessWidget {
  const CustomerWhatsappIcon({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 24,
      height: 24,
      child: CustomPaint(
        painter: _WhatsappPainter(
          IconTheme.of(context).color ??
              Theme.of(context).colorScheme.onSurface,
        ),
      ),
    ),
  );
}

class _WhatsappPainter extends CustomPainter {
  const _WhatsappPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 16, 0);
    canvas.scale(size.width / 512, size.height / 512);
    final path = Path()
      ..moveTo(380.900, 97.100)
      ..cubicTo(339.000, 55.100, 283.200, 32.000, 223.900, 32.000)
      ..cubicTo(101.500, 32.000, 1.900, 131.600, 1.900, 254.000)
      ..cubicTo(1.900, 293.100, 12.100, 331.300, 31.500, 365.000)
      ..lineTo(0.000, 480.000)
      ..lineTo(117.700, 449.100)
      ..cubicTo(150.100, 466.800, 186.600, 476.100, 223.800, 476.100)
      ..lineTo(223.900, 476.100)
      ..cubicTo(346.200, 476.100, 448.000, 376.500, 448.000, 254.100)
      ..cubicTo(448.000, 194.800, 422.800, 139.100, 380.900, 97.100)
      ..close()
      ..moveTo(223.900, 438.700)
      ..cubicTo(190.700, 438.700, 158.200, 429.800, 129.900, 413.000)
      ..lineTo(123.200, 409.000)
      ..lineTo(53.400, 427.300)
      ..lineTo(72.000, 359.200)
      ..lineTo(67.600, 352.200)
      ..cubicTo(49.100, 322.800, 39.400, 288.900, 39.400, 254.000)
      ..cubicTo(39.400, 152.300, 122.200, 69.500, 224.000, 69.500)
      ..cubicTo(273.300, 69.500, 319.600, 88.700, 354.400, 123.600)
      ..cubicTo(389.200, 158.500, 410.600, 204.800, 410.500, 254.100)
      ..cubicTo(410.500, 355.900, 325.600, 438.700, 223.900, 438.700)
      ..close()
      ..moveTo(325.100, 300.500)
      ..cubicTo(319.600, 297.700, 292.300, 284.300, 287.200, 282.500)
      ..cubicTo(282.100, 280.600, 278.400, 279.700, 274.700, 285.300)
      ..cubicTo(271.000, 290.900, 260.400, 303.300, 257.100, 307.100)
      ..cubicTo(253.900, 310.800, 250.600, 311.300, 245.100, 308.500)
      ..cubicTo(212.500, 292.200, 191.100, 279.400, 169.600, 242.500)
      ..cubicTo(163.900, 232.700, 175.300, 233.400, 185.900, 212.200)
      ..cubicTo(187.700, 208.500, 186.800, 205.300, 185.400, 202.500)
      ..cubicTo(184.000, 199.700, 172.900, 172.400, 168.300, 161.300)
      ..cubicTo(163.800, 150.500, 159.200, 152.000, 155.800, 151.800)
      ..cubicTo(152.600, 151.600, 148.900, 151.600, 145.200, 151.600)
      ..cubicTo(141.500, 151.600, 135.500, 153.000, 130.400, 158.500)
      ..cubicTo(125.300, 164.100, 111.000, 177.500, 111.000, 204.800)
      ..cubicTo(111.000, 232.100, 130.900, 258.500, 133.600, 262.200)
      ..cubicTo(136.400, 265.900, 172.700, 321.900, 228.400, 346.000)
      ..cubicTo(263.600, 361.200, 277.400, 362.500, 295.000, 359.900)
      ..cubicTo(305.700, 358.300, 327.800, 346.500, 332.400, 333.500)
      ..cubicTo(337.000, 320.500, 337.000, 309.400, 335.600, 307.100)
      ..cubicTo(334.300, 304.600, 330.600, 303.200, 325.100, 300.500)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WhatsappPainter oldDelegate) =>
      oldDelegate.color != color;
}
