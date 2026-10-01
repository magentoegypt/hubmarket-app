import '../../../l10n/l10n.dart';

/// "Only 3 left in size M" / "Only 3 left", from the count the store reports
/// (`only_x_left_in_stock`) and the option the customer chose ("size M", see
/// `ProductDetail.stockOptionLabel`). Shared by the product page's low-stock line
/// and the added-to-cart sheet's.
String lowStockText(AppLocalizations l10n, int left, String? option) =>
    option == null || option.isEmpty
    ? l10n.pdpOnlyLeft(left)
    : l10n.pdpOnlyLeftIn(left, option);
