import 'cms_document.dart';

/// A storefront CMS page (Content › Pages in Magento admin), rendered natively.
class CmsPage {
  CmsPage({
    required this.identifier,
    required this.title,
    required this.content,
    this.contentHeading = '',
    this.urlKey = '',
  });

  final String identifier;
  final String title;

  /// Raw page HTML, directives already resolved by Magento.
  final String content;
  final String contentHeading;

  /// The page's URL key — its path on the storefront, for sharing.
  final String urlKey;

  /// [content] as native blocks, parsed once.
  late final List<CmsBlock> blocks = CmsDocument.parse(content);

  /// App-bar title: the page title, else its content heading.
  String get displayTitle => title.trim().isNotEmpty
      ? title.trim()
      : contentHeading.trim();

  factory CmsPage.fromJson(Map<String, dynamic> json) => CmsPage(
    identifier: (json['identifier'] as String?) ?? '',
    title: (json['title'] as String?) ?? '',
    content: (json['content'] as String?) ?? '',
    contentHeading: (json['content_heading'] as String?) ?? '',
    urlKey: (json['url_key'] as String?) ?? '',
  );
}
