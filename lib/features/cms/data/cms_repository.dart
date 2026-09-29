import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';
import '../domain/cms_page.dart';

/// Core Magento CMS reads: pages by identifier or by URL, and blocks.
abstract final class CmsQueries {
  static const String _pageFields = r'''
fragment CmsPageFields on CmsPage {
  identifier
  url_key
  title
  content_heading
  content
}
''';

  static String _withPageFields(String operation) =>
      '$operation\n$_pageFields';

  static final String pageByIdentifier = _withPageFields(r'''
query CmsPageByIdentifier($identifier: String!) {
  cmsPage(identifier: $identifier) { ...CmsPageFields }
}''');

  /// `route` resolves any storefront path; only a CMS page is rendered here.
  static final String pageByUrl = _withPageFields(r'''
query CmsPageByUrl($url: String!) {
  route(url: $url) {
    __typename
    ... on CmsPage { ...CmsPageFields }
  }
}''');

  static const String blocks = r'''
query CmsBlockContent($ids: [String]) {
  cmsBlocks(identifiers: $ids) {
    items { identifier content }
  }
}
''';
}

class CmsRepository {
  CmsRepository(this._client);

  final GraphQLClient _client;

  /// The page with [identifier] in the active store view, or null when the
  /// store has no such page (or it is disabled).
  Future<CmsPage?> fetchPage(String identifier) async {
    final data = await _query(CmsQueries.pageByIdentifier, {
      'identifier': identifier,
    });
    final page = data?['cmsPage'];
    return page is Map<String, dynamic> ? CmsPage.fromJson(page) : null;
  }

  /// The CMS page at the store-relative [url] (see `storePathOf`), or null
  /// when the path is unknown or belongs to something else (a product, a
  /// category).
  Future<CmsPage?> fetchPageByUrl(String url) async {
    final data = await _query(CmsQueries.pageByUrl, {'url': url});
    final route = data?['route'];
    if (route is! Map<String, dynamic> || route['__typename'] != 'CmsPage') {
      return null;
    }
    return CmsPage.fromJson(route);
  }

  /// The HTML of block [identifier], or null when the block doesn't exist or
  /// is disabled in the active store view.
  Future<String?> fetchBlock(String identifier) async {
    final data = await _query(CmsQueries.blocks, {
      'ids': [identifier],
    });
    final items =
        (data?['cmsBlocks'] as Map<String, dynamic>?)?['items']
            as List<dynamic>?;
    for (final item in items ?? const <dynamic>[]) {
      if (item is Map<String, dynamic> && item['identifier'] == identifier) {
        return item['content'] as String?;
      }
    }
    return null;
  }

  /// Runs a read. Magento answers a missing page or block with a
  /// `graphql-no-such-entity` error; that is "nothing there" (null), anything
  /// else is a [Failure].
  Future<Map<String, dynamic>?> _query(
    String document,
    Map<String, dynamic> variables,
  ) async {
    try {
      final result = await _client.query(
        QueryOptions(
          document: gql(document),
          variables: variables,
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      final exception = result.exception;
      if (exception != null) {
        final missing = exception.graphqlErrors.isNotEmpty &&
            exception.graphqlErrors.every(
              (e) => e.extensions?['category'] == 'graphql-no-such-entity',
            );
        if (missing) return null;
        throw mapOperationException(exception);
      }
      return result.data;
    } on Failure {
      rethrow;
    } catch (error) {
      throw Failure(FailureKind.unknown, detail: error.toString());
    }
  }
}

final cmsRepositoryProvider = Provider<CmsRepository>(
  (ref) => CmsRepository(ref.watch(graphqlClientProvider)),
);
