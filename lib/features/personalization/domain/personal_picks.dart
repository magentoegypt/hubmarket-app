import '../../catalog/domain/product.dart';

/// Picked For You for one shopper (`hmPickedForYou`).
class PersonalPicks {
  const PersonalPicks({required this.items, required this.personalized});

  /// Up to 16 products, best first.
  final List<Product> items;

  /// True: ranked from this shopper's own Algolia profile. False: no profile
  /// yet, the top-rated list the Home section already shows.
  final bool personalized;
}

/// How many Picked For You cards the Home draws at a time (Figma 07).
const int kPickedPageSize = 4;

/// The picks Refresh has reached: [pageSize] products of [pool] from
/// [offset] on, wrapping round the end so a page is always full while the
/// pool has enough. The whole pool when it fits one page.
List<Product> pickedPage(
  List<Product> pool,
  int offset, {
  int pageSize = kPickedPageSize,
}) {
  if (pool.length <= pageSize) return pool;
  final start = offset % pool.length;
  return [for (var i = 0; i < pageSize; i++) pool[(start + i) % pool.length]];
}

/// Where the next Refresh starts: a page further, round to the start after the
/// last one.
int nextPickedOffset(
  int offset,
  int poolLength, {
  int pageSize = kPickedPageSize,
}) => poolLength <= pageSize ? 0 : (offset + pageSize) % poolLength;
