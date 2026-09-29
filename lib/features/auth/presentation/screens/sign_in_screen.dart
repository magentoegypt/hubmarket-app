import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/config/backend_capabilities.dart';
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

/// Figma "03 Sign in" (+ "S6 Sign-in errors").
///
/// Email: e-mail + password (`generateCustomerToken`). Mobile: the number gets
/// a WhatsApp code, typed on "05 Verify WhatsApp code" (sign-in by code goes
/// through the REST pair that answers a token). "Continue with WhatsApp code"
/// is the shortcut to the Mobile tab.
///
/// Errors stay on the form (S6): the fields' own checks under each field; a
/// refused sign-in as the red banner under the title with both fields
/// outlined; a refused number under the mobile field.
///
/// The frame's Apple / Google / Facebook row is not built: the store has no
/// social sign-in to back it.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _mobile = TextEditingController();

  bool _mobileTab = false;
  bool _busy = false;
  bool _obscure = true;

  /// Re-checks the fields as they change once a submit has failed on them.
  bool _submitted = false;

  /// The last refused sign-in (banner) and whether the fields still carry it.
  AuthError? _signInError;
  bool _credentialsFlagged = false;

  /// A refused mobile number (no account, too many codes…).
  String? _mobileError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _mobile.dispose();
    super.dispose();
  }

  AuthController get _auth => ref.read(authControllerProvider.notifier);

  Future<void> _signIn() async {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _signInError = null;
      _credentialsFlagged = false;
    });
    try {
      await _auth.login(_email.text.trim(), _password.text);
      if (mounted) context.go(AppRoutes.home);
    } catch (error) {
      if (!mounted) return;
      final authError = AuthError.from(error);
      setState(() {
        _signInError = authError;
        _credentialsFlagged = authError.kind == AuthErrorKind.wrongCredentials;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    final phone = Phone.normalizeUae(_mobile.text);
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _mobileError = null;
    });
    try {
      await _auth.requestLoginOtp(phone);
      if (!mounted) return;
      setState(() => _busy = false);
      final outcome = await context.push<VerifyCodeOutcome>(
        AppRoutes.verifyCode,
        extra: VerifyCodeFlow.signIn(_auth, phone),
      );
      if (mounted && outcome == VerifyCodeOutcome.useEmail) _switchTab(false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _mobileError = AuthError.from(
          error,
        ).message(l10n, fallback: l10n.authOtpRequestError);
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
      _signInError = null;
      _credentialsFlagged = false;
      _mobileError = null;
    });
  }

  void _unflagCredentials() {
    if (_credentialsFlagged) setState(() => _credentialsFlagged = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Sign-in by code needs the endpoint that trades a code for a token;
    // without it the screen is e-mail + password only.
    final phoneLogin = ref.watch(
      backendCapabilitiesProvider.select((c) => c.whatsappOtpLogin),
    );
    final mobileTab = phoneLogin && _mobileTab;
    final banner = !mobileTab ? _signInError : null;
    return Form(
      key: _formKey,
      autovalidateMode: _submitted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: AuthScaffold(
        content: [
          // S6: a refused sign-in takes the subtitle's place.
          AuthHeader(
            title: l10n.authSignInWelcome,
            subtitle: banner == null ? l10n.authSignInSubtitle : null,
          ),
          if (banner != null) _banner(l10n, banner),
          if (phoneLogin)
            AuthMethodTabs(
              emailLabel: l10n.authMethodEmail,
              phoneLabel: l10n.authMethodPhone,
              phoneSelected: mobileTab,
              onChanged: _switchTab,
            ),
          if (mobileTab)
            ..._mobileSection(l10n)
          else
            ..._emailSection(l10n, phoneLogin: phoneLogin),
        ],
        bottom: [
          AuthFooterPrompt(
            prompt: l10n.authNoAccount,
            action: l10n.authSignUpLink,
            onTap: () => context.push(AppRoutes.signUp),
          ),
        ],
      ),
    );
  }

  Widget _banner(AppLocalizations l10n, AuthError error) {
    if (error.kind == AuthErrorKind.wrongCredentials) {
      return AuthErrorBanner(
        title: l10n.authErrorWrongCredentials,
        message: l10n.authErrorWrongCredentialsHint,
      );
    }
    return AuthErrorBanner(
      title: error.message(l10n, fallback: l10n.authSignInError),
    );
  }

  List<Widget> _emailSection(
    AppLocalizations l10n, {
    required bool phoneLogin,
  }) => [
    AuthField(
      controller: _email,
      label: l10n.authEmailHint,
      icon: Icons.mail_outline_rounded,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      ltrInput: true,
      showErrorBorder: _credentialsFlagged,
      validator: (v) => Validators.email(context, v),
      onChanged: (_) => _unflagCredentials(),
    ),
    AuthField(
      controller: _password,
      label: l10n.fieldPassword,
      icon: Icons.lock_outline_rounded,
      obscureText: _obscure,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.password],
      showErrorBorder: _credentialsFlagged,
      trailing: PasswordVisibilityToggle(
        obscured: _obscure,
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
      validator: (v) => Validators.password(context, v),
      onChanged: (_) => _unflagCredentials(),
      onSubmitted: (_) => _signIn(),
    ),
    Align(
      alignment: AlignmentDirectional.centerEnd,
      child: AuthLink(
        label: l10n.authForgotLink,
        onTap: () => context.push(AppRoutes.forgotPassword),
      ),
    ),
    AuthButton.primary(
      label: l10n.authSignInAction,
      busy: _busy,
      onPressed: _signIn,
    ),
    if (phoneLogin) ...[
      AuthOrDivider(label: l10n.authOr),
      AuthButton.outline(
        label: l10n.authContinueWithWhatsapp,
        leading: const MessageCircleIcon(),
        onPressed: _busy ? null : () => _switchTab(true),
      ),
    ],
  ];

  List<Widget> _mobileSection(AppLocalizations l10n) => [
    AuthField(
      controller: _mobile,
      label: l10n.fieldMobileWhatsapp,
      icon: Icons.phone_outlined,
      hint: l10n.authPhonePlaceholder,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.telephoneNumber],
      ltrInput: true,
      errorText: _mobileError,
      validator: (v) => Validators.uaePhone(context, v),
      onChanged: (_) {
        if (_mobileError != null) setState(() => _mobileError = null);
      },
      onSubmitted: (_) => _sendCode(),
    ),
    AuthButton.primary(
      label: l10n.authSendWhatsappCode,
      busy: _busy,
      onPressed: _sendCode,
    ),
  ];
}
