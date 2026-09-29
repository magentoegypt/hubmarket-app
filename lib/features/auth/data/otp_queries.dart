/// WhatsApp-OTP mutations from the live `MagentoEgypt_OtpVerification` module
/// (verified against `hub-market.magento2.click/graphql`, `Store: eg_en`). All are anonymous.
///
/// On failure these return a GraphQL `errors[]` entry (input-exception) with a
/// localized message — the data layer maps that to `Failure(server, detail:)`,
/// which the UI surfaces verbatim (it is already localized eg_en / eg_ar). The
/// `*/request` mutations for login & password always return `success:true`
/// (anti-enumeration) — never infer account existence from them.
///
/// Guest-checkout OTP is cart-bound and lives with the checkout queries
/// (`checkout_queries.dart`), not here.
abstract final class OtpQueries {
  static const String requestLoginOtp = r'''
mutation RequestLoginOtp($phone: String!) {
  requestLoginOtp(phone: $phone) { success message }
}
''';

  static const String loginWithOtp = r'''
mutation LoginWithOtp($phone: String!, $code: String!) {
  loginWithOtp(phone: $phone, code: $code) { success token message }
}
''';

  static const String requestRegistrationOtp = r'''
mutation RequestRegistrationOtp($phone: String!) {
  requestRegistrationOtp(phone: $phone) { success message }
}
''';

  static const String verifyRegistrationOtp = r'''
mutation VerifyRegistrationOtp($phone: String!, $code: String!) {
  verifyRegistrationOtp(phone: $phone, code: $code) { success message }
}
''';

  static const String requestPasswordResetOtp = r'''
mutation RequestPasswordResetOtp($phone: String!) {
  requestPasswordResetOtp(phone: $phone) { success message }
}
''';

  static const String resetPasswordWithOtp = r'''
mutation ResetPasswordWithOtp($phone: String!, $code: String!, $newPassword: String!) {
  resetPasswordWithOtp(phone: $phone, code: $code, newPassword: $newPassword) { success message }
}
''';
}
