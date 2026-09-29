import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/checkout/data/checkout_repository.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';
import 'package:hubmarket_app/features/checkout/domain/payment_session.dart';
import 'package:hubmarket_app/features/checkout/payments/payment_method_card.dart';
import 'package:hubmarket_app/features/checkout/payments/wallet_availability.dart';
import 'package:hubmarket_app/features/checkout/presentation/screens/complete_payment_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';

const _methods = [
  PaymentMethodOption(code: 'ngeniusonline', title: 'Card'),
  PaymentMethodOption(code: 'tabby_checkout', title: 'Tabby'),
];

Future<FakeCheckoutRepository> _pump(
  WidgetTester tester, {
  PaymentSession? session,
  String? currentMethod = 'ngeniusonline',
  String locale = 'en',
  List<PaymentMethodOption> methods = _methods,
  // Overridden in every test: the real provider calls the `hubmarket/payments`
  // channel, which has no handler under `flutter test` and would leave the
  // probe's timeout pending through pumpAndSettle.
  WalletAvailability wallets = const WalletAvailability(
    applePay: true,
    samsungPay: true,
  ),
}) async {
  final repo = FakeCheckoutRepository(paymentSession: session);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        checkoutRepositoryProvider.overrideWithValue(repo),
        walletAvailabilityProvider.overrideWith((ref) async => wallets),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CompletePaymentScreen(
          args: CompletePaymentArgs(
            orderNumber: '000000123',
            methods: methods,
            currentMethodCode: currentMethod,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('shows the awaiting-payment message, methods and pay-later', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.textContaining('000000123'), findsOneWidget);
    expect(find.text('Card'), findsOneWidget);
    expect(find.text('Tabby'), findsOneWidget);
    expect(find.text("I'll pay later"), findsOneWidget);
    // Pay now is disabled until a method is selected.
    final payNow = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Pay now'),
    );
    expect(payNow.onPressed, isNull);
  });

  testWidgets('switching to a different method calls setOrderPaymentMethod', (
    tester,
  ) async {
    // No session back → run ends "unavailable", stays on the screen.
    final repo = await _pump(tester, session: null);
    await tester.tap(find.text('Tabby')); // different from currentMethod
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay now'));
    await tester.pumpAndSettle();

    expect(repo.switchedToMethod, 'tabby_checkout');
    // Still on the complete-payment screen (no navigation on unavailable).
    expect(find.text('Pay now'), findsOneWidget);
  });

  testWidgets('retrying the SAME method recreates its session (no switch)', (
    tester,
  ) async {
    final repo = await _pump(tester, session: null);
    await tester.tap(find.text('Card')); // == currentMethod
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay now'));
    await tester.pumpAndSettle();

    expect(
      repo.switchedToMethod,
      isNull,
    ); // used fetchPaymentSession, not switch
  });

  testWidgets('renders translated + RTL in Arabic', (tester) async {
    await _pump(tester, locale: 'ar');
    expect(find.text('إتمام الدفع'), findsOneWidget); // completePaymentTitle
    expect(find.text('سأدفع لاحقًا'), findsOneWidget); // pay later
    expect(
      Directionality.of(tester.element(find.text('سأدفع لاحقًا'))),
      TextDirection.rtl,
    );
  });

  testWidgets('hides a wallet the device cannot pay with', (tester) async {
    // A method hidden at checkout must stay hidden on the retry screen. The
    // caller already filters, but this route takes its args from `extra`, so it
    // must not rely on that.
    await _pump(
      tester,
      methods: const [
        PaymentMethodOption(code: 'ngeniusonline_applepay', title: 'Apple Pay'),
        PaymentMethodOption(code: 'ngeniusonline_samsungpay', title: 'Samsung Pay'),
        PaymentMethodOption(code: 'ngeniusonline', title: 'Visa & MasterCard'),
      ],
      wallets: const WalletAvailability(applePay: true),
    );
    expect(find.text('Apple Pay'), findsOneWidget);
    expect(find.text('Samsung Pay'), findsNothing);
    expect(find.text('Visa & MasterCard'), findsOneWidget);
  });

  testWidgets('orders the switchable methods per CL042-DEV27', (tester) async {
    // Same reasoning as the wallet filter above: the caller passes an
    // already-ordered list, but this route takes its args from `extra`, so the
    // screen sorts them itself. Fed in deliberately shuffled API order — the
    // order QA saw on a stale build (CL042-QA01).
    //
    // Cash on Delivery is not a redirect method, so it is filtered out here
    // rather than sorted last as it is at checkout.
    await _pump(
      tester,
      methods: const [
        PaymentMethodOption(code: 'cashondelivery', title: 'Cash on Delivery'),
        PaymentMethodOption(code: 'tabby_installments', title: 'Tabby'),
        PaymentMethodOption(
          code: 'ngeniusonline_samsungpay',
          title: 'Samsung Pay',
        ),
        PaymentMethodOption(code: 'ngeniusonline', title: 'Visa & MasterCard'),
        PaymentMethodOption(code: 'ngeniusonline_applepay', title: 'Apple Pay'),
      ],
    );

    final rendered = tester
        .widgetList<PaymentMethodCard>(find.byType(PaymentMethodCard))
        .map((card) => card.method.title)
        .toList();
    expect(rendered, [
      'Apple Pay',
      'Samsung Pay',
      'Visa & MasterCard',
      'Tabby',
    ]);
  });
}
