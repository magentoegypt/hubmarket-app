import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/store_timezone.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/domain/money.dart';
import '../../domain/order.dart';
import '../order_actions.dart';
import '../order_format.dart';
import '../widgets/order_cancel_section.dart';

/// Full detail for a single placed order, navigated to with the [CustomerOrder]
/// via go_router `extra` (the list already holds every field, so no extra
/// query). Shows items, totals, shipping method and shipment tracking, and
/// "Cancel order" when the store and the order allow it (Figma 22 / 21b).
class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.order});

  final CustomerOrder order;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  /// Replaced by Magento's copy once the order is cancelled here.
  late CustomerOrder _order = widget.order;

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    // Magento stamps order times in the store's zone — see orderFmtDate.
    final storeZone = ref.watch(storeTimezoneProvider).valueOrNull ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(l10n.orderDetailsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.orderNumber(order.number),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            '${orderFmtDate(order.date, locale, storeZone)} · ${order.status}',
            style: const TextStyle(color: AppColors.inkMuted),
          ),
          const SizedBox(height: 16),

          // Reorder — re-adds every line to the cart (QA request for this page).
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => reorderOrder(context, ref, order),
              icon: const Icon(Icons.shopping_cart_outlined, size: 18),
              label: Text(l10n.orderReorder),
            ),
          ),
          const SizedBox(height: 24),

          _SectionTitle(l10n.orderItemsSection),
          for (final line in order.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailThumb(url: line.imageUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(line.name),
                        const SizedBox(height: 2),
                        if (line.sku != null && line.sku!.isNotEmpty)
                          Text(
                            '${l10n.specSku}: ${line.sku}',
                            style: const TextStyle(
                              color: AppColors.inkMuted,
                              fontSize: 12,
                            ),
                          ),
                        Text(
                          l10n.orderQty(line.quantity.toInt()),
                          style: const TextStyle(
                            color: AppColors.inkMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (line.price != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      line.price!.formatted(),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(color: AppColors.inkMuted),
                    ),
                  ],
                ],
              ),
            ),

          const Divider(height: 32),
          if (order.subtotal != null)
            _TotalRow(label: l10n.cartSubtotal, amount: order.subtotal!),
          if (order.discount != null)
            _TotalRow(
              label:
                  order.discountLabel != null && order.discountLabel!.isNotEmpty
                  ? '${l10n.cartDiscount} (${order.discountLabel})'
                  : l10n.cartDiscount,
              amount: order.discount!,
              negative: true,
            ),
          if (order.shippingAmount != null)
            _TotalRow(label: l10n.orderShippingLabel, amount: order.shippingAmount!),
          if (order.total != null)
            _TotalRow(label: l10n.cartTotal, amount: order.total!, emphasize: true),

          if (order.paymentMethodName != null &&
              order.paymentMethodName!.isNotEmpty) ...[
            const Divider(height: 32),
            _SectionTitle(l10n.orderPaymentSection),
            Text(order.paymentMethodName!),
          ],

          if (order.shippingAddress != null &&
              order.shippingAddress!.isNotEmpty) ...[
            const Divider(height: 32),
            _SectionTitle(l10n.orderDeliveryAddress),
            _AddressBlock(
              name: order.shippingName,
              address: order.shippingAddress!,
              country: _countryName(l10n, order.shippingCountryCode),
              phone: order.shippingPhone,
            ),
          ],

          if (order.billingAddress != null &&
              order.billingAddress!.isNotEmpty) ...[
            const Divider(height: 32),
            _SectionTitle(l10n.orderBillingAddress),
            _AddressBlock(
              name: order.billingName,
              address: order.billingAddress!,
              country: _countryName(l10n, order.billingCountryCode),
              phone: order.billingPhone,
            ),
          ],

          if (order.shippingMethod != null &&
              order.shippingMethod!.isNotEmpty) ...[
            const Divider(height: 32),
            _SectionTitle(l10n.checkoutShippingMethod),
            Text(
              [order.carrier, order.shippingMethod]
                  .where((s) => s != null && s.isNotEmpty)
                  .join(' · '),
            ),
          ],

          if (order.comments.isNotEmpty) ...[
            const Divider(height: 32),
            _SectionTitle(l10n.orderTimelineSection),
            for (final c in order.comments.reversed)
              _TimelineRow(
                message: c.message,
                timestamp: orderFmtDateTime(c.timestamp, locale, storeZone),
              ),
          ],

          const Divider(height: 32),
          _SectionTitle(l10n.orderTrackingSection),
          if (!order.hasTracking)
            Text(
              l10n.orderNoTracking,
              style: const TextStyle(color: AppColors.inkMuted),
            )
          else
            for (final t in order.trackings)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.local_shipping_outlined,
                  color: AppColors.brandPrimary,
                ),
                title: Text(
                  [t.carrier, t.title].where((s) => s.isNotEmpty).join(' · '),
                ),
                subtitle: Text(t.number, textDirection: TextDirection.ltr),
                trailing: IconButton(
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: l10n.orderTrackingSection,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: t.number));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.orderTrackingCopied)),
                      );
                    }
                  },
                ),
              ),

          OrderCancelSection(
            order: order,
            onCancelled: (updated) => setState(() => _order = updated),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// 48×48 product thumbnail for an order-detail item row.
class _DetailThumb extends StatelessWidget {
  const _DetailThumb({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      width: 48,
      height: 48,
      child: HubImage(
        url: url,
        decodeWidth: 48,
        placeholder: (_) => const ColoredBox(color: AppColors.surfaceTint),
        error: (_) => const ColoredBox(
          color: AppColors.surfaceTint,
          child: Icon(
            Icons.image_outlined,
            size: 16,
            color: AppColors.inkMuted,
          ),
        ),
      ),
    ),
  );
}

/// Localized country name for an order address ISO code — `AE` →
/// "United Arab Emirates" / "الإمارات العربية المتحدة". Null/empty when unset;
/// an unknown code falls back to the code itself.
String? _countryName(AppLocalizations l10n, String? code) {
  if (code == null || code.trim().isEmpty) return null;
  return code.trim().toUpperCase() == 'AE' ? l10n.countryUae : code.trim();
}

/// Recipient name (bold) + a single-line address, the country on its own line,
/// then the phone number.
class _AddressBlock extends StatelessWidget {
  const _AddressBlock({
    required this.name,
    required this.address,
    this.country,
    this.phone,
  });
  final String? name;
  final String address;
  final String? country;
  final String? phone;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (name != null && name!.isNotEmpty)
        Text(name!, style: const TextStyle(fontWeight: FontWeight.w600)),
      Text(
        address,
        style: const TextStyle(color: AppColors.inkMuted, height: 1.35),
      ),
      if (country != null && country!.isNotEmpty)
        Text(
          country!,
          style: const TextStyle(color: AppColors.inkMuted, height: 1.35),
        ),
      if (phone != null && phone!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            children: [
              const Icon(
                Icons.phone_outlined,
                size: 13,
                color: AppColors.inkMuted,
              ),
              const SizedBox(width: 4),
              Text(
                phone!,
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: AppColors.inkMuted, fontSize: 12.5),
              ),
            ],
          ),
        ),
    ],
  );
}

/// One status-history entry: a burgundy dot, the message, and its time.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.message, required this.timestamp});
  final String message;
  final String timestamp;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsetsDirectional.only(top: 5, end: 10),
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppColors.brandPrimary,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.isNotEmpty) Text(message),
              if (timestamp.isNotEmpty)
                Text(
                  timestamp,
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.amount,
    this.emphasize = false,
    this.negative = false,
  });

  final String label;
  final Money amount;
  final bool emphasize;

  /// Renders the amount as a reduction: `−AED x.xx` in the brand colour (used
  /// for the discount line, matching the cart summary).
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? const TextStyle(fontWeight: FontWeight.w700)
        : const TextStyle(color: AppColors.inkMuted);
    final valueStyle = emphasize
        ? const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.brandPrimary,
          )
        : negative
        ? const TextStyle(color: AppColors.brandPrimary)
        : style;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Text(
            negative ? '−${amount.formatted()}' : amount.formatted(),
            textDirection: TextDirection.ltr,
            style: valueStyle,
          ),
        ],
      ),
    );
  }
}
