import 'package:flutter/material.dart';

import '../features/daily_ledger/application/financial_gateway.dart';
import '../features/daily_ledger/application/opening_gateway.dart';
import '../features/daily_ledger/application/pending_opening_store.dart';
import '../features/daily_ledger/domain/financial_draft.dart';
import '../features/daily_ledger/presentation/daily_ledger_screen.dart';
import '../features/daily_ledger/presentation/financial_trade_screen.dart';
import '../features/onboarding/application/onboarding_store.dart';
import '../features/shop_accounts/domain/shop_account.dart';
import '../theme/app_tokens.dart';

/// Keeps the ledger as the initial workspace and exposes all Arabic destinations.
class ShopWorkspace extends StatefulWidget {
  const ShopWorkspace({
    super.key,
    required this.shop,
    required this.onSignOut,
    required this.onToggleTheme,
    required this.onChangeShop,
    this.gateway,
    this.store,
    this.userId,
    this.refreshGeneration = 0,
    this.onRefreshShops,
    this.onboardingStore,
    this.inventoryBuilder,
    this.traderBuilder,
  });

  final ShopAccount shop;
  final Future<void> Function() onSignOut;
  final Future<void> Function(Brightness) onToggleTheme;
  final VoidCallback onChangeShop;
  final OpeningGateway? gateway;
  final PendingOpeningStore? store;
  final String? userId;
  final int refreshGeneration;
  final Future<void> Function()? onRefreshShops;
  final OnboardingStore? onboardingStore;
  final WidgetBuilder? inventoryBuilder;
  final WidgetBuilder? traderBuilder;

  @override
  State<ShopWorkspace> createState() => _ShopWorkspaceState();
}

class _ShopWorkspaceState extends State<ShopWorkspace> {
  int _destination = 1;
  int _guideGeneration = 0;
  static const _labels = [
    'الرئيسية',
    'الدفتر اليومي',
    'المخزون',
    'العملاء',
    'التقارير',
    'المزيد',
  ];
  static const _icons = [
    Icons.home_outlined,
    Icons.menu_book_outlined,
    Icons.inventory_2_outlined,
    Icons.people_outline,
    Icons.assessment_outlined,
    Icons.more_horiz,
  ];

  void _select(int index) => setState(() => _destination = index);

