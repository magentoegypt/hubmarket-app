import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../graphql/graphql_client.dart';
import '../hubapp/hubapp_providers.dart';
import '../store/store_controller.dart';
import 'app_config.dart';

/// Store contact details — the single source of truth for the Help & FAQ
/// screen's contact channels.
///
/// Every channel is optional. A null field means the backend doesn't publish
/// it, and the screens leave that button or row out instead of showing a
/// placeholder — or another store's details. Where they come from:
///
/// * the Hub Market App settings (`hmAppConfig.contact`: WhatsApp, phone,
///   e-mail, service hours — Stores › Configuration › Hub Market App) when
///   that API is deployed;
/// * otherwise, and for a WhatsApp link those settings leave empty, the
///   `wa.me` link in the `hm_footer_customer` CMS block (the website footer's
///   "Customer" column), read through core `cmsBlocks`. CMS blocks are
///   store-scoped, so each language reads its own block;
/// * **website** — the storefront origin (the GraphQL endpoint's host).
///
/// Core `StoreConfig` has no business name / address fields; the app's first
/// client served them from a custom `magentoegypt_beauty_config` field that
/// this backend doesn't have.
class StoreContact {
  const StoreContact({
    required this.website,
    this.company,
    this.address,
    this.phone,
    this.phoneDisplay,
    this.email,
    this.hours = '',
    this.whatsapp,
  });

  final String? company;
  final String? address;

  /// E.164 number for `tel:` links.
  final String? phone;

  /// Human-formatted number for display.
  final String? phoneDisplay;
  final String? email;

  /// Business hours (admin text), empty when unset.
  final String hours;

  /// Full `https://wa.me/...` URL.
  final String? whatsapp;
  final String website;
}

/// The CMS block carrying the store's WhatsApp support link.
const String supportCmsBlockId = 'hm_footer_customer';

const String _supportBlockQuery = r'''
query StoreSupportBlock($identifiers: [String]) {
  cmsBlocks(identifiers: $identifiers) {
    items { identifier content }
  }
}
''';

/// HTML of [supportCmsBlockId] for the active store view; null when the block
/// is missing (Magento answers with an error) or the request fails. Refetches
/// on a store / language switch.
final _supportBlockHtmlProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final client = ref.watch(graphqlClientProvider);
  try {
    final result = await client.query(
      QueryOptions(
        document: gql(_supportBlockQuery),
        variables: const {
          'identifiers': [supportCmsBlockId],
        },
        fetchPolicy: FetchPolicy.networkOnly,
      ),
    );
    if (result.hasException) return null;
    final items =
        (result.data?['cmsBlocks'] as Map<String, dynamic>?)?['items']
            as List<dynamic>?;
    for (final item in items ?? const <dynamic>[]) {
      if (item is Map<String, dynamic> &&
          item['identifier'] == supportCmsBlockId) {
        return item['content'] as String?;
      }
    }
    return null;
  } catch (_) {
    return null;
  }
});

final RegExp _whatsappLink = RegExp(
  r'https?://(?:api\.)?(?:wa\.me/|whatsapp\.com/send/?\?phone=)\+?(\d{6,15})',
  caseSensitive: false,
);

/// The first WhatsApp chat link in [html], normalised to
/// `https://wa.me/<digits>`, or null when there is none.
String? whatsappLinkFromHtml(String? html) {
  if (html == null || html.isEmpty) return null;
  final match = _whatsappLink.firstMatch(html);
  return match == null ? null : 'https://wa.me/${match.group(1)}';
}

/// The store's published contact channels (see [StoreContact]). Until a
/// source loads — or when none has a link — WhatsApp is null too, so the
/// screens simply show fewer channels.
final storeContactProvider = Provider.autoDispose<StoreContact>((ref) {
  final contact = ref.watch(hmAppConfigProvider)?.contact;
  // The footer block is only read when the settings have no WhatsApp link.
  final whatsapp =
      contact?.whatsappUrl ??
      whatsappLinkFromHtml(ref.watch(_supportBlockHtmlProvider).valueOrNull);
  return StoreContact(
    website: Uri.parse(ref.watch(appConfigProvider).graphqlEndpoint).origin,
    whatsapp: whatsapp,
    phone: contact?.phone,
    phoneDisplay: contact?.phone,
    email: contact?.email,
    hours: contact?.hours ?? '',
  );
});
