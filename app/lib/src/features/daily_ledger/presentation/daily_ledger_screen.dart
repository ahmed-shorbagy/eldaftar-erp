import 'package:flutter/material.dart';

import '../../../shell/shell_copy.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/brand_mark.dart';
import '../../shop_accounts/domain/shop_account.dart';
import '../application/daily_ledger_view.dart';
import '../application/opening_gateway.dart';
import '../application/pending_opening_store.dart';
import '../domain/opening_catalog.dart';
import '../domain/opening_draft.dart';
import '../domain/opening_issue.dart';
import '../domain/postgres_integer.dart';
import '../domain/quantities.dart';
import 'daily_ledger_controller.dart';
import 'opening_copy.dart';

class DailyLedgerScreen extends StatefulWidget {
  const DailyLedgerScreen({
    super.key,
    required this.shop,
    required this.onSignOut,
    required this.onToggleTheme,
    required this.onChangeShop,
    this.onRefreshShops,
    this.gateway,
    this.store,
    this.userId,
    this.refreshGeneration = 0,
    this.newKey,
  });

  final ShopAccount shop;
  final Future<void> Function() onSignOut;
  final Future<void> Function(Brightness) onToggleTheme;
  final VoidCallback onChangeShop;
  final Future<void> Function()? onRefreshShops;
  final OpeningGateway? gateway;
  final PendingOpeningStore? store;
  final String? userId;
  final int refreshGeneration;
  final String Function()? newKey;

  @override
  State<DailyLedgerScreen> createState() => _DailyLedgerScreenState();
}

class _DailyLedgerScreenState extends State<DailyLedgerScreen> {
  DailyLedgerController? _controller;
  final _scroll = ScrollController();

  bool get _expired => widget.shop.entitlement == ShopEntitlement.expired;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    final gateway = widget.gateway;
    final store = widget.store;
    final userId = widget.userId;
    if (gateway == null || store == null || userId == null || userId.isEmpty) {
      return;
    }
    final controller = DailyLedgerController(
      gateway: gateway,
      store: store,
      userId: userId,
      shopId: widget.shop.id,
      shopIsActive: widget.shop.entitlement == ShopEntitlement.active,
      newKey: widget.newKey,
    );
    controller.addListener(_onController);
    _controller = controller;
    controller.start();
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant DailyLedgerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged =
        oldWidget.userId != widget.userId ||
        oldWidget.shop.id != widget.shop.id ||
        oldWidget.gateway != widget.gateway ||
        oldWidget.store != widget.store;
    if (identityChanged) {
      _controller?.removeListener(_onController);
      _controller?.dispose();
      _controller = null;
      _attach();
      return;
    }
    _controller?.updateShopActive(
      widget.shop.entitlement == ShopEntitlement.active,
    );
    if (oldWidget.refreshGeneration != widget.refreshGeneration) {
      _controller?.refresh();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onController);
    _controller?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: BrandLockup(
          title: 'الدفتر اليومي',
          titleKey: const Key('ledger-title'),
          markSize: 22,
          maxLines: 2,
          style: MediaQuery.sizeOf(context).width < 400
              ? theme.textTheme.titleMedium
              : null,
        ),
        actions: [
          IconButton(
            tooltip: 'اختيار متجر آخر',
            onPressed: widget.onChangeShop,
            icon: const Icon(Icons.storefront_outlined),
          ),
          IconButton(
            tooltip: 'تحديث الدفتر',
            onPressed: widget.onRefreshShops ?? _controller?.refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            key: const Key('theme-toggle'),
            tooltip: theme.brightness == Brightness.dark
                ? ShellCopy.toggleToLight
                : ShellCopy.toggleToDark,
            onPressed: () => widget.onToggleTheme(theme.brightness),
            icon: Icon(
              theme.brightness == Brightness.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.contentMaxWidth,
            ),
            child: ListView(
              key: const Key('ledger-scroll'),
              controller: _scroll,
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              children: [
                Text(widget.shop.name, style: theme.textTheme.titleLarge),
                if (_expired || (controller?.readOnly ?? false)) ...[
                  const SizedBox(height: 12),
                  Text(
                    'منتهي - للقراءة فقط',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('الاشتراك منتهٍ. العرض للقراءة فقط.'),
                  const SizedBox(height: 8),
                  const Text(
                    'انتهى اشتراك هذا المتجر. الوصول الحالي للقراءة فقط، ولا يمكن إجراء تغييرات.',
                  ),
                ],
                const SizedBox(height: 16),
                if (controller == null)
                  const SizedBox.shrink()
                else if (controller.phase == LedgerPhase.loading)
                  const LinearProgressIndicator()
                else
                  _LedgerBody(controller: controller, expired: _expired),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LedgerBody extends StatelessWidget {
  const _LedgerBody({required this.controller, required this.expired});

  final DailyLedgerController controller;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = controller.message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message != null) ...[
          Text(
            message,
            key: const Key('ledger-message'),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 12),
        ],
        switch (controller.phase) {
          LedgerPhase.form =>
            controller.readOnly
                ? const Text('لا يوجد رصيد افتتاحي مؤكد لهذا المتجر.')
                : _EntryForm(controller: controller),
          LedgerPhase.review => _Review(
            controller: controller,
            showActions: !controller.readOnly,
          ),
          LedgerPhase.pending => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _PendingNotice(),
              if (controller.reviewDraft != null) ...[
                const SizedBox(height: 12),
                _Review(controller: controller, showActions: false),
              ],
            ],
          ),
          LedgerPhase.confirmed => _ConfirmedLedger(ledger: controller.ledger),
          LedgerPhase.refreshFailed => const _RefreshFailedNotice(),
          LedgerPhase.accessDenied => const SizedBox.shrink(),
          LedgerPhase.expiredEmpty => const Text(
            'لا يوجد رصيد افتتاحي مؤكد لهذا المتجر.',
          ),
          LedgerPhase.failed => const SizedBox.shrink(),
          LedgerPhase.loading => const SizedBox.shrink(),
        },
      ],
    );
  }
}

