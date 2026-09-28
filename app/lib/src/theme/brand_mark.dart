import 'package:flutter/material.dart';

import '../shell/shell_copy.dart';
import 'app_tokens.dart';

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
        painter: const _BrandMarkPainter(),
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
  const _BrandMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 32;
    canvas.scale(scale);
    final brown = Paint()..color = AppTokens.seed;
    final page = Paint()..color = AppTokens.lightSurface;
    final spine = Paint()..color = AppTokens.darkPrimaryContainer;
    final gold = Paint()..color = AppTokens.brandGold;
    final ink = Paint()
      ..color = AppTokens.seed
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 32, 32),
        const Radius.circular(8),
      ),
      brown,
    );
    canvas.drawPath(
      Path()
        ..moveTo(6.5, 10.2)
        ..lineTo(15, 12.2)
        ..lineTo(15, 23.2)
        ..lineTo(6.5, 21.2)
        ..close(),
      page,
    );
    canvas.drawPath(
      Path()
        ..moveTo(17, 12.2)
        ..lineTo(25.5, 10.2)
        ..lineTo(25.5, 21.2)
        ..lineTo(17, 23.2)
        ..close(),
      page,
    );
    canvas.drawRect(const Rect.fromLTWH(15, 12.2, 2, 11), spine);
    canvas.drawLine(const Offset(8.3, 15), const Offset(13.2, 15), ink);
    canvas.drawLine(const Offset(8.4, 17.6), const Offset(12.4, 17.6), ink);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(18.7, 15.4, 5, 3.1),
        const Radius.circular(0.7),
      ),
      gold,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
