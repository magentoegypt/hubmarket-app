import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/presentation/search_providers.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/search_no_results.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';
import '../../../support/fonts.dart';
import '../../../support/hubapp_fakes.dart';

/// The no-results page (S2) with [tries] as the store's suggestions.
Widget _app({
  required String locale,
  required List<String> tries,
  ValueChanged<String>? onTry,
  GlobalKey? boundary,
}) {
  final app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(locale),
    locale: Locale(locale),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: SearchNoResults(query: 'sofa bed velvet green', onTry: onTry),
    ),
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(const HubAppState.unavailable()),
      searchTrySuggestionsProvider.overrideWith((ref, query) async => tries),
      searchPopularNowProvider.overrideWith((ref) async => const <Product>[]),
    ],
    child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadAppFonts);

  for (final locale in const ['en', 'ar']) {
    testWidgets('"Try" offers the store\'s suggested searches ($locale)', (
      tester,
    ) async {
      _phone(tester);
      final key = GlobalKey();
      final tried = <String>[];
      final tries = locale == 'ar'
          ? ['كنبة سرير', 'كنبة خضراء', 'أثاث']
          : ['sofa bed', 'green sofa', 'Furniture'];
      await tester.pumpWidget(
        _app(locale: locale, tries: tries, onTry: tried.add, boundary: key),
      );
      await tester.pumpAndSettle();
      await captureScreen(tester, key, 'search_no_results_try_$locale');

      final l10n = lookupAppLocalizations(Locale(locale));
      expect(find.text(l10n.searchTryLabel), findsOneWidget);
      for (final term in tries) {
        expect(find.text(term), findsOneWidget);
      }
      await tester.tap(find.text(tries[1]));
      expect(tried, [tries[1]]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no suggestions index: no "Try" row', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(locale: 'en', tries: const [], onTry: (_) {}),
    );
    await tester.pumpAndSettle();
    expect(find.text('Try'), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('nowhere to search from: no "Try" row', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(locale: 'en', tries: const ['sofa bed']));
    await tester.pumpAndSettle();
    expect(find.text('sofa bed'), findsNothing);
  });
}
