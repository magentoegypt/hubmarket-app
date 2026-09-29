import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/storage/secure_token_store.dart';
import '../../../core/store/store_controller.dart';
import '../../../core/validation/phone.dart';
import '../../account/data/guest_order_store.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../catalog/domain/money.dart';
import '../data/checkout_repository.dart';
import '../domain/checkout.dart';
import '../domain/payment_session.dart';
import '../payments/payment_order.dart';
import '../payments/wallet_availability.dart';

class CheckoutState {
  const CheckoutState({
    this.email = '',
    this.lastname = '',
    this.isGuest = false,
    this.shippingMethods = const <ShippingMethodOption>[],
    this.selectedShipping,
    this.paymentMethods = const <PaymentMethodOption>[],
    this.selectedPayment,
    this.selectedSavedCardHash,
    this.saveCard = false,
    this.grandTotal,
    this.submittedPhone = '',
    this.guestOtpVerified = false,
    this.isBusy = false,
    this.error,
  });

  /// Billing email + lastname captured at the address step — sent to
  /// `paymentSession` so a guest order can reach the gateway.
  final String email;
  final String lastname;
  final bool isGuest;
  final List<ShippingMethodOption> shippingMethods;
  final ShippingMethodOption? selectedShipping;
  final List<PaymentMethodOption> paymentMethods;
  final PaymentMethodOption? selectedPayment;

  /// `public_hash` of the stored card the shopper picked, or null for "use a
  /// new card". Only ever set alongside a [selectedPayment] that is
  /// `isCardVault` — the two travel together to `setPaymentMethodOnCart`.
  final String? selectedSavedCardHash;

  /// "Save this card for next time" — asks the gateway to tokenise the card
  /// being entered. Only meaningful on the plain card method, and only for a
  /// signed-in customer (Magento's vault is keyed to one).
  final bool saveCard;

  final Money? grandTotal;

  /// The normalized (E.164) telephone last submitted with the shipping address —
  /// the number the guest-checkout OTP is actually sent to. Drives the "Code
  /// sent to …" caption and the verify-card key so they track the *submitted*
  /// number, not the live (possibly-edited) address field.
  final String submittedPhone;

  /// Guest-checkout OTP has been verified for the current cart. Gates Place
  /// Order for guests (the server rejects `placeOrder` without it). Reset with
  /// the rest of the state on checkout entry via [CheckoutController.reset].
  final bool guestOtpVerified;

  final bool isBusy;
  final Object? error;

  bool get addressDone => shippingMethods.isNotEmpty;
  bool get shippingDone =>
      selectedShipping != null && paymentMethods.isNotEmpty;
  bool get paymentDone => selectedPayment != null;

  /// The saved-card method, when the backend advertises one for this customer.
  PaymentMethodOption? get cardVaultMethod {
    for (final m in paymentMethods) {
      if (m.isCardVault) return m;
    }
    return null;
  }

  /// The rows checkout actually draws. The vault method is folded into the
  /// ordinary card row (the picker renders inside it) rather than shown as a
  /// second "Visa & MasterCard"-ish entry.
  ///
  /// Folding only happens when there *is* a card row to fold into: a store that
  /// somehow offers the vault code alone must still show it, or its saved cards
  /// would be unreachable.
  List<PaymentMethodOption> get visiblePaymentMethods {
    if (!paymentMethods.any((m) => m.isCard)) return paymentMethods;
    return paymentMethods.where((m) => !m.isCardVault).toList();
  }

  /// Whether [row] should read as selected. The card row stays lit while a
  /// saved card is chosen, because the selected *method* is then the vault code
  /// and the card row is what the picker lives in.
  bool isRowSelected(PaymentMethodOption row) {
    final selected = selectedPayment;
    if (selected == null) return false;
    if (selected.code == row.code) return true;
    return row.isCard && selected.isCardVault;
  }

  static const Object _keep = Object();

