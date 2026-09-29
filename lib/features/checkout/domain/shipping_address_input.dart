import '../../account/domain/customer_address.dart';

/// Builders for Magento's `ShippingAddressInput`.
///
/// The two shapes are not interchangeable, and picking the wrong one is not a
/// cosmetic mistake. `SetShippingAddressesOnCart` forces
/// `save_in_address_book = true` whenever an `address` literal arrives without a
/// `customer_address_id` and without the flag, so sending a saved address as a
/// literal writes a duplicate address-book row on every checkout. Referencing
/// the id takes Magento's `createBasedOnCustomerAddress` path instead: nothing
/// is saved, and the stored address is used verbatim.
abstract final class ShippingAddressInput {
  /// A saved address, by reference. Never carries an `address` literal.
  static Map<String, dynamic> saved(CustomerAddress address) =>
      <String, dynamic>{'customer_address_id': address.id};

  /// A newly entered address. Magento saves this one to the address book, which
  /// is what a shopper expects when they type an address at checkout.
  static Map<String, dynamic> fresh(Map<String, dynamic> address) =>
      <String, dynamic>{'address': address};
}
