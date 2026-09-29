import Flutter
import UIKit

#if canImport(NISdk)
  import NISdk
#endif

/// Native half of the `hubmarket/payments` MethodChannel — the N-Genius (Network
/// International) card SDK and its Apple Pay wallet. Contract:
/// docs/backend/payment-contract.md §③.
///
/// The whole NISdk dependency is behind `#if canImport(NISdk)` on purpose. If
/// the pod is missing or fails to install, this still compiles and `pay`
/// answers `FlutterMethodNotImplemented`, which Dart already handles as
/// `MissingPluginException` -> `PaymentGatewayUnavailable` -> "awaiting
/// payment". That's exactly the behaviour before this module existed, so a
/// broken dependency degrades instead of breaking the build or the checkout.
///
/// Tabby is deliberately NOT handled here: its SDK ships as a Flutter package
/// (`tabby_flutter_inapp_sdk`), so it belongs in Dart, not in this module.
final class PaymentChannel: NSObject {
  private static let channelName = "hubmarket/payments"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    let instance = PaymentChannel()
    channel.setMethodCallHandler { call, result in
      instance.handle(call, result: result)
    }
    // Retained by the handler closure above; keep an explicit reference so the
    // delegate isn't deallocated mid-payment while NISdk holds it weakly.
    Self.retained = instance
  }

  private static var retained: PaymentChannel?

  // Both session types are declared inside NISdk's delegate protocols, so the
  // properties are guarded too — the #else path has to compile without the pod.
  #if canImport(NISdk)
    /// Held for the duration of one payment. NISdk keeps only a weak reference
    /// to the delegate, so without this the callback never arrives and the
    /// Flutter result is never fulfilled — the checkout would hang forever.
    private var activeSession: NGeniusSession?

    /// Same reason as `activeSession`.
    private var activeApplePaySession: ApplePaySession?
  #endif

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]

    // Which wallets this device can pay with, so Dart can hide the rows it
    // cannot honour. PassKit is a system framework, so this answers correctly
    // even in a build where the NISdk pod is missing.
    if call.method == "walletAvailability" {
      result([
        "applePay": ApplePayRequestBuilder.canUseApplePay(args),
        // Samsung Pay is Android-only; the row is hidden even if the backend
        // offers the method to every device.
        "samsungPay": false,
      ])
      return
    }

    guard call.method == "pay" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let gateway = args["gateway"] as? String ?? ""

    guard gateway == "ngenius" else {
      // Tabby (and anything else) is handled in Dart. Reporting "not
      // implemented" lets the Dart layer fall back rather than fail hard.
      result(FlutterMethodNotImplemented)
      return
    }

    let orderNumber = args["orderNumber"] as? String ?? ""

    // Apple Pay is an N-Genius *wallet*, not a gateway: same order, same
    // session, different SDK entry point.
    switch args["wallet"] as? String ?? "card" {
    case "card":
      #if canImport(NISdk)
        startNGeniusCard(args: args, result: result)
      #else
        result(FlutterMethodNotImplemented)
      #endif
    case "applepay":
      #if canImport(NISdk)
        startApplePay(args: args, result: result)
      #else
        result(FlutterMethodNotImplemented)
      #endif
    case "samsungpay":
      // FAILED rather than notImplemented(): "not implemented" means "the native
      // module is missing", which Dart turns into "order awaiting payment".
      // That would be a lie — this can only be a Dart bug, since
      // walletAvailability already answers samsungPay=false on iOS.
      result(
        Self.payload(
          status: "FAILED", orderNumber: orderNumber, raw: "samsungpay is Android-only"))
    default:
      result(
        Self.payload(status: "FAILED", orderNumber: orderNumber, raw: "unsupported wallet"))
    }
  }

  #if canImport(NISdk)
    private func startNGeniusCard(args: [String: Any], result: @escaping FlutterResult) {
      let orderNumber = args["orderNumber"] as? String ?? ""

      // iOS drives the SDK from the full order JSON (Android uses the
      // payment-authorization href instead). Both are always sent.
      guard let orderJson = args["orderResponse"] as? String,
        let data = orderJson.data(using: .utf8)
      else {
        result(Self.payload(status: "FAILED", orderNumber: orderNumber,
                            raw: "orderResponse missing or not a string"))
        return
      }

      let order: OrderResponse
      do {
        order = try OrderResponse.decodeFrom(data: data)
      } catch {
        result(Self.payload(status: "FAILED", orderNumber: orderNumber,
                            raw: "orderResponse did not decode: \(error)"))
        return
      }

      guard let parent = Self.topViewController() else {
        result(Self.payload(status: "FAILED", orderNumber: orderNumber,
                            raw: "no view controller to present over"))
        return
      }

      // Render the SDK's own UI in the customer's language.
      if let language = args["language"] as? String, !language.isEmpty {
        NISdk.sharedInstance.setSDKLanguage(language: language)
      }

      let session = NGeniusSession(orderNumber: orderNumber) { [weak self] payload in
        self?.activeSession = nil
        result(payload)
      }
      activeSession = session

      // A stored card is a different SDK screen: it shows the saved card and
      // asks only for the CVV. Which one opens is decided from the order the
      // backend built — it attaches `savedCard` when the quote carried a vault
      // token (docs/backend/payment-contract.md §④) — not from a channel
      // argument, so Dart never has to describe the card. The CVV-less overload
      // is deliberate: the SDK collects it, so no CVV crosses the channel.
      let savedCard = order.savedCard != nil
      DispatchQueue.main.async {
        if savedCard {
          NISdk.sharedInstance.launchSavedCardPayment(
            cardPaymentDelegate: session, overParent: parent, for: order)
        } else {
          NISdk.sharedInstance.showCardPaymentViewWith(
            cardPaymentDelegate: session, overParent: parent, for: order)
        }
      }
    }

    /// Apple Pay on the same N-Genius order the card path uses. The only new
    /// input is the `PKPaymentRequest`, which PassKit needs and the order JSON
    /// does not carry.
    private func startApplePay(args: [String: Any], result: @escaping FlutterResult) {
      let orderNumber = args["orderNumber"] as? String ?? ""

      guard let orderJson = args["orderResponse"] as? String,
        let data = orderJson.data(using: .utf8)
      else {
        result(Self.payload(status: "FAILED", orderNumber: orderNumber,
                            raw: "orderResponse missing or not a string"))
        return
      }

      let order: OrderResponse
      do {
        order = try OrderResponse.decodeFrom(data: data)
      } catch {
        result(Self.payload(status: "FAILED", orderNumber: orderNumber,
                            raw: "orderResponse did not decode: \(error)"))
        return
      }

      // Must match `com.apple.developer.in-app-payments` in the entitlements the
      // build was signed with — which, in CI, come from the provisioning profile
      // rather than Runner.entitlements. A blank id here means the build was
      // never configured, and walletAvailability has already hidden the row.
      guard let merchantId = args["applePayMerchantId"] as? String, !merchantId.isEmpty
      else {
        result(Self.payload(status: "FAILED", orderNumber: orderNumber,
                            raw: "applepay: no merchant identifier"))
        return
      }

      guard let request = ApplePayRequestBuilder.build(args: args, merchantId: merchantId)
      else {
        result(Self.payload(status: "FAILED", orderNumber: orderNumber,
                            raw: "applepay: could not build PKPaymentRequest"))
        return
      }

      // NISdk presents the PassKit sheet itself, but still wants the presenting
      // controller — same as the card path.
      guard let parent = Self.topViewController() else {
        result(Self.payload(status: "FAILED", orderNumber: orderNumber,
                            raw: "no view controller to present over"))
        return
      }

      let session = ApplePaySession(orderNumber: orderNumber) { [weak self] payload in
        self?.activeApplePaySession = nil
        result(payload)
      }
      activeApplePaySession = session

      // No setSDKLanguage here: the PassKit sheet is rendered by the system in
      // the device locale, and NISdk shows none of its own UI on this path.
      DispatchQueue.main.async {
        NISdk.sharedInstance.initiateApplePayWith(
          applePayDelegate: session, cardPaymentDelegate: session,
          overParent: parent, for: order, with: request)
      }
    }
  #endif

  /// Result map shape from the contract: status / gateway / orderNumber /
  /// reference / raw.
  static func payload(
    status: String, orderNumber: String, reference: String? = nil, raw: String? = nil
  ) -> [String: Any] {
    var map: [String: Any] = [
      "status": status,
      "gateway": "ngenius",
      "orderNumber": orderNumber,
    ]
    if let reference { map["reference"] = reference }
    if let raw { map["raw"] = raw }
    return map
  }

  /// The app is scene-based (see SceneDelegate), so `window` on the app
  /// delegate is not reliable — walk the active scene's key window instead,
  /// then down through anything already presented.
  static func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow }
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}

