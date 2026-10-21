import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../application/idempotency_key.dart';
import '../domain/opening_catalog.dart';
import 'ledger_form_fields.dart';

/// A selectable trade item name and its stock category.
final class TradeItemChoice {
  const TradeItemChoice(this.label, this.category, {this.icon});
  final String label;
  final String category;
  final Widget? icon;
}

/// Current «أخرى» names: Egypt-market built-ins followed by shop products.
final class TradeOtherCatalog {
  const TradeOtherCatalog({
    required this.choices,
    this.loading = false,
    this.failed = false,
    this.hasMore = false,
  });
  final List<TradeItemChoice> choices;
  final bool loading;
  final bool failed;
  final bool hasMore;
}

sealed class TradeCreateOutcome {
  const TradeCreateOutcome();
}

final class TradeCreated extends TradeCreateOutcome {
  const TradeCreated(this.choice);
  final TradeItemChoice choice;
}

/// [retryable] keeps the same idempotency key and payload for the next try.
final class TradeCreateFailed extends TradeCreateOutcome {
  const TradeCreateFailed(this.message, {this.retryable = false});
  final String message;
  final bool retryable;
}

typedef TradeCreateItem =
    Future<TradeCreateOutcome> Function(String name, int karat, String key);

/// Opens the item picker: a bottom sheet on phones, a dialog on wide screens.
/// With [createOnly], it opens directly on the new-item form.
Future<TradeItemChoice?> showTradeItemPicker(
  BuildContext context, {
  required String title,
  required List<TradeItemChoice> mainChoices,
  required ValueListenable<TradeOtherCatalog> others,
  required Set<String> reservedNames,
  VoidCallback? onRetry,
  VoidCallback? onMore,
  TradeCreateItem? onCreate,
  bool createOnly = false,
}) {
  final body = TradeItemPicker(
    title: title,
    mainChoices: mainChoices,
    others: others,
    reservedNames: reservedNames,
    onRetry: onRetry,
    onMore: onMore,
    onCreate: onCreate,
    createOnly: createOnly,
  );
  final size = MediaQuery.sizeOf(context);
  if (size.width >= AppTokens.wideBreakpoint) {
    return showDialog<TradeItemChoice>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: AppTokens.contentMaxWidth,
            maxHeight: size.height * .84,
          ),
          child: body,
        ),
      ),
    );
  }
  return showModalBottomSheet<TradeItemChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: BoxConstraints(
      maxWidth: AppTokens.contentMaxWidth,
      maxHeight: size.height * .88,
    ),
    builder: (_) => body,
  );
}

class TradeItemPicker extends StatefulWidget {
  const TradeItemPicker({
    super.key,
    required this.title,
    required this.mainChoices,
    required this.others,
    required this.reservedNames,
    this.onRetry,
    this.onMore,
    this.onCreate,
    this.createOnly = false,
  });

  final String title;
  final List<TradeItemChoice> mainChoices;
  final ValueListenable<TradeOtherCatalog> others;
  final Set<String> reservedNames;
  final VoidCallback? onRetry;
  final VoidCallback? onMore;
  final TradeCreateItem? onCreate;
  final bool createOnly;

  @override
  State<TradeItemPicker> createState() => _TradeItemPickerState();
}

class _TradeItemPickerState extends State<TradeItemPicker> {
  static const _searchThreshold = 9;

