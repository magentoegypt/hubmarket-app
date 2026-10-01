import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/graphql/resilience_link.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/store/store_repository.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/presentation/screens/edit_profile_screen.dart';
import 'package:hubmarket_app/core/widgets/hub_switch.dart';
import 'package:hubmarket_app/features/auth/presentation/widgets/auth_field.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/notifications/presentation/notification_settings_controller.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';

/// Magento's answer to a wrong current password (CustomerGraphQl's
/// CheckCustomerPassword): an authentication error on the mutation's field,
/// sent with HTTP 401.
const GraphQLError _wrongPassword = GraphQLError(
  message: 'Invalid login or password.',
  path: ['changeCustomerPassword'],
  extensions: {'category': 'graphql-authentication'},
);

/// What `changePassword` throws when the server answers [answer].
Future<Failure> _changePasswordFailure(Object answer) async {
  final client = fakeHubAppClient({'ChangePassword': answer});
  Object? thrown;
  try {
    await AccountRepository(client).changePassword('old-secret', 'New@2026x');
  } on Object catch (error) {
    thrown = error;
  }
  expect(
    client.requests.single.context.entry<CredentialCheck>(),
    isNotNull,
    reason: 'the session must survive a refused password',
  );
  expect(thrown, isA<Failure>());
  return thrown! as Failure;
}

/// Records the change-password call and fails it with the store's message.
class _RefusingAccountRepository extends FakeAccountRepository {
  _RefusingAccountRepository(this.refusal);

  final Object refusal;
  final List<String> changes = [];
  final List<String> profileSaves = [];

  /// Save changes saves the profile first; the refusal comes after it.
  @override
  Future<void> updateProfile({
    required String firstName,
    required String lastName,
    String? dateOfBirth,
  }) async {
    profileSaves.add('$firstName $lastName');
  }

  @override
  Future<void> changePassword(String current, String next) async {
    changes.add('$current>$next');
    throw refusal;
  }
}

Future<void> _pumpProfile(
  WidgetTester tester,
  _RefusingAccountRepository account, {
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: AppRoutes.editProfile,
    routes: [
      GoRoute(
        path: AppRoutes.editProfile,
        builder: (_, __) => const EditProfileScreen(),
      ),
      for (final path in [
        AppRoutes.home,
        AppRoutes.categories,
        AppRoutes.cart,
        AppRoutes.wishlist,
        AppRoutes.account,
        AppRoutes.signIn,
      ])
        GoRoute(path: path, builder: (_, __) => const Scaffold()),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheProvider.overrideWithValue(FakeLocalCache()),
        localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
        secureTokenStoreProvider.overrideWithValue(
          FakeSecureTokenStore('persisted'),
        ),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(customer: kSampleCustomer),
        ),
        storeRepositoryProvider.overrideWithValue(
          FakeStoreRepository(kSampleStores),
        ),
        graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
        cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
        wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
        accountRepositoryProvider.overrideWithValue(account),
        storeFeaturesProvider.overrideWith(
          (ref) async => const StoreFeatures(newsletterEnabled: false),
        ),
        pushNotificationsAvailableProvider.overrideWithValue(false),
        hubAppOverride(const HubAppState.unavailable()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: Locale(locale),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The text field of the [AuthField] labelled [label].
Finder _field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(AuthField)),
  matching: find.byType(TextField),
);

/// Opens the Change password card, fills it and presses Save changes.
Future<void> _submitPasswords(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  await tester.tap(find.byType(HubSwitch));
  await tester.pumpAndSettle();
  await tester.enterText(_field(l10n.fieldCurrentPassword), 'old-secret');
  await tester.enterText(_field(l10n.fieldNewPassword), 'New@2026x');
  await tester.enterText(_field(l10n.profileConfirmNewPassword), 'New@2026x');
  final save = find.widgetWithText(FilledButton, l10n.profileSaveChanges);
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  group('AccountRepository.changePassword', () {
    test(
      "a wrong current password carries the store's message (401)",
      () async {
        final failure = await _changePasswordFailure(
          const ServerException(
            statusCode: 401,
            parsedResponse: Response(response: {}, errors: [_wrongPassword]),
          ),
        );
        expect(failure.kind, FailureKind.server);
        expect(failure.detail, 'Invalid login or password.');
      },
    );

    test('also when the refusal comes as a GraphQL error', () async {
      final failure = await _changePasswordFailure(
        const Response(response: {}, errors: [_wrongPassword]),
      );
      expect(failure.kind, FailureKind.server);
      expect(failure.detail, 'Invalid login or password.');
    });

    test('a new password the store refuses keeps its message', () async {
      const message =
          "The password can't be the same as the email address. Create a "
          'new password and try again.';
      final failure = await _changePasswordFailure(
        const Response(
          response: {},
          errors: [
            GraphQLError(
              message: message,
              path: ['changeCustomerPassword'],
              extensions: {'category': 'graphql-input'},
            ),
          ],
        ),
      );
      expect(failure.kind, FailureKind.server);
      expect(failure.detail, message);
    });
  });

  group('Profile details › Change password', () {
    testWidgets("shows the store's refusal, not a generic error", (
      tester,
    ) async {
      final en = lookupAppLocalizations(const Locale('en'));
      final account = _RefusingAccountRepository(
        const Failure(FailureKind.server, detail: 'Invalid login or password.'),
      );
      await _pumpProfile(tester, account);
      await _submitPasswords(tester, en);

      // The profile went first, then the password, which the store refused.
      expect(account.profileSaves, ['Layla Hassan']);
      expect(account.changes, ['old-secret>New@2026x']);
      expect(find.text('Invalid login or password.'), findsOneWidget);
      expect(find.text(en.errorGeneric), findsNothing);
    });

    testWidgets('a failure without a message stays generic', (tester) async {
      final en = lookupAppLocalizations(const Locale('en'));
      final account = _RefusingAccountRepository(
        const Failure(FailureKind.unknown, detail: 'trace'),
      );
      await _pumpProfile(tester, account);
      await _submitPasswords(tester, en);

      expect(find.text(en.errorGeneric), findsOneWidget);
      expect(find.text('trace'), findsNothing);
    });
  });
}
