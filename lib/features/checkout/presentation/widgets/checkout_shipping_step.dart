import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/validation/validators.dart';
import '../../../../l10n/l10n.dart';
import '../../../account/domain/customer_address.dart';
import '../../../catalog/domain/money.dart';
import '../../domain/checkout.dart';
import 'checkout_parts.dart';

/// Step 1 cards (Figma 17 / 17a): the guest's contact card, the saved-address
/// picker, "Ship to" and the shipping methods.

/// Guest contact (17a): the email the order confirmation goes to, and — when
/// the store says the address already has an account — a prompt to sign in.
class ContactCard extends StatelessWidget {
  const ContactCard({
    super.key,
    required this.email,
    required this.focusNode,
    required this.registeredEmail,
    required this.onSignIn,
    required this.onForgotPassword,
  });

  final TextEditingController email;
  final FocusNode focusNode;

  /// The address the store reported as having an account. The prompt shows
  /// while the field still holds it.
  final String? registeredEmail;
  final VoidCallback onSignIn;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CheckoutCard(
      title: l10n.checkoutContactTitle,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.checkoutEmailLabel, style: CheckoutText.captionStrong),
            const SizedBox(height: 6),
            TextFormField(
              controller: email,
              focusNode: focusNode,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                hintText: l10n.authEmailHint,
                prefixIcon: const Icon(
                  Icons.mail_outline,
                  size: 20,
                  color: AppColors.inkMuted,
                ),
              ),
              validator: (v) => Validators.email(context, v),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: email,
              builder: (context, value, _) =>
                  registeredEmail != null &&
                      value.text.trim() == registeredEmail
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _ExistingAccountNote(
                        onSignIn: onSignIn,
                        onForgotPassword: onForgotPassword,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );
  }
}

class _ExistingAccountNote extends StatelessWidget {
  const _ExistingAccountNote({
    required this.onSignIn,
    required this.onForgotPassword,
  });

  final VoidCallback onSignIn;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.infoSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.info),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.checkoutExistingAccount,
                  style: CheckoutText.bodyStrong.copyWith(
                    color: AppColors.info,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: onSignIn,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: const StadiumBorder(),
                        textStyle: checkoutButtonText(
                          context,
                          fontSize: 12,
                        )?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      child: Text(l10n.checkoutSignIn),
                    ),
                    InkWell(
                      onTap: onForgotPassword,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          l10n.checkoutForgotPassword,
                          style: CheckoutText.link.copyWith(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A signed-in customer's saved addresses as radio cards (default first
/// selected), then "Use a new address", which opens [newAddressForm] below.
class SavedAddressPicker extends StatelessWidget {
  const SavedAddressPicker({
    super.key,
    required this.addresses,
    required this.selectedId,
    required this.useNew,
    required this.onSelect,
    required this.onUseNew,
    required this.newAddressForm,
  });

  final List<CustomerAddress> addresses;
  final int? selectedId;
  final bool useNew;
  final ValueChanged<CustomerAddress> onSelect;
  final VoidCallback onUseNew;
  final Widget newAddressForm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in addresses)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CheckoutOption(
              selected: !useNew && a.id == selectedId,
              onTap: () => onSelect(a),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckoutRadio(selected: !useNew && a.id == selectedId),
                  const SizedBox(width: 12),
                  Expanded(child: _AddressSummary(address: a)),
                ],
              ),
            ),
          ),
        CheckoutOption(
          selected: useNew,
          onTap: onUseNew,
          child: Row(
            children: [
              CheckoutRadio(selected: useNew),
              const SizedBox(width: 12),
              const Icon(
                Icons.add_location_alt_outlined,
                size: 18,
                color: AppColors.brandPrimary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.checkoutUseNewAddress,
                  style: CheckoutText.bodyStrong,
                ),
              ),
            ],
          ),
        ),
        if (useNew) ...[const SizedBox(height: 14), newAddressForm],
      ],
    );
  }
}

class _AddressSummary extends StatelessWidget {
  const _AddressSummary({required this.address});

  final CustomerAddress address;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = address.labelText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                address.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CheckoutText.bodyStrong,
              ),
            ),
            if (label != null && label.isNotEmpty) ...[
              const SizedBox(width: 8),
              AddressLabelChip(label: label),
            ],
            if (address.defaultShipping) ...[
              const SizedBox(width: 6),
              AddressLabelChip(label: l10n.addressDefaultBadge),
            ],
          ],
        ),
        if (address.telephone.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(displayPhone(address.telephone), style: CheckoutText.caption),
        ],
        const SizedBox(height: 2),
        Text(address.summary, style: CheckoutText.caption),
      ],
    );
  }
}

/// The small grey pill after "Ship to" — the address label ("Home").
class AddressLabelChip extends StatelessWidget {
  const AddressLabelChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.surfaceSubtle,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.inkMuted,
      ),
    ),
  );
}

/// "Ship to" (Figma 17): the submitted address, with "Change" reopening the
/// address form.
class ShipToCard extends StatelessWidget {
  const ShipToCard({super.key, required this.shipTo, required this.onChange});

  final ShipTo shipTo;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = shipTo.label;
    return CheckoutCard(
      spacing: 6,
      children: [
        Row(
          children: [
            const Icon(
              Icons.location_on_outlined,
              size: 18,
              color: AppColors.accentStrong,
            ),
            const SizedBox(width: 8),
            Text(l10n.checkoutShipTo, style: CheckoutText.title),
            if (label != null && label.isNotEmpty) ...[
              const SizedBox(width: 8),
              AddressLabelChip(label: label),
            ],
            const Spacer(),
            CheckoutLink(label: l10n.actionChange, onTap: onChange),
          ],
        ),
        Text(
          '${shipTo.name} · ${displayPhone(shipTo.telephone)}',
          style: CheckoutText.bodyStrong,
        ),
        Text(shipTo.address, style: CheckoutText.bodyMuted),
      ],
    );
  }
}

/// "Shipping method" (Figma 17): the methods Magento offers for the address,
/// with the store's free-shipping threshold underneath when it publishes one.
class ShippingMethodsCard extends StatelessWidget {
  const ShippingMethodsCard({
    super.key,
    required this.methods,
    required this.selected,
    required this.onSelect,
    this.freeShippingOver,
  });

  final List<ShippingMethodOption> methods;
  final ShippingMethodOption? selected;
  final ValueChanged<ShippingMethodOption> onSelect;

  /// Magento's free-shipping minimum; null (the row hides) when the store
  /// publishes none — Hub Market today.
  final Money? freeShippingOver;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CheckoutCard(
      title: l10n.checkoutShippingMethodTitle,
      spacing: 10,
      children: [
        for (final m in methods)
          CheckoutOption(
            selected: m.id == selected?.id,
            onTap: () => onSelect(m),
            child: Row(
              children: [
                CheckoutRadio(selected: m.id == selected?.id),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.title, style: CheckoutText.bodyStrong),
                      if (m.detail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(m.detail, style: CheckoutText.caption),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                m.isFree
                    ? Text(
                        l10n.cartDeliveryFree,
                        style: CheckoutText.bodyStrong.copyWith(
                          color: AppColors.successStrong,
                        ),
                      )
                    : MoneyText(m.amount),
              ],
            ),
          ),
        if (freeShippingOver != null)
          Row(
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                size: 14,
                color: AppColors.successStrong,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.checkoutFreeShippingOver(freeShippingOver!.formatted()),
                  style: CheckoutText.caption.copyWith(
                    color: AppColors.successStrong,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
