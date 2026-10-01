import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/hubapp/hubapp.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../cart/domain/bundle_cart_request.dart';
import '../../../cart/presentation/cart_controller.dart';
import '../../../cart/presentation/widgets/added_to_cart_sheet.dart';
import '../../../marketplace/domain/seller_groups.dart';
import '../../../marketplace/presentation/seller_widgets.dart';
import '../../data/bundle_quote_repository.dart';
import '../../domain/bundle_choice.dart';
import '../../domain/bundle_product.dart';
import '../../domain/money.dart';
import '../../domain/product_detail.dart';
import '../widgets/product_gallery.dart';
import '../../../../core/widgets/hub_bottom_sheet.dart';
import '../../../../app/theme/hub_icons.dart';

/// Figma 14b — a bundle's own page (core `bundle`, or `new_bundle` with
/// HubApp): the package's items, one per option, each swappable for the
/// option's other selections and addable on its own; a configurable item's
/// size and colour; the package's price; and "Add bundle to cart", which
/// sends the whole package through `hmAddBundleToCart`.
///
/// The price of any complete package is the server's (`hmBundleQuote`, what
/// the cart will charge), asked [quoteDelay] after the last change; until it
/// answers — or where it can't — the page shows its own estimate and says the
/// cart has the final figure.
///
/// Shown only with HubApp (HubAppBundle); without it a bundle opens on the
/// plain product page, as today.
class BundleProductScreen extends ConsumerStatefulWidget {
  const BundleProductScreen({
    super.key,
    required this.product,
    required this.bundle,
    this.seller,
  });

  final ProductDetail product;
  final BundleProduct bundle;
  final HmSellerSummary? seller;

  /// How long the package must stay unchanged before the server prices it.
  static const Duration quoteDelay = Duration(milliseconds: 400);

  @override
  ConsumerState<BundleProductScreen> createState() =>
      _BundleProductScreenState();
}

/// Items the package card shows before "+N more items".
const int _collapsedRows = 3;

class _BundleProductScreenState extends ConsumerState<BundleProductScreen> {
  late BundleChoice _choice = BundleChoice.initial(widget.bundle);
  int _quantity = 1;
  bool _expanded = false;

  /// The package the server was last asked to price; the opening package is
  /// asked at once, later ones after [BundleProductScreen.quoteDelay].
  late BundleCartRequest? _quoted = _package();
  Timer? _quoteTimer;

  @override
  void didUpdateWidget(BundleProductScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Read again (a store switch): start from the new data's own package.
    if (!identical(oldWidget.bundle, widget.bundle)) {
      _choice = BundleChoice.initial(widget.bundle);
      _quoteTimer?.cancel();
      _quoted = _package();
    }
  }

  @override
  void dispose() {
    _quoteTimer?.cancel();
    super.dispose();
  }

  /// The package as the cart would get it, or null while it is incomplete.
  BundleCartRequest? _package() => _choice.issues(widget.bundle).isNotEmpty
      ? null
      : _choice.toRequest(
          widget.product.sku,
          widget.bundle,
          quantity: _quantity.toDouble(),
        );

  /// Asks the server for the new package's price once it settles.
  void _requote() {
    _quoteTimer?.cancel();
    _quoteTimer = Timer(BundleProductScreen.quoteDelay, () {
      if (mounted) setState(() => _quoted = _package());
    });
  }

  void _update(BundleChoice choice) {
    setState(() => _choice = choice);
    _requote();
  }

