import '../../../core/hubapp/hubapp.dart';

/// The lines one seller sells — one package when the order ships.
class SellerGroup<T> {
  const SellerGroup({required this.seller, required this.items});

  /// Null for lines the backend sent no seller for (it leaves `hm_seller` out
  /// for a seller that is not approved).
  final HmSellerSummary? seller;
  final List<T> items;
}

/// Groups [items] by seller (`hm_seller.code`, the contract's grouping key):
/// sellers in the order they first appear, lines in their own order, every
/// Hub Market line in one group.
///
/// Null when no line names a seller — the backend doesn't serve `hm_seller`
/// (HubApp not deployed), so the caller keeps today's flat list. Lines without
/// a seller next to lines with one go last, in a group of their own.
List<SellerGroup<T>>? groupBySeller<T>(
  Iterable<T> items,
  HmSellerSummary? Function(T item) sellerOf,
) {
  final groups = <String, ({HmSellerSummary seller, List<T> items})>{};
  final unknown = <T>[];
  for (final item in items) {
    final seller = sellerOf(item);
    if (seller == null) {
      unknown.add(item);
      continue;
    }
    groups
        .putIfAbsent(seller.groupKey, () => (seller: seller, items: <T>[]))
        .items
        .add(item);
  }
  if (groups.isEmpty) return null;
  return List.unmodifiable([
    for (final group in groups.values)
      SellerGroup<T>(
        seller: group.seller,
        items: List.unmodifiable(group.items),
      ),
    if (unknown.isNotEmpty)
      SellerGroup<T>(seller: null, items: List.unmodifiable(unknown)),
  ]);
}

/// Grouping and linking rules for a seller summary.
extension HmSellerSummaryMarketplace on HmSellerSummary {
  /// The key lines are grouped by: the seller code; one shared key for Hub
  /// Market (items of a deleted seller come back as Hub Market too); the name
  /// when a summary somehow has neither.
  String get groupKey =>
      isMarketplace ? '__hub_market__' : (code ?? link?.code ?? 'name:$name');

  /// The code the store page opens with (`hmStore(code)`), or null when there
  /// is no store page: Hub Market itself, or a summary without a code.
  String? get storeCode => isMarketplace ? null : (code ?? link?.code);
}
