import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/checkout/domain/tabby_config.dart';
import 'package:hubmarket_app/features/checkout/payments/tabby_promo.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

const _aed = Money(amount: 200, currency: 'AED');

TabbyProduct _installments({
  bool enabled = true,
  bool promo = true,
  double? min,
  double? max = 5000,
}) => TabbyProduct(
  type: TabbyProductType.installments,
  methodCode: 'tabby_installments',
  enabled: enabled,
  promoEnabled: promo,
  minAmount: min,
  maxAmount: max,
);

TabbyProduct _payLater({bool enabled = true, bool promo = true}) =>
    TabbyProduct(
      type: TabbyProductType.payLater,
      methodCode: 'tabby_checkout',
      enabled: enabled,
      promoEnabled: promo,
    );

TabbyConfig _config(List<TabbyProduct> products) =>
    TabbyConfig(enabled: true, currency: 'AED', products: products);

Future<void> _pump(
  WidgetTester tester,
  TabbyConfig? config,
  Money price,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [tabbyConfigProvider.overrideWith((ref) => config)],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: TabbyPromo(price: price)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('TabbyProduct / TabbyConfig', () {
    test(
      'promo eligibility honours enable, promo flag, currency and bounds',
      () {
        final p = _installments(min: 100, max: 5000);
        expect(p.isPromoEligible(_aed, 'AED'), isTrue);
        expect(
          p.isPromoEligible(const Money(amount: 50, currency: 'AED'), 'AED'),
          isFalse,
        );
        expect(
          p.isPromoEligible(const Money(amount: 9000, currency: 'AED'), 'AED'),
          isFalse,
        );
        expect(
          p.isPromoEligible(const Money(amount: 200, currency: 'USD'), 'AED'),
          isFalse,
        );
        expect(
          _installments(enabled: false).isPromoEligible(_aed, 'AED'),
          isFalse,
        );
        // Enabled product with promo off → eligible to pay, not to promote.
        expect(_installments(promo: false).isEligible(_aed, 'AED'), isTrue);
        expect(
          _installments(promo: false).isPromoEligible(_aed, 'AED'),
          isFalse,
        );
      },
    );

    test('promoFor returns only enabled, promo-on, in-range products', () {
      final config = _config([_installments(max: 100), _payLater()]);
      final promo = config.promoFor(_aed);
      expect(promo, hasLength(1));
      expect(promo.single.type, TabbyProductType.payLater);
    });

    test('installments split by the product count; pay later does not', () {
      expect(
        _installments().perInstallment(
          const Money(amount: 200, currency: 'AED'),
        ),
        const Money(amount: 50, currency: 'AED'),
      );
      expect(_payLater().perInstallment(_aed), isNull);
    });
  });

  group('TabbyPromo', () {
    testWidgets('shows a line for each promo-eligible product', (tester) async {
      await _pump(tester, _config([_installments(), _payLater()]), _aed);
      // One brand chip for the (now bordered, tappable) card, one message line
      // per eligible product.
      expect(find.text('tabby'), findsOneWidget);
      expect(find.textContaining('interest-free payments of'), findsOneWidget);
      expect(find.textContaining('AED 50.00'), findsOneWidget); // 200 / 4
      expect(find.textContaining('pay later'), findsOneWidget);
    });

    testWidgets('shows only Pay Later when Pay in 4 is out of range', (
      tester,
    ) async {
      await _pump(
        tester,
        _config([_installments(max: 100), _payLater()]),
        _aed,
      );
      expect(find.text('tabby'), findsOneWidget);
      expect(find.textContaining('pay later'), findsOneWidget);
      expect(find.textContaining('interest-free payments of'), findsNothing);
    });

    testWidgets('hides a product whose promo flag is off', (tester) async {
      await _pump(tester, _config([_installments(promo: false)]), _aed);
      expect(find.text('tabby'), findsNothing);
    });

    testWidgets('hides entirely when nothing is configured', (tester) async {
      await _pump(tester, null, _aed);
      expect(find.text('tabby'), findsNothing);
    });
  });
}
