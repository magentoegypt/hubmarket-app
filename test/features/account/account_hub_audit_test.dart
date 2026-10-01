import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/customer_address.dart';
import 'package:hubmarket_app/features/account/domain/saved_card.dart';
import 'package:hubmarket_app/features/account/presentation/account_overview.dart';
import 'package:hubmarket_app/features/account/presentation/account_screen.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';

import '../../support/fonts.dart';
import 'audit_harness.dart';

/// Renders the Account hub as Figma 20 draws it (and its Arabic twin AR-20) to
/// `build/test_screens/audit_20_account_<locale>.png`, the capture
/// `tool/ui_audit/pairs.py` pairs with the frame. The frame's customer: 7
/// orders (2 active), 5 wishlist items, 1 open return, 2 saved addresses,
/// AED 120 of credit, a card in the vault, and AED 1,284 spent over 7 orders.

const _address = CustomerAddress(
  firstName: 'Sara',
  lastName: 'Ahmed',
  telephone: '+971501234567',
  street: 'Marina Walk',
  city: 'Dubai Marina',
);

void main() {
  setUpAll(loadAppFonts);

  for (final locale in const ['en', 'ar']) {
    testWidgets('20 Account ($locale)', (tester) async {
      final wishlist = (await tester.runAsync(() => wishlistOf(5)))!;
      final boundary = await pumpAuditScreen(
        tester,
        screen: const AccountScreen(),
        pushed: false,
        locale: locale,
        // The frames' full scroll: 1287 (EN) / 1331 (AR).
        height: locale == 'ar' ? 1331 : 1287,
        wishlist: wishlist,
        overrides: [
          accountOrdersOverviewProvider.overrideWith(
            (ref) async => const AccountOrdersOverview(
              activeCount: 2,
              stats: ShoppingStats(
                totalSpent: Money(amount: 1284, currency: 'AED'),
                ordersThisYear: 7,
                averageOrder: Money(amount: 183.4, currency: 'AED'),
              ),
            ),
          ),
          openReturnsCountProvider.overrideWith((ref) async => 1),
          addressesProvider.overrideWith(
            (ref) async => const [_address, _address],
          ),
          savedCardsProvider.overrideWith(
            (ref) async => const [
              SavedCard(
                publicHash: 'h1',
                brandCode: 'VI',
                last4: '4242',
                expiryMonth: 8,
                expiryYear: 2028,
              ),
            ],
          ),
        ],
      );
      await captureAudit(tester, boundary, 'audit_20_account', locale);
    });
  }
}
