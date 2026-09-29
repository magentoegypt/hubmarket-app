import '../../../core/error/failure.dart';

/// Variables and result handling shared by the Vnecoms SMS GraphQL OTP
/// mutations (`customer{Register,ForgotPassword,Checkout}{Send,Verify}Otp`,
/// module `Vnecoms_SmsGraphQl`).
///
/// Codes arrive over WhatsApp: the module's SMS gateway on this store is
/// `MagentoEgypt_SmsExtend`. They are six digits by the store's `vsms/settings`
/// (`otp_format` num, `otp_length` 6), which is what `OtpCodeField` collects.
abstract final class VnecomsOtp {
  /// `CustomerSendOtp`. `resend: true` marks a repeat request, which the module
  /// counts toward its resend limit.
  static Map<String, dynamic> sendVariables(
    String mobile, {
    bool resend = false,
  }) => <String, dynamic>{
    'input': <String, dynamic>{'mobile': mobile, 'resend': resend},
  };

  /// `CustomerrVerifyOtp` (sic — the schema's spelling).
  static Map<String, dynamic> verifyVariables(String mobile, String code) =>
      <String, dynamic>{
        'input': <String, dynamic>{'mobile': mobile, 'otp': code},
      };

  /// These resolvers never raise a GraphQL error for a refused request. They
  /// answer `success: false` with the reason in `msg` ("The OTP code is not
  /// valid.", "The mobile number is used by another customer account.",
  /// "You are sending OTP too much times."), in the store view's language.
  ///
  /// Returns the payload when `success` is true; otherwise throws the
  /// [Failure] the rest of the app surfaces — `server`, with that message.
  static Map<String, dynamic> requireSuccess(Object? payload) {
    if (payload is Map<String, dynamic> && payload['success'] == true) {
      return payload;
    }
    final message = payload is Map<String, dynamic>
        ? (payload['msg'] as String?)?.trim()
        : null;
    throw Failure(
      FailureKind.server,
      detail: (message == null || message.isEmpty) ? null : message,
    );
  }
}
