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

class CheckoutState {
  const CheckoutState({
    this.email = '',
    this.lastname = '',
    this.isGuest = false,
    this.shippingMethods = const <ShippingMethodOption>[],
    this.selectedShipping,
    this.paymentMethods = const <PaymentMethodOption>[],
    this.selectedPayment,
    this.grandTotal,
    this.submittedPhone = '',
    this.guestOtpVerified = false,
    this.isBusy = false,
    this.error,
  });

  /// Email + lastname captured at the address step — kept with a guest's
  /// order reference so "Track order" can find the order later.
  final String email;
  final String lastname;
  final bool isGuest;
  final List<ShippingMethodOption> shippingMethods;
  final ShippingMethodOption? selectedShipping;
  final List<PaymentMethodOption> paymentMethods;
  final PaymentMethodOption? selectedPayment;

  final Money? grandTotal;

  /// The normalized (E.164) telephone last submitted with the shipping address —
  /// the number the guest-checkout OTP is actually sent to. Drives the "Code
  /// sent to …" caption and the verify-card key so they track the *submitted*
  /// number, not the live (possibly-edited) address field.
  final String submittedPhone;

  /// Guest-checkout OTP has been verified for [submittedPhone]. Gates Place
  /// Order for guests — only when `BackendCapabilities.guestCheckoutOtp` is on.
  /// Reset with the rest of the state on checkout entry via
  /// [CheckoutController.reset].
  final bool guestOtpVerified;

  final bool isBusy;
  final Object? error;

  bool get addressDone => shippingMethods.isNotEmpty;
  bool get shippingDone =>
      selectedShipping != null && paymentMethods.isNotEmpty;
  bool get paymentDone => selectedPayment != null;

  static const Object _keep = Object();

  CheckoutState copyWith({
    String? email,
    String? lastname,
    bool? isGuest,
    List<ShippingMethodOption>? shippingMethods,
    Object? selectedShipping = _keep,
    List<PaymentMethodOption>? paymentMethods,
    Object? selectedPayment = _keep,
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
      // the code was sent to that number, so editing an unrelated address
      // field (same phone) shouldn't force re-verification, but a new number
      // must.
      final phoneChanged = phone != state.submittedPhone;
      state = state.copyWith(
        email: email,
        lastname: lastname,
        isGuest: guest,
        shippingMethods: methods,
        selectedShipping: null,
        paymentMethods: const [],
        selectedPayment: null,
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
      // Only what `available_payment_methods` returns, minus the online
      // methods the app cannot complete yet (see payableInApp) — on Hub Market
      // that leaves cash on delivery.
      final payments = payableInApp(
        await _repo.setBillingSameAsShipping(cartId),
      );
      state = state.copyWith(
        selectedShipping: method,
        grandTotal: total,
        paymentMethods: payments,
        selectedPayment: null,
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
  PaymentMethodOption? _defaultPayment(List<PaymentMethodOption> methods) {
    if (methods.isEmpty) return null;
    for (final m in methods) {
      if (m.isCashOnDelivery) return m;
    }
    return methods.first;
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

  Future<bool> selectPayment(PaymentMethodOption method) async {
    final cartId = _cartId;
    if (cartId == null) return false;
    state = state.copyWith(isBusy: true, error: null);
    try {
      await _repo.setPaymentMethod(cartId, method.code);
      // Re-read the total once a method is on the quote. Our grandTotal was
      // read when the *shipping* method was set, before any payment method
      // existed; a method-dependent charge (a payment surcharge extension)
      // would otherwise leave the summary and the Place Order button quoting
      // less than the customer is charged. Stock Hub Market has no such
      // charge, so this normally reads back the same figure.
      final refreshed = await _refreshedGrandTotal();
      state = state.copyWith(
        selectedPayment: method,
        grandTotal: refreshed,
        isBusy: false,
      );
      return true;
    } catch (error) {
      state = state.copyWith(isBusy: false, error: error);
      return false;
    }
  }

  /// Sends a guest-checkout code to the delivery phone submitted with the
  /// address ([CheckoutState.submittedPhone]). Throws [Failure] (localized
  /// `detail`) so the verify card can surface the backend message;
  /// deliberately does **not** touch `isBusy` (the card owns its own local
  /// spinner, avoiding the screen-wide busy barrier for a small inline action).
  Future<void> requestGuestOtp({bool resend = false}) async {
    final phone = state.submittedPhone;
    if (_cartId == null || phone.isEmpty) {
      throw const Failure(FailureKind.unknown);
    }
    await _repo.requestGuestCheckoutOtp(phone, resend: resend);
  }

  /// Checks the guest-checkout [code] for the submitted phone and marks it
  /// verified. Throws [Failure] on a wrong/expired code.
  Future<void> verifyGuestOtp(String code) async {
    final phone = state.submittedPhone;
    if (_cartId == null || phone.isEmpty) {
      throw const Failure(FailureKind.unknown);
    }
    await _repo.verifyGuestCheckoutOtp(phone, code);
    // Only if the number wasn't changed while the code was in flight.
    if (state.submittedPhone == phone) {
      state = state.copyWith(guestOtpVerified: true);
    }
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
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(CheckoutController.new);
