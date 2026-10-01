import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/shell/hub_bottom_nav.dart';
import 'package:hubmarket_app/app/shell/hub_scaffold.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/widgets/hub_top_bar.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../support/fakes.dart';

Widget _app(HubScaffold scaffold) {
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, __) => scaffold)],
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light('en'),
    ),
  );
}

void main() {
  testWidgets('shows the tab bar and the screen\'s own header, no side menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const HubScaffold(
          currentTab: AppTab.cart,
          appBar: HubTopBar(title: 'My cart'),
          body: Text('body'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HubBottomNav), findsOneWidget);
    expect(find.text('My cart'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    expect(find.byTooltip('Open navigation menu'), findsNothing);
  });

  testWidgets('showTabBar: false leaves the five tabs out (a pushed page)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const HubScaffold(
          currentTab: AppTab.account,
          showTabBar: false,
          appBar: HubTopBar(title: 'Privacy & data'),
          body: Text('body'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HubBottomNav), findsNothing);
    expect(find.text('Privacy & data'), findsOneWidget);
  });

  testWidgets('a pinned bottom bar still shows without the tab bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const HubScaffold(
          currentTab: AppTab.home,
          showTabBar: false,
          bottomBar: SizedBox(height: 40, child: Text('Add to cart')),
          body: Text('body'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add to cart'), findsOneWidget);
    expect(find.byType(HubBottomNav), findsNothing);
  });
}
