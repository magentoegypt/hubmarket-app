import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../../core/storage/secure_token_store.dart';
import '../../notifications/data/device_token_repository.dart';
import '../data/auth_repository.dart';
import '../domain/customer.dart';

enum AuthStatus { unknown, authenticated, guest }

class AuthState {
  const AuthState({this.customer, this.status = AuthStatus.unknown});

  final Customer? customer;
  final AuthStatus status;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

/// Bumped every time a session ends **against the customer's will** — Magento
/// rejects the bearer mid-flight (`graphql-authorization` / "Consumer key has
/// expired") or the persisted token is already dead at launch.
///
/// The app chrome listens and says so, because silently dropping to guest left
/// people with a bare "Something went wrong" and no idea they had been signed
/// out (CL042-DEV20). Deliberately **not** raised by [AuthController.logout] or
/// [AuthController.deleteAccount]: those are the customer's own doing.
class SessionExpiredSignal extends Notifier<int> {
  @override
  int build() => 0;

  void raise() => state = state + 1;
}

final sessionExpiredSignalProvider =
    NotifierProvider<SessionExpiredSignal, int>(SessionExpiredSignal.new);

/// Owns the customer session: restores a persisted token on startup, and drives
/// login / register / logout / password-reset. The token lives in secure
/// storage; [AuthLink] reads it per request.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(_restore);
    return const AuthState();
  }

  SecureTokenStore get _tokens => ref.read(secureTokenStoreProvider);
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> _restore() async {
    final token = await _tokens.read();
    if (token == null) {
      state = const AuthState(status: AuthStatus.guest);
      return;
    }
    try {
      final customer = await _repo.fetchCustomer();
      state = AuthState(customer: customer, status: AuthStatus.authenticated);
    } on Failure catch (failure) {
      if (failure.kind == FailureKind.auth) {
        // Token actually rejected -> drop it and continue as guest. Tell the
        // customer: from their side the app just "forgot" them.
        await _tokens.clear();
        state = const AuthState(status: AuthStatus.guest);
        _signalSessionExpired();
      } else {
        // Transient failure at launch (network / WAF-HTML / timeout) — do NOT
        // log the customer out. Keep the token and stay signed in; the profile
        // refreshes on the next successful request, and a genuinely-expired
        // token is caught mid-session by the resilience link.
        state = const AuthState(status: AuthStatus.authenticated);
      }
    } on Object {
      // Non-Failure error — be conservative and keep the session rather than
      // wiping a possibly-valid token on a transient hiccup.
      state = const AuthState(status: AuthStatus.authenticated);
    }
  }

  Future<void> login(String email, String password) async {
    final token = await _repo.login(email, password);
    await _completeLogin(token);
  }

  /// Shared post-authentication effects for both password and OTP login:
  /// persist the token, reset the cache (drop guest data; [AuthLink] now sends
  /// the bearer), load the profile, and re-bind this device's FCM token.
  Future<void> _completeLogin(String token) async {
    await _tokens.write(token);
    ref.invalidate(graphqlClientProvider);
    final customer = await _repo.fetchCustomer();
    state = AuthState(customer: customer, status: AuthStatus.authenticated);
    unawaited(ref.read(deviceTokenSyncProvider).register());
  }

  Future<void> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? mobileNumber,
  }) async {
    await _repo.register(
      firstName: firstName,
      lastName: lastName,
      email: email,
      password: password,
      mobileNumber: mobileNumber,
    );
    await login(email, password);
  }

  // --- WhatsApp OTP ----------------------------------------------------------

  /// Sends a passwordless-login OTP to [phone].
  Future<void> requestLoginOtp(String phone) => _repo.requestLoginOtp(phone);

  /// Completes a passwordless login: exchanges the code for a token and runs the
  /// same post-login flow as an email/password sign-in.
  Future<void> loginWithOtp(String phone, String code) async {
    final token = await _repo.loginWithOtp(phone, code);
    await _completeLogin(token);
  }

  /// Requests / verifies the registration OTP (WhatsApp). Verification must land
  /// within the module's post-verify window before the account is created.
  Future<void> requestRegistrationOtp(String phone) =>
      _repo.requestRegistrationOtp(phone);
  Future<void> verifyRegistrationOtp(String phone, String code) =>
      _repo.verifyRegistrationOtp(phone, code);

  /// Requests a password-reset OTP (always succeeds server-side).
  Future<void> requestPasswordResetOtp(String phone) =>
      _repo.requestPasswordResetOtp(phone);

  /// Resets the password with a phone OTP. The customer then signs in normally
  /// (phone or email) — there is no auto-login here since no email is captured
  /// on the phone path.
  Future<void> resetPasswordWithOtp({
    required String phone,
    required String code,
    required String newPassword,
  }) => _repo.resetPasswordWithOtp(
    phone: phone,
    code: code,
    newPassword: newPassword,
  );

  Future<void> logout() async {
    // Unbind this device first, while the bearer is still valid (the resolver
    // scopes the delete to the authenticated customer).
    await ref.read(deviceTokenSyncProvider).unregister();
    await _repo.revokeToken();
    await _tokens.clear();
    ref.invalidate(graphqlClientProvider);
    state = const AuthState(status: AuthStatus.guest);
  }

  /// Permanently deletes the customer account, then drops to guest.
  ///
  /// Required by App Store Review Guideline 5.1.1(v). Deliberately lets a
  /// server-side failure propagate so the UI can say deletion did not happen —
  /// local state is only wiped once Magento confirms. The device is unbound
  /// first, while the bearer is still valid.
  Future<void> deleteAccount() async {
    await ref.read(deviceTokenSyncProvider).unregister();
    await _repo.deleteAccount();
    await _tokens.clear();
    ref.invalidate(graphqlClientProvider);
    state = const AuthState(status: AuthStatus.guest);
  }

  Future<void> requestPasswordReset(String email) =>
      _repo.requestPasswordReset(email);

  /// Completes a reset with the emailed token, then signs the customer in with
  /// their new password so they land authenticated.
  Future<void> resetPassword({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    await _repo.resetPassword(
      email: email,
      token: token,
      newPassword: newPassword,
    );
    await login(email, newPassword);
  }

  /// Invoked when a live request reports the token is invalid/expired
  /// mid-session (the resilience link detects `graphql-authorization`). Drops
  /// the session to guest locally — no revoke round-trip, since the token is
  /// already rejected — and resets the cache so customer data is cleared.
  Future<void> handleSessionExpired() async {
    // Clear the token unconditionally. A stale/expired token can linger in
    // secure storage even while the state already reads guest — AuthLink sends
    // whatever token is stored on every request, so Magento then rejects every
    // call with "Consumer key has expired". Wiping it lets requests proceed as
    // guest and recover, instead of failing forever.
    final wasSignedIn = state.status == AuthStatus.authenticated;
    await _tokens.clear();
    ref.invalidate(graphqlClientProvider);
    if (state.status != AuthStatus.guest) {
      state = const AuthState(status: AuthStatus.guest);
    }
    // Only when they *were* signed in — a lingering token wiped while the state
    // already reads guest is housekeeping, not a session the customer lost.
    if (wasSignedIn) _signalSessionExpired();
  }

  void _signalSessionExpired() =>
      ref.read(sessionExpiredSignalProvider.notifier).raise();

  /// Re-fetches the customer profile (e.g. after an Edit Profile save).
  Future<void> refreshCustomer() async {
    if (!state.isAuthenticated) return;
    try {
      final customer = await _repo.fetchCustomer();
      state = AuthState(customer: customer, status: AuthStatus.authenticated);
    } on Object {
      // keep current profile on failure
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
