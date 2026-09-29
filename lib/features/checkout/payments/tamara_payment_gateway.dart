import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../catalog/domain/money.dart';
import '../domain/payment_session.dart';
import 'payment_gateway.dart';

/// Tamara BNPL checkout.
///
/// Tamara ships neither a Flutter package (as Tabby does) nor a native SDK the
/// app uses (as N-Genius does). The Magento module creates the session
/// server-side and `paymentSession` hands over a hosted `web_url`, so this
/// renders that page and reads the result from the return to the store.
///
/// **The return page must be allowed to load.** Magento reconciles the payment
/// with Tamara synchronously while serving `…/success`, so intercepting that
/// navigation and closing early would report a success the store never
/// recorded. The WebView therefore follows the redirect and closes on
/// `onPageFinished`, not on `onNavigationRequest`.
///
/// Return URLs (backend, 2026-09-28):
/// `{base}tamara/payment/{ORDER_ENTITY_ID}/{success|cancel|failure}` — matched
/// on the **path segment**; Magento reads no query parameters, and anything
/// Tamara appends is ignored.
class TamaraPaymentGateway implements PaymentGateway {
  const TamaraPaymentGateway({required String host}) : storeHost = host;

  /// Host of the store's own base URL (e.g. `hub-market.magento2.click`) — where Tamara sends
  /// the customer when it is done.
  final String storeHost;

  @override
  Future<PaymentOutcome> present(
    BuildContext context,
    PaymentSession session, {
    Money? amount,
  }) async {
    final webUrl = session.webUrl;
    // A READY Tamara session always carries a web_url. Without one there is
    // nothing to present, and reporting failure sends the customer to
    // CompletePaymentScreen rather than showing a success they did not get.
    if (webUrl == null || webUrl.isEmpty) return PaymentOutcome.failed;
    if (storeHost.isEmpty) return PaymentOutcome.failed;

    final outcome = await Navigator.of(context).push<PaymentOutcome>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TamaraCheckout(
          webUrl: webUrl,
          storeHost: storeHost,
          // The resolver also publishes success_url / cancel_url /
          // failure_url. They are matched exactly when present; the path shape
          // below is the fallback if the keys ever stop being sent.
          knownReturns: {
            for (final key in const ['success_url', 'cancel_url', 'failure_url'])
              if ((session.additionalData[key] ?? '').isNotEmpty)
                key: session.additionalData[key]!,
          },
        ),
      ),
    );
    // Popped without a verdict — the system back gesture or the close button.
    // A dismissal is a cancellation, never a success.
    return outcome ?? PaymentOutcome.cancelled;
  }
}

/// Reads Tamara's verdict from a return URL.
///
/// Matches the **last path segment** of
/// `{base}tamara/payment/{ORDER_ENTITY_ID}/{success|cancel|failure}`. Query
/// parameters are deliberately ignored: Magento reads none of them, so
/// anything Tamara appends is noise, and matching on it would be matching on
/// something the store itself does not act upon.
///
/// Returns null when the URL is on the store's host but is not a Tamara return
/// — the caller keeps browsing rather than guessing.
@visibleForTesting
PaymentOutcome? classifyTamaraReturn(Uri uri) {
  final segments = uri.pathSegments
      .where((s) => s.isNotEmpty)
      .map((s) => s.toLowerCase())
      .toList();
  if (segments.length < 2) return null;
  // Guard on the route as well as the verdict, so an unrelated store page
  // ending in "success" cannot be read as a payment result.
  final onTamaraRoute = segments.contains('tamara') &&
      segments.contains('payment');
  if (!onTamaraRoute) return null;
  return switch (segments.last) {
    'success' => PaymentOutcome.success,
    'cancel' => PaymentOutcome.cancelled,
    'failure' => PaymentOutcome.failed,
    // `notification` is the server-to-server endpoint and never a customer
    // return; anything else is not a verdict either.
    _ => null,
  };
}

class _TamaraCheckout extends StatefulWidget {
  const _TamaraCheckout({
    required this.webUrl,
    required this.storeHost,
    required this.knownReturns,
  });

  final String webUrl;
  final String storeHost;

  /// `success_url` / `cancel_url` / `failure_url` from `additional_data`.
  final Map<String, String> knownReturns;

  @override
  State<_TamaraCheckout> createState() => _TamaraCheckoutState();
}

class _TamaraCheckoutState extends State<_TamaraCheckout> {
  late final WebViewController _controller;
  int _progress = 0;

  /// The verdict seen in a redirect, held until its page has actually loaded.
  PaymentOutcome? _pending;

  /// Guards the pop — a redirect chain can fire more than once.
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigate,
          onProgress: (p) => setState(() => _progress = p),
          onPageFinished: _onPageFinished,
          onWebResourceError: _onError,
        ),
      )
      ..loadRequest(Uri.parse(widget.webUrl));
  }

  /// Exact match against the URLs the resolver published, ignoring query.
  PaymentOutcome? _matchKnown(Uri uri) {
    for (final entry in widget.knownReturns.entries) {
      final known = Uri.tryParse(entry.value);
      if (known == null) continue;
      if (known.host == uri.host && known.path == uri.path) {
        return switch (entry.key) {
          'success_url' => PaymentOutcome.success,
          'cancel_url' => PaymentOutcome.cancelled,
          _ => PaymentOutcome.failed,
        };
      }
    }
    return null;
  }

  NavigationDecision _onNavigate(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    // Anything off the store's host is part of the payment: Tamara itself, a
    // bank's 3-D Secure step. Detecting the return by ARRIVING at the store
    // rather than by leaving Tamara is what keeps 3-D Secure from looking like
    // the end of the flow.
    if (uri == null || uri.host != widget.storeHost) {
      return NavigationDecision.navigate;
    }
    _pending = _matchKnown(uri) ?? classifyTamaraReturn(uri);
    // Allow it either way. On success Magento reconciles with Tamara while
    // serving this page, so closing here would report a payment the store
    // never recorded.
    return NavigationDecision.navigate;
  }

  void _onPageFinished(String url) {
    setState(() => _progress = 100);
    final outcome = _pending;
    if (outcome == null) return;
    // The return page has now loaded, so the reconciliation it performs has
    // run. Safe to close on the verdict.
    _finish(outcome);
  }

  void _onError(WebResourceError error) {
    // Only the return page failing matters. A success page that did not load
    // means reconciliation did not happen, so this must NOT report success —
    // the customer goes to CompletePaymentScreen, where the real state is
    // resolved rather than assumed.
    if (_pending == null) return;
    _finish(
      _pending == PaymentOutcome.success ? PaymentOutcome.failed : _pending!,
    );
  }

  void _finish(PaymentOutcome outcome) {
    if (_finished || !mounted) return;
    _finished = true;
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          // Closing mid-flow is a cancellation — and per the backend, closing
          // before the success page loads is exactly what must not be treated
          // as payment. The order stays placed and the customer lands on
          // CompletePaymentScreen.
          onPressed: () => _finish(PaymentOutcome.cancelled),
        ),
        title: const Text('Tamara'),
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
