import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/hubapp/hubapp_models.dart';
import '../features/catalog/presentation/storefront_links.dart';
import 'routes.dart';

/// The native route for [link], or null when it has none (EXTERNAL, a type
/// newer than this build, or a link missing the uid/code its type needs) —
/// then [openHmLink] falls back to the storefront URL.
String? hmLinkRoute(HmLink link) {
  final code = link.code?.trim();
  final hasCode = code != null && code.isNotEmpty;
  return switch (link.type) {
    HmLinkType.category when (link.uid ?? '').isNotEmpty =>
      AppRoutes.category(link.uid!),
    HmLinkType.product when hasCode => AppRoutes.product(code),
    HmLinkType.cmsPage when hasCode => AppRoutes.cmsPageById(code),
    HmLinkType.store when hasCode => AppRoutes.store(code),
    HmLinkType.stores => AppRoutes.stores,
    HmLinkType.brand when hasCode => AppRoutes.brandPage(code),
    HmLinkType.brands => AppRoutes.brands,
    HmLinkType.bundles => AppRoutes.bundles,
    HmLinkType.deals => AppRoutes.deals,
    HmLinkType.search => AppRoutes.search,
    _ => null,
  };
}

/// Opens a Hub Market App link natively: every [HmLinkType] has its screen —
/// product, category, CMS page, brand(s), store(s), deals, bundles, search.
/// EXTERNAL links, and any link the app can't place, go through
/// [openStorefrontUrl] with [HmLink.url]: our own pages resolve in-app, a
/// foreign host opens in the browser.
///
/// [title] names the destination while it loads (a category's name, a CMS
/// page's title).
Future<void> openHmLink(
  BuildContext context,
  WidgetRef ref,
  HmLink link, {
  String? title,
}) async {
  final route = hmLinkRoute(link);
  if (route != null) {
    switch (link.type) {
      case HmLinkType.category:
        context.push(route, extra: title);
      case HmLinkType.cmsPage:
        context.push(AppRoutes.cmsPageById(link.code!.trim(), title: title));
      case HmLinkType.search:
        context.push(route, extra: link.code?.trim());
      default:
        context.push(route);
    }
    return;
  }
  if (link.url.trim().isEmpty) return;
  await openStorefrontUrl(context, ref, link.url, title: title);
}