  Future<void> _practiceSale() async {
    final gateway = widget.gateway;
    final userId = widget.userId;
    if (gateway == null || gateway is! FinancialGateway || userId == null) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FinancialTradeScreen(
          kind: FinancialKind.sale,
          gateway: gateway as FinancialGateway,
          statusGateway: gateway,
          userId: userId,
          shopId: widget.shop.id,
          practice: true,
          onboardingStore: widget.onboardingStore,
        ),
      ),
    );
  }

  void _resumeLedger() {
    setState(() {
      _destination = 1;
      _guideGeneration++;
    });
  }

  Widget _page(String title, List<Widget> children) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTokens.contentMaxWidth,
          ),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: children,
          ),
        ),
      ),
    ),
  );

  Widget _link(String label, IconData icon, VoidCallback onTap, {Key? key}) =>
      Card(
        child: ListTile(
          key: key,
          minVerticalPadding: 16,
          leading: ExcludeSemantics(child: Icon(icon)),
          title: Text(label),
          trailing: const ExcludeSemantics(child: Icon(Icons.chevron_right)),
          onTap: onTap,
        ),
      );

  Widget _help() => _page('المساعدة والإرشاد', [
    const Text('تابع من موضعك السابق أو جرّب أدوات البيع في مسودة آمنة.'),
    const SizedBox(height: 16),
    _link('استئناف إرشاد الدفتر', Icons.menu_book_outlined, () {
      Navigator.pop(context);
      _resumeLedger();
    }),
    if (widget.gateway is FinancialGateway && widget.userId != null)
      _link(
        'تدريب على أول بيع — دون حفظ',
        Icons.school_outlined,
        _practiceSale,
        key: const Key('help-practice-sale'),
      ),
    if (widget.inventoryBuilder != null)
      _link('إرشاد المخزون', Icons.inventory_2_outlined, () {
        Navigator.pop(context);
        _select(2);
      }),
    if (widget.traderBuilder != null)
      _link('إرشاد التجار والأمانات', Icons.storefront_outlined, () {
        Navigator.pop(context);
        _openTraders();
      }),
  ]);

  void _openHelp() => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => _help()));

  void _openTraders() {
    final builder = widget.traderBuilder;
    if (builder != null) {
      Navigator.of(context).push<void>(MaterialPageRoute(builder: builder));
    }
  }

  Widget _body() => switch (_destination) {
    0 => _page('الرئيسية', [
      Text(widget.shop.name, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text(
        'ابدأ يومك من الدفتر وتابع الأرصدة المؤكدة قبل تسجيل حركة جديدة.',
      ),
      const SizedBox(height: 16),
      _link('فتح الدفتر اليومي', Icons.menu_book_outlined, () => _select(1)),
      if (widget.inventoryBuilder != null)
        _link('عرض المخزون', Icons.inventory_2_outlined, () => _select(2)),
      if (widget.traderBuilder != null)
        _link('التجار والأمانات', Icons.storefront_outlined, _openTraders),
      _link('المساعدة والإرشاد', Icons.help_outline, _openHelp),
    ]),
    1 => DailyLedgerScreen(
      shop: widget.shop,
      gateway: widget.gateway,
      store: widget.store,
      userId: widget.userId,
      refreshGeneration: widget.refreshGeneration,
      guideResumeGeneration: _guideGeneration,
      onSignOut: widget.onSignOut,
      onToggleTheme: widget.onToggleTheme,
      onChangeShop: widget.onChangeShop,
      onRefreshShops: widget.onRefreshShops,
      onboardingStore: widget.onboardingStore,
    ),
    2 =>
      widget.inventoryBuilder?.call(context) ??
          _page('المخزون', [
            const Text(
              'واجهة المخزون غير متاحة في هذا الاتصال. افتح الدفتر لمراجعة الأرصدة المؤكدة.',
            ),
            _link(
              'فتح الدفتر اليومي',
              Icons.menu_book_outlined,
              () => _select(1),
            ),
          ]),
    3 => _page('العملاء', [
      const Text(
        'إدارة ملفات العملاء ضمن المرحلة الرابعة. بيانات طرف العملية متاحة في تفاصيل العملية المؤكدة داخل الدفتر.',
      ),
      _link('فتح العمليات المؤكدة', Icons.menu_book_outlined, () => _select(1)),
    ]),
    4 => _page('التقارير', [
      const Text(
        'التقارير الدورية ضمن المرحلة الخامسة. يمكنك الآن قراءة الدفتر وتصدير نسخة عربية من العملية المؤكدة.',
      ),
      _link('فتح الدفتر اليومي', Icons.menu_book_outlined, () => _select(1)),
    ]),
    _ => _page('المزيد', [
      if (widget.traderBuilder != null)
        _link('التجار والأمانات', Icons.storefront_outlined, _openTraders),
      _link('التقارير', Icons.assessment_outlined, () => _select(4)),
      _link(
        'المساعدة والإرشاد',
        Icons.help_outline,
        _openHelp,
        key: const Key('workspace-help'),
      ),
      _link(
        Theme.of(context).brightness == Brightness.dark
            ? 'المظهر الفاتح'
            : 'المظهر الداكن',
        Icons.brightness_6_outlined,
        () => widget.onToggleTheme(Theme.of(context).brightness),
      ),
      _link(
        'العودة إلى حساب المتجر',
        Icons.storefront_outlined,
        widget.onChangeShop,
      ),
      _link('تسجيل الخروج', Icons.logout, widget.onSignOut),
    ]),
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      if (size.maxWidth >= AppTokens.wideBreakpoint) {
        return Scaffold(
          body: Row(
            children: [
              SafeArea(
                child: NavigationRail(
                  extended: true,
                  minExtendedWidth: 176,
                  selectedIndex: _destination,
                  onDestinationSelected: _select,
                  destinations: [
                    for (var i = 0; i < _labels.length; i++)
                      NavigationRailDestination(
                        icon: Icon(_icons[i]),
                        label: Text(_labels[i]),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _body()),
            ],
          ),
        );
      }
      const indices = [0, 1, 2, 3, 5];
      return Scaffold(
        body: _body(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _destination == 4 ? 4 : indices.indexOf(_destination),
          onDestinationSelected: (index) => _select(indices[index]),
          destinations: [
            for (final index in indices)
              NavigationDestination(
                key: Key('workspace-nav-$index'),
                icon: Icon(_icons[index]),
                label: index == 1 ? 'الدفتر' : _labels[index],
                tooltip: 'فتح ${_labels[index]}',
              ),
          ],
        ),
      );
    },
  );
}
