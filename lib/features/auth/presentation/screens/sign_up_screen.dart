import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/validation/phone.dart';
import '../../../../core/validation/validators.dart';
import '../../../../l10n/l10n.dart';
import '../../../cms/presentation/widgets/legal_links_text.dart';
import '../../domain/auth_error.dart';
import '../auth_controller.dart';
import '../auth_error_text.dart';
import '../auth_navigation.dart';
import '../widgets/auth_field.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_widgets.dart';
import 'verify_code_screen.dart';

/// Figma "04 Register": first / last name, e-mail, mobile (WhatsApp),
/// password with its rule, the terms and newsletter boxes, Create account.
///
/// Create account sends a WhatsApp code to the mobile and opens "05 Verify
/// WhatsApp code"; once the code is accepted the account is created
/// (`createCustomer`, with the verified `mobilenumber`) and signed in. The
/// backend requires the number but does not re-check the code, so this order
/// is what enforces verification. Refusals land on the field they concern
/// (number or e-mail already in use); anything else in the banner.
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  bool _agreedToTerms = false;
  bool _newsletter = false;
  bool _submitted = false;

  String? _emailError;
  String? _mobileError;
  String? _formError;

  @override
  void initState() {
    super.initState();
    // The rule line under the password turns green as it is met.
    _password.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    _password.removeListener(_onPasswordChanged);
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _mobile.dispose();
    _password.dispose();
    super.dispose();
  }

  void _onPasswordChanged() => setState(() {});

  AuthController get _auth => ref.read(authControllerProvider.notifier);

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _formError = null;
    });
    final valid = _formKey.currentState!.validate();
    if (!valid || !_agreedToTerms) return;

    final l10n = AppLocalizations.of(context);
    final phone = Phone.normalizeUae(_mobile.text);
    setState(() => _busy = true);
    try {
      await _auth.requestRegistrationOtp(phone);
      if (!mounted) return;
      setState(() => _busy = false);
      final outcome = await context.push<VerifyCodeOutcome>(
        AppRoutes.verifyCode,
        extra: VerifyCodeFlow.register(_auth, phone),
      );
      if (!mounted || outcome != VerifyCodeOutcome.verified) return;
      setState(() => _busy = true);
      await _auth.register(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        mobileNumber: phone,
        subscribeToNewsletter: _newsletter,
      );
      if (mounted) completeAuthFlow(context);
    } catch (error) {
      if (!mounted) return;
      final authError = AuthError.from(error);
      final message = authError.message(l10n, fallback: l10n.errorGeneric);
      setState(() {
        switch (authError.kind) {
          case AuthErrorKind.emailInUse:
            _emailError = message;
          case AuthErrorKind.mobileInUse ||
              AuthErrorKind.tooManyAttempts ||
              AuthErrorKind.noAccount:
            _mobileError = message;
          default:
            _formError = message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Back to Sign in when Register was opened from there, else Sign in in
  /// Register's place (Register is also reached from Welcome and Account).
  void _toSignIn() {
    final matches = GoRouter.of(
      context,
    ).routerDelegate.currentConfiguration.matches;
    final below = matches.length > 1 ? matches[matches.length - 2] : null;
    if (below?.matchedLocation == AppRoutes.signIn) {
      context.pop();
    } else {
      context.pushReplacement(AppRoutes.signIn);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final termsMissing = _submitted && !_agreedToTerms;
    return Form(
      key: _formKey,
      autovalidateMode: _submitted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: AuthScaffold(
        title: l10n.authCreateAccount,
        gap: 16,
        topPadding: 4,
        content: [
          Text(
            l10n.authSignUpSubtitle,
            style: t.body.copyWith(color: AppColors.inkMuted),
          ),
          if (_formError != null) AuthErrorBanner(title: _formError!),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AuthField(
                  controller: _firstName,
                  label: l10n.fieldFirstName,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.givenName],
                  validator: (v) => Validators.required(context, v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AuthField(
                  controller: _lastName,
                  label: l10n.fieldLastName,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.familyName],
                  validator: (v) => Validators.required(context, v),
                ),
              ),
            ],
          ),
          AuthField(
            controller: _email,
            label: l10n.authEmailHint,
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            ltrInput: true,
            errorText: _emailError,
            validator: (v) => Validators.email(context, v),
            onChanged: (_) {
              if (_emailError != null) setState(() => _emailError = null);
            },
          ),
          AuthField(
            controller: _mobile,
            label: l10n.fieldMobileWhatsapp,
            icon: Icons.phone_outlined,
            hint: l10n.authPhonePlaceholder,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            ltrInput: true,
            errorText: _mobileError,
            validator: (v) => Validators.uaePhone(context, v),
            onChanged: (_) {
              if (_mobileError != null) setState(() => _mobileError = null);
            },
          ),
          AuthField(
            controller: _password,
            label: l10n.fieldPassword,
            icon: Icons.lock_outline_rounded,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            trailing: PasswordVisibilityToggle(
              obscured: _obscure,
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            validator: (v) => Validators.newPassword(context, v),
          ),
          AuthHelperLine.rule(
            l10n.validationPasswordRule,
            met: Validators.meetsPasswordRule(_password.text),
            failed: _submitted,
          ),
          AuthCheckRow(
            value: _agreedToTerms,
            label: l10n.authAgreeTerms,
            // "Terms of Service" and "Privacy Policy" open the store's pages.
            labelBuilder: (label, style) => LegalLinksText(label, style: style),
            error: termsMissing,
            onChanged: (v) => setState(() => _agreedToTerms = v),
          ),
          if (termsMissing) AuthHelperLine.error(l10n.authAgreeTermsRequired),
          AuthCheckRow(
            value: _newsletter,
            label: l10n.authNewsletterOptIn,
            emphasised: false,
            onChanged: (v) => setState(() => _newsletter = v),
          ),
        ],
        bottom: [
          AuthButton.primary(
            label: l10n.authCreateAccount,
            busy: _busy,
            onPressed: _submit,
          ),
          AuthFooterPrompt(
            prompt: l10n.authHaveAccount,
            action: l10n.authSignInAction,
            onTap: _toSignIn,
          ),
        ],
      ),
    );
  }
}
