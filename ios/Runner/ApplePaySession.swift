import Foundation
import PassKit

#if canImport(NISdk)
  import NISdk
#endif

/// Builds the `PKPaymentRequest` for an Apple Pay attempt.
///
/// Pure PassKit on purpose — no NISdk import — so it compiles, and can be
/// reasoned about, even in a build where the pod failed to resolve. Everything
/// it needs arrives as `pay` channel arguments, so the merchant id, country and
/// card schemes can be retuned from `config/*.json` without a native release.
enum ApplePayRequestBuilder {

  /// Card schemes to offer, intersected with what this OS version knows.
  ///
  /// The default is deliberately just Visa + Mastercard: those are what a UAE
  /// N-Genius outlet carries by default. `mada` is the *Saudi* domestic scheme
  /// and Amex depends on the outlet, so both are opt-in through config rather
  /// than baked in here.
  static func networks(from raw: [String]?) -> [PKPaymentNetwork] {
    let names = (raw?.isEmpty == false) ? raw! : ["visa", "mastercard"]
    var known: [String: PKPaymentNetwork] = [
      "visa": .visa,
      "mastercard": .masterCard,
      "amex": .amex,
      "discover": .discover,
      "jcb": .JCB,
    ]
    if #available(iOS 12.1.1, *) { known["mada"] = .mada }

    let requested = names.compactMap { known[$0.lowercased().trimmingCharacters(in: .whitespaces)] }
    // An unrecognised string from config must not be able to poison
    // canMakePayments, so keep only networks this OS actually supports.
    let available = Set(PKPaymentRequest.availableNetworks())
    let usable = requested.filter { available.contains($0) }
    return usable.isEmpty ? [.visa, .masterCard] : usable
  }

  static func build(args: [String: Any], merchantId: String) -> PKPaymentRequest? {
    guard let total = decimalAmount(args) else { return nil }

    let request = PKPaymentRequest()
    request.merchantIdentifier = merchantId
    request.countryCode = (args["applePayCountryCode"] as? String) ?? "AE"
    request.currencyCode = (args["currency"] as? String) ?? "AED"
    // Required by Apple for card payments. capabilityCredit/capabilityDebit are
    // restrictions, not features — we want both.
    request.merchantCapabilities = [.capability3DS]
    request.supportedNetworks = networks(from: args["applePayNetworks"] as? [String])

    let label = (args["merchantName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Hub Market"
    request.paymentSummaryItems = [
      PKPaymentSummaryItem(label: label, amount: total, type: .final)
    ]
    return request
  }

  /// NEVER `NSDecimalNumber(value: Double)`.
  ///
  /// `amount` crosses the channel as a Dart double, and 199.00 round-trips
  /// through binary floating point as 199.00000000000003 — which the Apple Pay
  /// sheet would both DISPLAY and CHARGE. Dart therefore also sends
  /// `amountString`, a fixed 2-decimal string, and that is authoritative;
  /// the double is only a fallback and is formatted before conversion.
  static func decimalAmount(_ args: [String: Any]) -> NSDecimalNumber? {
    if let text = args["amountString"] as? String, !text.isEmpty {
      let value = NSDecimalNumber(string: text, locale: Locale(identifier: "en_US_POSIX"))
      if value != NSDecimalNumber.notANumber { return value }
    }
    guard let double = (args["amount"] as? NSNumber)?.doubleValue else { return nil }
    return NSDecimalNumber(
      string: String(format: "%.2f", double), locale: Locale(identifier: "en_US_POSIX"))
  }

  /// Whether this device can actually pay: an Apple-Pay-capable device with a
  /// provisioned card on one of the accepted networks.
  ///
  /// `canMakePayments(usingNetworks:capabilities:)` rather than the bare
  /// `canMakePayments()`, which is true on any capable device even with an empty
  /// Wallet — offering a row that dead-ends at the sheet is worse than hiding it.
  /// Synchronous and cheap, so it is safe to call while building the method list.
  static func canUseApplePay(_ args: [String: Any]) -> Bool {
    #if canImport(NISdk)
      guard let merchantId = args["applePayMerchantId"] as? String, !merchantId.isEmpty
      else { return false }
      return PKPaymentAuthorizationController.canMakePayments(
        usingNetworks: networks(from: args["applePayNetworks"] as? [String]),
        capabilities: .capability3DS)
    #else
      // Without the SDK the payment could never complete, so never offer it.
      return false
    #endif
  }
}

#if canImport(NISdk)
  /// One Apple Pay attempt.
  ///
  /// Subclasses [NGeniusSession] so the entire `PaymentStatus` → canonical-status
  /// mapping and the fulfil-exactly-once guard are shared with the card path —
  /// there is one status mapping in this module, and it cannot drift. Apple Pay
  /// authorizations go through the same 3DS/authorization callbacks, so the
  /// inherited `AUTH_FAILED` / `THREE_DS_FAILURE` handling applies verbatim.
  ///
  /// Only the `ApplePayDelegate` conformance is new.
  final class ApplePaySession: NGeniusSession, ApplePayDelegate {
    /// The PassKit sheet is up and NISdk is about to authorize. Nothing to do —
    /// the outcome still arrives through `paymentDidComplete(with:)`.
    func applePayProcessBegan() {}
  }
#endif
