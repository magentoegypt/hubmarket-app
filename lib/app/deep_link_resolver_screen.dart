import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/store/store_controller.dart';
import '../core/store/store_urls.dart';
import '../core/widgets/web_view_screen.dart';
import '../features/catalog/data/catalog_repository.dart';
import '../features/catalog/presentation/storefront_links.dart';
import '../features/cms/domain/cms_links.dart';
import '../l10n/l10n.dart';
import 'not_found_state.dart';
import 'routes.dart';
import 'theme/app_colors.dart';

/// Landing point for any location the route table can't match — in practice an
/// incoming Android App Link such as
/// `https://hub-market.magento2.click/uae-en/fragrance/6085010044712.html`.
///
/// The Android manifest claims `hub-market.magento2.click`, so the OS hands these URLs to
/// Flutter, but no `GoRoute` matches a storefront path. Without this screen
/// go_router renders its raw `GoException: no routes for location: …` page —
/// the bug reported in CL042-DEV10.
///
/// Resolution order:
///  1. an Arabic/English store segment (`/uae-ar/`) switches the app language,
///     so a shared Arabic link opens in Arabic;
///  2. a seller's page (`/shop/<code>/`) opens the native store page while
///     the Hub Market App's seller API is there; `urlResolver` maps the path
///     to a PRODUCT (PDP), CATEGORY (PLP) or CMS_PAGE (the native content
///     page);
///  3. anything else on our own domain (`shopbrand`, the blog) opens in the
///     in-app [WebViewScreen] rather than dead-ending;
///  4. only a foreign host or an unparseable URL falls through to the "page
///     isn't available" page (Figma S7, [NotFoundPage]). It deliberately does
///     **not** hand the URL back to the browser:
///     the app claims the domain, so that can bounce straight back here.
class DeepLinkResolverScreen extends ConsumerStatefulWidget {
  const DeepLinkResolverScreen({super.key, required this.uri});

  final Uri uri;

  @override
  ConsumerState<DeepLinkResolverScreen> createState() =>
      _DeepLinkResolverScreenState();
}

class _DeepLinkResolverScreenState
    extends ConsumerState<DeepLinkResolverScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    final url = widget.uri.toString();

    // A cold-start app link runs before `bootstrap`'s unawaited `loadStores()`
    // has landed on a fresh install, and every step below reads the view list:
    // which hosts are ours, which language the path segment belongs to, and
    // which `Store` header `urlResolver` runs under. Without this an Arabic
    // link opened in English on first launch.
    await ref.read(storeControllerProvider.notifier).ensureStoresLoaded();
    if (!mounted) return;

    if (widget.uri.host.isEmpty || !isInternalStoreUrl(ref, url)) {
      if (mounted) setState(() => _failed = true);
      return;
    }

    // A link carrying the other store view's path segment is a link in that
    // language. Switch first so `urlResolver` and the destination screen both
    // run under the right `Store` header.
    final locale = localeForStoreUrl(ref.read(storeControllerProvider), url);
    if (locale != null &&
        locale != ref.read(storeControllerProvider).activeLocale) {
      await ref.read(storeControllerProvider.notifier).switchLocale(locale);
      if (!mounted) return;
    }

    // The storefront root (`/`, `/uae-en`, `/uae-ar/`) is the home page, not
    // an entity — `urlResolver` has nothing to resolve, so send it to Home
    // rather than letting it fall through to a WebView of the home page.
    final segments = widget.uri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList();
    final afterStore = locale != null ? segments.skip(1) : segments;
    if (afterStore.isEmpty) {
      GoRouter.of(context).go(AppRoutes.home);
      return;
    }

    // A seller's page (`/en/shop/loly/`) has no `url_rewrite` either. With
    // the Hub Market App's seller API it opens the native store page (Figma
    // 13) — no round trip; without it, the page in the in-app browser, as
    // before.
    final sellerCode = sellerCodeOf(url);
    final storePath = sellerCode != null && await hubAppStoresReady(ref)
        ? (sellerCode.isEmpty ? AppRoutes.stores : AppRoutes.store(sellerCode))
        : null;
    if (!mounted) return;

    // A `shopbrand` path has no `url_rewrite`, so `urlResolver` can only
    // answer null for it. Map it to the app's own brand listing instead, and
    // skip the round trip entirely (CL042-DEV19/QA01).
    final isBrandUrl = shopbrandKey(url) != null;
    final brand = isBrandUrl ? await lookUpBrand(ref, url) : null;
    if (!mounted) return;

    final resolved = isBrandUrl || storePath != null
        ? null
        : await ref.read(catalogRepositoryProvider).resolveUrl(url);
    if (!mounted) return;

    // Grab the router and the strings up front: `go` below tears this
    // screen down, so `context` must not be touched after it.
    final router = GoRouter.of(context);
    final title = AppLocalizations.of(context).appTitle;

    final String path;
    Object? extra;
    if (storePath != null) {
      path = storePath;
    } else if (resolved != null &&
        resolved.type == 'PRODUCT' &&
        resolved.urlKey != null) {
      path = AppRoutes.product(resolved.urlKey!);
    } else if (resolved != null &&
        resolved.type == 'CATEGORY' &&
        resolved.uid.isNotEmpty) {
      path = AppRoutes.category(resolved.uid);
    } else if (resolved != null &&
        resolved.type == 'CMS_PAGE' &&
        storePathOf(url).isNotEmpty) {
      // A CMS page renders natively instead of in the in-app browser.
      path = AppRoutes.cmsPageByUrl(storePathOf(url));
    } else if (brand != null) {
      // A `shopbrand` link is a brand landing, not a catalogue entity, so
      // `urlResolver` returns null for it. Open the app's own brand listing —
      // the same destination a home banner CTA now reaches (CL042-DEV19/QA01).
      path = AppRoutes.brand;
      extra = brand;
    } else if (isBrandIndexUrl(url)) {
      path = AppRoutes.brands;
    } else {
      // Ours, but not a catalogue entity (CMS page, blog) — show the real page
      // in the in-app browser.
      path = AppRoutes.webview;
      extra = WebViewArgs(url: url, title: title);
    }

    // Seed Home underneath so Back from a deep link returns to the app
    // instead of exiting it.
    router.go(AppRoutes.home);
    // The seed must be committed before the destination goes on top. On a
    // COLD start the platform is still delivering the launch URI in this same
    // frame, and a push issued alongside it loses Home — verified on device:
    // warm links kept Home, cold ones exited to the launcher on Back.
    await WidgetsBinding.instance.endOfFrame;
    router.push(path, extra: extra);
  }

  @override
  Widget build(BuildContext context) {
    if (!_failed) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.brandPrimary),
        ),
      );
    }
    // Figma S7: the page for a link that leads nowhere.
    return const NotFoundPage();
  }
}
