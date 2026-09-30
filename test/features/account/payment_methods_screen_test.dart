import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/saved_card.dart';
import 'package:hubmarket_app/features/account/presentation/screens/payment_methods_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

Future<void> _pump(
  WidgetTester tester, {
  List<SavedCard> cards = const [],
  String locale = 'en',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [savedCardsProvider.overrideWith((ref) async => cards)],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PaymentMethodsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final locale in ['en', 'ar']) {
    testWidgets('with no card it promises no checkout opt-in ($locale)', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(Locale(locale));
      await _pump(tester, locale: locale);

      expect(find.text(l10n.savedCardsEmptyTitle), findsOneWidget);
      expect(find.text(l10n.savedCardsEmptyBody), findsOneWidget);
      // The app has no "Save this card" box to tick.
      expect(l10n.savedCardsEmptyBody, isNot(contains('Save this card')));
      expect(l10n.savedCardsEmptyBody, isNot(contains('احفظ هذه البطاقة')));
    });
  }

  testWidgets('lists a saved card with its remove action', (tester) async {
    await _pump(
      tester,
      cards: const [
        SavedCard(
          publicHash: 'h1',
          brandCode: 'VI',
          last4: '1111',
          expiryMonth: 12,
          expiryYear: 2030,
        ),
      ],
    );
    expect(find.text('Visa'), findsOneWidget);
    expect(find.text('•••• 1111'), findsOneWidget);
    expect(find.byTooltip('Remove card'), findsOneWidget);
  });
}
