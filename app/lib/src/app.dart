import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config/supabase_startup.dart';
import 'features/auth/domain/auth_gateway.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'features/daily_ledger/application/opening_gateway.dart';
import 'features/daily_ledger/application/pending_opening_store.dart';
import 'features/onboarding/application/onboarding_store.dart';
import 'features/shop_accounts/domain/shop_account_gateway.dart';
import 'shell/shell_copy.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

class ElDafttarApp extends StatelessWidget {
  const ElDafttarApp({
    super.key,
    required this.supabaseStatus,
    required this.themeController,
    this.authGateway,
    this.shopAccountGateway,
    this.openingGateway,
    this.pendingOpeningStore,
    this.onboardingStore,
    this.currentUserId,
  });

  final SupabaseStartupStatus supabaseStatus;
  final ThemeController themeController;
  final AuthGateway? authGateway;
  final ShopAccountGateway? shopAccountGateway;
  final OpeningGateway? openingGateway;
  final PendingOpeningStore? pendingOpeningStore;
  final OnboardingStore? onboardingStore;
  final String? Function()? currentUserId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: ShellCopy.appTitle,
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localeResolutionCallback: (_, _) => const Locale('ar'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeController.mode,
          home: AuthGate(
            supabaseStatus: supabaseStatus,
            authGateway: authGateway,
            shopAccountGateway: shopAccountGateway,
            openingGateway: openingGateway,
            pendingOpeningStore: pendingOpeningStore,
            onboardingStore: onboardingStore,
            currentUserId: currentUserId,
            onToggleTheme: themeController.toggle,
          ),
        );
      },
    );
  }
}
