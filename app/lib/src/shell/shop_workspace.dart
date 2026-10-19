import 'package:flutter/material.dart';

import '../features/daily_ledger/application/opening_gateway.dart';
import '../features/daily_ledger/application/pending_opening_store.dart';
import '../features/daily_ledger/presentation/daily_ledger_screen.dart';
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
    this.onChangeShop,
    this.gateway,
    this.store,
    this.userId,
    this.refreshGeneration = 0,
    this.onActivateSubscription,
    this.onboardingStore,
    this.inventoryBuilder,
    this.traderBuilder,
    this.repairBuilder,
    this.debtBuilder,
    this.customerBuilder,
    this.appearanceBuilder,
    this.messageBuilder,
    this.syncTicks,
  });

  final ShopAccount shop;
  final Future<void> Function() onSignOut;
  final Future<void> Function(Brightness) onToggleTheme;
  final VoidCallback? onChangeShop;
  final OpeningGateway? gateway;
  final PendingOpeningStore? store;
  final String? userId;
  final int refreshGeneration;
  final Future<void> Function()? onActivateSubscription;
  final OnboardingStore? onboardingStore;
  final WidgetBuilder? inventoryBuilder;
  final WidgetBuilder? traderBuilder;
  final WidgetBuilder? repairBuilder;
  final WidgetBuilder? debtBuilder;
  final WidgetBuilder? customerBuilder;
  final WidgetBuilder? appearanceBuilder;
  final WidgetBuilder? messageBuilder;
  final Listenable? syncTicks;

  @override
  State<ShopWorkspace> createState() => _ShopWorkspaceState();
}

class _ShopWorkspaceState extends State<ShopWorkspace> {
  int _destination = 0;
  Route<void>? _repairRoute;
  Route<void>? _debtRoute;
  Route<void>? _appearanceRoute;
  Route<void>? _messageRoute;

  @override
  void dispose() {
    _detach(_repairRoute);
    _detach(_debtRoute);
    _detach(_appearanceRoute);
    _detach(_messageRoute);
    super.dispose();
  }

