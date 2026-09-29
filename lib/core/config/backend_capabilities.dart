import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which optional backend features the connected Magento store provides.
///
/// The app was started from another client's storefront app, whose backend
/// had custom modules Hub Market doesn't. The operations for those modules are
/// gone from the code — `tool/validate_ops.py` checks every document against
/// the live schema — and these flags keep the flows that depended on them
/// switched off instead of half-working: a flow whose flag is off never
/// starts, so nothing waits on a call that cannot succeed.
///
/// Turning a flag on is only half of the job: the backend feature and the
/// operation that talks to it have to come back with it. That is also why
/// these are compile-time constants rather than remote config — none of them
/// can be switched on without an app release anyway.
class BackendCapabilities {
  const BackendCapabilities({
    this.whatsappOtpLogin = false,
    this.guestCheckoutOtp = false,
    this.gatewayPaymentSessions = false,
    this.tabbyPromo = false,
    this.pushDeviceTokens = false,
  });

  /// Passwordless sign-in with a WhatsApp code.
  ///
  /// Backed by `MagentoEgypt_SmsExtend`'s REST pair
  /// `POST /V1/whatsapp/otp/{send,verify}` with `type: LOGIN` — the only
  /// endpoint on this backend that answers a verified code with a customer
  /// token (see `WhatsAppOtpApi`). Off hides the Phone tab on sign-in and
  /// leaves e-mail + password.
  final bool whatsappOtpLogin;

  /// Guests confirm the delivery phone with a WhatsApp code before Place Order
  /// (`customerCheckoutSendOtp` / `customerCheckoutVerifyOtp`, wired).
  ///
  /// Off, like the website: the store has `vsms/settings/verify_address_mobile`
  /// disabled, and even when enabled the module only enforces it on the web
  /// checkout — GraphQL `placeOrder` never checks it — so on the app it would
  /// be friction with no server-side effect.
  final bool guestCheckoutOtp;

  /// A payment session for a placed order — what card (N-Genius), wallet,
  /// Tabby and Tamara payments present. Needs a `paymentSession` /
  /// `setOrderPaymentMethod` resolver, which Hub Market doesn't have.
  ///
  /// Off: checkout drops those methods from `available_payment_methods`
  /// (placing an order with one would leave it unpaid), so only methods that
  /// complete on `placeOrder` remain — cash on delivery on this store.
  final bool gatewayPaymentSessions;

  /// Tabby eligibility + "Pay in 4" promo metadata (`tabbyConfig`) for the
  /// product page and cart. Off hides the promo.
  final bool tabbyPromo;

  /// Binding this device's FCM token to the customer, for pushes addressed to
  /// one person (order updates) rather than a topic. Needs a
  /// register/remove-device endpoint; Hub Market has none yet, so the app
  /// neither fetches the token for it nor calls one. Topic pushes (the
  /// promotions opt-in) don't depend on this.
  final bool pushDeviceTokens;

  /// What the Hub Market backend supports today.
  static const BackendCapabilities hubMarket = BackendCapabilities(
    whatsappOtpLogin: true,
  );
}

/// The capabilities the app runs with. A provider (not a bare constant) so a
/// test can exercise a flow the live backend has switched off.
final backendCapabilitiesProvider = Provider<BackendCapabilities>(
  (ref) => BackendCapabilities.hubMarket,
);
