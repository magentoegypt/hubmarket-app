import 'package:flutter/foundation.dart';

import '../../cart/domain/bundle_cart_request.dart';
import 'bundle_product.dart';
import 'money.dart';
import 'product_detail.dart';

/// What still stops a package from going to the cart.
enum BundleIssueKind {
  /// A required option has no selection.
  needsSelection,

  /// A configurable selection has an attribute (size, colour) not chosen.
  needsAttribute,

  /// A chosen selection (or its chosen variant) is out of stock.
  outOfStock,
}

@immutable
class BundleIssue {
  const BundleIssue(this.kind, this.option, {this.selection, this.attribute});

  final BundleIssueKind kind;
  final BundleOption option;
  final BundleSelection? selection;
  final ConfigurableOption? attribute;

  @override
  String toString() =>
      'BundleIssue(${kind.name}, ${option.title}'
      '${selection == null ? '' : ', ${selection!.name}'}'
      '${attribute == null ? '' : ', ${attribute!.label}'})';
}

/// The package the shopper is putting together on the bundle page: the
/// selections chosen for each option, changed quantities and each
/// configurable child's attributes. Immutable; every change returns a copy.
@immutable
class BundleChoice {
  const BundleChoice._(this._chosen, this._quantities, this._attributes);

  /// The bundle's own starting package: each option's default selections; a
  /// required option with a single selection takes it; any other option
  /// without a default starts empty (a required one then asks the shopper).
  factory BundleChoice.initial(BundleProduct bundle) {
    final chosen = <String, List<String>>{};
    for (final option in bundle.options) {
      final defaults = [
        for (final selection in option.selections)
          if (selection.isDefault) selection.uid,
      ];
      final picks = defaults.isNotEmpty
          ? (option.type.allowsMany ? defaults : [defaults.first])
          : (option.required && option.selections.length == 1
                ? [option.selections.single.uid]
                : const <String>[]);
      if (picks.isNotEmpty) chosen[option.uid] = List.unmodifiable(picks);
    }
    return BundleChoice._(Map.unmodifiable(chosen), const {}, const {});
  }

  /// Option uid → chosen selection uids, in the order they were chosen.
  final Map<String, List<String>> _chosen;

  /// Selection uid → quantity, for quantities the shopper changed.
  final Map<String, double> _quantities;

  /// Selection uid → `attribute_code` → `value_index`.
  final Map<String, Map<String, int>> _attributes;

  /// [option]'s chosen selections, in the store's order.
  List<BundleSelection> chosenIn(BundleOption option) {
    final uids = _chosen[option.uid] ?? const <String>[];
    return [
      for (final selection in option.selections)
        if (uids.contains(selection.uid)) selection,
    ];
  }

  bool isChosen(BundleOption option, BundleSelection selection) =>
      _chosen[option.uid]?.contains(selection.uid) ?? false;

  double quantityOf(BundleSelection selection) =>
      _quantities[selection.uid] ?? selection.quantity;

  Map<String, int> attributesOf(BundleSelection selection) =>
      _attributes[selection.uid] ?? const <String, int>{};

  /// The variant a configurable selection's chosen attributes pick.
  BundleVariant? variantOf(BundleSelection selection) =>
      selection.child?.variantFor(attributesOf(selection));

  /// Puts [selection] in [option]: it replaces the current one of a
  /// single-choice option and joins the others in a multi-choice one.
  BundleChoice choose(BundleOption option, BundleSelection selection) {
    final current = _chosen[option.uid] ?? const <String>[];
    if (current.contains(selection.uid) && !option.type.allowsMany) {
      return this;
    }
    final next = option.type.allowsMany
        ? [...current.where((uid) => uid != selection.uid), selection.uid]
        : [selection.uid];
    return _withChosen(option, next);
  }

  /// Takes [selection] out of [option] (multi-choice options, and optional
  /// single-choice ones).
  BundleChoice remove(BundleOption option, BundleSelection selection) =>
      _withChosen(option, [
        for (final uid in _chosen[option.uid] ?? const <String>[])
          if (uid != selection.uid) uid,
      ]);

  /// A multi-choice option's checkbox: in if out, out if in.
  BundleChoice toggle(BundleOption option, BundleSelection selection) =>
      isChosen(option, selection)
      ? remove(option, selection)
      : choose(option, selection);

  BundleChoice withQuantity(BundleSelection selection, double quantity) {
    if (!selection.canChangeQuantity || quantity < 1) return this;
    return BundleChoice._(
      _chosen,
      Map.unmodifiable({..._quantities, selection.uid: quantity}),
      _attributes,
    );
  }

  BundleChoice withAttribute(
    BundleSelection selection,
    String attributeCode,
    int valueIndex,
  ) => BundleChoice._(
    _chosen,
    _quantities,
    Map.unmodifiable({
      ..._attributes,
      selection.uid: Map<String, int>.unmodifiable({
        ...attributesOf(selection),
        attributeCode: valueIndex,
      }),
    }),
  );

