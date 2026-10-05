import 'package:flutter/material.dart';

import '../shell/shell_copy.dart';

/// Open ledger and gold ingot. Geometry matches `assets/brand/mark.svg`.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        key: const Key('brand-mark'),
        size: Size.square(size),
        painter: _BrandMarkPainter(Theme.of(context).colorScheme),
      ),
    );
  }
}

/// Large opening mark: the ledger symbol, the name, then the tagline.
class BrandHero extends StatelessWidget {
  const BrandHero({super.key, this.markSize = 112, this.compact = false});

  final double markSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (compact) {
      return Row(
        children: [
          BrandMark(size: markSize),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ShellCopy.appTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  ShellCopy.brandTagline,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        BrandMark(size: markSize),
        const SizedBox(height: 16),
        Text(
          ShellCopy.appTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          ShellCopy.brandTagline,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    required this.title,
    this.titleKey,
    this.markSize = 28,
    this.maxLines = 1,
    this.style,
  });

  final String title;
  final Key? titleKey;
  final double markSize;
  final int maxLines;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        BrandMark(size: markSize),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            key: titleKey,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter(this.scheme);
  final ColorScheme scheme;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64);
    final background = Paint()..color = scheme.surface;
    final gold = Paint()..color = scheme.primary;
    final line = Paint()
      ..color = scheme.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, 1, 62, 62),
        const Radius.circular(14),
      ),
      background,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, 1, 62, 62),
        const Radius.circular(14),
      ),
      line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(8, 24)
        ..lineTo(30, 30)
        ..lineTo(30, 55)
        ..lineTo(8, 49)
        ..close(),
      gold,
    );
    canvas.drawPath(
      Path()
        ..moveTo(34, 30)
        ..lineTo(56, 24)
        ..lineTo(56, 49)
        ..lineTo(34, 55)
        ..close(),
      line,
    );
    final ink = Paint()
      ..color = scheme.surface
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var y = 33.0; y <= 45; y += 6) {
      canvas.drawLine(Offset(13, y), Offset(24, y + 3), ink);
    }
    canvas.drawRect(const Rect.fromLTWH(39, 42, 3, 7), gold);
    canvas.drawRect(const Rect.fromLTWH(44, 37, 3, 10), gold);
    canvas.drawRect(const Rect.fromLTWH(49, 32, 3, 13), gold);
    canvas.drawPath(
      Path()
        ..moveTo(24, 13)
        ..lineTo(28, 8)
        ..lineTo(36, 8)
        ..lineTo(40, 13)
        ..lineTo(32, 23)
        ..close(),
      line,
    );
    canvas.drawLine(const Offset(24, 13), const Offset(40, 13), line);
    canvas.drawLine(const Offset(28, 8), const Offset(32, 23), line);
    canvas.drawLine(const Offset(36, 8), const Offset(32, 23), line);
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter oldDelegate) =>
      oldDelegate.scheme != scheme;
}
