import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/validation/phone.dart';
import '../../../../core/validation/validators.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/auth_error.dart';
import '../auth_controller.dart';
import '../auth_error_text.dart';
import '../widgets/auth_field.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_method_tabs.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_widgets.dart';
import 'verify_code_screen.dart';
import '../../../../app/theme/hub_icons.dart';

/// Figma "06 Forgot password": the orange lock badge, "Reset your password",
/// the e-mail field and the link-expiry note, "Send reset link" / "Back to
/// sign in".
///
/// The store also resets passwords by WhatsApp code (Vnecoms
/// `customerForgotPassword{Send,Verify}Otp`), so the screen carries Sign in's
/// Email | Mobile tabs: Mobile sends a code, typed on "05 Verify WhatsApp
/// code", which leads to the new-password step.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _mobile = TextEditingController();

  bool _mobileTab = false;
  bool _busy = false;
  bool _submitted = false;
  bool _emailSent = false;
  String? _fieldError;

  @override
  void dispose() {
    _email.dispose();
    _mobile.dispose();
    super.dispose();
  }

  AuthController get _auth => ref.read(authControllerProvider.notifier);

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _fieldError = null;
    });
    try {
      if (_mobileTab) {
        final phone = Phone.normalizeUae(_mobile.text);
        await _auth.requestPasswordResetOtp(phone);
        if (!mounted) return;
        setState(() => _busy = false);
        final outcome = await context.push<VerifyCodeOutcome>(
          AppRoutes.verifyCode,
          extra: VerifyCodeFlow.resetPassword(_auth, phone),
        );
        if (mounted && outcome == VerifyCodeOutcome.useEmail) {
          _switchTab(false);
        }
      } else {
        await _auth.requestPasswordReset(_email.text.trim());
        if (mounted) setState(() => _emailSent = true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _fieldError = AuthError.from(error).message(
          l10n,
          fallback: _mobileTab ? l10n.authOtpRequestError : l10n.errorGeneric,
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchTab(bool mobile) {
    if (mobile == _mobileTab) return;
    setState(() {
      _mobileTab = mobile;
      _submitted = false;
      _fieldError = null;
    });
  }

  void _backToSignIn() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.signIn);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_emailSent) return _sentView(l10n);
    return Form(
      key: _formKey,
      autovalidateMode: _submitted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: AuthScaffold(
        gap: 20,
        content: [
          const AuthBadge.lock(),
          AuthHeader(
            title: l10n.authForgotTitle,
            subtitle: _mobileTab
                ? l10n.authForgotPhoneIntro
                : l10n.authForgotIntro,
            gap: 8,
          ),
          AuthMethodTabs(
            emailLabel: l10n.authMethodEmail,
            phoneLabel: l10n.authMethodPhone,
            phoneSelected: _mobileTab,
            onChanged: _switchTab,
          ),
          if (_mobileTab)
            AuthField(
              key: const ValueKey('forgot-mobile'),
              controller: _mobile,
              label: l10n.fieldMobileWhatsapp,
              icon: HubIcons.phone,
              hint: l10n.authPhonePlaceholder,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              ltrInput: true,
              errorText: _fieldError,
              validator: (v) => Validators.uaePhone(context, v),
              onChanged: (_) => _clearFieldError(),
              onSubmitted: (_) => _submit(),
            )
          else ...[
            AuthField(
              key: const ValueKey('forgot-email'),
              controller: _email,
              label: l10n.authEmailHint,
              icon: HubIcons.mail,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              ltrInput: true,
              errorText: _fieldError,
              validator: (v) => Validators.email(context, v),
              onChanged: (_) => _clearFieldError(),
              onSubmitted: (_) => _submit(),
            ),
            AuthInfoNote(text: l10n.authForgotLinkNote),
          ],
        ],
        bottom: [
          AuthButton.primary(
            label: _mobileTab ? l10n.authSendWhatsappCode : l10n.authForgotSubmit,
            busy: _busy,
            onPressed: _submit,
          ),
          AuthButton.text(
            label: l10n.authBackToSignIn,
            onPressed: _busy ? null : _backToSignIn,
          ),
        ],
      ),
    );
  }

  void _clearFieldError() {
    if (_fieldError != null) setState(() => _fieldError = null);
  }

  /// After "Send reset link": the same layout, saying the link is on its way.
  Widget _sentView(AppLocalizations l10n) => AuthScaffold(
    gap: 20,
    content: [
      const AuthBadge(
        icon: Icon(HubIcons.mailCheck),
        background: AppColors.successSubtle,
        foreground: AppColors.successStrong,
      ),
      AuthHeader(
        title: l10n.authForgotTitle,
        subtitle: l10n.authForgotSent,
        gap: 8,
      ),
      AuthInfoNote(text: l10n.authForgotLinkNote),
    ],
    bottom: [
      AuthButton.primary(label: l10n.authBackToSignIn, onPressed: _backToSignIn),
    ],
  );
}
