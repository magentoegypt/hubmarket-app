import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/diagnostics/payment_trace.dart';
import '../domain/checkout.dart';
import '../domain/payment_wallet.dart';
import 'native_payment_gateway.dart';

/// Which wallets this *device* can actually pay with.
///
/// The API cannot answer this — `available_payment_methods` is a store/cart
/// concern and will happily offer Apple Pay to an Android phone. Apple Pay needs
/// an Apple-Pay-capable device with a provisioned card; Samsung Pay needs a
/// Samsung device with Samsung Wallet, a registered app signature and a
/// provisioned card. So the app asks the platform and filters the list.
class WalletAvailability {
  const WalletAvailability({this.applePay = false, this.samsungPay = false});

  /// Nothing available — also the answer whenever the probe cannot be trusted
  /// (module missing, platform error, timeout). Fail *closed*: hiding a row is
  /// always better than offering one that dead-ends at the payment sheet.
  static const WalletAvailability none = WalletAvailability();

  final bool applePay;
  final bool samsungPay;

  /// Exhaustive over [PaymentWallet] on purpose — a future wallet becomes a
  /// compile error here rather than silently defaulting to unavailable.
  bool allows(PaymentWallet wallet) => switch (wallet) {
    PaymentWallet.card => true,
    PaymentWallet.applePay => applePay,
    PaymentWallet.samsungPay => samsungPay,
  };
}

/// Asks the native `hubmarket/payments` module which wallets are usable.
///
/// Never throws. An older native binary answers `MissingPluginException`, and a
/// widget test with no mock handler does the same; both must quietly mean "no
/// wallets" and leave card / COD / Tabby untouched.
class WalletProbe {
  const WalletProbe({this.config = AppConfig.current});

  /// Identifiers the native side needs before it can even ask the SDK: a blank
  /// Samsung service id makes `SamsungPayClient` throw on construction, so it is
  /// checked natively before the client is built.
  final AppConfig config;

  /// Bounded because [CheckoutController] awaits this while building the payment
  /// step — a hung platform call would freeze checkout behind the busy barrier.
  static const Duration timeout = Duration(seconds: 3);

  Future<WalletAvailability> query() async {
    try {
      final result = await NativePaymentGateway.channel
          .invokeMapMethod<String, dynamic>(
            'walletAvailability',
            config.walletIdentifierArgs,
          )
          .timeout(timeout);
      // `== true` rather than a cast: a native side that omits a key, or sends
      // a string, degrades to unavailable instead of throwing.
      final availability = WalletAvailability(
        applePay: result?['applePay'] == true,
        samsungPay: result?['samsungPay'] == true,
      );
      PaymentTrace.record(
        'wallets: applePay=${availability.applePay} '
        'samsungPay=${availability.samsungPay}',
      );
      return availability;
    } on MissingPluginException {
      PaymentTrace.record('wallets: native module missing → none');
      return WalletAvailability.none;
    } on PlatformException catch (error) {
      PaymentTrace.record('wallets: PlatformException ${error.code} → none');
      return WalletAvailability.none;
    } on TimeoutException {
      PaymentTrace.record('wallets: probe timed out → none');
      return WalletAvailability.none;
    }
  }
}

final walletProbeProvider = Provider<WalletProbe>(
  (ref) => WalletProbe(config: ref.watch(appConfigProvider)),
);

/// Resolved once per container and cached, so the complete-payment screen can
/// read it synchronously without a second platform round trip. Invalidated on
/// checkout entry — a shopper can provision a Samsung card while the app runs.
final walletAvailabilityProvider = FutureProvider<WalletAvailability>(
  (ref) => ref.watch(walletProbeProvider).query(),
);

/// Drops wallet rows this device cannot pay with, keeping everything else.
///
/// Never returns an empty list: `CheckoutState.shippingDone` requires
/// `paymentMethods.isNotEmpty`, so filtering to nothing would hide the whole
/// payment step and dead-end checkout. If a store ever offered *only* wallets to
/// a device that supports neither, an unusable row that fails at the sheet is
/// still better than a checkout with no step 3.
List<PaymentMethodOption> filterUnavailableWallets(
  List<PaymentMethodOption> methods,
  WalletAvailability availability,
) {
  final kept = [
    for (final method in methods)
      if (availability.allows(method.wallet)) method,
  ];
  return kept.isEmpty ? methods : kept;
}