  void _setQuantity(int quantity) {
    setState(() => _quantity = quantity);
    _requote();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _issueText(AppLocalizations l10n, BundleIssue issue) =>
      switch (issue.kind) {
        BundleIssueKind.needsSelection => l10n.bundleNeedsSelection(
          issue.option.title,
        ),
        BundleIssueKind.needsAttribute => l10n.bundleNeedsAttribute(
          issue.attribute?.label ?? '',
          issue.selection?.name ?? '',
        ),
        BundleIssueKind.outOfStock => l10n.bundleOutOfStock(
          issue.selection?.name ?? issue.option.title,
        ),
      };

  Future<void> _addBundle(BundleQuote quote) async {
    final l10n = AppLocalizations.of(context);
    final issues = _choice.issues(widget.bundle);
    if (issues.isNotEmpty) {
      _snack(_issueText(l10n, issues.first));
      return;
    }
    final product = widget.product;
    try {
      await ref
          .read(cartControllerProvider.notifier)
          .addBundleToCart(
            _choice.toRequest(
              product.sku,
              widget.bundle,
              quantity: _quantity.toDouble(),
            ),
          );
      if (!mounted) return;
      await AddedToCartSheet.show(
        context,
        item: AddedItem(
          name: product.name,
          quantity: _quantity,
          imageUrl: product.gallery.isEmpty ? null : product.gallery.first,
          unitPrice: quote.total,
          options: [
            for (final option in widget.bundle.options)
              for (final selection in _choice.chosenIn(option)) selection.name,
          ],
        ),
        recommendations: product.alsoLike,
      );
    } on HubAppMissing {
      _snack(l10n.bundleUnavailable);
    } catch (error) {
      if (mounted) _snack(serverMessageOr(context, error, l10n.errorGeneric));
    }
  }

  Future<void> _addItemOnly(BundleSelection selection) async {
    final l10n = AppLocalizations.of(context);
    final child = selection.child;
    if (child == null) return;
    final attributes = _choice.attributesOf(selection);
    final uids = child.isConfigurable ? child.optionUidsFor(attributes) : null;
    if (child.isConfigurable && uids == null) {
      final missing = child.options.firstWhere(
        (o) => !attributes.containsKey(o.attributeCode),
      );
      _snack(l10n.bundleNeedsAttribute(missing.label, child.name));
      return;
    }
    final variant = _choice.variantOf(selection);
    try {
      await ref
          .read(cartControllerProvider.notifier)
          .addToCart(sku: child.sku, selectedOptionUids: uids ?? const []);
      if (!mounted) return;
      await AddedToCartSheet.show(
        context,
        item: AddedItem(
          name: child.name,
          quantity: 1,
          imageUrl: variant?.imageUrl ?? child.imageUrl,
          unitPrice: variant?.finalPrice ?? child.finalPrice,
          options: [
            for (final option in child.options)
              for (final value in option.values)
                if (value.valueIndex == attributes[option.attributeCode])
                  '${option.label}: ${value.label}',
          ],
        ),
      );
    } catch (error) {
      if (mounted) _snack(serverMessageOr(context, error, l10n.errorGeneric));
    }
  }

  Future<void> _swap(BundleOption option) => showHubBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _SwapSheet(
      bundle: widget.bundle,
      option: option,
      choice: _choice,
      onChanged: _update,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final product = widget.product;
    final bundle = widget.bundle;
    // The server's figure for the package on show; the page's own estimate
    // until it answers, or when it can't.
    final package = _package();
    final served = package != null && package == _quoted
        ? ref.watch(bundleQuoteProvider(package)).valueOrNull
        : null;
    final quote = served?.quote ?? BundleQuote.of(bundle, _choice);
    final refusal = served != null && !served.available ? served.message : null;
    final saving = quote.saving;
    final percent = quote.savingPercent;
    final busy = ref.watch(cartControllerProvider.select((s) => s.isMutating));
    final seller = widget.seller;
    final isEn = Localizations.localeOf(context).languageCode != 'ar';
    final description = product.shortDescription ?? product.description;

    return HubScaffold(
      currentTab: AppTab.home,
      bottomBar: _BuyBar(
        quantity: _quantity,
        busy: busy,
        onQuantity: _setQuantity,
        onAdd: () => _addBundle(quote),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          ProductGallery(
            images: product.gallery,
            sku: product.sku,
            urlKey: product.urlKey,
            badge: product.badge,
            bottomBadges: [
              if (percent != null)
                GalleryBadge(
                  label: l10n.bundleDiscountBadge(percent),
                  color: AppColors.accentSale,
                  textDirection: null,
                ),
              if (saving != null)
                GalleryBadge(
                  label: l10n.bundleSaveBadge(saving.formatted()),
                  color: AppColors.successStrong,
                  textDirection: null,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (seller != null && !seller.isMarketplace) ...[
                  _SoldByLine(seller: seller),
                  const SizedBox(height: 6),
                ],
                Text(
                  product.name,
                  style: TextStyle(
                    // Playfair Display has no Arabic glyphs.
                    fontFamily: isEn ? AppTheme.displayFont : null,
                    fontSize: 22,
                    height: 28 / 22,
                    fontWeight: FontWeight.w700,
                    color: context.scaffoldHeading,
                  ),
                ),
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    description,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 20 / 14,
                      color: context.scaffoldMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                _PriceLine(bundle: bundle, quote: quote),
                const SizedBox(height: 16),
                _PackageCard(
                  bundle: bundle,
                  choice: _choice,
                  expanded: _expanded,
                  onExpand: () => setState(() => _expanded = !_expanded),
                  onChanged: _update,
                  onSwap: _swap,
                  onAddItemOnly: _addItemOnly,
                ),
                const SizedBox(height: 16),
                _PackageSummary(bundle: bundle, quote: quote, refusal: refusal),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Sold by Test 1 ✓" above the title (Figma 14b); opens the store.
class _SoldByLine extends StatelessWidget {
  const _SoldByLine({required this.seller});

  final HmSellerSummary seller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: InkWell(
        onTap: seller.storeCode == null
            ? null
            : () => openSellerStore(context, seller),
        borderRadius: BorderRadius.circular(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.pdpSoldBy,
              style: TextStyle(fontSize: 12, color: context.scaffoldMuted),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                seller.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.info,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const SellerVerifiedIcon(size: 13),
          ],
        ),
      ),
    );
  }
}

/// AED 61  AED 72  You save AED 11 — or "From AED …" when the package can't
/// be priced here.
class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.bundle, required this.quote});

  final BundleProduct bundle;
  final BundleQuote quote;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final total = quote.total;
    final saving = quote.saving;
    final from = bundle.minFinal;
    if (total == null && from == null) return const SizedBox.shrink();
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(
          total != null
              ? total.formatted()
              : l10n.bundlePriceFrom(from!.formatted()),
          style: const TextStyle(
            fontSize: 24,
            height: 30 / 24,
            fontWeight: FontWeight.w700,
            color: AppColors.accentStrong,
          ),
        ),
        if (saving != null && quote.regular != null)
          Text(
            quote.regular!.formatted(),
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 14,
              color: context.scaffoldMuted,
              decoration: TextDecoration.lineThrough,
            ),
          ),
        if (saving != null)
          Text(
            l10n.bundleYouSave(saving.formatted()),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.successStrong,
            ),
          ),
      ],
    );
  }
}

