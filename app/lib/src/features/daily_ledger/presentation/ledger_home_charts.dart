import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One confirmed amount drawn in a home chart.
///
/// [amount] is an integer quantity (piastres or milligrams). Chart geometry
/// derived from it is display-only.
class LedgerChartSlice {
  const LedgerChartSlice({
    required this.id,
    required this.label,
    required this.valueLabel,
    required this.amount,
    this.icon,
  });

  final String id;
  final String label;
  final String valueLabel;
  final BigInt amount;
  final IconData? icon;
}

/// Display-only shares. Each value is tenths of a percent (0–1000).
abstract final class ChartShares {
  /// Shares that sum to 1000 when [parts] has a positive total.
  ///
  /// The rounding remainder is added to the largest part so the written
  /// percentages add up to 100.0%. Equal amounts keep the earlier part.
  static List<int> tenthsOfPercent(List<BigInt> parts) {
    if (parts.isEmpty) return const [];
    final total = parts.fold<BigInt>(BigInt.zero, (sum, part) => sum + part);
    if (total <= BigInt.zero) return List<int>.filled(parts.length, 0);
    final tenths = [
      for (final part in parts)
        part <= BigInt.zero ? 0 : ((part * BigInt.from(1000)) ~/ total).toInt(),
    ];
    final drift = 1000 - tenths.fold<int>(0, (sum, part) => sum + part);
    if (drift != 0) {
      var index = 0;
      for (var i = 1; i < parts.length; i++) {
        if (parts[i] > parts[index]) index = i;
      }
      tenths[index] += drift;
    }
    return tenths;
  }

  static String label(int tenths) {
    final whole = tenths ~/ 10;
    final fraction = tenths % 10;
    return '$whole.$fraction%';
  }
}

List<Color> ledgerChartSeries(ColorScheme scheme, int count) {
  final roles = <Color>[
    scheme.primary,
    scheme.tertiary,
    scheme.secondary,
    scheme.onSurfaceVariant,
    scheme.onSurface,
  ];
  return [for (var i = 0; i < count; i++) roles[i % roles.length]];
}

/// Gold composition: each arc is that karat’s share of confirmed weight.
class LedgerShareDonut extends StatefulWidget {
  const LedgerShareDonut({
    super.key,
    required this.slices,
    required this.centerValue,
    required this.centerUnit,
    required this.shareKeyPrefix,
    required this.rankLabel,
    required this.chartLabel,
  });

  final List<LedgerChartSlice> slices;
  final String centerValue;
  final String centerUnit;
  final String shareKeyPrefix;
  final String rankLabel;
  final String chartLabel;

  @override
  State<LedgerShareDonut> createState() => _LedgerShareDonutState();
}