  final _search = TextEditingController();
  final _name = TextEditingController();
  late bool _creating = widget.createOnly;
  int _karat = 21;
  bool _busy = false;
  bool _frozen = false;
  String? _key;
  String? _message;

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    super.dispose();
  }

  void _pick(TradeItemChoice choice) => Navigator.of(context).pop(choice);

  void _openCreate() => setState(() {
    _creating = true;
    _name.text = _search.text.trim();
    _message = null;
  });

  void _backToList() {
    if (_busy) return;
    setState(() {
      _creating = false;
      _message = null;
      if (!_frozen) _key = null;
    });
  }

  TradeItemChoice? _existing(String name) {
    for (final choice in widget.others.value.choices) {
      if (choice.label == name) return choice;
    }
    return null;
  }

  Future<void> _save() async {
    final create = widget.onCreate;
    final name = _name.text.trim();
    if (create == null || _busy || name.isEmpty) return;
    if (widget.reservedNames.contains(name) || _existing(name) != null) return;
    final key = _key ??= newIdempotencyKey();
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome = await create(name, _karat, key);
    if (!mounted) return;
    switch (outcome) {
      case TradeCreated(:final choice):
        Navigator.of(context).pop(choice);
      case TradeCreateFailed(:final message, :final retryable):
        setState(() {
          _busy = false;
          _frozen = retryable;
          if (!retryable) _key = null;
          _message = message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            const Divider(height: 1),
            Flexible(
              child: _creating ? _createBody(context) : _listBody(context),
            ),
            if (_creating) _createFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final back = _creating && !widget.createOnly;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(back ? 4 : 20, 8, 8, 8),
      child: Row(
        children: [
          if (back)
            IconButton(
              key: const Key('trade-picker-back'),
              tooltip: 'رجوع إلى الأصناف',
              onPressed: _busy ? null : _backToList,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          Expanded(
            child: Text(
              _creating ? 'صنف جديد في «أخرى»' : widget.title,
              style: theme.textTheme.titleLarge,
            ),
          ),
          IconButton(
            key: const Key('trade-picker-close'),
            tooltip: 'إغلاق',
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _listBody(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<TradeOtherCatalog>(
      valueListenable: widget.others,
      builder: (context, catalog, _) {
        final query = _search.text.trim();
        final visible = query.isEmpty
            ? catalog.choices
            : [
                for (final choice in catalog.choices)
                  if (choice.label.contains(query)) choice,
              ];
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            AppTokens.spaceMd,
            AppTokens.spaceMd,
            AppTokens.spaceMd,
            AppTokens.spaceLg,
          ),
          children: [
            if (widget.mainChoices.isNotEmpty) ...[
              _SectionLabel('الأصناف الرئيسية'),
              const SizedBox(height: AppTokens.spaceSm),
              TradeChoiceGrid(
                compactColumns: 3,
                columns: 4,
                children: [
                  for (final choice in widget.mainChoices)
                    TradeChoiceTile(
                      key: Key('trade-new-category-${choice.label}'),
                      label: choice.label,
                      icon: choice.icon,
                      onTap: () => _pick(choice),
                    ),
                ],
              ),
              const SizedBox(height: AppTokens.spaceLg),
            ],
            _SectionLabel(
              'أصناف أخرى',
              trailing: catalog.loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            const SizedBox(height: AppTokens.spaceSm),
            if (catalog.choices.length >= _searchThreshold) ...[
              TextField(
                key: const Key('trade-picker-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: ledgerFieldDecoration(
                  context,
                  label: 'ابحث في الأصناف',
                ).copyWith(prefixIcon: const Icon(Icons.search_rounded)),
              ),
              const SizedBox(height: AppTokens.spaceSm + 4),
            ],
            TradeChoiceGrid(
              children: [
                for (final choice in visible)
                  TradeChoiceTile(
                    key: Key('trade-new-category-${choice.label}'),
                    label: choice.label,
                    onTap: () => _pick(choice),
                  ),
                if (widget.onCreate != null)
                  TradeAddTile(
                    key: const Key('trade-picker-create'),
                    label: query.isEmpty ? 'صنف جديد' : 'إضافة «$query»',
                    onTap: _openCreate,
                  ),
              ],
            ),
            if (query.isNotEmpty && visible.isEmpty) ...[
              const SizedBox(height: AppTokens.spaceSm),
              Text('لا يوجد صنف بهذا الاسم.', style: theme.textTheme.bodySmall),
            ],
            if (catalog.failed && widget.onRetry != null)
              Padding(
                padding: const EdgeInsets.only(top: AppTokens.spaceSm),
                child: _InlineNotice(
                  message: 'تعذر تحميل أصناف المتجر.',
                  error: true,
                  action: TextButton(
                    onPressed: catalog.loading ? null : widget.onRetry,
                    child: const Text('إعادة المحاولة'),
                  ),
                ),
              ),
            if (catalog.hasMore && widget.onMore != null)
              Padding(
                padding: const EdgeInsets.only(top: AppTokens.spaceSm),
                child: TextButton.icon(
                  key: const Key('trade-picker-more'),
                  onPressed: catalog.loading ? null : widget.onMore,
                  icon: const Icon(Icons.expand_more_rounded),
                  label: const Text('عرض المزيد من أصناف المتجر'),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _createBody(BuildContext context) {
    final theme = Theme.of(context);
    final name = _name.text.trim();
    final reserved = widget.reservedNames.contains(name);
    final existing = reserved ? null : _existing(name);
    final karats = StockCategory.workedJewelry.karats.toList()..sort();
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceMd,
        AppTokens.spaceMd,
        AppTokens.spaceMd,
        AppTokens.spaceMd,
      ),
      children: [
        Text(
          'يُحفظ الاسم في أصناف المتجر ويظهر مع الأصناف الأخرى في كل بيع وشراء. '
          'الحفظ لا يضيف وزناً ولا نقداً.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        TextField(
          key: const Key('trade-other-product-name'),
          controller: _name,
          autofocus: !_frozen,
          enabled: !_busy && !_frozen,
          maxLength: 120,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _message = null),
          onSubmitted: (_) => _save(),
          decoration:
              ledgerFieldDecoration(
                context,
                label: 'اسم الصنف',
                helper: 'مثال: بروش، كوليه، محبس',
              ).copyWith(
                counterText: '',
                errorText: reserved
                    ? 'هذا صنف رئيسي. اختره من الأصناف الرئيسية.'
                    : null,
              ),
        ),
        if (existing != null) ...[
          const SizedBox(height: AppTokens.spaceSm),
          _InlineNotice(
            key: const Key('trade-other-product-exists'),
            message: '«${existing.label}» موجود بالفعل في أصناف المتجر.',
            action: TextButton(
              key: const Key('trade-other-product-use-existing'),
              onPressed: _busy ? null : () => _pick(existing),
              child: const Text('اختياره'),
            ),
          ),
        ],
        const SizedBox(height: AppTokens.spaceMd),
        Text('العيار', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppTokens.spaceSm),
        SegmentedButton<int>(
          key: const Key('trade-other-product-karat'),
          showSelectedIcon: false,
          segments: [
            for (final karat in karats)
              ButtonSegment(
                value: karat,
                label: Text('$karat', key: Key('trade-other-karat-$karat')),
              ),
          ],
          selected: {_karat},
          onSelectionChanged: _busy || _frozen
              ? null
              : (value) => setState(() => _karat = value.first),
        ),
        if (_message != null) ...[
          const SizedBox(height: AppTokens.spaceMd),
          _InlineNotice(
            key: const Key('trade-other-product-status'),
            message: _message!,
            error: true,
          ),
        ],
      ],
    );
  }

  Widget _createFooter(BuildContext context) {
    final name = _name.text.trim();
    final blocked =
        name.isEmpty ||
        widget.reservedNames.contains(name) ||
        _existing(name) != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.spaceMd,
          AppTokens.spaceSm,
          AppTokens.spaceMd,
          AppTokens.spaceMd,
        ),
        child: FilledButton(
          key: const Key('trade-other-product-save'),
          onPressed: _busy || blocked ? null : _save,
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_frozen ? 'إعادة المحاولة' : 'حفظ واختيار الصنف'),
        ),
      ),
    );
  }
}

/// Responsive equal-width tile grid used across trade item selection.
class TradeChoiceGrid extends StatelessWidget {
  const TradeChoiceGrid({
    super.key,
    required this.children,
    this.columns = 3,
    this.compactColumns = 2,
  });

  final List<Widget> children;
  final int columns;
  final int compactColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, size) {
        final scaled = MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final count = size.maxWidth < 360 || scaled ? compactColumns : columns;
        const gap = AppTokens.spaceSm;
        final width = (size.maxWidth - gap * (count - 1)) / count;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class TradeChoiceTile extends StatelessWidget {
  const TradeChoiceTile({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
  });

  final String label;
  final Widget? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = selected
        ? BorderSide(color: scheme.primary, width: 1.6)
        : BorderSide(color: scheme.outline);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.fieldRadius),
          side: border,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: icon == null ? 52 : 84),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      IconTheme.merge(
                        data: IconThemeData(color: scheme.primary, size: 26),
                        child: icon!,
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurface,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
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

/// Distinct «add» tile that sits at the end of a choice grid.
class TradeAddTile extends StatelessWidget {
  const TradeAddTile({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final color = enabled
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: .38);
    return Semantics(
      button: true,
      child: Material(
        color: scheme.primary.withValues(alpha: .06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.fieldRadius),
          side: BorderSide(color: color.withValues(alpha: .7)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, size: 20, color: color),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width action under the item cards that starts the next item.
class TradeAddItemButton extends StatelessWidget {
  const TradeAddItemButton({
    super.key,
    required this.itemCount,
    required this.onPressed,
    this.scrap = false,
  });

  final int itemCount;
  final bool scrap;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      label: 'إضافة صنف آخر',
      excludeSemantics: true,
      child: Material(
        color: scheme.primary.withValues(alpha: .05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.fieldRadius),
          side: BorderSide(
            color: AppTokens.goldFrameFor(
              theme.brightness,
            ).withValues(alpha: enabled ? 1 : .4),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMd,
              vertical: 12,
            ),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(
                    dimension: 36,
                    child: Icon(
                      Icons.add_rounded,
                      color: enabled
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: .38),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إضافة صنف آخر',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: enabled ? scheme.primary : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        scrap
                            ? 'سطر كسر جديد بوزنه وعياره'
                            : '${_itemCountText(itemCount)} في العملية · اختر نوع القطعة التالية',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_left_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _itemCountText(int count) => switch (count) {
  1 => 'صنف واحد',
  2 => 'صنفان',
  >= 3 && <= 10 => '$count أصناف',
  _ => '$count صنفاً',
};

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    super.key,
    required this.message,
    this.error = false,
    this.action,
  });

  final String message;
  final bool error;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = error ? scheme.onErrorContainer : scheme.onSurface;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: error ? scheme.errorContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTokens.fieldRadius),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
          child: Row(
            children: [
              Icon(
                error
                    ? Icons.error_outline_rounded
                    : Icons.info_outline_rounded,
                size: 20,
                color: foreground,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: foreground),
                ),
              ),
              ?action,
            ],
          ),
        ),
      ),
    );
  }
}
