import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/address/regions.dart';
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
    final regions = ref.watch(regionsProvider);
    final postcodeRequired =
        ref.watch(postcodeRequiredProvider).valueOrNull ?? false;
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
        validator: (v) => Validators.uaePhone(context, v),
      ),
      _EmirateField(controller: controller, regions: regions),
      AuthField(
        controller: controller.area,
        label: l10n.checkoutFieldArea,
        textCapitalization: TextCapitalization.words,
      ),
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
  }
}

/// The Emirate picker, drawn like the design's Input: the label over a 52 px
/// field with a map-pin first and a chevron last. While the list loads it is a
/// disabled field; if the store's list can't be read it falls back to typing
/// the name, so the form is never blocked.
class _EmirateField extends StatelessWidget {
  const _EmirateField({required this.controller, required this.regions});

  final AddressFormController controller;
  final AsyncValue<List<RegionOption>> regions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final label = l10n.checkoutFieldEmirate;
    return regions.when(
      data: (list) => FormField<int>(
        initialValue: controller.regionId.value,
        // The picker is drawn by the dropdown below; this field owns the form's
        // check and the message, so a missing emirate reads like the other
        // fields' errors (an alert and a red outline).
        validator: (_) =>
            controller.regionId.value == null ? l10n.validationRequired : null,
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: t.captionStrong.copyWith(color: AppColors.inkHeading),
            ),
            const SizedBox(height: 6),
            ValueListenableBuilder<int?>(
              valueListenable: controller.regionId,
              builder: (context, value, _) => DropdownButtonFormField<int>(
                initialValue: value,
                isExpanded: true,
                // Not dense: the button keeps the 48 px a menu item has, which
                // with the decoration's 2 px above and below makes the 52 px
                // field of the design.
                isDense: false,
                icon: const Icon(
                  HubIcons.chevronDown,
                  size: 20,
                  color: AppColors.inkMuted,
                ),
                style: t.body.copyWith(color: AppColors.inkHeading),
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
                decoration: _fieldDecoration(
                  context,
                  icon: HubIcons.mapPin,
                  error: state.hasError,
                ),
                hint: Text(
                  label,
                  style: t.body.copyWith(color: AppColors.inkFaint),
                ),
                items: [
                  for (final r in list)
                    DropdownMenuItem<int>(value: r.id, child: Text(r.name)),
                ],
                onChanged: (v) {
                  controller.regionId.value = v;
                  state.didChange(v);
                },
              ),
            ),
            if (state.hasError) ...[
              const SizedBox(height: 6),
              AuthHelperLine.error(state.errorText!),
            ],
          ],
        ),
      ),
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: t.captionStrong.copyWith(color: AppColors.inkHeading),
          ),
          const SizedBox(height: 6),
          InputDecorator(
            decoration: _fieldDecoration(context, icon: HubIcons.mapPin),
            child: const SizedBox(
              height: 48,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        ],
      ),
      error: (_, _) => AuthField(
        controller: controller.region,
        label: label,
        icon: HubIcons.mapPin,
        validator: (v) => Validators.required(context, v),
      ),
    );
  }

  /// Mirrors `AuthField`'s box: white, 12 px radius, a `border/strong` hairline
  /// that turns navy (1.5 px) when focused. Vertical padding of 2 around the
  /// dropdown's 48 px content makes the 52 px of the design.
  InputDecoration _fieldDecoration(
    BuildContext context, {
    IconData? icon,
    bool error = false,
  }) {
    OutlineInputBorder outline(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsetsDirectional.fromSTEB(
        icon == null ? 16 : 0,
        2,
        16,
        2,
      ),
      prefixIcon: icon == null
          ? null
          : Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, end: 10),
              child: Icon(icon, size: 20, color: AppColors.inkMuted),
            ),
      prefixIconConstraints: const BoxConstraints(),
      border: outline(error ? AppColors.danger : AppColors.borderStrong, 1),
      enabledBorder: error
          ? outline(AppColors.danger, 1.5)
          : outline(AppColors.borderStrong, 1),
      disabledBorder: outline(AppColors.borderStrong, 1),
      focusedBorder: error
          ? outline(AppColors.danger, 1.5)
          : outline(AppColors.brandPrimary, 1.5),
    );
  }
}