  CheckoutState copyWith({
    String? email,
    String? lastname,
    bool? isGuest,
    List<ShippingMethodOption>? shippingMethods,
    Object? selectedShipping = _keep,
    List<PaymentMethodOption>? paymentMethods,
    Object? selectedPayment = _keep,
    Object? selectedSavedCardHash = _keep,
    bool? saveCard,
    Object? grandTotal = _keep,
    String? submittedPhone,
    bool? guestOtpVerified,
    bool? isBusy,
    Object? error = _keep,
  }) => CheckoutState(
    email: email ?? this.email,
    lastname: lastname ?? this.lastname,
    isGuest: isGuest ?? this.isGuest,
    shippingMethods: shippingMethods ?? this.shippingMethods,
    selectedShipping: identical(selectedShipping, _keep)
        ? this.selectedShipping
        : selectedShipping as ShippingMethodOption?,
    paymentMethods: paymentMethods ?? this.paymentMethods,
    selectedPayment: identical(selectedPayment, _keep)
        ? this.selectedPayment
        : selectedPayment as PaymentMethodOption?,
    selectedSavedCardHash: identical(selectedSavedCardHash, _keep)
        ? this.selectedSavedCardHash
        : selectedSavedCardHash as String?,
    saveCard: saveCard ?? this.saveCard,
    grandTotal: identical(grandTotal, _keep)
        ? this.grandTotal
        : grandTotal as Money?,
    submittedPhone: submittedPhone ?? this.submittedPhone,
    guestOtpVerified: guestOtpVerified ?? this.guestOtpVerified,
    isBusy: isBusy ?? this.isBusy,
    error: identical(error, _keep) ? this.error : error,
  );
}

/// Drives the sequential checkout mutations against the active cart.
class CheckoutController extends Notifier<CheckoutState> {
  @override
  CheckoutState build() {
    // A language/store switch re-evaluates the cart against the new store view
    // and resets the GraphQL cache. The shipping/payment method titles + totals
    // held here are store- and locale-specific, so clear them; the user re-runs
    // the steps (address → shipping → payment) in the new language. Without this
    // the checkout kept the previous language's method labels + a stale total.
    ref.listen<String>(
      storeControllerProvider.select((s) => s.activeStoreCode),
      (prev, next) {
        if (prev != null && prev != next) state = const CheckoutState();
      },
    );
    return const CheckoutState();
  }

  /// Clears all checkout progress back to a clean slate. This controller is a
  /// session-wide singleton, so the checkout screen calls this on entry —
  /// otherwise a *second* checkout in the same session (or a checkout after
  /// logout) reuses the previous order's shipping method / payment / total.
  /// That both shows a stale grand total and makes the UI treat shipping/payment
  /// as already-done, so it skips those mutations on the new cart and
  /// `placeOrder` then fails ("Something went wrong").
  void reset() => state = const CheckoutState();

  CheckoutRepository get _repo => ref.read(checkoutRepositoryProvider);

  String? get _cartId {
    final id = ref.read(cartControllerProvider).cart.id;
    return id.isEmpty ? null : id;
  }

  /// Submits the checkout shipping address.
  ///
  /// [shippingAddress] is a Magento `ShippingAddressInput` — `{'address': {...}}`
  /// for a newly entered address, or `{'customer_address_id': id}` for a saved
  /// one. [lastname] and [telephone] are passed alongside rather than read back
  /// out of the map, because the saved-address form carries neither.
  Future<bool> submitAddress({
    required String email,
    required Map<String, dynamic> shippingAddress,
    required String lastname,
    required String telephone,
    required bool isGuest,
  }) async {
    final cartId = _cartId;
    if (cartId == null) return false;
    state = state.copyWith(isBusy: true, error: null);
    try {
      // AuthLink sends whatever bearer is in secure storage on every request,
      // independent of the auth *state*. If a token lingers while the app reads
      // as a guest (the startup restore window, or a state/token skew), Magento
      // treats the request as the logged-in customer and rejects
      // setGuestEmailOnCart ("The request is not allowed for logged in
      // customers") — which used to block Continue (QA 86d3mdef7 #1). Gate the
      // guest-only email on the actual token (what AuthLink sends), and drive
      // the rest of checkout (OTP gating, placeOrder auth) by that same flag so
      // a real bearer runs the customer path end-to-end.
      final hasToken = (await ref.read(secureTokenStoreProvider).read()) != null;
      final guest = isGuest && !hasToken;
      if (guest && email.isNotEmpty) {
        await _repo.setGuestEmail(cartId, email);
      }
      final methods = await _repo.setShippingAddress(cartId, shippingAddress);
      final phone = Phone.normalizeUae(telephone);
      // Keep a prior guest-OTP verification only when the phone is unchanged —
      // the challenge is bound to the cart's number, so editing an unrelated
      // address field (same phone) shouldn't force re-verification, but a new
      // number must.
      final phoneChanged = phone != state.submittedPhone;
      state = state.copyWith(
        email: email,
        lastname: lastname,
        isGuest: guest,
        shippingMethods: methods,
        selectedShipping: null,
        paymentMethods: const [],
        selectedPayment: null,
        selectedSavedCardHash: null,
        submittedPhone: phone,
        guestOtpVerified: phoneChanged ? false : state.guestOtpVerified,
        isBusy: false,
      );
      // Auto-select the default (free/standard) shipping so the payment step +
      // order summary populate without an extra tap — QA: "Standard Shipping
      // FREE selected by default". This cascades into the default payment.
      final defaultShipping = _defaultShipping(methods);
      if (defaultShipping != null) {
        await selectShipping(defaultShipping);
      }
      return true;
    } catch (error) {
      state = state.copyWith(isBusy: false, error: error);
      return false;
    }
  }

