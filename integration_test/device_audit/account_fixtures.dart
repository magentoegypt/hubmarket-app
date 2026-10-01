import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/store/store_controller.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/saved_card.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/domain/customer.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';
import 'package:hubmarket_app/features/cms/data/cms_repository.dart';
import 'package:hubmarket_app/features/notifications/data/notification_inbox.dart';
import 'package:hubmarket_app/features/notifications/domain/notification_item.dart';
import 'package:hubmarket_app/features/notifications/presentation/notification_settings_controller.dart';
import 'package:hubmarket_app/features/store_credit/data/store_credit_repository.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';

import '../../test/support/fakes.dart';
import '../../test/support/store_credit_fakes.dart';
import 'audit_scene.dart';
import 'harness.dart';

/// What the Account scenes (E20 .. E20h, E27, E28) share. They are ported from
/// test/features/account/account_hub_audit_test.dart and
/// account_subpages_audit_test.dart, which mount their screens with
/// `pumpAuditScreen` (test/features/account/audit_harness.dart) — a harness
/// that differs a little from the one the device audit uses
/// (`auditOverrides` in test/support/audit_pump.dart). [accountSetup] closes
/// that gap, so each scene runs over the same fakes its widget test does.

/// The customer of the Account frames (Figma 20, 20c, 27).
const Customer kAccountCustomer = Customer(
  firstName: 'Sara',
  lastName: 'Ahmed',
  email: 'sara.ahmed@gmail.com',
  mobileNumber: '+971501234567',
);

/// The Arabic frames' customer.
const Customer kAccountCustomerAr = Customer(
  firstName: 'سارة',
  lastName: 'أحمد',
  email: 'sara.ahmed@gmail.com',
  mobileNumber: '+971501234567',
);

/// The Hub Market App there with returns and store credit on, as the Account
/// frame (20) assumes: the Returns tile, My credit and the credit line of
/// Privacy & data all depend on these two switches.
const HubAppState kAccountHubApp = HubAppState.available(
  HmAppConfig(
    storeCode: 'en',
    locale: 'en_US',
    features: {'returns': true, 'store_credit': true},
  ),
);

/// The store's switches in the account tests: the newsletter and the contact
/// form on (the harness's own also turns order cancellation on, which no
/// Account screen reads).
const StoreFeatures kAccountFeatures = StoreFeatures(
  newsletterEnabled: true,
  contactEnabled: true,
);

/// The card of Figma 20 and 20e.
const SavedCard kVisaCard = SavedCard(
  publicHash: 'h1',
  brandCode: 'VI',
  last4: '4242',
  expiryMonth: 8,
  expiryYear: 2028,
);

/// The Mastercard Figma 20e lists under it.
const SavedCard kMastercard = SavedCard(
  publicHash: 'h2',
  brandCode: 'MC',
  last4: '5100',
  expiryMonth: 11,
  expiryYear: 2027,
);

/// A wishlist that already holds [count] products (the frame's "5 wishlist
/// items"). `wishlistOf` in test/features/account/audit_harness.dart adds them
/// with awaits before the app is mounted; a scene's `setup` is synchronous, so
/// the products go in on the first read instead.
class SeededWishlist extends FakeWishlistRepository {
  SeededWishlist(this.count);

  final int count;
  bool _seeded = false;

  @override
  Future<WishlistData?> fetchWishlist() async {
    if (!_seeded) {
      _seeded = true;
      for (var i = 1; i <= count; i++) {
        await addProduct('wl-1', 'sku-$i');
      }
    }
    return super.fetchWishlist();
  }
}

/// The store controller with the store views already loaded, as the app's
/// bootstrap leaves it before any screen is built: store URLs need them —
/// without them Account has no "Sell on Hub Market" row. `pumpAuditScreen`
/// runs `loadStores()` and settles before it pushes the screen; a scene
/// mounts through the harness's `runScene`, which has no such step. Loading
/// them after the screen is up does not work either: the store code changes
/// under the controllers that load their data in a microtask, and they fail
/// with "Cannot use ref functions after the dependency of a provider
/// changed". So the state is built loaded, from the sample store views, the
/// way `StoreController._applyStores` would map them.
class _StoreViewsController extends StoreController {
  @override
  StoreState build() {
    final initial = super.build();
    final defaultStore = kSampleStores.firstWhere(
      (s) => s.isDefault,
      orElse: () => kSampleStores.first,
    );
    return initial.copyWith(
      stores: kSampleStores,
      localeToCode: {
        for (final s in kSampleStores) s.languageCode: s.storeCode,
      },
      defaultLocale: defaultStore.languageCode,
      currency: defaultStore.currency,
    );
  }
}

