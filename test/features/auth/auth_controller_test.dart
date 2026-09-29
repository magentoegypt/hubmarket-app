import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';

import '../../support/fakes.dart';

ProviderContainer _container({String? token, bool loginFails = false}) {
  final container = ProviderContainer(
    overrides: [
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore(token)),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(loginFails: loginFails),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Same wiring, but with a caller-supplied repository so a test can inspect
/// what the controller asked it to do.
ProviderContainer _containerWith(FakeAuthRepository repo) {
  final container = ProviderContainer(
    overrides: [
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore(null)),
      authRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('AuthController', () {
    test('restores as guest when no token is stored', () async {
      final container = _container();
      container.read(authControllerProvider); // build -> _restore
      await pumpEventQueue();
      expect(container.read(authControllerProvider).status, AuthStatus.guest);
    });

    test('restores an authenticated session from a stored token', () async {
      final container = _container(token: 'persisted');
      container.read(authControllerProvider);
      await pumpEventQueue();
      final state = container.read(authControllerProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.customer?.email, 'layla@example.com');
    });

    test('login authenticates and exposes the customer', () async {
      final container = _container();
      await container
          .read(authControllerProvider.notifier)
          .login('layla@example.com', 'password1');
      final state = container.read(authControllerProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.customer?.fullName, 'Layla Hassan');
    });

    test('login propagates a failure on bad credentials', () async {
      final container = _container(loginFails: true);
      await expectLater(
        container.read(authControllerProvider.notifier).login('x@y.com', 'bad'),
        throwsA(isA<Object>()),
      );
    });

    test('resetPassword completes then signs the customer in', () async {
      final container = _container();
      await container
          .read(authControllerProvider.notifier)
          .resetPassword(
            email: 'layla@example.com',
            token: 'reset-code',
            newPassword: 'newpassword1',
          );
      expect(container.read(authControllerProvider).isAuthenticated, isTrue);
    });

    test('handleSessionExpired drops an authed session to guest', () async {
      final container = _container();
      final notifier = container.read(authControllerProvider.notifier);
      await notifier.login('layla@example.com', 'password1');
      expect(container.read(authControllerProvider).isAuthenticated, isTrue);

      await notifier.handleSessionExpired();
      expect(container.read(authControllerProvider).status, AuthStatus.guest);
    });

    test('logout returns to guest', () async {
      final container = _container();
      final notifier = container.read(authControllerProvider.notifier);
      await notifier.login('layla@example.com', 'password1');
      expect(container.read(authControllerProvider).isAuthenticated, isTrue);

      await notifier.logout();
      expect(container.read(authControllerProvider).status, AuthStatus.guest);
    });

    // CL042-DEV20: an expiry the customer didn't ask for has to be explained,
    // but a logout they tapped themselves must stay quiet.
    group('session-expired signal', () {
      test('rises when a live session is rejected', () async {
        final container = _container();
        final notifier = container.read(authControllerProvider.notifier);
        await notifier.login('layla@example.com', 'password1');
        final before = container.read(sessionExpiredSignalProvider);

        await notifier.handleSessionExpired();

        expect(container.read(sessionExpiredSignalProvider), before + 1);
      });

      test('stays quiet on a deliberate logout', () async {
        final container = _container();
        final notifier = container.read(authControllerProvider.notifier);
        await notifier.login('layla@example.com', 'password1');
        final before = container.read(sessionExpiredSignalProvider);

        await notifier.logout();

        expect(container.read(sessionExpiredSignalProvider), before);
      });

      test('stays quiet when there was no session to lose', () async {
        final container = _container();
        final notifier = container.read(authControllerProvider.notifier);
        await pumpEventQueue(); // settles to guest
        final before = container.read(sessionExpiredSignalProvider);

        await notifier.handleSessionExpired();

        expect(container.read(sessionExpiredSignalProvider), before);
      });
    });

    test('deleteAccount deletes server-side then returns to guest', () async {
      final repo = FakeAuthRepository();
      final container = _containerWith(repo);
      final notifier = container.read(authControllerProvider.notifier);
      await notifier.login('layla@example.com', 'password1');

      await notifier.deleteAccount();
      expect(repo.deleteAccountCalled, isTrue);
      expect(container.read(authControllerProvider).status, AuthStatus.guest);
    });

    // The customer must stay signed in when the server refuses, otherwise the
    // app looks like it deleted an account that still exists.
    test('deleteAccount keeps the session when the server refuses', () async {
      final repo = FakeAuthRepository()..deleteAccountFails = true;
      final container = _containerWith(repo);
      final notifier = container.read(authControllerProvider.notifier);
      await notifier.login('layla@example.com', 'password1');

      await expectLater(notifier.deleteAccount(), throwsA(isA<Object>()));
      expect(container.read(authControllerProvider).isAuthenticated, isTrue);
    });
  });
}
