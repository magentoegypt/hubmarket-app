import 'aggregation.dart';
import 'category.dart';
import 'product.dart';

/// Attribute code of the category facet in `products.aggregations`.
const String kCategoryAggregationCode = 'category_uid';

/// A category holding some of a search's results — the type-ahead's "or in …"
/// links and category chips, and the results' Categories tab.
class SearchCategory {
  const SearchCategory({
    required this.uid,
    required this.name,
    required this.count,
    this.level = 0,
  });

  final String uid;
  final String name;

  /// How many of the search's products the category holds.
  final int count;

  /// Magento depth (2 = top level); 0 when unknown.
  final int level;
}

/// The categories a search's results fall into, best first.
///
/// The source is the `category_uid` aggregation, which lists every category
/// holding a match with its match count — including ones a shopper cannot
/// reach from the menu (Luma sample categories, the hidden "Bags" parent,
/// "All"). An option is kept only when it is known to be shown: a loaded hit
/// files it with `include_in_menu` set, or it is a menu entry of the app's
/// category [tree]. Anything else is dropped rather than guessed at.
///
/// Ordered by match count, the deeper (more specific) category first on a tie,
/// then by the aggregation's own order. [excludeUid] drops the category the
/// search is already scoped to.
List<SearchCategory> searchCategoriesFrom({
  required List<Aggregation> aggregations,
  required List<Product> products,
  List<Category> tree = const <Category>[],
  String? excludeUid,
}) {
  final facet = aggregations
      .where((a) => a.attributeCode == kCategoryAggregationCode)
      .firstOrNull;
  if (facet == null) return const <SearchCategory>[];

  final filed = <String, ProductCategoryRef>{};
  for (final product in products) {
    for (final category in product.categories) {
      filed.putIfAbsent(category.uid, () => category);
    }
  }
  final menuLevels = _menuLevels(tree);

  final ranked = <(SearchCategory, int)>[];
  for (final option in facet.options) {
    final uid = option.value;
    if (uid.isEmpty || uid == excludeUid || option.count <= 0) continue;
    final ref = filed[uid];
    final int level;
    if (ref != null) {
      if (!ref.inMenu) continue;
      level = ref.level;
    } else if (menuLevels[uid] case final int treeLevel) {
      level = treeLevel;
    } else {
      continue;
    }
    final name = option.label.trim().isNotEmpty
        ? option.label.trim()
        : (ref?.name ?? '');
    if (name.isEmpty) continue;
    ranked.add((
      SearchCategory(uid: uid, name: name, count: option.count, level: level),
      ranked.length,
    ));
  }
  // List.sort is not stable, so the aggregation order is the last tie-break.
  ranked.sort((a, b) {
    final byCount = b.$1.count.compareTo(a.$1.count);
    if (byCount != 0) return byCount;
    final byDepth = b.$1.level.compareTo(a.$1.level);
    return byDepth != 0 ? byDepth : a.$2.compareTo(b.$2);
  });
  return List.unmodifiable(ranked.map((entry) => entry.$1));
}

/// Menu entries of the category tree by uid, with their Magento level. The
/// tree's roots are the top level (2); a child switched out of the menu is
/// skipped along with everything under it.
Map<String, int> _menuLevels(List<Category> tree) {
  final levels = <String, int>{};
  void visit(List<Category> nodes, int level) {
    for (final node in nodes) {
      if (!node.includeInMenu || node.uid.isEmpty) continue;
      levels[node.uid] = level;
      visit(node.children, level + 1);
    }
  }

  visit(tree, 2);
  return levels;
}