class _LedgerShareDonutState extends State<LedgerShareDonut>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final CurvedAnimation _progress;
  String? _selectedId;
  var _started = false;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _progress = CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _entrance.duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 700);
    if (!_started) {
      _started = true;
      _entrance.forward();
    }
  }

  @override
  void didUpdateWidget(covariant LedgerShareDonut oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _selectedId;
    if (selected != null &&
        widget.slices.every((slice) => slice.id != selected)) {
      _selectedId = null;
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slices.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tenths = ChartShares.tenthsOfPercent([
      for (final slice in widget.slices) slice.amount,
    ]);
    final colors = ledgerChartSeries(scheme, widget.slices.length);
    final lead = _leadingSlice(widget.slices);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lead != null && lead.amount > BigInt.zero) ...[
          Text(
            '${widget.rankLabel}: ${lead.label} · ${lead.valueLabel}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final sideBySide = constraints.maxWidth >= 420;
            final ring = _Ring(
              chartLabel: widget.chartLabel,
              centerValue: widget.centerValue,
              centerUnit: widget.centerUnit,
              tenths: tenths,
              colors: colors,
              progress: _progress,
              highlighted: _highlightIndex(),
              trackColor: scheme.surfaceContainerHighest,
            );
            final legend = _Legend(
              slices: widget.slices,
              tenths: tenths,
              colors: colors,
              shareKeyPrefix: widget.shareKeyPrefix,
              selectedId: _selectedId,
              onSelect: _toggle,
            );
            if (!sideBySide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: ring),
                  const SizedBox(height: 8),
                  legend,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ring,
                const SizedBox(width: 20),
                Expanded(child: legend),
              ],
            );
          },
        ),
      ],
    );
  }

  int? _highlightIndex() {
    final selected = _selectedId;
    if (selected == null) return null;
    final index = widget.slices.indexWhere((slice) => slice.id == selected);
    return index < 0 ? null : index;
  }

  void _toggle(String id) {
    setState(() => _selectedId = _selectedId == id ? null : id);
  }
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.chartLabel,
    required this.centerValue,
    required this.centerUnit,
    required this.tenths,
    required this.colors,
    required this.progress,
    required this.highlighted,
    required this.trackColor,
  });

  final String chartLabel;
  final String centerValue;
  final String centerUnit;
  final List<int> tenths;
  final List<Color> colors;
  final Animation<double> progress;
  final int? highlighted;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: chartLabel,
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 196,
          height: 196,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ListenableBuilder(
                listenable: progress,
                builder: (context, _) => CustomPaint(
                  size: const Size.square(196),
                  painter: _ShareRingPainter(
                    tenths: tenths,
                    colors: colors,
                    trackColor: trackColor,
                    highlighted: highlighted,
                    progress: progress.value,
                  ),
                ),
              ),
              SizedBox(
                width: 108,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text.rich(
                        TextSpan(
                          text: centerValue,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          children: [
                            TextSpan(
                              text: '\n$centerUnit',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Text(
                      'الإجمالي',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.slices,
    required this.tenths,
    required this.colors,
    required this.shareKeyPrefix,
    required this.selectedId,
    required this.onSelect,
  });

  final List<LedgerChartSlice> slices;
  final List<int> tenths;
  final List<Color> colors;
  final String shareKeyPrefix;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < slices.length; index++)
          _SliceButton(
            semanticsKey: Key('$shareKeyPrefix-${slices[index].id}'),
            slice: slices[index],
            share: ChartShares.label(tenths[index]),
            color: colors[index],
            selected: selectedId == slices[index].id,
            dimmed: selectedId != null && selectedId != slices[index].id,
            semanticsLabel:
                '${slices[index].label}، ${slices[index].valueLabel}، ${ChartShares.label(tenths[index])} من الإجمالي',
            onTap: () => onSelect(slices[index].id),
          ),
      ],
    );
  }
}

class _SliceButton extends StatelessWidget {
  const _SliceButton({
    required this.semanticsKey,
    required this.slice,
    required this.share,
    required this.color,
    required this.selected,
    required this.dimmed,
    required this.semanticsLabel,
    required this.onTap,
  });

  final Key semanticsKey;
  final LedgerChartSlice slice;
  final String share;
  final Color color;
  final bool selected;
  final bool dimmed;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    final muted = selected
        ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant;
    return Semantics(
      key: semanticsKey,
      button: true,
      selected: selected,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Material(
            type: selected ? MaterialType.canvas : MaterialType.transparency,
            color: selected ? scheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: dimmed ? color.withValues(alpha: 0.35) : color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          slice.label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                slice.valueLabel,
                                textAlign: TextAlign.end,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            Text(
                              share,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: muted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareRingPainter extends CustomPainter {
  const _ShareRingPainter({
    required this.tenths,
    required this.colors,
    required this.trackColor,
    required this.highlighted,
    required this.progress,
  });

  final List<int> tenths;
  final List<Color> colors;
  final Color trackColor;
  final int? highlighted;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const maxStroke = 22.0;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - maxStroke) / 2 - 1;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..color = trackColor;
    canvas.drawArc(rect, 0, math.pi * 2 - 0.001, false, track);

    final total = tenths.fold<int>(0, (sum, part) => sum + part);
    if (total <= 0 || progress <= 0) return;
    var start = -math.pi / 2;
    for (var i = 0; i < tenths.length; i++) {
      final raw = tenths[i] / total * math.pi * 2 * progress;
      if (raw <= 0) {
        continue;
      }
      final gap = tenths.length > 1 && raw > 0.14 ? 0.05 : 0.0;
      final sweep = math.min(math.max(raw - gap, 0.0), math.pi * 2 - 0.001);
      final emphasized = highlighted == null || highlighted == i;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = highlighted == i ? maxStroke : 16
        ..color = emphasized ? colors[i] : colors[i].withValues(alpha: 0.28);
      if (sweep > 0) {
        canvas.drawArc(rect, start + gap / 2, sweep, false, paint);
      }
      start += raw;
    }
  }

  @override
  bool shouldRepaint(covariant _ShareRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.highlighted != highlighted ||
      oldDelegate.trackColor != trackColor ||
      !_sameList(oldDelegate.tenths, tenths) ||
      !_sameList(oldDelegate.colors, colors);
}

/// Cash comparison: bar length follows the largest confirmed balance.
class LedgerCompareBars extends StatefulWidget {
  const LedgerCompareBars({
    super.key,
    required this.slices,
    required this.shareKeyPrefix,
    required this.rankLabel,
  });

  final List<LedgerChartSlice> slices;
  final String shareKeyPrefix;
  final String rankLabel;

  @override
  State<LedgerCompareBars> createState() => _LedgerCompareBarsState();
}

class _LedgerCompareBarsState extends State<LedgerCompareBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final CurvedAnimation _progress;
  String? _selectedId;
  var _started = false;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _progress = CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _entrance.duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 700);
    if (!_started) {
      _started = true;
      _entrance.forward();
    }
  }

