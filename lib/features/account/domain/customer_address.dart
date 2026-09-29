class CustomerAddress {
  const CustomerAddress({
    this.id,
    required this.firstName,
    required this.lastName,
    required this.telephone,
    required this.street,
    required this.city,
    this.apartment = '',
    this.postcode = '',
    this.region = '',
    this.regionId,
    this.countryCode = 'AE',
    this.defaultShipping = false,
    this.defaultBilling = false,
    this.labelOptionId,
    this.labelText,
  });

  final int? id;
  final String firstName;
  final String lastName;
  final String telephone;

  /// Street line — Magento `street[0]`.
  final String street;

  /// Apartment / floor — optional Magento `street[1]`.
  final String apartment;

  /// Locality / district (Magento `city`), shown as "Area" in the form.
  final String city;
  final String postcode;

  /// Free-text region label (fallback / display).
  final String region;

  /// Magento system region id (a UAE emirate). Required for AE addresses.
  final int? regionId;
  final String countryCode;
  final bool defaultShipping;
  final bool defaultBilling;

  /// Selected `address_label` option id (e.g. "123") — written as
  /// `custom_attributesV2`. Null when no label is chosen.
  final String? labelOptionId;

  /// Display label of the selected `address_label` option (e.g. "Home"), read
  /// from `selected_options` (store-scoped, so the AR store returns AR labels).
  final String? labelText;

  String get fullName => '$firstName $lastName'.trim();

  /// Compact one-line address for cards (saved addresses, checkout selection).
  /// `city` is the app-derived emirate — a duplicate of `region`, sometimes in a
  /// different language ("Dubai" vs "دبي") — so the emirate is shown once via
  /// `region` (falling back to `city`). The country is always the UAE here, so
  /// it isn't repeated on every card (previously rendered as a raw "AE").
  String get summary {
    final emirate = region.isNotEmpty ? region : city;
    return [
      street,
      apartment,
      emirate,
    ].where((p) => p.isNotEmpty).join(', ');
  }

  /// Magento `CustomerAddressInput`. AE has system regions, so a valid
  /// `region_id` is sent (nested under `region`) rather than free-text.
  Map<String, dynamic> toInput() => <String, dynamic>{
    'firstname': firstName,
    'lastname': lastName,
    'telephone': telephone,
    'street': [street, if (apartment.isNotEmpty) apartment],
    'city': city,
    if (postcode.isNotEmpty) 'postcode': postcode,
    'country_code': countryCode,
    if (regionId != null)
      'region': <String, dynamic>{'region_id': regionId}
    else if (region.isNotEmpty)
      'region': <String, dynamic>{'region': region},
    'default_shipping': defaultShipping,
    'default_billing': defaultBilling,
    // `address_label` is a select attribute — the value is the option id.
    if (labelOptionId != null && labelOptionId!.isNotEmpty)
      'custom_attributesV2': <Map<String, dynamic>>[
        {'attribute_code': 'address_label', 'value': labelOptionId},
      ],
  };
}
