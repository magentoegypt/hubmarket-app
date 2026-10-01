import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';
import 'package:hubmarket_app/features/account/data/address_rules.dart';
import 'package:hubmarket_app/features/account/domain/customer_address.dart';
import 'package:hubmarket_app/features/account/presentation/screens/address_form_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/addresses_screen.dart';

import '../../support/audit_pump.dart';
import '../../support/fakes.dart';
import '../../support/fonts.dart';

/// Renders Figma 24 "Saved addresses" (22:1452 / 53:2139) in English and Arabic
/// to build/test_screens/audit_24_addresses_{en,ar}.png and checks what the
/// radio cards do.
class _AddressBook extends FakeAccountRepository {
  _AddressBook(this.addresses, {this.locale = 'en'});

  List<CustomerAddress> addresses;
  final String locale;
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

  final List<CustomerAddress> created = [];

  @override
  Future<void> createAddress(CustomerAddress address) async {
    created.add(address);
  }

  /// The store's `address_label` options.
  @override
  Future<List<({String value, String label})>> fetchAddressLabelOptions() async =>
      locale == 'ar'
      ? const [
          (value: '1', label: 'المنزل'),
          (value: '2', label: 'العمل'),
          (value: '3', label: 'آخر'),
        ]
      : const [
          (value: '1', label: 'Home'),
          (value: '2', label: 'Work'),
          (value: '3', label: 'Other'),
        ];
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

/// The UAE has no postcodes: the frame has no such field, and a store whose
/// settings make it optional shows none.
final _noPostcode = postcodeRequiredProvider.overrideWith((ref) async => false);

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

  // Figma 24b (84:3411 / 99:3799), filled the way the frame shows it.
  for (final locale in ['en', 'ar']) {
    testWidgets('24b Add address ($locale)', (tester) async {
      final ar = locale == 'ar';
      final key = GlobalKey();
      final book = _AddressBook(const [], locale: locale);
      await pumpAudit(
        tester,
        locale: locale,
        boundary: key,
        height: ar ? 1208 : 1198,
        screen: const AddressFormScreen(),
        account: book,
        overrides: [_noPostcode],
      );
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), ar ? 'سارة أحمد' : 'Sara Ahmed');
      await tester.enterText(fields.at(1), '+971 50 123 4567');
      await tester.tap(find.byIcon(HubIcons.globe));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ar ? 'دبي' : 'Dubai').last);
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(2), ar ? 'مارينا جيت 2' : 'Marina Gate 2');
      await tester.enterText(fields.at(3), '1204');
      await tester.tap(find.text(ar ? 'المنزل' : 'Home').last);
      await tester.tap(
        find.text(ar ? 'تعيين كعنوان افتراضي' : 'Set as default address'),
      );
      await tester.pumpAndSettle();
      await captureScreen(tester, key, 'audit_24b_address_form_$locale');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('24b Add address: saves what was filled in', (tester) async {
    final book = _AddressBook(const []);
    await pumpAudit(
      tester,
      height: 1198,
      screen: const AddressFormScreen(),
      account: book,
      overrides: [_noPostcode],
    );
    // The frame's map, location, area, landmark and OTP rows have nothing
    // behind them in the app.
    for (final out in [
      'Use my current location',
      'Move the map to pin your building',
      'Area',
      'Landmark (optional)',
      'Get OTP',
    ]) {
      expect(find.text(out), findsNothing);
    }
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Sara Ahmed');
    await tester.enterText(fields.at(1), '050 123 4567');
    await tester.tap(find.byIcon(HubIcons.globe));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dubai').last);
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(2), 'Marina Gate 2');
    await tester.enterText(fields.at(3), '1204');
    await tester.tap(find.text('Work'));
    await tester.tap(find.text('Set as default address'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save address'));
    await tester.pumpAndSettle();
    expect(book.created, hasLength(1));
    final saved = book.created.single;
    expect(saved.firstName, 'Sara');
    expect(saved.lastName, 'Ahmed');
    expect(saved.telephone, '+971501234567');
    expect(saved.region, 'Dubai');
    expect(saved.city, 'Dubai');
    expect(saved.street, 'Marina Gate 2');
    expect(saved.apartment, '1204');
    expect(saved.labelOptionId, '2');
    expect(saved.defaultShipping, isTrue);
  });

  testWidgets('24b Edit address: keeps what the address was saved with', (
    tester,
  ) async {
    final book = _AddressBook(_book('en'));
    await pumpAudit(
      tester,
      height: 1198,
      screen: AddressFormScreen(initial: _book('en').first),
      account: book,
      overrides: [_noPostcode],
    );
    expect(find.text('Edit address'), findsOneWidget);
    final fields = find.byType(TextField);
    expect(tester.widget<TextField>(fields.at(0)).controller!.text, 'Sara Ahmed');
    expect(
      tester.widget<TextField>(fields.at(1)).controller!.text,
      '+971 50 123 4567',
    );
    // Saved as text only (the store has no UAE regions): shown as it is.
    expect(find.text('Dubai'), findsOneWidget);
    await tester.tap(find.text('Save address'));
    await tester.pumpAndSettle();
    expect(book.updates, [(id: 1, defaultShipping: true)]);
  });

  testWidgets('24b Add address: asks for the required fields', (tester) async {
    final book = _AddressBook(const []);
    await pumpAudit(
      tester,
      height: 1198,
      screen: const AddressFormScreen(),
      account: book,
      overrides: [_noPostcode],
    );
    await tester.tap(find.text('Save address'));
    await tester.pumpAndSettle();
    expect(book.created, isEmpty);
    expect(find.text('Required'), findsWidgets);
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