/// [AuditSetup] for an Account scene: the fakes `pumpAuditScreen` gives every
/// screen of the area, on top of the harness's own. The customer of the
/// frames (Sara Ahmed, in the language of the capture), the Hub Market App
/// with returns and store credit on, an empty CMS, the store credit backend
/// ([credit]: AED 120 by default), no saved card, 7 orders, push available and
/// the store views loaded. [account] and [wishlist] replace the harness's
/// empty ones; [overrides] go last, so a scene's own fakes win.
AuditSetup accountSetup(
  String locale, {
  AccountRepository? account,
  WishlistRepository? wishlist,
  FakeStoreCreditRepository? credit,
  List<Override> overrides = const [],
}) => AuditSetup(
  account: account,
  wishlist: wishlist,
  features: kAccountFeatures,
  hubApp: kAccountHubApp,
  overrides: [
    authRepositoryProvider.overrideWithValue(
      FakeAuthRepository(
        customer: locale == 'ar' ? kAccountCustomerAr : kAccountCustomer,
      ),
    ),
    cmsRepositoryProvider.overrideWithValue(FakeCmsRepository()),
    storeCreditRepositoryProvider.overrideWithValue(
      credit ?? FakeStoreCreditRepository(),
    ),
    savedCardsProvider.overrideWith((ref) async => const <SavedCard>[]),
    customerOrderCountProvider.overrideWith((ref) => 7),
    // The frames show the Notifications row and the push switch, which a
    // build without a Firebase config hides.
    pushNotificationsAvailableProvider.overrideWithValue(true),
    storeControllerProvider.overrideWith(_StoreViewsController.new),
    ...overrides,
  ],
);

/// Mounts [child] once the session has been restored, whether to a customer or
/// to a guest. The app restores it at launch, before any screen can be opened,
/// but the harness mounts the screen at once, and a screen that reads the
/// customer only when it is built would see none: the Help centre's contact
/// form fills in the name, the e-mail and the phone from it (Figma 27 draws
/// them filled), and in the widget test that renders the frame they are empty
/// for the same reason.
class SessionRestored extends ConsumerWidget {
  const SessionRestored({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restored = ref.watch(
      authControllerProvider.select((s) => s.status != AuthStatus.unknown),
    );
    return restored ? child : const SizedBox.shrink();
  }
}

/// The notification inbox (a process-wide singleton, which the feed binds to)
/// holding [items] while [child] is up, and empty again afterwards: the widget
/// tests do it with a `tearDown`, and a leaked inbox would put an unread dot
/// on every bell the next scenes draw.
class InboxSeed extends StatefulWidget {
  const InboxSeed({super.key, required this.items, required this.child});

  final List<NotificationItem> items;
  final Widget child;

  @override
  State<InboxSeed> createState() => _InboxSeedState();
}

class _InboxSeedState extends State<InboxSeed> {
  @override
  void initState() {
    super.initState();
    NotificationInbox.instance.items.value = widget.items;
  }

  @override
  void dispose() {
    NotificationInbox.instance.items.value = const [];
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Builds [target] and brings it into view. A list builds only what is near
/// its viewport, and the phone's viewport is 360 x 820 where the widget tests'
/// is as tall as the frame, so a field or a checkbox further down does not
/// exist yet: scroll the main scroll view a screen at a time until it does.
Future<void> revealWidget(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 12 && target.evaluate().isEmpty; i++) {
    if (!scrollMain(tester)) break;
    await pumpFor(tester, 150);
  }
  await tester.ensureVisible(target);
  await pumpFor(tester, 150);
}

/// Types [text] into [field] as the widget tests do (`tester.enterText`), on
/// the phone as well as in the test renderer. The integration-test binding
/// leaves the fake keyboard (`testTextInput`) uninstalled, "to test real IME
/// input": `enterText` would then raise the phone's own keyboard, whose inset
/// resizes the screen under the capture. So the fake keyboard is installed for
/// the typing and taken away again, and the field is let go of: filled but not
/// focused, which is also how the frames draw it. [field] must be built
/// (`revealWidget`).
Future<void> typeInto(WidgetTester tester, Finder field, String text) async {
  final keyboard = tester.testTextInput;
  final install = !keyboard.isRegistered;
  if (install) keyboard.register();
  try {
    await tester.enterText(field, text);
    // Closes the connection through the fake keyboard, while it is still there.
    FocusManager.instance.primaryFocus?.unfocus();
    await pumpFor(tester, 100);
  } finally {
    if (install) keyboard.unregister();
  }
}

/// Back to the top of every vertical scroll view, so the capture (and the
/// scrolled ones after it) start from the screen's first row after an `act`
/// that had to scroll down to reach something.
void scrollToTop(WidgetTester tester) {
  for (final element in find.byType(Scrollable).evaluate()) {
    if (element is! StatefulElement) continue;
    final state = element.state;
    if (state is! ScrollableState) continue;
    final axis = state.axisDirection;
    if (axis == AxisDirection.left || axis == AxisDirection.right) continue;
    state.position.jumpTo(0);
  }
}
