import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';
import 'package:hubmarket_app/features/checkout/domain/payment_session.dart';
import 'package:hubmarket_app/features/checkout/domain/payment_wallet.dart';
import 'package:hubmarket_app/features/checkout/payments/payment_method_card.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

Future<void> _pumpCard(
  WidgetTester tester,
  PaymentMethodOption method, {
  String locale = 'en',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PaymentMethodCard(method: method, selected: false, onTap: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PaymentSession _session(String methodCode) => PaymentSession(
  orderNumber: '2000000001',
  methodCode: methodCode,
  gateway: PaymentProvider.ngenius,
  status: PaymentSessionStatus.ready,
);

void main() {
  group('walletForMethodCode', () {
    test('recognises Apple Pay however the backend spells the code', () {
      for (final code in [
        // The live code, confirmed against available_payment_methods on
        // 2026-08-20. The rest are spellings the matcher tolerates.
        'ngeniusonline_applepay',
        'ngenius_applepay',
        'ngenius_apple_pay',
        'NGENIUS_APPLEPAY',
        'apple-pay',
        'applepay',
        'ngeniusApplePay',
        'magentoegypt_apple_pay',
      ]) {
        expect(
          walletForMethodCode(code),
          PaymentWallet.applePay,
          reason: 'expected $code to be Apple Pay',
        );
      }
    });

    test('recognises Samsung Pay however the backend spells the code', () {
      for (final code in [
        // The live code, confirmed 2026-08-20.
        'ngeniusonline_samsungpay',
        'ngenius_samsungpay',
        'ngenius_samsung_pay',
        'SAMSUNG-PAY',
        'samsungpay',
      ]) {
        expect(
          walletForMethodCode(code),
          PaymentWallet.samsungPay,
          reason: 'expected $code to be Samsung Pay',
        );
      }
    });

    test('everything else is the plain card wallet', () {
      for (final code in [
        'ngeniusonline',
        'cashondelivery',
        'checkmo',
        'free',
        'tabby_installments',
        'tabby_checkout',
        '',
      ]) {
        expect(
          walletForMethodCode(code),
          PaymentWallet.card,
          reason: 'expected $code to be card',
        );
      }
    });

    test('wire values match the native switch', () {
      expect(PaymentWallet.card.wire, 'card');
      expect(PaymentWallet.applePay.wire, 'applepay');
      expect(PaymentWallet.samsungPay.wire, 'samsungpay');
    });
  });

  group('PaymentMethodOption — wallets', () {
    test('exposes the wallet flags', () {
      const apple = PaymentMethodOption(
        code: 'ngeniusonline_applepay',
        title: 'Apple Pay',
      );
      const samsung = PaymentMethodOption(
        code: 'ngeniusonline_samsungpay',
        title: 'Samsung Pay',
      );
      const card = PaymentMethodOption(
        code: 'ngeniusonline',
        title: 'Visa & MasterCard',
      );

      expect(apple.isApplePay, isTrue);
      expect(apple.isSamsungPay, isFalse);
      expect(apple.isWallet, isTrue);
      expect(samsung.isSamsungPay, isTrue);
      expect(samsung.isWallet, isTrue);
      expect(card.isWallet, isFalse);
    });

    test(
      'a wallet is a redirect method EVEN WITHOUT an ngenius substring',
      () {
        // The regression guard for the worst failure mode in this feature: if a
        // wallet code slips past isRedirect, _placeOrder skips the payment
        // session entirely and shows order-success for an order nobody paid.
        // The backend codes are provisional, so this must not depend on them
        // happening to contain "ngenius".
        const apple = PaymentMethodOption(code: 'apple_pay', title: 'Apple Pay');
        const samsung = PaymentMethodOption(
          code: 'samsung_pay',
          title: 'Samsung Pay',
        );
        expect(apple.isRedirect, isTrue);
        expect(samsung.isRedirect, isTrue);
      },
    );

    test('wallets do not disturb the existing method flags', () {
      const apple = PaymentMethodOption(
        code: 'ngeniusonline_applepay',
        title: 'Apple Pay',
      );
      expect(apple.isFree, isFalse);
      expect(apple.isTabby, isFalse);
      expect(apple.tabbyProduct, isNull);

      // And the non-gateway methods are still non-gateway.
      expect(
        const PaymentMethodOption(code: 'free', title: 'X').isRedirect,
        isFalse,
      );
      expect(
        const PaymentMethodOption(code: 'cashondelivery', title: 'X').isRedirect,
        isFalse,
      );
      expect(
        const PaymentMethodOption(code: 'checkmo', title: 'X').isRedirect,
        isFalse,
      );
    });
  });

  group('PaymentSession.wallet', () {
    test('derives from the method code, gateway stays N-Genius', () {
      expect(_session('ngeniusonline_applepay').wallet, PaymentWallet.applePay);
      expect(_session('ngeniusonline_samsungpay').wallet, PaymentWallet.samsungPay);
      expect(_session('ngeniusonline').wallet, PaymentWallet.card);
      // A wallet must never become a new gateway — the resolver switch depends
      // on that staying true.
      expect(_session('ngeniusonline_applepay').gateway, PaymentProvider.ngenius);
    });
  });

  group('PaymentMethodCard — wallets', () {
    testWidgets('Apple Pay renders its subtitle (EN)', (tester) async {
      await _pumpCard(
        tester,
        const PaymentMethodOption(
          code: 'ngeniusonline_applepay',
          title: 'Apple Pay',
        ),
      );
      expect(find.text('Apple Pay'), findsOneWidget);
      expect(find.text('Pay quickly with Apple Pay'), findsOneWidget);
    });

    testWidgets('Samsung Pay renders its subtitle (AR)', (tester) async {
      await _pumpCard(
        tester,
        const PaymentMethodOption(
          code: 'ngeniusonline_samsungpay',
          title: 'Samsung Pay',
        ),
        locale: 'ar',
      );
      // The brand name stays in Latin script even in Arabic — it is a protected
      // mark and Apple/Samsung guidelines require the untranslated name.
      expect(find.text('ادفع بسرعة عبر Samsung Pay'), findsOneWidget);
    });

    testWidgets('a wallet row shows no Tabby chip', (tester) async {
      await _pumpCard(
        tester,
        const PaymentMethodOption(
          code: 'ngeniusonline_applepay',
          title: 'Apple Pay',
        ),
      );
      expect(find.text('tabby'), findsNothing);
    });
  });
}
