import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../hubapp/hubapp.dart';

/// What the Hub Market App backend's account module
/// (`MagentoEgypt_HubAppAccount`, contract `lib/core/graphql/hubapp.graphql`)
/// lets the app do on the server it talks to.
///
/// Everything is off until the module is deployed, and the app then behaves
/// as Build 1: no store credit, no push-device registration, and sign-in by
/// WhatsApp code through `MagentoEgypt_SmsExtend`'s REST pair.
@immutable
class HubAppAccountFeatures {
  const HubAppAccountFeatures({
    this.storeCredit = false,
    this.pushDevices = false,
    this.whatsappSignIn = false,
  });

  /// Build 1: the module isn't there.
  static const HubAppAccountFeatures none = HubAppAccountFeatures();

  /// The module is deployed and every feature is switched on.
  static const HubAppAccountFeatures all = HubAppAccountFeatures(
    storeCredit: true,
    pushDevices: true,
    whatsappSignIn: true,
  );

  /// `hmAppConfig.features` codes (Stores › Configuration › Hub Market App ›
  /// Features).
  static const String storeCreditFlag = 'store_credit';
  static const String pushFlag = 'push';
  static const String whatsappSignInFlag = 'whatsapp_login';

  /// `hmStoreCredit`, `hmApplyStoreCredit` / `hmRemoveStoreCredit`,
  /// `Cart.hm_store_credit` and `OrderTotal.hm_store_credit`. Whether the
  /// customer may *spend* credit is the website's own rule
  /// (`credit/general/credit_group`), which the server answers per customer.
  final bool storeCredit;

  /// `hmRegisterDevice` / `hmUnregisterDevice`. Pushes also need FCM, which
  /// stays off until Hub Market's Firebase config is bundled.
  final bool pushDevices;

  /// `hmSendWhatsAppCode` / `hmSignInWithWhatsAppCode`.
  final bool whatsappSignIn;

  @override
  bool operator ==(Object other) =>
      other is HubAppAccountFeatures &&
      other.storeCredit == storeCredit &&
      other.pushDevices == pushDevices &&
      other.whatsappSignIn == whatsappSignIn;

  @override
  int get hashCode => Object.hash(storeCredit, pushDevices, whatsappSignIn);

  @override
  String toString() =>
      'HubAppAccountFeatures(storeCredit: $storeCredit, '
      'pushDevices: $pushDevices, whatsappSignIn: $whatsappSignIn)';
}

/// What the server advertises: the Hub Market App API answered
/// ([HubAppStatus.available]) and `hmAppConfig.features` switches the feature
/// on — `store_credit`, `push`, `whatsapp_login`. A code the backend doesn't
/// list stays off, so an admin turns each one on once `HubAppAccount` is
/// deployed (the rollout ships it after the read-only modules).
///
/// While the probe runs or can't tell ([HubAppStatus.unknown]) everything
/// stays on its Build 1 path.
final hubAppAccountAdvertisedProvider = Provider<HubAppAccountFeatures>((ref) {
  if (ref.watch(hubAppStatusProvider) != HubAppStatus.available) {
    return HubAppAccountFeatures.none;
  }
  bool on(String code) => ref.watch(hubAppFlagProvider(code)) ?? false;
  return HubAppAccountFeatures(
    storeCredit: on(HubAppAccountFeatures.storeCreditFlag),
    pushDevices: on(HubAppAccountFeatures.pushFlag),
    whatsappSignIn: on(HubAppAccountFeatures.whatsappSignInFlag),
  );
});

/// Set once an account operation answers "Cannot query field …": the server
/// has the Hub Market App module but not its account part — the P2 rollout
/// deploys `HubAppAccount` after the read-only modules. Every account feature
/// then keeps to its Build 1 path until the next launch.
class HubAppAccountMissing extends Notifier<bool> {
  @override
  bool build() => false;

  void mark() {
    if (!state) state = true;
  }
}

final hubAppAccountMissingProvider =
    NotifierProvider<HubAppAccountMissing, bool>(HubAppAccountMissing.new);

/// The account features the app runs with: what the server advertises,
/// unless an operation has shown the module isn't actually deployed.
final hubAppAccountFeaturesProvider = Provider<HubAppAccountFeatures>((ref) {
  if (ref.watch(hubAppAccountMissingProvider)) {
    return HubAppAccountFeatures.none;
  }
  return ref.watch(hubAppAccountAdvertisedProvider);
});