  void _detach(Route<void>? route) {
    final navigator = route?.navigator;
    if (route == null || navigator == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted && route.isActive) navigator.removeRoute(route);
    });
  }

  static const _labels = [
    'الدفتر اليومي',
    'المخزون',
    'العملاء',
    'التقارير',
    'المزيد',
  ];
  static const _icons = [
    Icons.menu_book_outlined,
    Icons.inventory_2_outlined,
    Icons.people_outline,
    Icons.assessment_outlined,
    Icons.more_horiz,
  ];

  void _select(int index) => setState(() => _destination = index);

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

  void _openTraders() {
    final builder = widget.traderBuilder;
    if (builder != null) {
      Navigator.of(context).push<void>(MaterialPageRoute(builder: builder));
    }
  }

  Future<void> _openRepairs() => _pushSingleton(
    widget.repairBuilder,
    () => _repairRoute,
    (route) => _repairRoute = route,
  );

  Future<void> _openDebts() => _pushSingleton(
    widget.debtBuilder,
    () => _debtRoute,
    (route) => _debtRoute = route,
  );

  Future<void> _openAppearance() => _pushSingleton(
    widget.appearanceBuilder,
    () => _appearanceRoute,
    (route) => _appearanceRoute = route,
  );

  Future<void> _openMessage() => _pushSingleton(
    widget.messageBuilder,
    () => _messageRoute,
    (route) => _messageRoute = route,
  );

  Future<void> _pushSingleton(
    WidgetBuilder? builder,
    Route<void>? Function() current,
    void Function(Route<void>?) assign,
  ) async {
    if (builder == null || current() != null) return;
    final route = MaterialPageRoute<void>(builder: builder);
    assign(route);
    try {
      await Navigator.of(context).push<void>(route);
    } finally {
      if (identical(current(), route)) assign(null);
    }
  }

  Widget _body() => switch (_destination) {
    0 => DailyLedgerScreen(
      shop: widget.shop,
      gateway: widget.gateway,
      store: widget.store,
      userId: widget.userId,
      refreshGeneration: widget.refreshGeneration,
      syncTicks: widget.syncTicks,
      onToggleTheme: widget.onToggleTheme,
      onChangeShop: widget.onChangeShop,
      onActivateSubscription: widget.onActivateSubscription,
      onboardingStore: widget.onboardingStore,
      inventoryPage: widget.inventoryBuilder,
      onOpenRepairs: _openRepairs,
      onOpenDebts: _openDebts,
      onOpenInvoiceAppearance: _openAppearance,
      onOpenInvoiceMessage: _openMessage,
      onOpenCustomers: () async {
        _select(2);
      },
    ),
    1 =>
      widget.inventoryBuilder?.call(context) ??
          _page('المخزون', [
            const Text(
              'واجهة المخزون غير متاحة في هذا الاتصال. افتح الدفتر لمراجعة الأرصدة المؤكدة.',
            ),
            _link(
              'فتح الدفتر اليومي',
              Icons.menu_book_outlined,
              () => _select(0),
            ),
          ]),
    2 =>
      widget.customerBuilder?.call(context) ??
          _page('العملاء', [
            const Text(
              'ملفات العملاء غير متاحة في هذا الاتصال. بيانات طرف العملية متاحة في تفاصيل العملية المؤكدة داخل الدفتر.',
            ),
            _link(
              'فتح العمليات المؤكدة',
              Icons.menu_book_outlined,
              () => _select(0),
            ),
          ]),
    3 => _page('التقارير', [
      const Text(
        'التقارير الدورية ضمن المرحلة الخامسة. يمكنك الآن قراءة الدفتر وتصدير نسخة عربية من العملية المؤكدة.',
      ),
      _link('فتح الدفتر اليومي', Icons.menu_book_outlined, () => _select(0)),
    ]),
    _ => _page('المزيد', [
      if (widget.traderBuilder != null)
        _link('التجار والأمانات', Icons.storefront_outlined, _openTraders),
      if (widget.repairBuilder != null)
        _link(
          'الصيانة',
          Icons.handyman_outlined,
          _openRepairs,
          key: const Key('workspace-repairs'),
        )
      else
        const ListTile(
          key: Key('workspace-repairs-unavailable'),
          enabled: false,
          title: Text('الصيانة'),
          subtitle: Text('الصيانة غير متاحة في هذا الاتصال.'),
          leading: ExcludeSemantics(child: Icon(Icons.handyman_outlined)),
        ),
      if (widget.debtBuilder != null)
        _link(
          'الديون',
          Icons.account_balance_wallet_outlined,
          _openDebts,
          key: const Key('workspace-debts'),
        )
      else
        const ListTile(
          key: Key('workspace-debts-unavailable'),
          enabled: false,
          title: Text('الديون'),
          subtitle: Text('الديون غير متاحة في هذا الاتصال.'),
          leading: ExcludeSemantics(
            child: Icon(Icons.account_balance_wallet_outlined),
          ),
        ),
      if (widget.appearanceBuilder != null)
        _link(
          'مظهر الفاتورة',
          Icons.receipt_long_outlined,
          _openAppearance,
          key: const Key('workspace-invoice-appearance'),
        )
      else
        const ListTile(
          key: Key('workspace-invoice-appearance-unavailable'),
          enabled: false,
          title: Text('مظهر الفاتورة'),
          subtitle: Text('مظهر الفاتورة غير متاح في هذا الاتصال.'),
          leading: ExcludeSemantics(child: Icon(Icons.receipt_long_outlined)),
        ),
      if (widget.messageBuilder != null)
        _link(
          'نص رسالة الفاتورة',
          Icons.message_outlined,
          _openMessage,
          key: const Key('workspace-invoice-message'),
        )
      else
        const ListTile(
          enabled: false,
          title: Text('نص رسالة الفاتورة'),
          subtitle: Text('نص الرسالة غير متاح في هذا الاتصال.'),
        ),
      _link('التقارير', Icons.assessment_outlined, () => _select(3)),
      _link(
        Theme.of(context).brightness == Brightness.dark
            ? 'المظهر الفاتح'
            : 'المظهر الداكن',
        Icons.brightness_6_outlined,
        () => widget.onToggleTheme(Theme.of(context).brightness),
      ),
      if (widget.onChangeShop != null)
        _link(
          'العودة إلى حساب المتجر',
          Icons.storefront_outlined,
          widget.onChangeShop!,
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
      const indices = [0, 1, 2, 4];
      return Scaffold(
        body: _body(),
        bottomNavigationBar: NavigationBar(
          height:
              80 +
              (MediaQuery.textScalerOf(context).scale(AppTokens.detailSize) -
                      AppTokens.detailSize)
                  .clamp(0, 80),
          selectedIndex: _destination == 3 ? 3 : indices.indexOf(_destination),
          onDestinationSelected: (index) => _select(indices[index]),
          destinations: [
            for (final index in indices)
              NavigationDestination(
                key: Key('workspace-nav-$index'),
                icon: Icon(_icons[index]),
                label: index == 0 ? 'الدفتر' : _labels[index],
                tooltip: 'فتح ${_labels[index]}',
              ),
          ],
        ),
      );
    },
  );
}
