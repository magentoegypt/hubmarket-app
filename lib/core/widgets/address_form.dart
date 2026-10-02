import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../address/city_fields.dart';
import '../validation/phone.dart';
import '../validation/validators.dart';

/// Holds the editable address fields, created and disposed by the host screen.
/// Mirrors the Figma "Add Address" form: a single Full Name, phone, an Emirate
/// picker + Area, a street line and an optional apartment/floor line. `regionId`
/// and `isDefault` are [ValueNotifier]s so their controls rebuild on change
/// without the host needing a `setState`.
class AddressFormController {
  AddressFormController({
    String country = 'AE',
    String fullName = '',
    String phone = '',
    String area = '',
    String street = '',
    String apartment = '',
    String region = '',
    int? regionId,
    bool isDefault = false,
  }) : country = ValueNotifier(country),
       fullName = TextEditingController(text: fullName),
       phone = TextEditingController(text: phone),
       area = TextEditingController(text: area),
       street = TextEditingController(text: street),
       apartment = TextEditingController(text: apartment),
       region = TextEditingController(text: region),
       regionId = ValueNotifier<int?>(regionId),
       isDefault = ValueNotifier<bool>(isDefault);

  final ValueNotifier<String> country;
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
    return (
      first: parts.sublist(0, parts.length - 1).join(' '),
      last: parts.last,
    );
  }

  /// The phone in explicit E.164 (`+971…`) for Magento / the guest-OTP flow —
  /// the field only holds local digits, so re-add the country code on read.
  String e164Phone() {
    final raw = phone.text.trim();
    return country.value == 'AE' || raw.startsWith('+') || raw.startsWith('00')
        ? Phone.normalizeUae(raw)
        : raw;
  }

  String? validatePhone(BuildContext context, String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return Validators.required(context, value);
    // A delivery country must not change the customer's international number.
    if (raw.startsWith('+') || raw.startsWith('00')) {
      if (RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(Phone.normalizeUae(raw))) return null;
    } else if (country.value == 'AE') {
      return Validators.uaePhone(context, value);
    }
    return Localizations.localeOf(context).languageCode == 'ar'
        ? 'أدخل رقم الهاتف مع رمز الدولة'
        : 'Enter phone including +country code';
  }

  /// Magento `street` array — drops the apartment line when empty.
  List<String> streetLines() => [
    street.text.trim(),
    if (apartment.text.trim().isNotEmpty) apartment.text.trim(),
  ];

  void dispose() {
    for (final c in [fullName, phone, area, street, apartment, region]) {
      c.dispose();
    }
    country.dispose();
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
          child: TextFormField(
            controller: controller.phone,
            decoration: InputDecoration(hintText: l10n.authPhoneHint),
            validator: (v) => controller.validatePhone(context, v),
          ),
        ),
        const SizedBox(height: 14),
        AddressCityFields(controller: controller),
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
