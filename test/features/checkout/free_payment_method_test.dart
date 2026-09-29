import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';
import 'package:hubmarket_app/features/checkout/presentation/widgets/payment_method_tile.dart';
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
        body: PaymentMethodTile(method: method, selected: false, onTap: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PaymentMethodOption — Zero Subtotal Checkout (free)', () {
    test('isFree is true only for the Magento `free` code', () {
      expect(
        const PaymentMethodOption(code: 'free', title: 'No Payment').isFree,
        isTrue,
      );
      expect(
        const PaymentMethodOption(code: 'FREE', title: 'X').isFree,
        isTrue,
      );
      expect(
        const PaymentMethodOption(code: 'freeshipping', title: 'X').isFree,
        isFalse,
      );
      expect(
        const PaymentMethodOption(code: 'cashondelivery', title: 'X').isFree,
        isFalse,
      );
    });

    test('free is an offline method, so checkout offers it', () {
      const free = PaymentMethodOption(code: 'free', title: 'No Payment');
      expect(payableInApp(const [free]), [free]);
    });
  });

  group('PaymentMethodTile — free method', () {
    testWidgets('renders the no-payment-needed subtitle (EN)', (tester) async {
      await _pumpCard(
        tester,
        const PaymentMethodOption(
          code: 'free',
          title: 'No Payment Information Required',
        ),
      );
      expect(
        find.text('No payment needed — your order total is free'),
        findsOneWidget,
      );
    });

    testWidgets('renders the no-payment-needed subtitle translated (AR)', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        const PaymentMethodOption(code: 'free', title: 'بدون دفع'),
        locale: 'ar',
      );
      expect(find.text('لا حاجة للدفع — إجمالي طلبك مجاني'), findsOneWidget);
    });
  });
}
