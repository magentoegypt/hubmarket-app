import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/account/domain/customer_address.dart';
import 'package:hubmarket_app/features/account/presentation/screens/addresses_screen.dart';

import '../../support/audit_pump.dart';
import '../../support/fakes.dart';
import '../../support/fonts.dart';

/// Renders Figma 24 "Saved addresses" (22:1452 / 53:2139) in English and Arabic
/// to build/test_screens/audit_24_addresses_{en,ar}.png and checks what the
/// radio cards do.
class _AddressBook extends FakeAccountRepository {
  _AddressBook(this.addresses);

  List<CustomerAddress> addresses;
  final List<({int id, bool defaultShipping})> updates = [];
  final List<int> deleted = [];

  @override
  Future<List<CustomerAddress>> fetchAddresses() async => addresses;

  @override
  Future<void> updateAddress(int id, CustomerAddress address) async {
    updates.add((id: id, defaultShipping: address.defaultShipping));
  }

  @override
  Future<void> deleteAddress(int id) async {
    deleted.add(id);
  }
}

List<CustomerAddress> _book(String locale) {
  final ar = locale == 'ar';
  return [
    CustomerAddress(
      id: 1,
      firstName: ar ? 'سارة' : 'Sara',
      lastName: ar ? 'أحمد' : 'Ahmed',
      telephone: '+971501234567',
      apartment: ar ? 'شقة 1204' : 'Apt 1204',
      street: ar ? 'مارينا جيت 2' : 'Marina Gate 2',
      city: ar ? 'دبي مارينا' : 'Dubai Marina',
      region: ar ? 'دبي' : 'Dubai',
      defaultShipping: true,
      labelText: ar ? 'المنزل' : 'Home',
    ),
    CustomerAddress(
      id: 2,
      firstName: ar ? 'سارة' : 'Sara',
      lastName: ar ? 'أحمد' : 'Ahmed',
      telephone: '+971501234567',
      street: ar ? 'مكتب 802، مبنى 4' : 'Office 802, Building 4',
      city: ar ? 'مدينة دبي للإنترنت' : 'Dubai Internet City',
      region: ar ? 'دبي' : 'Dubai',
      labelText: ar ? 'العمل' : 'Office',
    ),
  ];
}

void main() {
  setUpAll(loadAppFonts);

  for (final locale in ['en', 'ar']) {
    testWidgets('24 Saved addresses ($locale)', (tester) async {
      final key = GlobalKey();
      await pumpAudit(
        tester,
        locale: locale,
        boundary: key,
        screen: const AddressesScreen(),
        account: _AddressBook(_book(locale)),
      );
      await captureScreen(tester, key, 'audit_24_addresses_$locale');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('24 Saved addresses: the radio cards', (tester) async {
    final book = _AddressBook(_book('en'));
    await pumpAudit(
      tester,
      screen: const AddressesScreen(),
      account: book,
    );
    expect(find.text('Addresses'), findsOneWidget);
    expect(find.text('DEFAULT'), findsOneWidget);
    expect(find.text('Sara Ahmed · \u2066+971 50 123 4567\u2069'), findsNWidgets(2));
    expect(
      find.text('Apt 1204, Marina Gate 2, Dubai Marina, Dubai, UAE'),
      findsOneWidget,
    );
    expect(
      find.text('Office 802, Building 4, Dubai Internet City, Dubai, UAE'),
      findsOneWidget,
    );
    expect(find.text('Add new address'), findsOneWidget);
    // No map or location access: the frame's "Use my current location" is out.
    expect(find.text('Use my current location'), findsNothing);

    // Choosing the other card sends it back as the default shipping address.
    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();
    expect(book.updates, [(id: 2, defaultShipping: true)]);

    // The default one is already chosen: tapping it does nothing.
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(book.updates, hasLength(1));
  });

  testWidgets('24 Saved addresses: empty book', (tester) async {
    await pumpAudit(
      tester,
      screen: const AddressesScreen(),
      account: _AddressBook(const []),
    );
    expect(find.text('No saved addresses yet.'), findsOneWidget);
    expect(find.text('Add new address'), findsOneWidget);
  });
}
