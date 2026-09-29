import 'package:flutter/material.dart';

import '../../../../app/theme/theme_x.dart';
import '../../../../l10n/l10n.dart';
import '../../../marketplace/domain/seller_groups.dart';
import '../../../marketplace/presentation/seller_widgets.dart';
import '../../domain/order.dart';

/// Figma 22 "package N": one store's items of an order, under
/// "Package 1 · loly store". The frame's per-package status, timeline and
/// "Track parcel" / "Contact store" need per-seller shipment data the HubApp
/// contract doesn't have yet, so a package lists its items.
class OrderPackageCard extends StatelessWidget {
  const OrderPackageCard({
    super.key,
    required this.index,
    required this.package,
    required this.line,
  });

  /// 1-based, in the order the stores first appear.
  final int index;
  final SellerGroup<OrderLine> package;
  final Widget Function(OrderLine line) line;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final seller = package.seller;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 8),
      decoration: BoxDecoration(
        border: Border.all(color: context.hairline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (seller != null)
            SellerGroupHeader(
              seller: seller,
              title: l10n.orderPackageTitle(index, seller.name),
            )
          else
            Text(
              l10n.orderPackageTitleNoStore(index),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.scaffoldHeading,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: context.hairline),
          ),
          for (final item in package.items) line(item),
        ],
      ),
    );
  }
}