  BundleChoice _withChosen(BundleOption option, List<String> uids) {
    final chosen = Map<String, List<String>>.of(_chosen);
    if (uids.isEmpty) {
      chosen.remove(option.uid);
    } else {
      chosen[option.uid] = List.unmodifiable(uids);
    }
    return BundleChoice._(Map.unmodifiable(chosen), _quantities, _attributes);
  }

  /// What still stops the package from going to the cart, in option order.
  List<BundleIssue> issues(BundleProduct bundle) {
    final issues = <BundleIssue>[];
    for (final option in bundle.options) {
      final chosen = chosenIn(option);
      if (chosen.isEmpty && option.required) {
        issues.add(BundleIssue(BundleIssueKind.needsSelection, option));
      }
      for (final selection in chosen) {
        final child = selection.child;
        if (child == null) continue;
        if (!child.inStock) {
          issues.add(
            BundleIssue(
              BundleIssueKind.outOfStock,
              option,
              selection: selection,
            ),
          );
          continue;
        }
        if (!child.isConfigurable) continue;
        final attributes = attributesOf(selection);
        final missing = child.options
            .where((a) => !attributes.containsKey(a.attributeCode))
            .firstOrNull;
        if (missing != null) {
          issues.add(
            BundleIssue(
              BundleIssueKind.needsAttribute,
              option,
              selection: selection,
              attribute: missing,
            ),
          );
        } else if (variantOf(selection)?.inStock == false) {
          issues.add(
            BundleIssue(
              BundleIssueKind.outOfStock,
              option,
              selection: selection,
            ),
          );
        }
      }
    }
    return issues;
  }

  /// The `hmAddBundleToCart` request for [quantity] of this package: one
  /// entry per chosen selection, in option order; the quantity only where the
  /// shopper may set it; a configurable selection's chosen value uids.
  BundleCartRequest toRequest(
    String sku,
    BundleProduct bundle, {
    double quantity = 1,
  }) => BundleCartRequest(
    sku: sku,
    quantity: quantity,
    selections: [
      for (final option in bundle.options)
        for (final selection in chosenIn(option))
          BundleSelectionInput(
            selectionUid: selection.uid,
            quantity: selection.canChangeQuantity
                ? quantityOf(selection)
                : null,
            configurableOptionUids:
                selection.child?.optionUidsFor(attributesOf(selection)) ??
                const <String>[],
          ),
    ],
  );

  @override
  bool operator ==(Object other) =>
      other is BundleChoice &&
      mapEquals(_quantities, other._quantities) &&
      _sameLists(_chosen, other._chosen) &&
      _sameMaps(_attributes, other._attributes);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      _chosen.entries.map((e) => Object.hash(e.key, Object.hashAll(e.value))),
    ),
    Object.hashAllUnordered(_quantities.entries.map((e) => e.key)),
    Object.hashAllUnordered(_attributes.keys),
  );

  static bool _sameLists(
    Map<String, List<String>> a,
    Map<String, List<String>> b,
  ) =>
      a.length == b.length &&
      a.entries.every((e) => listEquals(e.value, b[e.key]));

  static bool _sameMaps(
    Map<String, Map<String, int>> a,
    Map<String, Map<String, int>> b,
  ) =>
      a.length == b.length &&
      a.entries.every((e) => mapEquals(e.value, b[e.key]));
}

/// A package's price as the bundle page shows it (Figma 14b "Package
/// summary").
@immutable
class BundleQuote {
  const BundleQuote({this.regular, this.total, this.exact = false});

  /// The chosen items at their regular prices ("Regular price").
  final Money? regular;

  /// What the package costs. Null when the package isn't complete yet or the
  /// app can't price it (a fixed-price bundle's other packages); the page
  /// then shows the bundle's "from" price.
  final Money? total;

  /// [total] is the server's own price for this package — the cheapest one,
  /// which `price_range` prices. Otherwise it is worked out from the
  /// children's prices, and the cart shows the final figure.
  final bool exact;

  /// "Bundle saving" / "You save": [regular] − [total] when there is one.
  Money? get saving {
    final r = regular;
    final t = total;
    if (r == null || t == null) return null;
    final amount = _round(r.amount - t.amount);
    return amount >= 0.01 ? Money(amount: amount, currency: t.currency) : null;
  }

  /// The saving as a rounded share of [regular]; null without a saving.
  int? get savingPercent {
    final s = saving;
    final r = regular;
    if (s == null || r == null || r.amount <= 0) return null;
    final percent = (s.amount * 100 / r.amount).round();
    return percent > 0 ? percent : null;
  }

