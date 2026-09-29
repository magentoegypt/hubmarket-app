import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/util/launch.dart';
import '../../catalog/presentation/storefront_links.dart';
import '../domain/cms_links.dart';

/// Follows a link tapped inside CMS content.
///
/// `#anchor` stays on the page ([onAnchor]); everything else goes through
/// [openStorefrontUrl], so a same-site link opens the matching app screen
/// (product, category, brand, another CMS page — the in-app browser only for
/// pages the app has no screen for) and a foreign link, `mailto:` or `tel:`
/// leaves for the platform.
Future<void> openCmsHref(
  BuildContext context,
  WidgetRef ref,
  String href, {
  ValueChanged<String>? onAnchor,
}) async {
  final value = href.trim();
  if (value.isEmpty) return;
  if (value.startsWith('#')) {
    if (value.length > 1) onAnchor?.call(value.substring(1));
    return;
  }
  await openStorefrontUrl(context, ref, value);
}

/// Icon for a footer legal link, picked from its URL (as in Figma 27).
IconData legalLinkIcon(CmsLink link) {
  final url = link.url.toLowerCase();
  if (url.contains('privacy')) return Icons.shield_outlined;
  if (url.contains('cookie')) return Icons.language;
  return Icons.edit_outlined;
}

/// Opens a link known to point at a storefront CMS page (the footer's legal
/// links) straight in the native content page — no `urlResolver` round trip.
/// A foreign link goes to the platform instead.
void openStorePageLink(
  BuildContext context,
  WidgetRef ref,
  CmsLink link,
) {
  final uri = Uri.tryParse(link.url);
  if (uri == null) return;
  final scheme = uri.scheme.toLowerCase();
  final foreign =
      (scheme.isNotEmpty && scheme != 'http' && scheme != 'https') ||
      (uri.host.isNotEmpty && !isInternalStoreUrl(ref, link.url));
  if (foreign) {
    launchExternalUri(uri);
    return;
  }
  final path = storePathOf(link.url);
  if (path.isEmpty) {
    // The storefront root is the app's Home.
    context.go(AppRoutes.home);
    return;
  }
  context.push(AppRoutes.cmsPageByUrl(path, title: link.label));
}
