import 'aggregation.dart';
import 'product.dart';

/// A page of `products` results plus paging metadata and filter aggregations.
class ProductPage {
  const ProductPage({
    required this.items,
    required this.totalCount,
    required this.currentPage,
    required this.totalPages,
    this.aggregations = const <Aggregation>[],
  });

  final List<Product> items;
  final int totalCount;
  final int currentPage;
  final int totalPages;
  final List<Aggregation> aggregations;

  bool get hasMore => currentPage < totalPages;

  static const ProductPage empty = ProductPage(
    items: <Product>[],
    totalCount: 0,
    currentPage: 1,
    totalPages: 0,
  );
}