  /// Prices [choice] of [bundle].
  ///
  /// The server prices only the cheapest package (`price_range` minimum): a
  /// required option's cheapest selection each, default quantities. When the
  /// choice is that package, the quote is the server's ([exact]). Any other
  /// package of a dynamic bundle is its children's prices times the bundle's
  /// own discount — the share the server's cheapest package costs of its
  /// children's prices — as Magento prices a dynamic bundle; the cart
  /// confirms it. A fixed-price bundle's other packages aren't priced here.
  static BundleQuote of(BundleProduct bundle, BundleChoice choice) {
    // Half a package has no price: the page shows the bundle's "from" price
    // until every required option is filled.
    if (bundle.options.any((o) => o.required && choice.chosenIn(o).isEmpty)) {
      return const BundleQuote();
    }
    final chosen = [
      for (final option in bundle.options)
        for (final selection in choice.chosenIn(option)) (option, selection),
    ];
    final items = _sum([
      for (final (_, selection) in chosen)
        _times(
          _unitPrice(bundle, choice, selection, regular: false),
          choice.quantityOf(selection),
        ),
    ]);
    final itemsRegular = _sum([
      for (final (_, selection) in chosen)
        _times(
          _unitPrice(bundle, choice, selection, regular: true),
          choice.quantityOf(selection),
        ),
    ]);

    final cheapest = _cheapestPackage(bundle);
    final isCheapest =
        cheapest != null &&
        chosen.length == cheapest.length &&
        chosen.every(
          (pick) =>
              cheapest.contains(pick.$2) &&
              choice.quantityOf(pick.$2) == pick.$2.quantity &&
              _unitPrice(bundle, choice, pick.$2, regular: false) ==
                  _basePrice(bundle, pick.$2, regular: false),
        );
    if (isCheapest && bundle.minFinal != null) {
      return BundleQuote(
        regular: bundle.minRegular ?? itemsRegular,
        total: bundle.minFinal,
        exact: true,
      );
    }
    if (!bundle.dynamicPrice || items == null) {
      return BundleQuote(regular: itemsRegular);
    }
    final cheapestFinal = cheapest == null
        ? null
        : _sum([
            for (final selection in cheapest)
              _times(
                _basePrice(bundle, selection, regular: false),
                selection.quantity,
              ),
          ]);
    final minFinal = bundle.minFinal;
    var factor = 1.0;
    if (minFinal != null &&
        cheapestFinal != null &&
        cheapestFinal.amount > 0 &&
        minFinal.amount <= cheapestFinal.amount) {
      factor = minFinal.amount / cheapestFinal.amount;
    }
    return BundleQuote(
      regular: itemsRegular,
      total: Money(
        amount: _round(items.amount * factor),
        currency: items.currency,
      ),
    );
  }

  /// The selections of the cheapest package, as Magento prices a bundle's
  /// minimum: each required option's cheapest in-stock selection at its
  /// default quantity — or, when no option is required, the single cheapest
  /// selection. Null when a price is missing.
  static List<BundleSelection>? _cheapestPackage(BundleProduct bundle) {
    BundleSelection? cheapestOf(Iterable<BundleSelection> selections) {
      BundleSelection? best;
      double? bestPrice;
      for (final selection in selections.where((s) => s.inStock)) {
        final price = _times(
          _basePrice(bundle, selection, regular: false),
          selection.quantity,
        )?.amount;
        if (price == null) continue;
        if (bestPrice == null || price < bestPrice) {
          best = selection;
          bestPrice = price;
        }
      }
      return best;
    }

    final required = bundle.options.where((o) => o.required).toList();
    if (required.isEmpty) {
      final single = cheapestOf(bundle.options.expand((o) => o.selections));
      return single == null ? null : [single];
    }
    final picks = <BundleSelection>[];
    for (final option in required) {
      final pick = cheapestOf(option.selections);
      if (pick == null) return null;
      picks.add(pick);
    }
    return picks;
  }

  /// A selection's price for one, before any choice: the child's own price
  /// (dynamic bundles), or the selection's fixed price.
  static Money? _basePrice(
    BundleProduct bundle,
    BundleSelection selection, {
    required bool regular,
  }) {
    if (bundle.dynamicPrice) {
      final child = selection.child;
      return regular
          ? (child?.regularPrice ?? child?.finalPrice)
          : (child?.finalPrice ?? child?.regularPrice);
    }
    final price = selection.price;
    if (price == null || selection.priceType == 'PERCENT') return null;
    final currency =
        bundle.minFinal?.currency ?? bundle.minRegular?.currency ?? 'AED';
    return Money(amount: price, currency: currency);
  }

  /// [_basePrice], or the chosen variant's price for a configurable child.
  static Money? _unitPrice(
    BundleProduct bundle,
    BundleChoice choice,
    BundleSelection selection, {
    required bool regular,
  }) {
    final variant = bundle.dynamicPrice ? choice.variantOf(selection) : null;
    if (variant != null) {
      final price = regular
          ? (variant.regularPrice ?? variant.finalPrice)
          : (variant.finalPrice ?? variant.regularPrice);
      if (price != null) return price;
    }
    return _basePrice(bundle, selection, regular: regular);
  }

  static Money? _times(Money? price, double quantity) => price == null
      ? null
      : Money(
          amount: _round(price.amount * quantity),
          currency: price.currency,
        );

  /// Null when any is null (a package can't be priced from part of it).
  static Money? _sum(List<Money?> prices) {
    if (prices.isEmpty || prices.any((p) => p == null)) return null;
    return Money(
      amount: _round(prices.fold<double>(0, (sum, p) => sum + p!.amount)),
      currency: prices.first!.currency,
    );
  }

  static double _round(double value) => (value * 100).roundToDouble() / 100;
}