/// A row of the package card: a chosen selection, or an option still to fill.
typedef _PackageRow = ({BundleOption option, BundleSelection? selection});

/// "Items in this package" (Figma 14b 61:2760).
class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.bundle,
    required this.choice,
    required this.expanded,
    required this.onExpand,
    required this.onChanged,
    required this.onSwap,
    required this.onAddItemOnly,
  });

  final BundleProduct bundle;
  final BundleChoice choice;
  final bool expanded;
  final VoidCallback onExpand;
  final ValueChanged<BundleChoice> onChanged;
  final ValueChanged<BundleOption> onSwap;
  final ValueChanged<BundleSelection> onAddItemOnly;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = <_PackageRow>[
      for (final option in bundle.options)
        ...switch (choice.chosenIn(option)) {
          final chosen when chosen.isNotEmpty => [
            for (final selection in chosen)
              (option: option, selection: selection),
          ],
          _ => [(option: option, selection: null)],
        },
    ];
    final itemCount = rows.where((r) => r.selection != null).length;
    final hidden = rows.length - _collapsedRows;
    final shown = expanded || hidden <= 0
        ? rows
        : rows.take(_collapsedRows).toList();
    final issues = choice.issues(bundle);

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 4),
      decoration: BoxDecoration(
        border: Border.all(color: context.hairline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.bundleItemsTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.scaffoldHeading,
                    ),
                  ),
                ),
                Icon(
                  HubIcons.package,
                  size: 14,
                  color: context.scaffoldMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.bundleItemCount(itemCount),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.scaffoldMuted,
                  ),
                ),
              ],
            ),
          ),
          for (final row in shown)
            _Divided(
              child: row.selection == null
                  ? _ChooseRow(
                      option: row.option,
                      onTap: () => onSwap(row.option),
                    )
                  : _ItemRow(
                      option: row.option,
                      selection: row.selection!,
                      choice: choice,
                      issue: issues
                          .where((i) => identical(i.selection, row.selection))
                          .firstOrNull,
                      onChanged: onChanged,
                      onSwap: () => onSwap(row.option),
                      onAddItemOnly: () => onAddItemOnly(row.selection!),
                    ),
            ),
          if (hidden > 0)
            _Divided(
              child: InkWell(
                onTap: onExpand,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Text(
                        expanded
                            ? l10n.bundleShowFewer
                            : l10n.bundleMoreItems(hidden),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accentStrong,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        expanded
                            ? HubIcons.chevronUp
                            : HubIcons.chevronDown,
                        size: 16,
                        color: AppColors.accentStrong,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A hairline above each row of the package card.
class _Divided extends StatelessWidget {
  const _Divided({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: context.hairline)),
    ),
    child: child,
  );
}

/// The 60×60 white tile an item's picture sits in.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, this.size = 60});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.borderSubtle),
    ),
    child: HubImage(url: url, fit: BoxFit.contain, width: size, height: size),
  );
}

