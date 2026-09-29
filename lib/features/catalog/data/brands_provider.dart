import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';
import '../../../core/store/store_controller.dart';
import '../domain/brand.dart';

const String _query = r'''
query Brands {
  brands {
    brand_id
    title
    url_key
    url
    image_url
    option_id
    position
  }
}
''';

/// Storefront brands (manufacturers) for the home "Explore Our Brands" rail,
/// sorted by position then title. Degrades to an empty list on error/absence so
/// the section simply hides.
final brandsProvider = FutureProvider.autoDispose<List<Brand>>((ref) async {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final client = ref.watch(graphqlClientProvider);
  try {
    final result = await client.query(
      QueryOptions(document: gql(_query), fetchPolicy: FetchPolicy.networkOnly),
    );
    if (result.hasException) return const <Brand>[];
    final list = result.data?['brands'] as List<dynamic>?;
    if (list == null) return const <Brand>[];
    final brands =
        list
            .whereType<Map<String, dynamic>>()
            .map(_parse)
            .where((b) => b.title.isNotEmpty)
            .toList()
          ..sort((a, b) {
            final byPos = a.position.compareTo(b.position);
            return byPos != 0 ? byPos : a.title.compareTo(b.title);
          });
    return brands;
  } catch (_) {
    return const <Brand>[];
  }
});

Brand _parse(Map<String, dynamic> j) => Brand(
  brandId: (j['brand_id'] as num?)?.toInt() ?? 0,
  title: (j['title'] as String?)?.trim() ?? '',
  urlKey: (j['url_key'] as String?)?.trim() ?? '',
  url: (j['url'] as String?)?.trim() ?? '',
  imageUrl: (j['image_url'] as String?)?.trim() ?? '',
  optionId: (j['option_id'] as num?)?.toInt(),
  position: (j['position'] as num?)?.toInt() ?? 0,
);
