import 'package:flutter/foundation.dart';

import 'money.dart';
import 'product_detail.dart';

/// How the shopper picks an option's selections (core `BundleItem.type`).
enum BundleOptionType {
  select,
  radio,
  checkbox,
  multi;

  /// Checkbox and multi-select options take several selections at once.
  bool get allowsMany => this == checkbox || this == multi;

  static BundleOptionType parse(Object? value) => switch (value) {
    'radio' => radio,
    'checkbox' => checkbox,
    'multi' => multi,
    _ => select,
  };
}

/// One variant of a configurable bundle child, with both of its prices.
@immutable
class BundleVariant {
  const BundleVariant({
    required this.sku,
    required this.attributes,
    this.regularPrice,
    this.finalPrice,
    this.inStock = true,
    this.imageUrl,
  });

  final String sku;

  /// `attribute_code` → `value_index`.
  final Map<String, int> attributes;
  final Money? regularPrice;
  final Money? finalPrice;
  final bool inStock;
  final String? imageUrl;
}

/// The product a bundle selection puts in the package.
@immutable
class BundleChild {
  const BundleChild({
    required this.sku,
    required this.name,
    this.urlKey,
    this.imageUrl,
    this.inStock = true,
    this.regularPrice,
    this.finalPrice,
    this.options = const <ConfigurableOption>[],
    this.variants = const <BundleVariant>[],
  });

  final String sku;
  final String name;
  final String? urlKey;
  final String? imageUrl;
  final bool inStock;

  /// The child's own prices; for a configurable child, its cheapest variant.
  final Money? regularPrice;
  final Money? finalPrice;

  /// A configurable child's attributes (size, colour), which the shopper
  /// picks on the bundle page.
  final List<ConfigurableOption> options;
  final List<BundleVariant> variants;

  bool get isConfigurable => options.isNotEmpty;

  /// The variant [attributes] (`attribute_code` → `value_index`) pick, or null
  /// until every attribute is chosen.
  BundleVariant? variantFor(Map<String, int> attributes) {
    if (!isConfigurable || attributes.length < options.length) return null;
    for (final variant in variants) {
      final matches = options.every(
        (o) =>
            variant.attributes[o.attributeCode] == attributes[o.attributeCode],
      );
      if (matches) return variant;
    }
    return null;
  }

  /// The chosen values' uids (`ConfigurableProductOptionsValues.uid`), one per
  /// attribute in attribute order; null until every attribute is chosen.
  List<String>? optionUidsFor(Map<String, int> attributes) {
    final uids = <String>[];
    for (final option in options) {
      final index = attributes[option.attributeCode];
      final value = option.values
          .where((v) => v.valueIndex == index && (v.uid ?? '').isNotEmpty)
          .firstOrNull;
      if (value == null) return null;
      uids.add(value.uid!);
    }
    return uids;
  }
}

/// One selection of a bundle option (core `BundleItemOption`).
@immutable
class BundleSelection {
  const BundleSelection({
    required this.uid,
    required this.label,
    this.quantity = 1,
    this.canChangeQuantity = false,
    this.isDefault = false,
    this.position = 0,
    this.price,
    this.priceType,
    this.child,
  });

  /// `BundleItemOption.uid` — `selection_uid` of `hmAddBundleToCart`.
  final String uid;
  final String label;

  /// The quantity the bundle puts in by default.
  final double quantity;

  /// Whether the shopper may change [quantity].
  final bool canChangeQuantity;
  final bool isDefault;
  final int position;

  /// A fixed-price bundle's price for this selection (`FIXED`: an amount,
  /// `PERCENT`: a share of the bundle's own price); unused by dynamic ones.
  final double? price;
  final String? priceType;

  final BundleChild? child;

  String get name => child?.name ?? label;
  bool get inStock => child?.inStock ?? true;
}

/// One option of a bundle (core `BundleItem`): an item of the package, with
/// the selections it can be filled with.
@immutable
class BundleOption {
  const BundleOption({
    required this.uid,
    required this.title,
    required this.selections,
    this.required = true,
    this.type = BundleOptionType.select,
    this.position = 0,
  });

  final String uid;
  final String title;
  final bool required;
  final BundleOptionType type;
  final int position;
  final List<BundleSelection> selections;
}

/// A bundle — core `bundle`, or `new_bundle` answering as one with HubApp —
/// as the bundle page (Figma 14b) builds and prices its package.
@immutable
class BundleProduct {
  const BundleProduct({
    required this.options,
    this.dynamicPrice = true,
    this.minRegular,
    this.minFinal,
    this.maxRegular,
    this.maxFinal,
  });

  /// In the store's order.
  final List<BundleOption> options;

  /// Priced from its children (dynamic), or from its own price plus fixed
  /// selection prices.
  final bool dynamicPrice;

  /// The server's price range: the cheapest package at regular and at final
  /// prices, and the dearest.
  final Money? minRegular;
  final Money? minFinal;
  final Money? maxRegular;
  final Money? maxFinal;

  /// One price for every package.
  bool get hasSinglePrice =>
      minFinal != null && maxFinal != null && minFinal == maxFinal;
}