/// One chosen item: picture, name, "Qty 1 · AED 32", a configurable item's
/// attributes, "Swap" and "Add this item only", and ✓ once it can go.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.option,
    required this.selection,
    required this.choice,
    required this.issue,
    required this.onChanged,
    required this.onSwap,
    required this.onAddItemOnly,
  });

  final BundleOption option;
  final BundleSelection selection;
  final BundleChoice choice;
  final BundleIssue? issue;
  final ValueChanged<BundleChoice> onChanged;
  final VoidCallback onSwap;
  final VoidCallback onAddItemOnly;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final child = selection.child;
    final variant = choice.variantOf(selection);
    final quantity = choice.quantityOf(selection);
    final unit = variant?.finalPrice ?? child?.finalPrice;
    final line = unit == null
        ? null
        : Money(amount: unit.amount * quantity, currency: unit.currency);
    // Only where there is something else to put in.
    final canSwap = option.selections.length > 1;
    final count = quantity.round();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Thumb(url: variant?.imageUrl ?? child?.imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selection.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.scaffoldHeading,
                  ),
                ),
                const SizedBox(height: 4),
                if (selection.canChangeQuantity)
                  _SmallStepper(
                    quantity: count,
                    price: line,
                    onChanged: (q) =>
                        onChanged(choice.withQuantity(selection, q.toDouble())),
                  )
                else
                  Text(
                    line == null
                        ? l10n.bundleLineQty(count)
                        : l10n.bundleLineQtyPrice(count, line.formatted()),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.scaffoldMuted,
                    ),
                  ),
                if (child != null && child.isConfigurable)
                  for (final attribute in child.options)
                    _AttributePicker(
                      attribute: attribute,
                      selected: choice.attributesOf(
                        selection,
                      )[attribute.attributeCode],
                      onSelect: (index) => onChanged(
                        choice.withAttribute(
                          selection,
                          attribute.attributeCode,
                          index,
                        ),
                      ),
                    ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    if (canSwap)
                      _Link(
                        icon: HubIcons.refreshCw,
                        label: l10n.bundleSwap,
                        color: AppColors.accentStrong,
                        onTap: onSwap,
                      ),
                    if (child != null)
                      _Link(
                        label: l10n.bundleAddItemOnly,
                        color: AppColors.info,
                        onTap: onAddItemOnly,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          issue == null
              ? const Icon(
                  HubIcons.check,
                  size: 18,
                  color: AppColors.successStrong,
                )
              : const Icon(
                  HubIcons.circleAlert,
                  size: 18,
                  color: AppColors.accentStrong,
                ),
        ],
      ),
    );
  }
}

/// An option with nothing chosen yet: "Choose Mat", or "Optional".
class _ChooseRow extends StatelessWidget {
  const _ChooseRow({required this.option, required this.onTap});

  final BundleOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.hairline),
              ),
              child: const Icon(HubIcons.plus, color: AppColors.accentStrong),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.bundleChoose(option.title),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentStrong,
                    ),
                  ),
                  if (!option.required)
                    Text(
                      l10n.bundleOptional,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.scaffoldMuted,
                      ),
                    ),
                ],
              ),
            ),
            Icon(HubIcons.chevronRight, size: 18, color: context.scaffoldMuted),
          ],
        ),
      ),
    );
  }
}