class _EntryForm extends StatelessWidget {
  const _EntryForm({required this.controller});

  final DailyLedgerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'لم يتم تأكيد الأرصدة الافتتاحية',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        for (final method in CashMethod.canonicalOrder) ...[
          _AmountField(
            label: cashMethodLabel(method),
            controller: controller.cash[method]!,
            fieldKey: Key('cash-${method.code}'),
            locked: controller.fieldsLocked,
          ),
          const SizedBox(height: 12),
        ],
        Text('المخزون', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var index = 0; index < controller.stock.length; index++) ...[
          _StockRow(
            entry: controller.stock[index],
            index: index,
            controller: controller,
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton(
          key: const Key('add-stock'),
          onPressed: controller.fieldsLocked ? null : controller.addStock,
          child: const Text('إضافة صنف'),
        ),
        const SizedBox(height: 16),
        Text('الكسر', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var index = 0; index < controller.scrap.length; index++) ...[
          _ScrapRow(
            entry: controller.scrap[index],
            index: index,
            controller: controller,
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton(
          key: const Key('add-scrap'),
          onPressed: controller.fieldsLocked ? null : controller.addScrap,
          child: const Text('إضافة كسر'),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('review-values'),
          onPressed: controller.fieldsLocked ? null : controller.reviewEntered,
          child: const Text('مراجعة الأرصدة'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('review-zero'),
          onPressed: controller.fieldsLocked ? null : controller.reviewZeros,
          child: const Text('تأكيد أرصدة صفرية'),
        ),
      ],
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.label,
    required this.controller,
    required this.fieldKey,
    required this.locked,
  });

  final String label;
  final TextEditingController controller;
  final Key fieldKey;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      readOnly: locked,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(
        labelText: label,
        helperText: 'بالجنيه',
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow({
    required this.entry,
    required this.index,
    required this.controller,
  });

  final StockEntry entry;
  final int index;
  final DailyLedgerController controller;

  @override
  Widget build(BuildContext context) {
    final karats = entry.category.karats.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<StockCategory>(
          key: Key('stock-category-$index'),
          initialValue: entry.category,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'الصنف',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final category in openingCategoryChoices)
              DropdownMenuItem(
                value: category,
                child: Text(stockCategoryLabel(category)),
              ),
          ],
          onChanged: controller.fieldsLocked
              ? null
              : (value) {
                  if (value != null) controller.setStockCategory(entry, value);
                },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          key: ValueKey(
            'stock-karat-$index-${entry.category.code}-${entry.karat}',
          ),
          initialValue: entry.karat,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'العيار',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final karat in karats)
              DropdownMenuItem(value: karat, child: Text('$karat')),
          ],
          onChanged: controller.fieldsLocked
              ? null
              : (value) {
                  if (value != null) controller.setStockKarat(entry, value);
                },
        ),
        const SizedBox(height: 8),
        TextField(
          key: Key('stock-grams-$index'),
          controller: entry.grams,
          readOnly: controller.fieldsLocked,
          textDirection: TextDirection.ltr,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'الوزن بالجرام',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: Key('stock-count-$index'),
          controller: entry.count,
          readOnly: controller.fieldsLocked,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'العدد',
            border: OutlineInputBorder(),
          ),
        ),
        if (controller.stock.length > 1)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: controller.fieldsLocked
                  ? null
                  : () => controller.removeStock(entry),
              child: const Text('حذف الصف'),
            ),
          ),
      ],
    );
  }
}

class _ScrapRow extends StatelessWidget {
  const _ScrapRow({
    required this.entry,
    required this.index,
    required this.controller,
  });

