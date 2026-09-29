import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../util/launch.dart';
import 'hub_back_button.dart';

/// Arguments for [WebViewScreen] — the live-site [url] to load and the [title]
/// shown in the app bar. Passed via `GoRouter` `state.extra`.
class WebViewArgs {
  const WebViewArgs({required this.url, required this.title});
  final String url;
  final String title;
}

/// In-app browser for store CMS pages (About, FAQs, Shipping, Returns, Privacy,
/// Terms) on the active store's live site. Keeps the user inside the app with a
/// branded chrome, a progress bar, an error/retry state, and an
/// "open in browser" escape hatch. The loaded page owns its own LTR/RTL — only
/// the surrounding chrome follows the app's [Directionality].
/// Last two labels of a host, so `uae-en.hub-market.magento2.click` and `www.hub-market.magento2.click` both
/// reduce to `hub-market.magento2.click`. Deliberately naive about multi-part public suffixes
/// (`co.uk`): it only ever guards against wandering off our own site, and is
/// not a security boundary.
String registrableDomain(String host) {
  final labels = host.toLowerCase().split('.');
  if (labels.length <= 2) return host.toLowerCase();
  return labels.sublist(labels.length - 2).join('.');
}

/// Whether a navigation should stay inside the in-app browser.
///
/// Without this the WebView is an unrestricted browser: a CMS page can link
/// anywhere and the user follows it under our app bar. That's a poor
/// experience, and to Apple it is an app with "unrestricted web access", which
/// forces a 17+ age rating (docs/appstore/app-information.md).
///
/// Sub-frame requests always pass: embedded maps and video players inside a CMS
/// page are not the user navigating away, and blocking them renders the page
/// broken.
bool staysInApp({
  required String url,
  required bool isMainFrame,
  required String allowedDomain,
}) {
  if (!isMainFrame) return true;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  // mailto:, tel: and app schemes belong to the platform, not this WebView.
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  return registrableDomain(uri.host) == allowedDomain;
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key, required this.args});

  final WebViewArgs args;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _hasError = false;

  /// URL that produced the current error, if any. Android fires
  /// `onHttpError`/`onWebResourceError` *before* `onPageStarted` for the same
  /// load, so `onPageStarted` must not blindly clear the error — it only clears
  /// when a genuinely different URL starts loading.
  String? _erroredUrl;

  /// Registrable domain of the page we were asked to open (e.g. `hub-market.magento2.click`).
  /// Navigation is confined to this domain — see [_shouldNavigate].
  late final String _allowedDomain = registrableDomain(
    Uri.tryParse(widget.args.url)?.host ?? '',
  );

  /// Confines the in-app browser to the store's own domain. Off-domain links
  /// and non-http schemes hand off to the platform browser instead.
  Future<NavigationDecision> _shouldNavigate(NavigationRequest request) async {
    if (staysInApp(
      url: request.url,
      isMainFrame: request.isMainFrame,
      allowedDomain: _allowedDomain,
    )) {
      return NavigationDecision.navigate;
    }
    final uri = Uri.tryParse(request.url);
    if (uri != null) await launchExternalUri(uri);
    return NavigationDecision.prevent;
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _shouldNavigate,
          onProgress: (p) => setState(() => _progress = p),
          onPageStarted: (url) => setState(() {
            if (_erroredUrl != url) _hasError = false;
            _progress = 0;
          }),
          onPageFinished: (_) => setState(() => _progress = 100),
          // Only the main document failing is a hard error; sub-resource
          // failures (an image, a tracker blocked by the WAF) are ignored so a
          // readable page isn't hidden behind the error state.
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              _erroredUrl = error.url;
              setState(() => _hasError = true);
            }
          },
          // A 4xx/5xx on the main document (e.g. a CMS page missing on the AR
          // store) still "loads" a body — the site's own 404. Show our error
          // state instead. This SDK's WebResourceRequest has no isForMainFrame,
          // so we treat it as the main document only when the failing request's
          // path matches the page we asked for — a sub-resource 404 (tracking
          // pixel, image) has a different path and is ignored.
          onHttpError: (error) {
            final code = error.response?.statusCode ?? 0;
            final failed = error.request?.uri ?? error.response?.uri;
            if (code >= 400 &&
                failed != null &&
                failed.path == Uri.parse(widget.args.url).path) {
              _erroredUrl = failed.toString();
              setState(() => _hasError = true);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.args.url));
  }

  void _reload() {
    _erroredUrl = null;
    setState(() => _hasError = false);
    _controller.loadRequest(Uri.parse(widget.args.url));
  }

  Future<void> _openExternally() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    if (!await launchExternalUri(Uri.parse(widget.args.url))) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loading = _progress < 100 && !_hasError;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: const HubBackButton(),
        title: Text(
          widget.args.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new, size: 20),
            tooltip: l10n.webviewOpenInBrowser,
            onPressed: _openExternally,
          ),
        ],
        bottom: loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress / 100,
                  minHeight: 2,
                  backgroundColor: AppColors.surfaceMuted,
                ),
              )
            : null,
      ),
      body: _hasError
          ? _ErrorState(onRetry: _reload)
          : WebViewWidget(controller: _controller),
    );
  }
}

/// Shown when the main document fails to load (offline / edge returned HTML).
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 44, color: AppColors.inkFaint),
            const SizedBox(height: 16),
            Text(
              l10n.errorNetwork,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkMuted, height: 1.4),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(l10n.actionRetry),
            ),
          ],
        ),
      ),
    );
  }
}
