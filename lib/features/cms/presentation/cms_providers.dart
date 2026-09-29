import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../data/cms_repository.dart';
import '../domain/cms_links.dart';
import '../domain/cms_page.dart';
import '../domain/faq.dart';

/// Which page a content screen shows: by CMS [identifier], or by storefront
/// [url] (a store-relative path, resolved through `route`).
typedef CmsPageRef = ({String? identifier, String? url});

/// The CMS page for [CmsPageRef]; null when the store has no such page.
/// Refetches on a store/language switch — pages are per store view.
final cmsPageProvider = FutureProvider.autoDispose
    .family<CmsPage?, CmsPageRef>((ref, page) {
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      final repo = ref.watch(cmsRepositoryProvider);
      final identifier = page.identifier?.trim() ?? '';
      if (identifier.isNotEmpty) return repo.fetchPage(identifier);
      final url = page.url?.trim() ?? '';
      if (url.isNotEmpty) return repo.fetchPageByUrl(url);
      return Future<CmsPage?>.value();
    });

/// The website footer's legal links (Privacy / Terms / Cookies) from the CMS
/// block `hm_footer_legal`, labelled and ordered as the admin wrote them.
/// Empty — the rows simply don't show — when the block is missing or can't
/// be read.
final legalLinksProvider = FutureProvider.autoDispose<List<CmsLink>>((
  ref,
) async {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  try {
    final html = await ref
        .watch(cmsRepositoryProvider)
        .fetchBlock(StorePages.legalLinksBlock);
    return html == null ? const <CmsLink>[] : linksFromHtml(html);
  } on Object {
    return const <CmsLink>[];
  }
});

/// The Help centre FAQ from the CMS block `hm_app_faq` (see [FaqDocument]),
/// or null when the block is missing, empty or unreadable — the Help centre
/// then shows the FAQ bundled with the app.
final cmsFaqProvider = FutureProvider.autoDispose<List<FaqTopic>?>((
  ref,
) async {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  try {
    final html = await ref
        .watch(cmsRepositoryProvider)
        .fetchBlock(StorePages.faqBlock);
    if (html == null) return null;
    final topics = FaqDocument.parse(html);
    return topics.isEmpty ? null : topics;
  } on Object {
    return null;
  }
});