  Future<bool> selectShipping(ShippingMethodOption method) async {
    final cartId = _cartId;
    if (cartId == null) return false;
    state = state.copyWith(isBusy: true, error: null);
    try {
      final total = await _repo.setShippingMethod(
        cartId,
        method.carrierCode,
        method.methodCode,
      );
      // Present payments in the client's requested order (CL042-DEV27: Apple
      // Pay, Samsung Pay, Visa & MasterCard, Tabby, Cash on Delivery) — the
      // checkout list still contains only what the backend returns in
      // `available_payment_methods`.
      //
      // The only thing the app *removes* is a wallet this device cannot pay
      // with: the API offers Apple Pay to Android phones too, because
      // availability is a device concern the backend cannot see. This single
      // filter point feeds `state.paymentMethods`, the default selection, and
      // the method list forwarded to the complete-payment screen.
      final payments = orderPayments(
        filterUnavailableWallets(
          await _repo.setBillingSameAsShipping(cartId),
          await ref.read(walletAvailabilityProvider.future),
        ),
      );
      state = state.copyWith(
        selectedShipping: method,
        grandTotal: total,
        paymentMethods: payments,
        selectedPayment: null,
        selectedSavedCardHash: null,
        isBusy: false,
      );
      // Pre-select Cash on Delivery (QA default) so the summary + Place Order
      // are ready immediately; the shopper can still switch method.
      final defaultPayment = _defaultPayment(payments);
      if (defaultPayment != null) {
        await selectPayment(defaultPayment);
      }
      return true;
    } catch (error) {
      state = state.copyWith(isBusy: false, error: error);
      return false;
    }
  }

  /// The default shipping method to auto-select: the cheapest (a free method,
  /// when the store offers one, sorts first).
  ShippingMethodOption? _defaultShipping(List<ShippingMethodOption> methods) {
    if (methods.isEmpty) return null;
    final sorted = [...methods]
      ..sort((a, b) => (a.amount?.amount ?? 0).compareTo(b.amount?.amount ?? 0));
    return sorted.first;
  }

  /// Cash on Delivery when present (QA default), else the first method.
  ///
  /// Deliberately still COD even though DEV27 moves its row to the bottom:
  /// Place Order stays armed on open as it does today, and pre-selecting the
  /// first row would arm a wallet payment sheet the shopper never asked for.
  PaymentMethodOption? _defaultPayment(List<PaymentMethodOption> methods) {
    if (methods.isEmpty) return null;
    for (final m in methods) {
      if (isCodMethod(m.code)) return m;
    }
    // Never the vault row: it isn't drawn on its own, and pre-selecting it
    // would arm a payment with no card chosen.
    for (final m in methods) {
      if (!m.isCardVault) return m;
    }
    return null;
  }

  /// Re-reads the cart so the totals reflect what the server now charges,
  /// returning its grand total (the previous one when the refresh fails).
  ///
  /// A stale total here is a money-shown-vs-money-charged bug, but a failed
  /// refresh must not block choosing a method — the amount the customer is
  /// charged comes from the server at placeOrder either way.
  Future<Money?> _refreshedGrandTotal() async {
    try {
      await ref.read(cartControllerProvider.notifier).refresh();
      return ref.read(cartControllerProvider).cart.totals.grandTotal ??
          state.grandTotal;
    } on Object {
      return state.grandTotal;
    }
  }

  /// Selects a payment method, optionally with a saved card.
  ///
  /// [savedCardHash] pays with a stored card — pass it together with the vault
  /// method (`CheckoutState.cardVaultMethod`), never with the plain card row.
  Future<bool> selectPayment(
    PaymentMethodOption method, {
    String? savedCardHash,
  }) async {
    final cartId = _cartId;
    if (cartId == null) return false;
    // The save opt-in only applies to the card the shopper is about to type.
    final wantsSave = savedCardHash == null && method.isCard && state.saveCard;
    state = state.copyWith(isBusy: true, error: null);
    try {
      final saved = await _repo.setPaymentMethod(
        cartId,
        method.code,
        publicHash: savedCardHash,
        saveCard: wantsSave,
      );
      // The method can change the total: Cash on Delivery carries a flat
      // handling fee the server puts inside grand_total (CL042-DEV43). Our
      // grandTotal was read when the *shipping* method was set, before any
      // payment method existed on the quote — and COD is the pre-selected
      // default — so without this the summary and the Place Order button
      // would quote a figure lower than the customer is actually charged.
      // Re-read on every method, including switching away, since that
      // removes the fee again.
      final refreshed = await _refreshedGrandTotal();
      state = state.copyWith(
        selectedPayment: method,
        selectedSavedCardHash: savedCardHash,
        grandTotal: refreshed,
        // The store refused the opt-in (§④ not deployed): untick it rather than
        // leave a checkbox promising something that won't happen.
        saveCard: wantsSave && !saved ? false : null,
        isBusy: false,
      );
      return true;
    } catch (error) {
      state = state.copyWith(isBusy: false, error: error);
      return false;
    }
  }

