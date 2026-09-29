import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/saved_card.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/presentation/cart_controller.dart';
import 'package:hubmarket_app/features/checkout/data/checkout_repository.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';
import 'package:hubmarket_app/features/checkout/payments/saved_card_picker.dart';
import 'package:hubmarket_app/features/checkout/payments/wallet_availability.dart';
import 'package:hubmarket_app/features/checkout/presentation/checkout_controller.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';

const _card = PaymentMethodOption(code: 'ngeniusonline', title: 'Visa & MC');
const _vault = PaymentMethodOption(
  code: 'ngeniusonline_vault',
  title: 'Saved card',
);
const _cod = PaymentMethodOption(code: 'cashondelivery', title: 'COD');

const _address = <String, dynamic>{
  'address': {
    'firstname': 'Layla',
    'lastname': 'Hassan',
    'telephone': '0500000000',
    'street': ['1 Marina Walk'],
    'city': 'Dubai',
    'country_code': 'AE',
  },
};

final _saved = SavedCard.fromToken(const {
  'public_hash': 'hash-1',
  'payment_method_code': 'ngeniusonline',
  'type': 'card',
  'details': '{"type":"VI","maskedCC":"1111","expirationDate":"12/2030"}',
})!;

Future<ProviderContainer> _seeded(FakeCheckoutRepository repo) async {
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      checkoutRepositoryProvider.overrideWithValue(repo),
      walletAvailabilityProvider.overrideWith(
        (ref) async => WalletAvailability.none,
      ),
    ],
  );
  addTearDown(container.dispose);
  container.listen(cartControllerProvider, (_, __) {});
  container.listen(authControllerProvider, (_, __) {});
  container.listen(checkoutControllerProvider, (_, __) {});
  await container.read(cartControllerProvider.notifier).addToCart(sku: 'SKU1');
  await container
      .read(checkoutControllerProvider.notifier)
      .submitAddress(
        email: 'shopper@example.com',
        shippingAddress: _address,
        lastname: 'Hassan',
        telephone: '0500000000',
        isGuest: false,
      );
  return container;
}

class _StubAuth extends AuthController {
  _StubAuth({required this.authenticated});

  final bool authenticated;

  @override
  AuthState build() => AuthState(
    status: authenticated ? AuthStatus.authenticated : AuthStatus.guest,
  );
}

