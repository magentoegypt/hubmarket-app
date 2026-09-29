/// What proving a password-reset code buys: the account's e-mail and a one-off
/// reset token for core `resetPassword` — the same token the reset e-mail's
/// link carries.
class PasswordResetTicket {
  const PasswordResetTicket({required this.email, required this.token});

  final String email;
  final String token;
}
