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
import '../features/audit_trail/domain/audit_trail.dart';
import '../features/audit_trail/presentation/audit_trail_screen.dart';
import '../features/support/domain/support_models.dart';
import '../features/support/presentation/support_screen.dart';
import '../features/shop_accounts/domain/shop_account.dart';
import '../features/shop_accounts/presentation/subscription_notice_banner.dart';
import '../theme/app_tokens.dart';
import 'workspace_chrome.dart';

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
    this.auditTrailGateway,
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
  final AuditTrailGateway? auditTrailGateway;
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _destination = 0;
  Route<void>? _repairRoute;
  Route<void>? _debtRoute;
  Route<void>? _appearanceRoute;
  Route<void>? _messageRoute;
  Route<void>? _shopImageRoute;
  Route<void>? _closingStaffRoute;
  Future<LogoUploadRecord?>? _logoDraft;

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

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
    'الحساب',
  ];
  static const _icons = [
    Icons.menu_book_outlined,
    Icons.inventory_2_outlined,
    Icons.people_outline,
    Icons.assessment_outlined,
    Icons.person_outline,
  ];

  void _select(int index) => setState(() => _destination = index);

  Widget _page(String title, List<Widget> children) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      leading: IconButton(
        key: const Key('workspace-menu'),
        tooltip: 'القائمة',
        icon: const Icon(Icons.menu),
        onPressed: _openDrawer,
      ),
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTokens.contentMaxWidth,
          ),
          child: ListView(
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            children: children,
          ),
        ),
      ),
    ),
  );

  Widget _link(String label, IconData icon, VoidCallback onTap, {Key? key}) =>
      ListTile(
        key: key,
        minVerticalPadding: 14,
        leading: ExcludeSemantics(child: Icon(icon)),
        title: Text(label),
        trailing: const ExcludeSemantics(child: Icon(Icons.chevron_left)),
        onTap: onTap,
      );

  String get _roleLabel => switch (widget.shop.memberRole) {
    ShopMemberRole.owner => 'صاحب المتجر',
    ShopMemberRole.partner => 'شريك',
    ShopMemberRole.employee => 'موظف',
    null => 'حساب المتجر',
  };

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
    _ => _accountPage(),
  };

  Widget _accountPage() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الحساب'),
        leading: IconButton(
          key: const Key('workspace-menu'),
          tooltip: 'القائمة',
          icon: const Icon(Icons.menu),
          onPressed: _openDrawer,
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.contentMaxWidth,
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceMd,
                AppTokens.spaceMd,
                AppTokens.spaceMd,
                AppTokens.spaceXl,
              ),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.spaceMd),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: scheme.primaryContainer,
                          foregroundColor: scheme.onPrimaryContainer,
                          backgroundImage: widget.shopImageBytes == null
                              ? null
                              : MemoryImage(widget.shopImageBytes!),
                          child: widget.shopImageBytes == null
                              ? const Icon(Icons.storefront_outlined, size: 28)
                              : null,
                        ),
                        const SizedBox(width: AppTokens.spaceMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.shop.name,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _roleLabel,
                                style: theme.textTheme.bodyMedium?.copyWith(
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
                const SizedBox(height: AppTokens.spaceMd),
                Text(
                  'افتح القائمة للتنقل إلى التجار والصيانة والديون والتقارير.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                if (!widget.shop.isEmployee) ...[
                  const SizedBox(height: AppTokens.spaceMd),
                  Text('الأرقام والمخزون', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppTokens.spaceSm),
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
                ],
                if (widget.shop.isOwner) ...[
                  const SizedBox(height: AppTokens.spaceLg),
                  _settingsGroup(
                    title: 'إعدادات المتجر',
                    children: [
                      if (widget.profileBuilder != null)
                        _link(
                          'بيانات المتجر',
                          Icons.store_mall_directory_outlined,
                          _openProfile,
                          key: const Key('workspace-shop-profile'),
                        ),
                      if (widget.shopImageBuilder != null)
                        _link(
                          'صورة المتجر',
                          Icons.photo_camera_outlined,
                          _openShopImage,
                          key: const Key('workspace-shop-image'),
                        ),
                      if (widget.paymentMethodsBuilder != null)
                        _link(
                          'وسائل الدفع',
                          Icons.payments_outlined,
                          _openPaymentMethods,
                          key: const Key('workspace-payment-methods'),
                        ),
                      if (widget.staffBuilder != null)
                        _link(
                          'الموظفون والصلاحيات',
                          Icons.badge_outlined,
                          _openStaff,
                          key: const Key('workspace-shop-staff'),
                        ),
                    ],
                  ),
                  if (widget.appearanceBuilder != null) ...[
                    const SizedBox(height: AppTokens.spaceMd),
                    _settingsGroup(
                      title: 'الفاتورة',
                      children: [
                        FutureBuilder<LogoUploadRecord?>(
                          future: _logoDraft,
                          builder: (context, snapshot) => ListTile(
                            key: const Key('workspace-invoice-appearance'),
                            minVerticalPadding: 14,
                            leading: const ExcludeSemantics(
                              child: Icon(Icons.receipt_long_outlined),
                            ),
                            title: const Text('مظهر الفاتورة'),
                            subtitle: snapshot.data?.fromRegistration == true
                                ? const Text(
                                    'مسودة شعار التسجيل بانتظار الرفع والمراجعة والحفظ.',
                                  )
                                : null,
                            trailing: const ExcludeSemantics(
                              child: Icon(Icons.chevron_left),
                            ),
                            onTap: _openAppearance,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: AppTokens.spaceMd),
                _settingsGroup(
                  title: 'الحساب والدعم',
                  children: [
                    _link(
                      dark ? 'المظهر الفاتح' : 'المظهر الداكن',
                      Icons.brightness_6_outlined,
                      () => widget.onToggleTheme(theme.brightness),
                      key: const Key('workspace-theme-toggle'),
                    ),
                    if (widget.helpGateway != null)
                      _link(
                        'المساعدة',
                        Icons.help_outline,
                        () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => HelpScreen(
                                gateway: widget.helpGateway!,
                                supportBuilder:
                                    widget.shop.isOwner &&
                                        widget.supportGateway != null
                                    ? (_) => SupportScreen(
                                        gateway: widget.supportGateway!,
                                      )
                                    : null,
                              ),
                            ),
                          );
                        },
                        key: const Key('workspace-help'),
                      ),
                    if (widget.shop.isOwner && widget.supportGateway != null)
                      _link(
                        'تواصل مع الدعم',
                        Icons.support_agent_outlined,
                        () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SupportScreen(
                                gateway: widget.supportGateway!,
                              ),
                            ),
                          );
                        },
                        key: const Key('workspace-support'),
                      ),
                    if (widget.onChangeShop != null)
                      _link(
                        'العودة إلى حساب المتجر',
                        Icons.swap_horiz_outlined,
                        widget.onChangeShop!,
                        key: const Key('workspace-change-shop'),
                      ),
                    _link(
                      'تسجيل الخروج',
                      Icons.logout,
                      widget.onSignOut,
                      key: const Key('workspace-sign-out'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsGroup({
    required String title,
    required List<Widget> children,
  }) {
    final items = children.whereType<Widget>().toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppTokens.spaceSm),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                if (index > 0)
                  Divider(
                    height: 1,
                    indent: 56,
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.7,
                    ),
                  ),
                items[index],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _workspaceDrawer() {
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.spaceSm,
            AppTokens.spaceMd,
            AppTokens.spaceSm,
            AppTokens.spaceLg,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceMd,
                0,
                AppTokens.spaceMd,
                AppTokens.spaceMd,
              ),
              child: Text('التنقل', style: theme.textTheme.titleLarge),
            ),
            _drawerLink(
              label: 'الدفتر اليومي',
              icon: Icons.menu_book_outlined,
              onTap: () {
                Navigator.of(context).pop();
                _select(0);
              },
            ),
            if (widget.shop.hasPermission(ShopPermission.inventory))
              _drawerLink(
                label: 'الجرد الفوري',
                icon: Icons.inventory_2_outlined,
                onTap: () {
                  Navigator.of(context).pop();
                  _select(1);
                },
              ),
            if (widget.shop.isOwner)
              _drawerLink(
                label: 'العملاء',
                icon: Icons.people_outline,
                onTap: () {
                  Navigator.of(context).pop();
                  _select(2);
                },
              ),
            if (widget.shop.hasPermission(ShopPermission.reports))
              _drawerLink(
                label: 'التقارير',
                icon: Icons.assessment_outlined,
                onTap: () {
                  Navigator.of(context).pop();
                  _select(3);
                },
                tileKey: const Key('workspace-reports'),
              ),
            if (widget.shop.hasPermission(ShopPermission.reports) &&
                widget.analyticsBuilder != null)
              _drawerLink(
                label: 'التحليلات',
                icon: Icons.insights_outlined,
                onTap: () {
                  Navigator.of(context).pop();
                  final builder = widget.analyticsBuilder;
                  if (builder != null) {
                    Navigator.of(
                      context,
                    ).push<void>(MaterialPageRoute(builder: builder));
                  }
                },
                tileKey: const Key('workspace-analytics'),
              ),
            if (widget.shop.isOwner && widget.traderBuilder != null)
              _drawerLink(
                label: 'التجار والأمانات',
                icon: Icons.storefront_outlined,
                onTap: () {
                  Navigator.of(context).pop();
                  _openTraders();
                },
                tileKey: const Key('workspace-traders'),
              ),
            if (widget.shop.isOwner && widget.repairBuilder != null)
              _drawerLink(
                label: 'الصيانة',
                icon: Icons.handyman_outlined,
                onTap: () {
                  Navigator.of(context).pop();
                  _openRepairs();
                },
                tileKey: const Key('workspace-repairs'),
              ),
            if (widget.shop.isOwner && widget.debtBuilder != null)
              _drawerLink(
                label: 'الديون',
                icon: Icons.account_balance_wallet_outlined,
                onTap: () {
                  Navigator.of(context).pop();
                  _openDebts();
                },
                tileKey: const Key('workspace-debts'),
              ),
            if (widget.shop.isOwner && widget.closingStaffBuilder != null)
              _drawerLink(
                label: 'فريق عد التقفيل',
                icon: Icons.fact_check_outlined,
                onTap: () {
                  Navigator.of(context).pop();
                  _openClosingStaff();
                },
                tileKey: const Key('workspace-closing-staff'),
              ),
            if (widget.shop.isOwner && widget.auditTrailGateway != null)
              _drawerLink(
                label: 'سجل العمليات',
                icon: Icons.history_outlined,
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AuditTrailScreen(gateway: widget.auditTrailGateway!),
                    ),
                  );
                },
                tileKey: const Key('workspace-audit-trail'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _drawerLink({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    Key? tileKey,
  }) => ListTile(
    key: tileKey,
    leading: ExcludeSemantics(child: Icon(icon)),
    title: Text(label),
    onTap: onTap,
  );

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
  Widget build(BuildContext context) => WorkspaceChrome(
    openDrawer: _openDrawer,
    child: LayoutBuilder(
      builder: (context, size) {
        if (size.maxWidth >= AppTokens.wideBreakpoint) {
          return Scaffold(
            key: _scaffoldKey,
            drawer: _workspaceDrawer(),
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
          key: _scaffoldKey,
          drawer: _workspaceDrawer(),
          body: _withNotice(_body()),
          bottomNavigationBar: NavigationBar(
            height:
                80 +
                (MediaQuery.textScalerOf(context).scale(AppTokens.detailSize) -
                        AppTokens.detailSize)
                    .clamp(0, 80),
            selectedIndex: _destination == 3
                ? 3
                : indices.indexOf(_destination),
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
    ),
  );
}
