/// A catalogue category (menu tree node / category landing).
class Category {
  const Category({
    required this.uid,
    required this.name,
    required this.urlKey,
    this.image,
    this.productCount = 0,
    this.includeInMenu = true,
    this.children = const <Category>[],
  });

  final String uid;
  final String name;
  final String urlKey;
  final String? image;
  final int productCount;

  /// Whether Magento flags this category for navigation surfaces.
  final bool includeInMenu;
  final List<Category> children;
}