/// "Swap" / "Add this item only".
class _Link extends StatelessWidget {
  const _Link({
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
}

/// A configurable item's attribute (Size: S M L) as small chips.
class _AttributePicker extends StatelessWidget {
  const _AttributePicker({
    required this.attribute,
    required this.selected,
    required this.onSelect,
  });

  final ConfigurableOption attribute;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final picked = attribute.values
        .where((v) => v.valueIndex == selected)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            picked == null
                ? attribute.label
                : '${attribute.label}: ${picked.label}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.scaffoldHeading,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final value in attribute.values)
                ChoiceChip(
                  label: Text(value.label),
                  selected: value.valueIndex == selected,
                  onSelected: (_) => onSelect(value.valueIndex),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  labelStyle: const TextStyle(fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// − N + with the line's price, for a selection whose quantity the shopper
/// sets.
class _SmallStepper extends StatelessWidget {
  const _SmallStepper({
    required this.quantity,
    required this.price,
    required this.onChanged,
  });

  final int quantity;
  final Money? price;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, VoidCallback? onTap) => InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          icon,
          size: 16,
          color: onTap == null
              ? context.scaffoldFaint
              : context.scaffoldHeading,
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          HubIcons.minus,
          quantity > 1 ? () => onChanged(quantity - 1) : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '$quantity',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.scaffoldHeading,
            ),
          ),
        ),
        button(HubIcons.plus, () => onChanged(quantity + 1)),
        if (price != null) ...[
          const SizedBox(width: 8),
          Text(
            price!.formatted(),
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 12, color: context.scaffoldMuted),
          ),
        ],
      ],
    );
  }
}

/// "Package summary" (Figma 14b 61:2776).
class _PackageSummary extends StatelessWidget {
  const _PackageSummary({
    required this.bundle,
    required this.quote,
    this.refusal,
  });

  final BundleProduct bundle;
  final BundleQuote quote;