Future<void> _pumpPicker(
  WidgetTester tester, {
  required PaymentMethodOption? vaultMethod,
  required List<SavedCard> cards,
  String? selectedHash,
  bool saveCard = false,
  bool authenticated = true,
  bool showSaveOption = true,
  String locale = 'en',
  void Function(SavedCard)? onSelectCard,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        savedCardsProvider.overrideWith((ref) async => cards),
        authControllerProvider.overrideWith(
          () => _StubAuth(authenticated: authenticated),
        ),
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
        home: Scaffold(
          body: SavedCardPicker(
            vaultMethod: vaultMethod,
            selectedHash: selectedHash,
            saveCard: saveCard,
            showSaveOption: showSaveOption,
            onSelectCard: onSelectCard ?? (_) {},
            onUseNewCard: () {},
            onSaveCardChanged: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PaymentMethodOption — vault code', () {
    test('isCardVault matches the N-Genius vault method only', () {
      expect(_vault.isCardVault, isTrue);
      expect(_card.isCardVault, isFalse);
      expect(_cod.isCardVault, isFalse);
      expect(
        const PaymentMethodOption(
          code: 'payflowpro_cc_vault',
          title: 'X',
        ).isCardVault,
        isFalse,
      );
    });

    test('the vault code still routes through the gateway path', () {
      // The failure that matters: if a vault order were treated as
      // non-redirect, checkout would skip the payment session and show success
      // for an order nobody paid for.
      expect(_vault.isRedirect, isTrue);
      expect(_vault.isWallet, isFalse);
      expect(_vault.isCard, isFalse);
      expect(_card.isCard, isTrue);
    });
  });

  group('CheckoutState — folding the vault row', () {
    const state = CheckoutState(paymentMethods: [_card, _vault, _cod]);

    test('hides the vault row but keeps it reachable', () {
      expect(state.visiblePaymentMethods.map((m) => m.code), [
        'ngeniusonline',
        'cashondelivery',
      ]);
      expect(state.cardVaultMethod?.code, 'ngeniusonline_vault');
    });

    test('shows the vault row when there is no card row to fold into', () {
      const orphan = CheckoutState(paymentMethods: [_vault, _cod]);
      expect(orphan.visiblePaymentMethods, hasLength(2));
    });

    test('a chosen saved card keeps the card row lit', () {
      const withCard = CheckoutState(
        paymentMethods: [_card, _vault, _cod],
        selectedPayment: _vault,
        selectedSavedCardHash: 'hash-1',
      );
      expect(withCard.isRowSelected(_card), isTrue);
      expect(withCard.isRowSelected(_cod), isFalse);
    });
  });

  group('CheckoutController - saved cards', () {
    test('sends the public hash with the vault method', () async {
      final repo = FakeCheckoutRepository(
        paymentMethods: const [_card, _vault, _cod],
      );
      final container = await _seeded(repo);
      final checkout = container.read(checkoutControllerProvider.notifier);

      await checkout.selectShipping(
        container.read(checkoutControllerProvider).shippingMethods.first,
      );
      await checkout.selectPayment(_vault, savedCardHash: 'hash-1');

      expect(repo.selectedPaymentCode, 'ngeniusonline_vault');
      expect(repo.selectedPublicHash, 'hash-1');
      expect(
        container.read(checkoutControllerProvider).selectedSavedCardHash,
        'hash-1',
      );
    });

    test('never pre-selects the vault row', () async {
      // COD is the usual default; with COD absent the fallback must still skip
      // a row that has no card chosen yet.
      final repo = FakeCheckoutRepository(paymentMethods: const [_vault, _card]);
      final container = await _seeded(repo);
      final checkout = container.read(checkoutControllerProvider.notifier);

      await checkout.selectShipping(
        container.read(checkoutControllerProvider).shippingMethods.first,
      );

      expect(repo.selectedPaymentCode, 'ngeniusonline');
    });

    test('switching to a new card clears the hash', () async {
      final repo = FakeCheckoutRepository(
        paymentMethods: const [_card, _vault, _cod],
      );
      final container = await _seeded(repo);
      final checkout = container.read(checkoutControllerProvider.notifier);

      await checkout.selectShipping(
        container.read(checkoutControllerProvider).shippingMethods.first,
      );
      await checkout.selectPayment(_vault, savedCardHash: 'hash-1');
      await checkout.selectPayment(_card);

      expect(repo.selectedPublicHash, isNull);
      expect(
        container.read(checkoutControllerProvider).selectedSavedCardHash,
        isNull,
      );
    });

    test('the save opt-in reaches the cart, and unticks if refused', () async {
      final repo = FakeCheckoutRepository(paymentMethods: const [_card, _cod])
        ..saveCardAccepted = false;
      final container = await _seeded(repo);
      final checkout = container.read(checkoutControllerProvider.notifier);

      await checkout.selectShipping(
        container.read(checkoutControllerProvider).shippingMethods.first,
      );
      await checkout.setSaveCard(true);
      await checkout.selectPayment(_card);

      expect(repo.lastSaveCard, isTrue);
      // A store without the backend half refuses the extra input; the order
      // still goes through, so the checkbox is corrected rather than blocking.
      expect(container.read(checkoutControllerProvider).saveCard, isFalse);
    });

    test('the opt-in is not sent with a saved card', () async {
      final repo = FakeCheckoutRepository(
        paymentMethods: const [_card, _vault, _cod],
      );
      final container = await _seeded(repo);
      final checkout = container.read(checkoutControllerProvider.notifier);

      await checkout.selectShipping(
        container.read(checkoutControllerProvider).shippingMethods.first,
      );
      await checkout.setSaveCard(true);
      await checkout.selectPayment(_vault, savedCardHash: 'hash-1');

      expect(repo.lastSaveCard, isFalse);
    });
  });

  group('SavedCardPicker', () {
    testWidgets('renders nothing for a guest', (tester) async {
      await _pumpPicker(
        tester,
        vaultMethod: _vault,
        cards: [_saved],
        authenticated: false,
      );
      expect(find.byType(Checkbox), findsNothing);
      expect(find.textContaining('1111'), findsNothing);
    });

    testWidgets('offers the save opt-in before any card exists', (tester) async {
      await _pumpPicker(tester, vaultMethod: null, cards: const []);
      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.text('Use a new card'), findsNothing);
    });

    testWidgets('hides cards the store cannot spend', (tester) async {
      // Cards exist but no vault method came back in available_payment_methods,
      // so choosing one would dead-end at place-order.
      await _pumpPicker(tester, vaultMethod: null, cards: [_saved]);
      expect(find.textContaining('1111'), findsNothing);
    });

    testWidgets('lists cards and a new-card row (EN)', (tester) async {
      SavedCard? picked;
      await _pumpPicker(
        tester,
        vaultMethod: _vault,
        cards: [_saved],
        onSelectCard: (card) => picked = card,
      );

      expect(find.text('Visa'), findsOneWidget);
      expect(find.text('•••• 1111'), findsOneWidget);
      expect(find.text('12/30'), findsOneWidget);
      expect(find.text('Use a new card'), findsOneWidget);

      await tester.tap(find.text('•••• 1111'));
      expect(picked?.publicHash, 'hash-1');
    });

    testWidgets('drops the opt-in once a saved card is chosen', (tester) async {
      await _pumpPicker(
        tester,
        vaultMethod: _vault,
        cards: [_saved],
        selectedHash: 'hash-1',
      );
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('renders in Arabic with the card number still LTR', (
      tester,
    ) async {
      await _pumpPicker(
        tester,
        vaultMethod: _vault,
        cards: [_saved],
        locale: 'ar',
      );

      expect(
        find.text('استخدام '
            'بطاقة '
            'جديدة'),
        findsOneWidget,
      );
      final number = tester.widget<Text>(
        find.text('•••• 1111'),
      );
      expect(number.textDirection, TextDirection.ltr);
    });

    testWidgets('marks an expired card and blocks selecting it', (tester) async {
      var taps = 0;
      final expired = SavedCard.fromToken(const {
        'public_hash': 'old',
        'payment_method_code': 'ngeniusonline',
        'type': 'card',
        'details': '{"type":"VI","maskedCC":"2222","expirationDate":"01/2020"}',
      })!;
      await _pumpPicker(
        tester,
        vaultMethod: _vault,
        cards: [expired],
        onSelectCard: (_) => taps++,
      );

      expect(find.text('Expired'), findsOneWidget);
      await tester.tap(find.text('•••• 2222'));
      expect(taps, 0);
    });
  });
}