  @override
  void didUpdateWidget(covariant LedgerCompareBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _selectedId;
    if (selected != null &&
        widget.slices.every((slice) => slice.id != selected)) {
      _selectedId = null;
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slices.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final amounts = [for (final slice in widget.slices) slice.amount];
    final tenths = ChartShares.tenthsOfPercent(amounts);
    final max = amounts.fold<BigInt>(
      BigInt.zero,
      (largest, amount) => amount > largest ? amount : largest,
    );
    final lead = _leadingSlice(widget.slices);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lead != null && lead.amount > BigInt.zero) ...[
          Text(
            '${widget.rankLabel}: ${lead.label} · ${lead.valueLabel}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
        ],
        for (var index = 0; index < widget.slices.length; index++) ...[
          _BarRow(
            semanticsKey: Key(
              '${widget.shareKeyPrefix}-${widget.slices[index].id}',
            ),
            slice: widget.slices[index],
            share: ChartShares.label(tenths[index]),
            fraction: _barFraction(widget.slices[index].amount, max),
            progress: _progress,
            selected: _selectedId == widget.slices[index].id,
            dimmed:
                _selectedId != null && _selectedId != widget.slices[index].id,
            onTap: () => _toggle(widget.slices[index].id),
          ),
          if (index < widget.slices.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  void _toggle(String id) {
    setState(() => _selectedId = _selectedId == id ? null : id);
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.semanticsKey,
    required this.slice,
    required this.share,
    required this.fraction,
    required this.progress,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  final Key semanticsKey;
  final LedgerChartSlice slice;
  final String share;
  final double fraction;
  final Animation<double> progress;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    final muted = selected
        ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant;
    final barColor = dimmed
        ? scheme.primary.withValues(alpha: 0.35)
        : scheme.primary;
    return Semantics(
      key: semanticsKey,
      button: true,
      selected: selected,
      label: '${slice.label}، ${slice.valueLabel}، $share من الإجمالي',
      child: ExcludeSemantics(
        child: Material(
          type: selected ? MaterialType.canvas : MaterialType.transparency,
          color: selected ? scheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (slice.icon != null) ...[
                          Icon(
                            slice.icon,
                            size: 20,
                            color: selected
                                ? scheme.onPrimaryContainer
                                : scheme.primary,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            slice.label,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(
                                  slice.valueLabel,
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: foreground,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              Text(
                                share,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: muted,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _AnimatedBar(
                      fraction: fraction,
                      progress: progress,
                      color: barColor,
                      trackColor: scheme.surfaceContainerHighest,
                      hasAmount: slice.amount > BigInt.zero,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedBar extends StatelessWidget {
  const _AnimatedBar({
    required this.fraction,
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.hasAmount,
  });

  final double fraction;
  final Animation<double> progress;
  final Color color;
  final Color trackColor;
  final bool hasAmount;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 14,
        width: double.infinity,
        child: ColoredBox(
          color: trackColor,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              final raw = maxWidth * fraction;
              final target = !hasAmount
                  ? 0.0
                  : (raw < 6 ? 6.0 : raw).clamp(0.0, maxWidth).toDouble();
              return ListenableBuilder(
                listenable: progress,
                builder: (context, _) => Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(
                    width: target * progress.value,
                    height: 14,
                    child: ColoredBox(color: color),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

LedgerChartSlice? _leadingSlice(List<LedgerChartSlice> slices) {
  if (slices.isEmpty) return null;
  var lead = slices.first;
  for (final slice in slices.skip(1)) {
    if (slice.amount > lead.amount) lead = slice;
  }
  return lead;
}

double _barFraction(BigInt value, BigInt max) {
  if (max <= BigInt.zero || value <= BigInt.zero) return 0;
  return ((value * BigInt.from(1000)) ~/ max).toInt() / 1000;
}
