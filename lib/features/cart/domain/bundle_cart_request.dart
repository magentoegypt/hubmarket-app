import 'package:flutter/foundation.dart';

/// One chosen bundle selection, as `hmAddBundleToCart` takes it
/// (`HmBundleSelectionInput`).
@immutable
class BundleSelectionInput {
  const BundleSelectionInput({
    required this.selectionUid,
    this.quantity,
    this.configurableOptionUids = const <String>[],
  });

  /// `BundleItemOption.uid`.
  final String selectionUid;

  /// Sent only when the shopper may change the selection's quantity.
  final double? quantity;

  /// For a configurable selection: the chosen
  /// `ConfigurableProductOptionsValues.uid` of each of its attributes.
  final List<String> configurableOptionUids;

  @override
  bool operator ==(Object other) =>
      other is BundleSelectionInput &&
      other.selectionUid == selectionUid &&
      other.quantity == quantity &&
      listEquals(other.configurableOptionUids, configurableOptionUids);

  @override
  int get hashCode => Object.hash(
    selectionUid,
    quantity,
    Object.hashAll(configurableOptionUids),
  );

  @override
  String toString() =>
      'BundleSelectionInput($selectionUid, qty: $quantity, '
      'options: $configurableOptionUids)';
}

/// A bundle line to add (`HmAddBundleToCartInput` without the cart id, which
/// the cart controller supplies).
@immutable
class BundleCartRequest {
  const BundleCartRequest({
    required this.sku,
    required this.selections,
    this.quantity = 1,
  });

  /// The bundle's (or `new_bundle`'s) SKU.
  final String sku;

  /// How many bundles.
  final double quantity;

  /// One per chosen selection.
  final List<BundleSelectionInput> selections;

  @override
  bool operator ==(Object other) =>
      other is BundleCartRequest &&
      other.sku == sku &&
      other.quantity == quantity &&
      listEquals(other.selections, selections);

  @override
  int get hashCode => Object.hash(sku, quantity, Object.hashAll(selections));

  @override
  String toString() => 'BundleCartRequest($sku x$quantity, $selections)';
}