  /// Toggles "save this card for next time". Re-sends the method when the card
  /// row is already selected, so the flag reaches the quote instead of only the
  /// UI — otherwise ticking the box after choosing the card would do nothing.
  Future<void> setSaveCard(bool value) async {
    if (state.saveCard == value) return;
    state = state.copyWith(saveCard: value);
    final selected = state.selectedPayment;
    if (selected != null && selected.isCard) {
      await selectPayment(selected);
    }
  }

  /// Sends a guest-checkout OTP to the cart's shipping phone. Throws [Failure]
  /// (localized `detail`) so the verify card can surface the backend message;
  /// deliberately does **not** touch `isBusy` (the card owns its own local
  /// spinner, avoiding the screen-wide busy barrier for a small inline action).
  Future<void> requestGuestOtp() async {
    final cartId = _cartId;
    if (cartId == null) throw const Failure(FailureKind.unknown);
    await _repo.requestGuestCheckoutOtp(cartId);
  }

  /// Verifies the guest-checkout OTP and binds it to the quote so `placeOrder`
  /// is allowed. Throws [Failure] on a wrong/expired code.
  Future<void> verifyGuestOtp(String code) async {
    final cartId = _cartId;
    if (cartId == null) throw const Failure(FailureKind.unknown);
    await _repo.verifyGuestCheckoutOtp(cartId, code);
    state = state.copyWith(guestOtpVerified: true);
  }

  Future<PlaceOrderResult?> placeOrder() async {
    final cartId = _cartId;
    if (cartId == null) return null;
    state = state.copyWith(isBusy: true, error: null);
    try {
      final result = await _repo.placeOrder(cartId);
      // Guests have no `customer { orders }` history, so remember the order's
      // lookup keys here — the one point where the token and the billing
      // email/lastname are both still in hand. Without it "Track Order" has
      // nothing to resolve once checkout state is reset.
      if (state.isGuest) {
        await ref
            .read(guestOrderStoreProvider.notifier)
            .remember(
              GuestOrderRef(
                number: result.orderNumber,
                token: result.orderToken,
                email: state.email,
                lastname: state.lastname,
                placedAt: DateTime.now().toIso8601String(),
              ),
            );
      }
      // The order consumed the cart server-side — reset it (drop the stale id +
      // persisted guest id) so it reads empty and the next add-to-cart creates a
      // fresh cart, instead of failing against the consumed one.
      await ref.read(cartControllerProvider.notifier).clearAfterOrder();
      state = state.copyWith(isBusy: false);
      return result;
    } catch (error) {
      state = state.copyWith(isBusy: false, error: error);
      return null;
    }
  }

  /// Loads the gateway session for a placed order. A `PENDING` session isn't yet
  /// launchable, so we back-off poll a few times before giving up (the contract's
  /// PENDING flow). A guest order authorizes via **either** the Magento order
  /// [orderToken] (`placeOrder.orderV2.token`) **or** the billing email +
  /// lastname captured at checkout; both are sent. A logged-in customer sends
  /// only the order number (the bearer authorizes). Null when the resolver
  /// isn't deployed.
  Future<PaymentSession?> loadPaymentSession(
    String orderNumber, {
    String? orderToken,
  }) async {
    final guest = state.isGuest;
    final email = guest ? state.email : null;
    final lastname = guest ? state.lastname : null;
    final token = guest ? orderToken : null;
    const maxAttempts = 4;
    PaymentSession? session;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      session = await _repo.fetchPaymentSession(
        orderNumber,
        email: email,
        lastname: lastname,
        token: token,
      );
      if (session == null ||
          session.status != PaymentSessionStatus.pending ||
          attempt == maxAttempts - 1) {
        return session;
      }
      await Future<void>.delayed(Duration(seconds: 1 + attempt));
    }
    return session;
  }
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(CheckoutController.new);
