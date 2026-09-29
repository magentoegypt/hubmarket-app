/// WhatsApp-OTP mutations of the Vnecoms SMS module (`Vnecoms_SmsGraphQl`) on
/// the Hub Market backend. All anonymous; variables and result handling are
/// shared in `VnecomsOtp` (`vnecoms_otp.dart`) — a refused request is
/// `success: false` + `msg`, never a GraphQL error.
///
/// Sign-in by code is **not** here: `customerLoginVerifyOtp` returns no customer
/// token, so passwordless sign-in goes through the REST pair in
/// `whatsapp_otp_api.dart`. Guest-checkout OTP lives with the checkout queries.
abstract final class OtpQueries {
  /// Registration: fails when another account already holds the number.
  static const String registerSendOtp = r'''
mutation RegisterSendOtp($input: CustomerSendOtp!) {
  customerRegisterSendOtp(input: $input) { success msg }
}
''';

  /// Consumes the code — the account itself is created by `createCustomer`.
  static const String registerVerifyOtp = r'''
mutation RegisterVerifyOtp($input: CustomerrVerifyOtp!) {
  customerRegisterVerifyOtp(input: $input) { success msg }
}
''';

  /// Password reset: fails when no account holds exactly this number.
  static const String forgotPasswordSendOtp = r'''
mutation ForgotPasswordSendOtp($input: CustomerSendOtp!) {
  customerForgotPasswordSendOtp(input: $input) { success msg }
}
''';

  /// Answers the account's e-mail and a one-off reset token for core
  /// `resetPassword` — the same token `requestPasswordResetEmail` would mail.
  static const String forgotPasswordVerifyOtp = r'''
mutation ForgotPasswordVerifyOtp($input: CustomerrVerifyOtp!) {
  customerForgotPasswordVerifyOtp(input: $input) {
    success
    msg
    email
    resetPasswordToken
  }
}
''';
}
