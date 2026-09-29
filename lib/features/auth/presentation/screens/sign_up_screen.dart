import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/validation/phone.dart';
import '../../../../core/validation/validators.dart';
import '../../../../core/widgets/brand_logo.dart';
import '../../../../core/widgets/button_spinner.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/otp_code_field.dart';
import '../../../../core/widgets/phone_number_field.dart';
import '../../../../core/widgets/resend_countdown.dart';
import '../../../../core/widgets/hub_back_button.dart';
import '../../../../l10n/l10n.dart';
import '../auth_controller.dart';
import '../widgets/auth_field.dart';
import '../widgets/auth_header.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneFormKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _otp = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  bool _agreedToTerms = false;
  bool _otpSent = false;
  bool _phoneVerified = false;
  String _sentPhone = '';

  @override
  void initState() {
    super.initState();
    _otp.addListener(_onOtpChanged);
  }

  @override
  void dispose() {
    _otp.removeListener(_onOtpChanged);
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  void _onOtpChanged() => setState(() {});

  AuthController get _controller => ref.read(authControllerProvider.notifier);

  /// Splits the single "Full name" into Magento's required firstname/lastname
  /// (last token is the surname; a single token fills both).
  ({String first, String last}) _splitName() {
    final parts = _fullName.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return (first: '', last: '');
    if (parts.length == 1) return (first: parts.first, last: parts.first);
    return (
      first: parts.sublist(0, parts.length - 1).join(' '),
      last: parts.last,
    );
  }

  Future<void> _sendWhatsappCode() async {
    if (!_phoneFormKey.currentState!.validate()) return;
    final phone = Phone.normalizeUae(_phone.text);
    setState(() => _busy = true);
    try {
      await _controller.requestRegistrationOtp(phone);
      if (mounted) {
        setState(() {
          _sentPhone = phone;
          _otpSent = true;
          _otp.clear();
        });
      }
    } catch (error) {
      if (!mounted) return;
      _snack(
        serverMessageOr(
          context,
          error,
          AppLocalizations.of(context).authOtpRequestError,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendCode() async {
    _otp.clear();
    try {
      await _controller.requestRegistrationOtp(_sentPhone);
    } catch (error) {
      if (!mounted) return;
      _snack(
        serverMessageOr(
          context,
          error,
          AppLocalizations.of(context).authOtpRequestError,
        ),
      );
    }
  }

  Future<void> _verifyCode() async {
    if (_otp.text.length != 6) return;
    setState(() => _busy = true);
    try {
      await _controller.verifyRegistrationOtp(_sentPhone, _otp.text);
      if (mounted) setState(() => _phoneVerified = true);
    } catch (error) {
      if (!mounted) return;
      _otp.clear();
      _snack(
        serverMessageOr(
          context,
          error,
          AppLocalizations.of(context).authOtpVerifyError,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    // Create Account is gated on terms + a verified mobile; the guard also
    // enforces the verified number server-side.
    if (!_agreedToTerms || !_phoneVerified) return;
    if (!_formKey.currentState!.validate()) return;
    final name = _splitName();
    setState(() => _busy = true);
    try {
      await _controller.register(
        firstName: name.first,
        lastName: name.last,
        email: _email.text.trim(),
        password: _password.text,
        mobileNumber: _sentPhone,
      );
      if (mounted) context.go(AppRoutes.home);
    } catch (error) {
      if (!mounted) return;
      _snack(
        serverMessageOr(
          context,
          error,
          AppLocalizations.of(context).authSignInError,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canSubmit = _agreedToTerms && _phoneVerified && !_busy;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: 80,
        leading: const HubBackButton(),
        title: const BrandLogo(height: 60),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthHeader(
                icon: Icons.person_outline,
                title: l10n.authSignUpTitle,
                subtitle: l10n.authSignUpSubtitle,
              ),
              const SizedBox(height: 24),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AuthField(
                      controller: _fullName,
                      icon: Icons.person_outline,
                      hint: l10n.fieldFullName,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => Validators.required(context, v),
                    ),
                    const SizedBox(height: 16),
                    // Mobile number + WhatsApp verification sits directly after
                    // the name and before email/password (Figma order).
                    _mobileSection(l10n),
                    const SizedBox(height: 16),
                    AuthField(
                      controller: _email,
                      icon: Icons.mail_outline,
                      hint: l10n.authEmailHint,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => Validators.email(context, v),
                    ),
                    const SizedBox(height: 16),
                    AuthField(
                      controller: _password,
                      icon: Icons.lock_outline,
                      hint: l10n.fieldPassword,
                      obscureText: _obscure,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.inkFaint,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      validator: (v) => Validators.password(context, v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Terms agreement — with the verified mobile, gates Create Account.
              InkWell(
                onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
                child: Row(
                  children: [
                    Checkbox(
                      value: _agreedToTerms,
                      onChanged: (v) =>
                          setState(() => _agreedToTerms = v ?? false),
                    ),
                    Expanded(
                      child: Text(
                        l10n.authAgreeTerms,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: canSubmit ? _submit : null,
                child: _busy
                    ? const ButtonSpinner()
                    : Text(l10n.authSignUpTitle),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(l10n.authHaveAccount),
                  TextButton(
                    onPressed: () => context.pop(),
                    child: Text(l10n.authSignInTitle),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileSection(AppLocalizations l10n) {
    return Form(
      key: _phoneFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhoneNumberField(
            controller: _phone,
            hint: l10n.authPhoneHint,
            enabled: !_otpSent && !_phoneVerified,
            validator: (v) => Validators.uaePhone(context, v),
          ),
          if (_phoneVerified) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                // Verified state uses the shared success token (matches the
                // checkout guest-verify card); the WhatsApp green stays on the
                // "Send WhatsApp code" action only.
                const Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.authMobileVerified,
                  style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ] else if (!_otpSent) ...[
            const SizedBox(height: 8),
            // Helper line under the mobile field (Figma).
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 2),
              child: Text(
                l10n.authSignUpMobileHelp,
                style: const TextStyle(color: AppColors.inkMuted, fontSize: 12.5),
              ),
            ),
            const SizedBox(height: 12),
            // Only the "Send WhatsApp code" action is WhatsApp-green (Figma).
            FilledButton.icon(
              onPressed: _busy ? null : _sendWhatsappCode,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.whatsappGreen,
              ),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: Text(l10n.authSendWhatsappCode),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              l10n.authOtpSentTo(Phone.maskBidi(_sentPhone)),
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            OtpCodeField(controller: _otp, onCompleted: (_) => _verifyCode()),
            const SizedBox(height: 12),
            // Verify is the standard burgundy action (Figma) — green is only for
            // the initial "Send WhatsApp code".
            FilledButton(
              onPressed: (_busy || _otp.text.length != 6) ? null : _verifyCode,
              child: _busy ? const ButtonSpinner() : Text(l10n.authVerify),
            ),
            Center(
              child: ResendCountdown(
                onResend: _resendCode,
                resendLabel: l10n.authResendCode,
                countingLabel: l10n.authResendIn,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
