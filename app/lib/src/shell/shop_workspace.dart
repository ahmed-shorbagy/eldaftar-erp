import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../features/daily_ledger/application/opening_gateway.dart';
import '../features/daily_ledger/application/pending_opening_store.dart';
import '../features/daily_ledger/presentation/daily_ledger_screen.dart';
import '../features/daily_ledger/presentation/ledger_more_balances.dart';
import '../features/onboarding/application/onboarding_store.dart';
import '../features/invoice_appearance/data/logo_upload_store.dart';
import '../features/help/domain/help_models.dart';
import '../features/help/presentation/announcement_banner.dart';
import '../features/help/presentation/help_screen.dart';
import '../features/support/domain/support_models.dart';
import '../features/support/presentation/support_screen.dart';
import '../features/shop_accounts/domain/shop_account.dart';
import '../features/shop_accounts/presentation/subscription_notice_banner.dart';
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
    this.subscriptionNotice,
    this.noticeDismissing = false,
    this.noticeDismissFailed = false,
    this.onDismissSubscriptionNotice,
    this.platformAnnouncement,
    this.onDismissPlatformAnnouncement,
    this.helpGateway,
    this.supportGateway,
    this.onboardingStore,
    this.inventoryBuilder,
    this.traderBuilder,
    this.repairBuilder,
    this.debtBuilder,
    this.customerBuilder,
    this.reportsBuilder,
    this.analyticsBuilder,
    this.appearanceBuilder,
    this.messageBuilder,
    this.shopImageBuilder,
    this.closingStaffBuilder,
    this.profileBuilder,
    this.staffBuilder,
    this.paymentMethodsBuilder,
    this.shopImageBytes,
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
  final SubscriptionNotice? subscriptionNotice;
  final bool noticeDismissing;
  final bool noticeDismissFailed;
  final Future<void> Function()? onDismissSubscriptionNotice;
  final PlatformAnnouncement? platformAnnouncement;
  final VoidCallback? onDismissPlatformAnnouncement;
  final HelpGateway? helpGateway;
  final SupportGateway? supportGateway;
  final OnboardingStore? onboardingStore;
  final WidgetBuilder? inventoryBuilder;
  final WidgetBuilder? traderBuilder;
  final WidgetBuilder? repairBuilder;
  final WidgetBuilder? debtBuilder;
  final WidgetBuilder? customerBuilder;
  final WidgetBuilder? reportsBuilder;
  final WidgetBuilder? analyticsBuilder;
  final WidgetBuilder? appearanceBuilder;
  final WidgetBuilder? messageBuilder;
  final WidgetBuilder? shopImageBuilder;
  final WidgetBuilder? closingStaffBuilder;
  final WidgetBuilder? profileBuilder;
  final WidgetBuilder? staffBuilder;
  final WidgetBuilder? paymentMethodsBuilder;
  final Uint8List? shopImageBytes;
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
  Route<void>? _shopImageRoute;
  Route<void>? _closingStaffRoute;
  Future<LogoUploadRecord?>? _logoDraft;

  @override
  void initState() {
    super.initState();
    _readLogoDraft();
  }

  void _readLogoDraft() {
    final user = widget.userId;
    _logoDraft = user == null || widget.appearanceBuilder == null
        ? null
        : const FileLogoUploadStore()
              .read(user, widget.shop.id)
              .catchError((Object _) => null);
  }

  @override
  void dispose() {
    _detach(_repairRoute);
    _detach(_debtRoute);
    _detach(_appearanceRoute);
    _detach(_messageRoute);
    _detach(_shopImageRoute);
    _detach(_closingStaffRoute);
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
    'الجرد الفوري',
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

  Future<void> _openClosingStaff() => _pushSingleton(
    widget.closingStaffBuilder,
    () => _closingStaffRoute,
    (route) => _closingStaffRoute = route,
  );

  Future<void> _openDebts() => _pushSingleton(
    widget.debtBuilder,
    () => _debtRoute,
    (route) => _debtRoute = route,
  );

  Future<void> _openAppearance() async {
    await _pushSingleton(
      widget.appearanceBuilder,
      () => _appearanceRoute,
      (route) => _appearanceRoute = route,
    );
    if (mounted) setState(_readLogoDraft);
  }

  Future<void> _openMessage() => _pushSingleton(
    widget.messageBuilder,
    () => _messageRoute,
    (route) => _messageRoute = route,
  );

  Future<void> _openShopImage() => _pushSingleton(
    widget.shopImageBuilder,
    () => _shopImageRoute,
    (route) => _shopImageRoute = route,
  );

  Route<void>? _profileRoute;
  Route<void>? _staffRoute;
  Route<void>? _paymentMethodsRoute;

  Future<void> _openProfile() => _pushSingleton(
    widget.profileBuilder,
    () => _profileRoute,
    (route) => _profileRoute = route,
  );

  Future<void> _openStaff() => _pushSingleton(
    widget.staffBuilder,
    () => _staffRoute,
    (route) => _staffRoute = route,
  );

  Future<void> _openPaymentMethods() => _pushSingleton(
    widget.paymentMethodsBuilder,
    () => _paymentMethodsRoute,
    (route) => _paymentMethodsRoute = route,
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
      shopImageBytes: widget.shopImageBytes,
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
      widget.shop.hasPermission(ShopPermission.inventory) &&
              widget.inventoryBuilder != null
          ? widget.inventoryBuilder!(context)
          : _page('الجرد الفوري', [
              Text(
                widget.shop.hasPermission(ShopPermission.inventory)
                    ? 'واجهة المخزون غير متاحة في هذا الاتصال. افتح الدفتر لمراجعة الأرصدة المؤكدة.'
                    : 'لا توجد صلاحية للجرد الفوري على هذا الحساب.',
              ),
              _link(
                'فتح الدفتر اليومي',
                Icons.menu_book_outlined,
                () => _select(0),
              ),
            ]),
    2 =>
      widget.shop.isOwner && widget.customerBuilder != null
          ? widget.customerBuilder!(context)
          : _page('العملاء', [
              Text(
                widget.shop.isOwner
                    ? 'ملفات العملاء غير متاحة في هذا الاتصال. بيانات طرف العملية متاحة في تفاصيل العملية المؤكدة داخل الدفتر.'
                    : 'إدارة العملاء متاحة لصاحب المتجر فقط.',
              ),
              _link(
                'فتح العمليات المؤكدة',
                Icons.menu_book_outlined,
                () => _select(0),
              ),
            ]),
    3 =>
      widget.shop.hasPermission(ShopPermission.reports) &&
              widget.reportsBuilder != null
          ? widget.reportsBuilder!(context)
          : _page('التقارير', [
              Text(
                widget.shop.hasPermission(ShopPermission.reports)
                    ? 'التقارير غير متاحة في هذا الاتصال. أعد الاتصال وحاول مجددًا.'
                    : 'لا توجد صلاحية للتقارير على هذا الحساب.',
              ),
              _link(
                'فتح الدفتر اليومي',
                Icons.menu_book_outlined,
                () => _select(0),
              ),
            ]),
    _ => _page('المزيد', [
      if (!widget.shop.isEmployee) ...[
        LedgerMoreBalances(
          key: ValueKey(
            'more-${widget.shop.id}-${widget.userId}-${widget.refreshGeneration}',
          ),
          shop: widget.shop,
          gateway: widget.gateway,
          userId: widget.userId,
          refreshGeneration: widget.refreshGeneration,
          syncTicks: widget.syncTicks,
        ),
        const SizedBox(height: 12),
      ],
      if (widget.shop.isOwner && widget.profileBuilder != null)
        _link(
          'بيانات المتجر',
          Icons.store_mall_directory_outlined,
          _openProfile,
          key: const Key('workspace-shop-profile'),
        ),
      if (widget.shop.isOwner && widget.paymentMethodsBuilder != null)
        _link(
          'وسائل الدفع',
          Icons.payments_outlined,
          _openPaymentMethods,
          key: const Key('workspace-payment-methods'),
        ),
      if (widget.shop.isOwner && widget.staffBuilder != null)
        _link(
          'الموظفون والصلاحيات',
          Icons.badge_outlined,
          _openStaff,
          key: const Key('workspace-shop-staff'),
        ),
      if (widget.shop.isOwner && widget.traderBuilder != null)
        _link('التجار والأمانات', Icons.storefront_outlined, _openTraders),
      if (widget.shop.isOwner && widget.repairBuilder != null)
        _link(
          'الصيانة',
          Icons.handyman_outlined,
          _openRepairs,
          key: const Key('workspace-repairs'),
        ),
      if (widget.shop.isOwner && widget.debtBuilder != null)
        _link(
          'الديون',
          Icons.account_balance_wallet_outlined,
          _openDebts,
          key: const Key('workspace-debts'),
        ),
      if (widget.shop.isOwner && widget.shopImageBuilder != null)
        _link(
          'صورة المتجر',
          Icons.storefront_outlined,
          _openShopImage,
          key: const Key('workspace-shop-image'),
        ),
      if (widget.shop.isOwner && widget.appearanceBuilder != null)
        FutureBuilder<LogoUploadRecord?>(
          future: _logoDraft,
          builder: (context, snapshot) => Card(
            child: ListTile(
              key: const Key('workspace-invoice-appearance'),
              minVerticalPadding: 16,
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('مظهر الفاتورة'),
              subtitle: snapshot.data?.fromRegistration == true
                  ? const Text(
                      'مسودة شعار التسجيل بانتظار الرفع والمراجعة والحفظ.',
                    )
                  : null,
              trailing: const Icon(Icons.chevron_right),
              onTap: _openAppearance,
            ),
          ),
        ),
      if (widget.shop.isOwner && widget.closingStaffBuilder != null)
        _link(
          'فريق عد التقفيل',
          Icons.fact_check_outlined,
          _openClosingStaff,
          key: const Key('workspace-closing-staff'),
        ),
      if (widget.shop.hasPermission(ShopPermission.reports))
        _link('التقارير', Icons.assessment_outlined, () => _select(3)),
      if (widget.shop.hasPermission(ShopPermission.reports) &&
          widget.analyticsBuilder != null)
        _link('التحليلات', Icons.insights_outlined, () {
          final builder = widget.analyticsBuilder;
          if (builder != null) {
            Navigator.of(
              context,
            ).push<void>(MaterialPageRoute(builder: builder));
          }
        }, key: const Key('workspace-analytics')),
      if (widget.shop.isOwner && widget.supportGateway != null)
        _link(
          'تواصل مع الدعم',
          Icons.support_agent_outlined,
          () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SupportScreen(gateway: widget.supportGateway!),
              ),
            );
          },
          key: const Key('workspace-support'),
        ),
      if (widget.helpGateway != null)
        _link('المساعدة', Icons.help_outline, () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HelpScreen(
                gateway: widget.helpGateway!,
                supportBuilder:
                    widget.shop.isOwner && widget.supportGateway != null
                    ? (_) => SupportScreen(gateway: widget.supportGateway!)
                    : null,
              ),
            ),
          );
        }, key: const Key('workspace-help')),
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

  Widget _withNotice(Widget child) {
    final notice = widget.subscriptionNotice;
    final announcement = widget.platformAnnouncement;
    final banners = <Widget>[
      if (notice != null && widget.onDismissSubscriptionNotice != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SubscriptionNoticeBanner(
            key: const Key('subscription-notice-banner'),
            notice: notice,
            dismissing: widget.noticeDismissing,
            dismissFailed: widget.noticeDismissFailed,
            onDismiss: () {
              final dismiss = widget.onDismissSubscriptionNotice;
              if (dismiss != null) dismiss();
            },
            onRenew: widget.onActivateSubscription == null
                ? null
                : () {
                    final renew = widget.onActivateSubscription;
                    if (renew != null) renew();
                  },
          ),
        ),
      if (announcement != null && widget.onDismissPlatformAnnouncement != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AnnouncementBanner(
            key: const Key('platform-announcement-banner'),
            announcement: announcement,
            onDismiss: widget.onDismissPlatformAnnouncement!,
          ),
        ),
    ];
    if (banners.isEmpty) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTokens.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: banners,
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

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
              Expanded(child: _withNotice(_body())),
            ],
          ),
        );
      }
      const indices = [0, 1, 2, 4];
      return Scaffold(
        body: _withNotice(_body()),
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
