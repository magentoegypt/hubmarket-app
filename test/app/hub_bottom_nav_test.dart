import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/shell/hub_bottom_nav.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../support/fakes.dart';

Widget _nav({
  AppTab current = AppTab.home,
  String locale = 'en',
  double textScale = 1,
}) => ProviderScope(
  overrides: [
    localCacheProvider.overrideWithValue(FakeLocalCache()),
    secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
    cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
  ],
  child: MaterialApp(
    locale: Locale(locale),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.light(locale),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(bottomNavigationBar: HubBottomNav(current: current)),
  ),
);

void main() {
  testWidgets('five tabs, the active one in the accent colours', (
    tester,
  ) async {
    await tester.pumpWidget(_nav(current: AppTab.categories));

    for (final label in const [
      'Home',
      'Categories',
      'Cart',
      'Wishlist',
      'Account',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    Color labelColor(String label) =>
        tester.widget<Text>(find.text(label)).style!.color!;
    expect(labelColor('Categories'), AppColors.accentStrong);
    expect(labelColor('Home'), AppColors.inkMuted);

    Color iconColor(IconData icon) =>
        tester.widget<Icon>(find.byIcon(icon)).color!;
    expect(iconColor(HubIcons.layoutGrid), AppColors.accent);
    expect(iconColor(HubIcons.house), AppColors.inkMuted);
  });

  testWidgets('the tab row is 55 px at 1x and the labels are Arabic in AR', (
    tester,
  ) async {
    await tester.pumpWidget(_nav(locale: 'ar'));

    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('الأقسام'), findsOneWidget);
    expect(find.text('حسابي'), findsOneWidget);
    // 55 + the 1 px rule.
    expect(tester.getSize(find.byType(HubBottomNav)).height, 56);
  });

  testWidgets('grows with the text size instead of overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(_nav());
    final base = tester.getSize(find.byType(HubBottomNav)).height;

    for (final scale in const [1.3, 2.0]) {
      await tester.pumpWidget(_nav(textScale: scale));
      expect(tester.takeException(), isNull, reason: 'scale $scale');
      expect(
        tester.getSize(find.byType(HubBottomNav)).height,
        greaterThanOrEqualTo(base),
      );
    }
  });
}