#if canImport(NISdk)
  /// One payment attempt. NISdk reports the outcome through
  /// `CardPaymentDelegate`; this normalises it to the contract's canonical
  /// status string and fulfils the Flutter result exactly once.
  ///
  /// Non-final and internally scoped so `ApplePaySession` can inherit the whole
  /// mapping rather than duplicating (and eventually drifting from) it.
  class NGeniusSession: NSObject, CardPaymentDelegate {
    private let orderNumber: String
    private var complete: (([String: Any]) -> Void)?
    /// Captured from the 3DS/authorization callbacks so a later generic
    /// `PaymentFailed` can be reported as the more specific cause.
    var failureCause: String?

    init(orderNumber: String, complete: @escaping ([String: Any]) -> Void) {
      self.orderNumber = orderNumber
      self.complete = complete
    }

    func finish(_ status: String, raw: String? = nil) {
      // NISdk can fire more than one terminal callback (e.g. a 3DS failure
      // followed by paymentDidComplete). Fulfilling a FlutterResult twice is a
      // hard crash, so only the first one counts.
      guard let complete else { return }
      self.complete = nil
      complete(PaymentChannel.payload(
        status: status, orderNumber: orderNumber, raw: raw))
    }

    func authorizationDidComplete(with status: AuthorizationStatus) {
      if status == .AuthFailed { failureCause = "AUTH_FAILED" }
    }

    func threeDSChallengeDidComplete(with status: ThreeDSStatus) {
      if status == .ThreeDSFailed { failureCause = "THREE_DS_FAILURE" }
    }

    func paymentDidComplete(with status: PaymentStatus) {
      switch status {
      case .PaymentSuccess:
        finish("SUCCESS", raw: status.rawVal)

      // Authorised now, captured asynchronously. The contract treats this as
      // success; the app re-queries Magento for the real order state anyway.
      case .PaymentPostAuthReview:
        finish("POST_AUTH_REVIEW", raw: status.rawVal)

      case .PaymentCancelled:
        finish("CANCELLED", raw: status.rawVal)

      case .PartialAuthDeclined, .PartialAuthDeclineFailed:
        finish("DECLINED", raw: status.rawVal)

      case .PaymentFailed, .InValidRequest:
        // Prefer the specific cause when 3DS or authorization already failed,
        // so the customer sees "declined" rather than a generic error.
        finish(failureCause ?? "FAILED", raw: status.rawVal)

      // Only part of the amount was authorised — not a clean success and not a
      // plain failure. Pass the SDK's own string through: it maps to `failed`
      // in Dart, which routes to CompletePaymentScreen rather than showing a
      // success screen for an order that isn't fully paid.
      case .PartiallyAuthorised:
        finish("PARTIALLY_AUTHORISED", raw: status.rawVal)

      @unknown default:
        finish("FAILED", raw: "unknown PaymentStatus")
      }
    }
  }
#endif
