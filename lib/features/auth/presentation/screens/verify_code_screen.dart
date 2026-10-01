import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/validation/phone.dart';
import '../../../../core/widgets/otp_code_field.dart';
import '../../../../core/widgets/resend_countdown.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/auth_error.dart';
import '../auth_controller.dart';
import '../auth_error_text.dart';
import '../auth_navigation.dart';
import '../widgets/auth_field.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_widgets.dart';
import '../../../../app/theme/hub_icons.dart';

/// How the Verify screen was left, for the screen that opened it. A plain back
/// or "Change number" pops with no result.
enum VerifyCodeOutcome {
  /// The code was accepted (register, change mobile).
  verified,

  /// The customer chose "Use email instead".
  useEmail,
}

/// Runs after a code is accepted, with the Verify screen's context — e.g. to
/// go Home or on to the new-password step.
typedef VerifyCodeNext = void Function(BuildContext context);

/// One use of the Verify screen: where the code went, how to send another, and
/// what accepting it does. The screen is the same for every flow; the calls
/// behind it are the ones each flow already makes.
class VerifyCodeFlow {
  const VerifyCodeFlow({
    required this.phone,
    required this.resend,
    required this.verify,
    this.offerEmail = false,
    this.resendAfterSeconds = 60,
  });

  /// Sign in by code — a pair that answers a customer token: the Hub Market
  /// App's GraphQL one when the server has it, else `MagentoEgypt_SmsExtend`'s
  /// REST one (`AuthRepository`). Then back to whatever opened Sign in
  /// ([completeAuthFlow]). [resendAfterSeconds] is the cooldown the backend
  /// gave with the code, when it said.
  factory VerifyCodeFlow.signIn(
    AuthController auth,
    String phone, {
    int? resendAfterSeconds,
  }) => VerifyCodeFlow(
    phone: phone,
    offerEmail: true,
    resendAfterSeconds: resendAfterSeconds ?? 60,
    resend: () => auth.requestLoginOtp(phone),
    verify: (code) async {
      await auth.loginWithOtp(phone, code);
      return completeAuthFlow;
    },
  );

  /// Sign-up — Vnecoms `customerRegister{Send,Verify}Otp`. Pops
  /// [VerifyCodeOutcome.verified]; Register then creates the account.
  factory VerifyCodeFlow.register(AuthController auth, String phone) =>
      VerifyCodeFlow(
        phone: phone,
        resend: () => auth.requestRegistrationOtp(phone, resend: true),
        verify: (code) async {
          await auth.verifyRegistrationOtp(phone, code);
          return null;
        },
      );

  /// Password reset — Vnecoms `customerForgotPassword{Send,Verify}Otp`. The
  /// accepted code buys a reset token; the new password is chosen next.
  factory VerifyCodeFlow.resetPassword(AuthController auth, String phone) =>
      VerifyCodeFlow(
        phone: phone,
        offerEmail: true,
        resend: () => auth.requestPasswordResetOtp(phone, resend: true),
        verify: (code) async {
          final ticket = await auth.verifyPasswordResetOtp(phone, code);
          return (BuildContext context) =>
              context.pushReplacement(AppRoutes.resetPassword, extra: ticket);
        },
      );

  /// Where the code was sent (E.164).
  final String phone;

  /// Sends another code ("Resend code").
  final Future<void> Function() resend;

  /// Checks [code] with the backend; throws its [Failure] on a refusal.
  /// Returns what to do next, or null to pop [VerifyCodeOutcome.verified].
  final Future<VerifyCodeNext?> Function(String code) verify;

  /// Offers "Use email instead" (sign in, password reset).
  final bool offerEmail;

  /// How long "Resend code" waits: the WhatsApp code's cooldown.
  final int resendAfterSeconds;
}

/// Figma "05 Verify WhatsApp code": the green chat badge, "Verify your number"
/// with the masked number and a "Change number" link, six code boxes, the
/// resend countdown, then "Verify & continue" (and, where there is an e-mail
/// route, "Use email instead"). A refused code turns the boxes red with the
/// reason under them (S6).
class VerifyCodeScreen extends StatefulWidget {
  const VerifyCodeScreen({super.key, required this.flow});

  final VerifyCodeFlow flow;

  @override
  State<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends State<VerifyCodeScreen> {
  static const int _length = 6;

  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _code
      ..removeListener(_onCodeChanged)
      ..dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    // Typing again clears the last refusal; the button follows the length.
    setState(() {
      if (_code.text.isNotEmpty) _error = null;
    });
  }

  Future<void> _verify() async {
    if (_busy) return;
    if (_code.text.length != _length) {
      // "Verify & continue" stays live (Figma 05); say what is missing.
      setState(() => _error = AppLocalizations.of(context).authOtpEnter);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final next = await widget.flow.verify(_code.text);
      if (!mounted) return;
      if (next != null) {
        next(context);
      } else {
        context.pop(VerifyCodeOutcome.verified);
      }
    } catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() {
        _error = _message(error, l10n.authOtpVerifyError);
        _code.clear();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _error = null;
      _code.clear();
    });
    try {
      await widget.flow.resend();
    } catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() => _error = _message(error, l10n.authOtpRequestError));
    }
  }

  String _message(Object error, String fallback) {
    final l10n = AppLocalizations.of(context);
    final authError = AuthError.from(error);
    // No password is involved here: an auth refusal is simply a code the
    // store would not accept.
    if (authError.kind == AuthErrorKind.wrongCredentials) return fallback;
    return authError.message(l10n, fallback: fallback);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return AuthScaffold(
      gap: 20,
      content: [
        const AuthBadge.whatsapp(),
        AuthHeader(
          title: l10n.authVerifyTitle,
          subtitle: l10n.authVerifyBody(Phone.maskBidi(widget.flow.phone)),
          gap: 8,
          trailing: AuthLink(
            label: l10n.authChangeNumber,
            onTap: _busy ? null : () => context.pop(),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OtpCodeField(
              controller: _code,
              length: _length,
              enabled: !_busy,
              hasError: _error != null,
              onCompleted: (_) => _verify(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              AuthHelperLine.error(_error!, centered: true),
            ],
          ],
        ),
        Center(
          child: ResendCountdown(
            onResend: _resend,
            cooldownSeconds: widget.flow.resendAfterSeconds,
            resendLabel: l10n.authResendCode,
            countingLabel: l10n.authResendIn,
            style: t.bodyStrong.copyWith(color: AppColors.accentStrong),
            countingBuilder: (context, seconds) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  HubIcons.clock,
                  size: 16,
                  color: AppColors.inkMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.authResendCodeIn,
                  style: t.body.copyWith(color: AppColors.inkMuted),
                ),
                const SizedBox(width: 6),
                Text(
                  ResendCountdown.clock(seconds),
                  textDirection: TextDirection.ltr,
                  style: t.bodyStrong.copyWith(color: AppColors.inkHeading),
                ),
              ],
            ),
          ),
        ),
      ],
      bottom: [
        AuthButton.primary(
          label: l10n.authVerifyContinue,
          busy: _busy,
          onPressed: _verify,
        ),
        if (widget.flow.offerEmail)
          AuthButton.text(
            label: l10n.authUseEmailInstead,
            onPressed: _busy
                ? null
                : () => context.pop(VerifyCodeOutcome.useEmail),
          ),
      ],
    );
  }
}
