import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../address/regions.dart';
import '../validation/phone.dart';
import '../validation/validators.dart';
import 'phone_number_field.dart';

/// Holds the editable address fields, created and disposed by the host screen.
/// Mirrors the Figma "Add Address" form: a single Full Name, phone, an Emirate
/// picker + Area, a street line and an optional apartment/floor line. `regionId`
/// and `isDefault` are [ValueNotifier]s so their controls rebuild on change
/// without the host needing a `setState`.
class AddressFormController {
  AddressFormController({
    String fullName = '',
    String phone = '',
    String area = '',
    String street = '',
    String apartment = '',
    String region = '',
    int? regionId,
    bool isDefault = false,
  }) : fullName = TextEditingController(text: fullName),
       // The phone field shows a fixed `+971` chip, so it holds only the local
       // subscriber digits — strip the country code off any prefilled E.164
       // value (a saved address) so it isn't doubled.
       phone = TextEditingController(text: Phone.localPart(phone)),
       area = TextEditingController(text: area),
       street = TextEditingController(text: street),
       apartment = TextEditingController(text: apartment),
       region = TextEditingController(text: region),
       regionId = ValueNotifier<int?>(regionId),
       isDefault = ValueNotifier<bool>(isDefault);

  final TextEditingController fullName;
  final TextEditingController phone;

  /// Locality / district (Magento `city`), e.g. "Jumeirah 1".
  final TextEditingController area;

  /// Street line — Magento `street[0]`.
  final TextEditingController street;

  /// Apartment / floor — optional Magento `street[1]`.
  final TextEditingController apartment;

  /// Free-text region — only a fallback when the emirate list fails to load.
  final TextEditingController region;

  /// Selected Magento `region_id` (a UAE emirate).
  final ValueNotifier<int?> regionId;

  /// "Set as default address" toggle.
  final ValueNotifier<bool> isDefault;

  /// Splits the single "Full Name" into Magento's firstname/lastname (last token
  /// is the surname). A single token fills both so Magento's required-name
  /// validation passes.
  ({String first, String last}) splitName() {
    final parts = fullName.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return (first: '', last: '');
    if (parts.length == 1) return (first: parts.first, last: parts.first);
    return (first: parts.sublist(0, parts.length - 1).join(' '), last: parts.last);
  }

  /// The phone in explicit E.164 (`+971…`) for Magento / the guest-OTP flow —
  /// the field only holds local digits, so re-add the country code on read.
  String e164Phone() => Phone.normalizeUae(phone.text);

  /// Magento `street` array — drops the apartment line when empty.
  List<String> streetLines() => [
    street.text.trim(),
    if (apartment.text.trim().isNotEmpty) apartment.text.trim(),
  ];

  void dispose() {
    for (final c in [fullName, phone, area, street, apartment, region]) {
      c.dispose();
    }
    regionId.dispose();
    isDefault.dispose();
  }
}

/// Shared address form fields (Figma "Add Address"), used by both the account
/// add/edit-address screen and checkout. The host wraps this in its own [Form]
/// and reads values from [controller]; this widget only renders fields +
/// validators. The "Set as default" toggle and submit button stay with the host
/// (they differ between checkout and the address book).
class AddressForm extends ConsumerWidget {
  const AddressForm({super.key, required this.controller});

  final AddressFormController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final regions = ref.watch(regionsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LabeledField(
          label: l10n.fieldFullName,
          child: _input(
            controller.fullName,
            l10n.addressHintName,
            textCapitalization: TextCapitalization.words,
            validator: (v) => Validators.required(context, v),
          ),
        ),
        const SizedBox(height: 14),
        _LabeledField(
          label: l10n.fieldPhone,
          // The website's phone field carries a country-code prefix — use the
          // shared `+971` chip field (same as registration) and validate a UAE
          // mobile so the guest-checkout OTP always has a well-formed number.
          child: PhoneNumberField(
            controller: controller.phone,
            hint: l10n.authPhoneHint,
            validator: (v) => Validators.uaePhone(context, v),
          ),
        ),
        const SizedBox(height: 14),
        // State + Country are stacked (not side-by-side) so the full country
        // name "United Arab Emirates" shows without truncating on a phone.
        _LabeledField(
          label: l10n.fieldEmirate,
          child: _emirateInput(context, l10n, regions),
        ),
        const SizedBox(height: 14),
        _LabeledField(
          label: l10n.fieldCountryLabel,
          child: _countryField(l10n),
        ),
        const SizedBox(height: 14),
        _LabeledField(
          label: l10n.fieldStreet,
          child: _input(
            controller.street,
            l10n.addressHintStreet,
            validator: (v) => Validators.required(context, v),
          ),
        ),
        const SizedBox(height: 14),
        // Apartment / floor is optional (Magento street[1]).
        _LabeledField(
          label: l10n.fieldApartment,
          child: _input(controller.apartment, ''),
        ),
      ],
    );
  }

  Widget _emirateInput(
    BuildContext context,
    AppLocalizations l10n,
    AsyncValue<List<RegionOption>> regions,
  ) => regions.when(
    data: (list) => ValueListenableBuilder<int?>(
      valueListenable: controller.regionId,
      builder: (context, value, _) => DropdownButtonFormField<int>(
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(),
        hint: Text(
          l10n.fieldEmirate,
          style: const TextStyle(color: AppColors.inkFaint, fontSize: 13.5),
        ),
        items: [
          for (final r in list)
            DropdownMenuItem<int>(value: r.id, child: Text(r.name)),
        ],
        onChanged: (v) {
          controller.regionId.value = v;
          // There's no separate Area/City field now (matching the website), so
          // derive Magento's required `city` from the selected state name.
          if (v != null) {
            for (final r in list) {
              if (r.id == v) {
                controller.area.text = r.name;
                break;
              }
            }
          }
        },
        validator: (v) => v == null ? l10n.validationRequired : null,
      ),
    ),
    loading: () => const TextField(
      enabled: false,
      decoration: InputDecoration(
        suffixIcon: Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    ),
    // Emirate list unavailable → free-text fallback so the form isn't blocked.
    error: (_, _) => TextFormField(
      controller: controller.region,
      validator: (v) => Validators.required(context, v),
    ),
  );

  /// Country — a dropdown (matching the website's Country control) showing the
  /// full localized country name. The UAE is the only market, so it carries a
  /// single fixed option; it's a dropdown rather than a static field so it reads
  /// as dynamic and the full name is always visible (QA 86d3mdefm #1).
  Widget _countryField(AppLocalizations l10n) =>
      DropdownButtonFormField<String>(
        initialValue: addressCountryCode,
        isExpanded: true,
        decoration: const InputDecoration(),
        items: [
          DropdownMenuItem<String>(
            value: addressCountryCode,
            child: Text(l10n.countryUae),
          ),
        ],
        onChanged: (_) {},
      );

  Widget _input(
    TextEditingController controller,
    String hint, {
    TextInputType? keyboard,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: controller,
    keyboardType: keyboard,
    textCapitalization: textCapitalization,
    decoration: InputDecoration(hintText: hint.isEmpty ? null : hint),
    validator: validator,
  );
}

/// A form field label (Medium 12, muted) sitting above its input — the Figma
/// "Add Address" field pattern.
class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 6, start: 2),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.inkMuted,
          ),
        ),
      ),
      child,
    ],
  );
}