  final ScrapEntry entry;
  final int index;
  final DailyLedgerController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<int>(
          key: Key('scrap-karat-$index'),
          initialValue: entry.karat,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'عيار الكسر',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final karat in scrapKaratChoices)
              DropdownMenuItem(value: karat, child: Text('$karat')),
          ],
          onChanged: controller.fieldsLocked
              ? null
              : (value) {
                  if (value != null) controller.setScrapKarat(entry, value);
                },
        ),
        const SizedBox(height: 8),
        TextField(
          key: Key('scrap-grams-$index'),
          controller: entry.grams,
          readOnly: controller.fieldsLocked,
          textDirection: TextDirection.ltr,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'وزن الكسر بالجرام',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.controller, required this.showActions});

  final DailyLedgerController controller;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = controller.reviewDraft;
    if (draft == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('مراجعة الأرصدة الافتتاحية', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'يؤكد هذا الإجراء الأرصدة الافتتاحية مرة واحدة، ولا يُعاد تأكيده.',
        ),
        const SizedBox(height: 12),
        Text('النقد بالجنيه', style: theme.textTheme.titleSmall),
        for (final method in CashMethod.canonicalOrder)
          _ReviewLine(
            label: cashMethodLabel(method),
            amount: draft.cash[method].poundsText,
          ),
        if (_totalCash(draft) case final total?)
          _ReviewLine(label: 'إجمالي النقد', amount: '$total جنيه'),
        if (draft.stock.isNotEmpty)
          Text('المخزون', style: theme.textTheme.titleSmall),
        for (final row in draft.stock) ...[
          _ReviewLine(
            label: '${stockCategoryLabel(row.category)} عيار ${row.karat}',
            amount: '${row.milligrams.gramsText} جرام',
          ),
          _ReviewLine(label: 'العدد', amount: row.count.wire),
        ],
        if (draft.scrap.isNotEmpty)
          Text('الكسر', style: theme.textTheme.titleSmall),
        for (final row in draft.scrap)
          _ReviewLine(
            label: 'كسر عيار ${row.karat}',
            amount: '${row.milligrams.gramsText} جرام',
          ),
        if (showActions) ...[
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('confirm-opening'),
            onPressed: controller.fieldsLocked
                ? null
                : controller.confirmReview,
            child: const Text('تأكيد الأرصدة الافتتاحية'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('back-to-edit'),
            onPressed: controller.fieldsLocked ? null : controller.backToEdit,
            child: const Text('رجوع للتعديل'),
          ),
        ],
      ],
    );
  }
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine({required this.label, required this.amount});

  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label)),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(amount, textAlign: TextAlign.end),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingNotice extends StatelessWidget {
  const _PendingNotice();

  @override
  Widget build(BuildContext context) {
    return const Text('بانتظار تأكيد الخادم', key: Key('opening-pending'));
  }
}

class _RefreshFailedNotice extends StatelessWidget {
  const _RefreshFailedNotice();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('تم تأكيد الأرصدة الافتتاحية'),
        SizedBox(height: 8),
        Text('تعذر تحديث الدفتر بعد التأكيد.'),
      ],
    );
  }
}

class _ConfirmedLedger extends StatelessWidget {
  const _ConfirmedLedger({required this.ledger});

  final DailyLedgerView? ledger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final view = ledger;
    if (view == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('تم تأكيد الأرصدة الافتتاحية', style: theme.textTheme.titleMedium),
        if (view.businessDay != null) ...[
          const SizedBox(height: 8),
          Text('يوم العمل ${formatServerDate(view.businessDay!.businessDate)}'),
        ],
        const SizedBox(height: 12),
        Text('النقد بالجنيه', style: theme.textTheme.titleSmall),
        for (final line in view.cash)
          _ReviewLine(label: line.labelAr, amount: line.pounds),
        if (view.totalCashPounds case final total?)
          _ReviewLine(label: 'إجمالي النقد', amount: '$total جنيه'),
        if (view.stock.isNotEmpty)
          Text('المخزون', style: theme.textTheme.titleSmall),
        for (final line in view.stock) ...[
          _ReviewLine(
            label: '${line.labelAr} عيار ${line.karat}',
            amount: '${line.grams} جرام',
          ),
          _ReviewLine(label: 'العدد', amount: line.count),
        ],
        if (view.scrap.isNotEmpty)
          Text('الكسر', style: theme.textTheme.titleSmall),
        for (final line in view.scrap)
          _ReviewLine(
            label: '${line.labelAr} عيار ${line.karat}',
            amount: '${line.grams} جرام',
          ),
        const SizedBox(height: 16),
        for (final line in view.feed) ...[
          Text(line.labelAr, style: theme.textTheme.titleMedium),
          Text(line.actorDisplayName),
          Text(formatServerCairoTimestamp(line.occurredAtCairo)),
        ],
      ],
    );
  }
}

String? _totalCash(OpeningDraft draft) {
  final sum = PostgresInteger.checkedSum([
    for (final method in CashMethod.canonicalOrder) draft.cash[method].value,
  ]);
  if (sum == null) return null;
  final parsed = Piastres.parseWire(sum.toString());
  if (parsed is! Accepted<Piastres>) return null;
  return parsed.value.poundsText;
}
