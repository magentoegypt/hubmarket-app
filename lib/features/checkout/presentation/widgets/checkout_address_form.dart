import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/hub_icons.dart';
import '../../../../core/address/regions.dart';
import '../../../../core/address/city_fields.dart';
import '../../../../core/validation/validators.dart';
import '../../../../core/widgets/address_form.dart';
import '../../../../l10n/l10n.dart';
import '../../../account/data/address_rules.dart';
import '../../../auth/presentation/widgets/auth_field.dart';

/// The guest's shipping address (Figma 17a "Shipping address"): full name,
/// mobile number, emirate, area, street & building, apartment / villa — and a
/// postcode when the store requires one for the UAE.
///
/// It fills the same [AddressFormController] the address book's form does, but
/// is laid out as the checkout frame draws it: the icon-led fields of the
/// design's Input (52 px, a navy outline when focused) 12 px apart, with the
/// emirate as a picker. The host wraps it in its own [Form].
///
/// Area is optional: Magento needs a `city`, so a blank Area falls back to the
/// emirate's name (see [CheckoutAddressForm.cityFor]).
class CheckoutAddressForm extends ConsumerWidget {
  const CheckoutAddressForm({
    super.key,
    required this.controller,
    required this.postcode,
  });

  final AddressFormController controller;

  /// Only shown (and validated) when the store requires a postcode.
  final TextEditingController postcode;

  /// Magento's `city`: the typed Area, else the chosen emirate's name, else
  /// the free-text emirate.
  static String cityFor(
    AddressFormController controller,
    List<RegionOption> regions,
  ) {
    final area = controller.area.text.trim();
    if (area.isNotEmpty) return area;
    for (final r in regions) {
      if (r.id == controller.regionId.value) return r.name;
    }
    return controller.region.text.trim();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return ValueListenableBuilder<String>(
      valueListenable: controller.country,
      builder: (context, country, _) {
        final postcodeRequired =
            ref.watch(postcodeRequiredByCountryProvider(country)).valueOrNull ??
            true;
        final fields = <Widget>[
          AuthField(
            controller: controller.fullName,
            label: l10n.checkoutFieldFullName,
            icon: HubIcons.user,
            hint: l10n.addressHintName,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            validator: (v) => Validators.required(context, v),
          ),
          // The phone is typed as the shopper writes it (+971 50 …, 050 …, 50 …):
          // the controller turns it into E.164 for Magento.
          AuthField(
            controller: controller.phone,
            label: l10n.checkoutFieldMobile,
            icon: HubIcons.phone,
            hint: l10n.authPhoneHint,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            ltrInput: true,
            validator: (v) => controller.validatePhone(context, v),
          ),
          AddressCityFields(controller: controller),
          AuthField(
            controller: controller.street,
            label: l10n.checkoutFieldStreet,
            hint: l10n.addressHintStreet,
            validator: (v) => Validators.required(context, v),
          ),
          // Optional (Magento street[1]).
          AuthField(
            controller: controller.apartment,
            label: l10n.checkoutFieldApartment,
            textInputAction: postcodeRequired
                ? TextInputAction.next
                : TextInputAction.done,
          ),
          if (postcodeRequired)
            AuthField(
              controller: postcode,
              label: l10n.fieldPostcode,
              textInputAction: TextInputAction.done,
              validator: (v) => Validators.required(context, v),
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < fields.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              fields[i],
            ],
          ],
        );
      },
    );
  }
}
