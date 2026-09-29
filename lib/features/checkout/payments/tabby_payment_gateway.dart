import 'package:flutter/widgets.dart';
import 'package:tabby_flutter_inapp_sdk/tabby_flutter_inapp_sdk.dart';

import '../../catalog/domain/money.dart';
import '../domain/payment_session.dart';
import 'payment_gateway.dart';

/// Tabby BNPL checkout. Unlike N-Genius this needs no native module: Tabby
/// ships an official Flutter package that renders its hosted checkout in an
/// embedded WebView, so the whole gateway lives in Dart on both platforms.
///
/// The session is already created server-side by the Magento Tabby module and
/// handed to us by `paymentSession` as a `web_url`, so this does NOT call
/// `TabbySDK().setup()` / `createSession()`. `TabbyWebView` never touches
/// `TabbySDK`, so skipping setup avoids a network round-trip that could only
/// add a failure mode — and avoids needing the publishable key on this path.
class TabbyPaymentGateway implements PaymentGateway {
  const TabbyPaymentGateway();

  @override
  Future<PaymentOutcome> present(
    BuildContext context,
    PaymentSession session, {
    Money? amount,
  }) async {
    final webUrl = session.webUrl;
    // A ready Tabby session always carries a web_url; without one there is
    // nothing to present, and reporting failure routes the customer to
    // CompletePaymentScreen rather than showing a success they didn't get.
    if (webUrl == null || webUrl.isEmpty) return PaymentOutcome.failed;

    final result = await TabbyWebView.showWebViewAsync(
      context: context,
      webUrl: webUrl,
    );

    return _mapResult(result);
  }

  /// `null` means the sheet was dismissed before Tabby reported anything (the
  /// customer swiped it away or went back), which is a cancellation — not a
  /// rejection, and definitely not a success.
  PaymentOutcome _mapResult(WebViewResult? result) {
    switch (result) {
      case WebViewResult.authorized:
        return PaymentOutcome.success;
      case WebViewResult.rejected:
        // Tabby declining an eligible-looking customer mid-flow is a normal
        // path, not an error — the caller bounces back to method selection
        // with the other methods intact.
        return PaymentOutcome.rejected;
      case WebViewResult.expired:
        return PaymentOutcome.expired;
      case WebViewResult.close:
      case null:
        return PaymentOutcome.cancelled;
    }
  }
}
