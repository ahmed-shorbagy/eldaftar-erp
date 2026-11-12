import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../features/daily_ledger/application/opening_gateway.dart';
import '../features/daily_ledger/application/pending_opening_store.dart';
import '../features/daily_ledger/presentation/daily_ledger_screen.dart';
import '../features/daily_ledger/presentation/ledger_more_balances.dart';
import '../features/onboarding/application/onboarding_store.dart';
import '../features/invoice_appearance/application/apply_shop_logo_to_invoice.dart';
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
import '../theme/app_messages.dart';
import '../theme/app_tokens.dart';
import '../theme/brand_mark.dart';

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
    this.ledgerArchiveBuilder,
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
    this.applyShopLogo,
    this.appVersion,
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
  final WidgetBuilder? ledgerArchiveBuilder;
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
  final ApplyShopLogoToInvoice? applyShopLogo;
  final String? appVersion;

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
  bool _logoApplyStarted = false;
  _LogoApply _logoApply = _LogoApply.idle;

  @override
  void initState() {
    super.initState();
    _readLogoDraft();
    _applyRegistrationLogo();
  }

  @override
  void didUpdateWidget(covariant ShopWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A subscription redeemed in this session activates the shop in place.
    if (oldWidget.shop.entitlement != ShopEntitlement.active &&
        widget.shop.entitlement == ShopEntitlement.active) {
      _applyRegistrationLogo();
    }
    // The shop image arrives after the first frame; try the O3 backfill then.
    if (oldWidget.shopImageBytes == null && widget.shopImageBytes != null) {
      _applyRegistrationLogo();
    }
  }

  void _readLogoDraft() {
    final user = widget.userId;
    _logoDraft = user == null || widget.appearanceBuilder == null
        ? null
        : const FileLogoUploadStore()
              .read(user, widget.shop.id)
              .catchError((Object _) => null);
  }

  Future<void> _applyRegistrationLogo() async {
    if (_logoApplyStarted) return;
    final apply = widget.applyShopLogo;
    final user = widget.userId;
    if (apply == null || user == null) return;
    if (!widget.shop.isOwner ||
        widget.shop.entitlement != ShopEntitlement.active) {
      return;
    }
    final draft = await (_logoDraft ?? Future<LogoUploadRecord?>.value());
    if (!mounted) return;
    if (draft?.fromRegistration != true) {
      await _backfillShopLogo(apply, user);
      return;
    }
    final bytes = await const FileLogoUploadStore().readBytes(
      user,
      widget.shop.id,
    );
    if (!mounted || bytes == null || _logoApplyStarted) return;
    _logoApplyStarted = true;
    setState(() => _logoApply = _LogoApply.running);
    final outcome = await apply.call(
      userId: user,
      shopId: widget.shop.id,
      logoBytes: bytes,
    );
    if (!mounted) return;
    switch (outcome) {
      case ApplyLogoOutcome.applied:
      case ApplyLogoOutcome.alreadyApplied:
        setState(() => _logoApply = _LogoApply.done);
        AppMessages.success(
          context,
          'تمت إضافة لوجو المحل إلى الفاتورة',
          id: 'invoice-logo-applied',
        );
      case ApplyLogoOutcome.failed:
        setState(() => _logoApply = _LogoApply.failed);
      case ApplyLogoOutcome.notAllowed:
      case ApplyLogoOutcome.skipped:
        _logoApplyStarted = false;
        setState(() => _logoApply = _LogoApply.idle);
    }
  }

  /// O3 (ADR 0047 D5): shops whose logo predates automatic application get
  /// it once on their invoice, only while no invoice appearance was saved.
  /// Quiet unless it succeeds; a failure retries on the next visit.
  Future<void> _backfillShopLogo(
    ApplyShopLogoToInvoice apply,
    String user,
  ) async {
    final bytes = widget.shopImageBytes;
    if (bytes == null || bytes.isEmpty || _logoApplyStarted) return;
    _logoApplyStarted = true;
    final outcome = await apply.call(
      userId: user,
      shopId: widget.shop.id,
      logoBytes: bytes,
      onlyWhenUnset: true,
    );
    if (!mounted) return;
    if (outcome == ApplyLogoOutcome.applied) {
      setState(() => _logoApply = _LogoApply.done);
      AppMessages.success(
        context,
        'تمت إضافة لوجو المحل إلى الفاتورة',
        id: 'invoice-logo-applied',
      );
    } else if (outcome != ApplyLogoOutcome.skipped &&
        outcome != ApplyLogoOutcome.alreadyApplied) {
      _logoApplyStarted = false;
    }
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
    'بيانات العملاء',
    'التقارير',
    'المزيد',
  ];
  static const _icons = [
    Icons.menu_book_outlined,
    Icons.inventory_2_outlined,
    Icons.people_outline,
    Icons.assessment_outlined,
    Icons.grid_view_rounded,
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
          : _page('بيانات العملاء', [
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
    _ => _morePage(),
  };

  Widget _morePage() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('المزيد'),
        automaticallyImplyLeading: false,
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
                              ? const BrandMark(size: 40)
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
                ..._morePages(),
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
                          'لوجو المحل',
                          Icons.image_outlined,
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
                  if (widget.appearanceBuilder != null ||
                      (widget.shop.isOwner &&
                          widget.messageBuilder != null)) ...[
                    const SizedBox(height: AppTokens.spaceMd),
                    _settingsGroup(
                      title: 'الفاتورة',
                      children: [
                        if (widget.appearanceBuilder != null)
                          FutureBuilder<LogoUploadRecord?>(
                            future: _logoDraft,
                            builder: (context, snapshot) => ListTile(
                              key: const Key('workspace-invoice-appearance'),
                              minVerticalPadding: 14,
                              leading: const ExcludeSemantics(
                                child: Icon(Icons.receipt_long_outlined),
                              ),
                              title: const Text('مظهر الفاتورة'),
                              subtitle: switch (_logoApply) {
                                _LogoApply.running => const Text(
                                  'جارٍ إضافة اللوجو إلى الفاتورة…',
                                ),
                                _LogoApply.failed => const Text(
                                  'تعذر إضافة اللوجو إلى الفاتورة. اضغط للمحاولة مرة أخرى.',
                                ),
                                _LogoApply.done => null,
                                _LogoApply.idle =>
                                  snapshot.data?.fromRegistration == true
                                      ? const Text(
                                          'سيُضاف لوجو المحل إلى الفاتورة بعد تفعيل الاشتراك.',
                                        )
                                      : null,
                              },
                              trailing: const ExcludeSemantics(
                                child: Icon(Icons.chevron_left),
                              ),
                              onTap: _openAppearance,
                            ),
                          ),
                        if (widget.shop.isOwner &&
                            widget.messageBuilder != null)
                          _link(
                            'رسالة الفاتورة',
                            Icons.chat_outlined,
                            _openMessage,
                            key: const Key('workspace-invoice-message'),
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
                if (widget.appVersion != null) ...[
                  const SizedBox(height: AppTokens.spaceLg),
                  Text(
                    'الإصدار \u2066${widget.appVersion}\u2069',
                    key: const Key('workspace-app-version'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
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

  List<Widget> _morePages() {
    final links = <Widget>[
      if (widget.shop.hasPermission(ShopPermission.reports) &&
          widget.ledgerArchiveBuilder != null)
        _link(
          'الدفاتر',
          Icons.menu_book_outlined,
          () {
            final builder = widget.ledgerArchiveBuilder;
            if (builder == null) return;
            Navigator.of(
              context,
            ).push<void>(MaterialPageRoute(builder: builder));
          },
          key: const Key('workspace-ledger-archive'),
        ),
      if (widget.shop.hasPermission(ShopPermission.reports))
        _link(
          'التقارير',
          Icons.assessment_outlined,
          () => _select(3),
          key: const Key('workspace-reports'),
        ),
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
      if (widget.shop.isOwner && widget.traderBuilder != null)
        _link(
          'التجار والأمانات',
          Icons.storefront_outlined,
          _openTraders,
          key: const Key('workspace-traders'),
        ),
      if (widget.shop.isOwner && widget.repairBuilder != null)
        _link(
          'المرمات',
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
      if (widget.shop.isOwner && widget.closingStaffBuilder != null)
        _link(
          'فريق عد التقفيل',
          Icons.fact_check_outlined,
          _openClosingStaff,
          key: const Key('workspace-closing-staff'),
        ),
      if (widget.shop.isOwner && widget.auditTrailGateway != null)
        _link(
          'سجل العمليات',
          Icons.history_outlined,
          () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    AuditTrailScreen(gateway: widget.auditTrailGateway!),
              ),
            );
          },
          key: const Key('workspace-audit-trail'),
        ),
    ];
    if (links.isEmpty) return const [];
    return [_settingsGroup(title: 'الصفحات', children: links)];
  }

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

enum _LogoApply { idle, running, done, failed }
