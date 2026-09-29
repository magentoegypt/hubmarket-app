import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';
import '../../../core/store/store_controller.dart';
import '../../../core/util/media.dart';
import '../domain/blog_post.dart';

/// Latest posts for the home "Hub Market Journal" rail, from the Mirasvit blog
/// (`blogPosts`). This exact field set is the one the backend resolves — an
/// earlier query using `short_content` / `featured_list_image` 500'd; the live
/// contract uses `short_filtered_content` + `first_image` (already HTTPS).
const String _query = r'''
query HomeBlog {
  blogPosts(pageSize: 3) {
    items {
      post_id
      title
      post_url
      publish_time
      first_image
      short_filtered_content
    }
  }
}
''';

/// Home Journal posts, newest first. Degrades to an empty list on any error or
/// absence (the blog module may be undeployed or return no published posts) so
/// the section simply hides — never a broken or fabricated rail.
final blogPostsProvider = FutureProvider.autoDispose<List<BlogPost>>((
  ref,
) async {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final client = ref.watch(graphqlClientProvider);
  try {
    final result = await client.query(
      QueryOptions(document: gql(_query), fetchPolicy: FetchPolicy.networkOnly),
    );
    if (result.hasException) return const <BlogPost>[];
    final items =
        (result.data?['blogPosts'] as Map<String, dynamic>?)?['items']
            as List<dynamic>?;
    if (items == null) return const <BlogPost>[];
    return items
        .whereType<Map<String, dynamic>>()
        .map(_parse)
        .where((p) => p.title.isNotEmpty && p.url.isNotEmpty)
        .toList(growable: false);
  } catch (_) {
    return const <BlogPost>[];
  }
});

BlogPost _parse(Map<String, dynamic> j) {
  // `first_image` is already returned as HTTPS (no mixed content).
  final image = (j['first_image'] as String?)?.trim() ?? '';
  return BlogPost(
    id: (j['post_id'] as num?)?.toInt() ?? 0,
    title: (j['title'] as String?)?.trim() ?? '',
    url: (j['post_url'] as String?)?.trim() ?? '',
    imageUrl: httpsMediaUrl(image) ?? '',
    excerpt: _plainText((j['short_filtered_content'] as String?) ?? ''),
    publishTime: (j['publish_time'] as String?)?.trim() ?? '',
  );
}

/// Strips tags/entities from the blog `short_filtered_content` HTML into a
/// one-paragraph excerpt. Lightweight — the full article renders in the web view.
String _plainText(String html) {
  if (html.isEmpty) return '';
  final text = html
      // Drop <style>/<script> blocks entirely first — Page Builder prefixes the
      // excerpt with a <style> block whose CSS would otherwise leak as text.
      .replaceAll(
        RegExp(
          r'<(style|script)[^>]*>.*?</\1>',
          caseSensitive: false,
          dotAll: true,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text;
}