  /// Why the cart would refuse the package, as the server put it.
  final String? refusal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final regular = quote.regular;
    final saving = quote.saving;
    final total = quote.total;
    final from = bundle.minFinal;
    Widget row(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: context.scaffoldMuted),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color ?? context.scaffoldHeading,
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.fieldFill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.bundleSummaryTitle,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.scaffoldHeading,
            ),
          ),
          if (regular != null)
            row(l10n.bundleRegularPrice, regular.formatted()),
          if (saving != null)
            row(
              l10n.bundleSaving,
              '− ${saving.formatted()}',
              color: AppColors.successStrong,
            ),
          // The fee depends on the address, so checkout works it out (the
          // frame's "Free" isn't something the product page can know).
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.cartDelivery,
                    style: TextStyle(
                      fontSize: 14,
                      color: context.scaffoldMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.cartDeliveryCalculated,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.scaffoldHeading,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: context.hairline),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.cartTotal,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.scaffoldHeading,
                  ),
                ),
              ),
              Text(
                total != null
                    ? total.formatted()
                    : (from == null
                          ? '—'
                          : l10n.bundlePriceFrom(from.formatted())),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.scaffoldHeading,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.bundleTaxesNote,
            style: TextStyle(fontSize: 12, color: context.scaffoldMuted),
          ),
          if (refusal != null) ...[
            const SizedBox(height: 2),
            Text(
              refusal!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.accentStrong,
              ),
            ),
          ] else if (!quote.exact && total != null) ...[
            const SizedBox(height: 2),
            Text(
              l10n.bundleEstimateNote,
              style: TextStyle(fontSize: 12, color: context.scaffoldMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// The pinned buy bar: quantity pill and "Add bundle to cart".
class _BuyBar extends StatelessWidget {
  const _BuyBar({
    required this.quantity,
    required this.busy,
    required this.onQuantity,
    required this.onAdd,
  });

  final int quantity;
  final bool busy;
  final ValueChanged<int> onQuantity;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget round(IconData icon, {required bool filled, VoidCallback? onTap}) =>
        Material(
          color: filled ? AppColors.brandPrimary : AppColors.surfaceSubtle,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 26,
              height: 26,
              child: Icon(
                icon,
                size: 16,
                color: filled ? Colors.white : AppColors.inkHeading,
              ),
            ),
          ),
        );
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.borderStrong),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  round(
                    HubIcons.minus,
                    filled: false,
                    onTap: quantity > 1 && !busy
                        ? () => onQuantity(quantity - 1)
                        : null,
                  ),
                  SizedBox(
                    width: 24,
                    child: Text(
                      '$quantity',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.scaffoldHeading,
                      ),
                    ),
                  ),
                  round(
                    HubIcons.plus,
                    filled: true,
                    onTap: busy ? null : () => onQuantity(quantity + 1),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: busy ? null : onAdd,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(HubIcons.shoppingCart, size: 20),
                  label: Text(l10n.bundleAddToCart),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The option's selections to swap in (single choice) or tick (several):
/// picture, name, price, and the difference from what is in now.
class _SwapSheet extends StatefulWidget {
  const _SwapSheet({
    required this.bundle,
    required this.option,
    required this.choice,
    required this.onChanged,
  });

  final BundleProduct bundle;
  final BundleOption option;
  final BundleChoice choice;
  final ValueChanged<BundleChoice> onChanged;

  @override
  State<_SwapSheet> createState() => _SwapSheetState();
}

class _SwapSheetState extends State<_SwapSheet> {
  late BundleChoice _choice = widget.choice;

  void _pick(BundleSelection selection) {
    final option = widget.option;
    final next = option.type.allowsMany
        ? _choice.toggle(option, selection)
        : _choice.choose(option, selection);
    setState(() => _choice = next);
    widget.onChanged(next);
    if (!option.type.allowsMany) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final option = widget.option;
    final many = option.type.allowsMany;
    final current = _choice.chosenIn(option).firstOrNull?.child?.finalPrice;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _choice.chosenIn(option).isEmpty
                ? l10n.bundleChoose(option.title)
                : l10n.bundleSwapTitle(option.title),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.scaffoldHeading,
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                // An optional single-choice item can be left out again.
                if (!option.required && !many)
                  _NoneRow(
                    chosen: _choice.chosenIn(option).isEmpty,
                    onTap: () {
                      var next = _choice;
                      for (final s in _choice.chosenIn(option)) {
                        next = next.remove(option, s);
                      }
                      widget.onChanged(next);
                      Navigator.of(context).pop();
                    },
                  ),
                for (final selection in option.selections)
                  _SwapRow(
                    selection: selection,
                    chosen: _choice.isChosen(option, selection),
                    many: many,
                    difference: many ? null : _difference(selection, current),
                    onTap: selection.inStock ? () => _pick(selection) : null,
                  ),
              ],
            ),
          ),
          if (many) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.bundleDone),
            ),
          ],
        ],
      ),
    );
  }

  /// "+AED 5.00" / "−AED 2.00" against what is in now; null when equal.
  String? _difference(BundleSelection selection, Money? current) {
    final price = selection.child?.finalPrice;
    if (price == null || current == null) return null;
    final delta = (price.amount - current.amount) * selection.quantity;
    if (delta.abs() < 0.005) return null;
    final text = Money(
      amount: delta.abs(),
      currency: price.currency,
    ).formatted();
    return delta > 0 ? '+$text' : '−$text';
  }
}

/// "None" at the head of an optional single-choice item's list.
class _NoneRow extends StatelessWidget {
  const _NoneRow({required this.chosen, required this.onTap});

  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.hairline),
            ),
            child: Icon(HubIcons.ban, color: context.scaffoldMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              AppLocalizations.of(context).bundleNone,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.scaffoldHeading,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            chosen ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: chosen ? AppColors.brandPrimary : context.scaffoldMuted,
          ),
        ],
      ),
    ),
  );
}

class _SwapRow extends StatelessWidget {
  const _SwapRow({
    required this.selection,
    required this.chosen,
    required this.many,
    required this.difference,
    required this.onTap,
  });

  final BundleSelection selection;
  final bool chosen;
  final bool many;
  final String? difference;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final child = selection.child;
    final price = child?.finalPrice;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _Thumb(url: child?.imageUrl, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selection.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: onTap == null
                          ? context.scaffoldFaint
                          : context.scaffoldHeading,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    !selection.inStock
                        ? l10n.productOutOfStock
                        : [
                            if (price != null) price.formatted(),
                            ?difference,
                          ].join('  ·  '),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.scaffoldMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              many
                  ? (chosen ? HubIcons.squareCheck : HubIcons.square)
                  : (chosen
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked),
              color: chosen ? AppColors.brandPrimary : context.scaffoldMuted,
            ),
          ],
        ),
      ),
    );
  }
}
