import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/validation/phone.dart';
import '../../../../core/validation/validators.dart';
import '../../../../core/widgets/brand_logo.dart';
import '../../../../core/widgets/button_spinner.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/otp_code_field.dart';
import '../../../../core/widgets/phone_number_field.dart';
import '../../../../core/widgets/hub_back_button.dart';
import '../../../../l10n/l10n.dart';
import '../auth_controller.dart';
import '../widgets/auth_field.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_method_tabs.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _phoneFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _phoneTab = false;
  bool _emailSent = false;
  bool _otpSent = false;
  String _sentPhone = '';
  bool _busy = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _otp.addListener(_onOtpChanged);
  }

  @override
  void dispose() {
    _otp.removeListener(_onOtpChanged);
    _email.dispose();
    _phone.dispose();
    _otp.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _onOtpChanged() => setState(() {});

  AuthController get _controller => ref.read(authControllerProvider.notifier);

  Future<void> _submitEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _controller.requestPasswordReset(_email.text.trim());
      if (mounted) setState(() => _emailSent = true);
    } catch (_) {
      if (mounted) _snack(AppLocalizations.of(context).errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _getOtp() async {
    if (!_phoneFormKey.currentState!.validate()) return;
    final phone = Phone.normalizeUae(_phone.text);
    setState(() => _busy = true);
    try {
      await _controller.requestPasswordResetOtp(phone);
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

  Future<void> _resetPassword() async {
    if (_otp.text.length != 6) return;
    if (!_resetFormKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _controller.resetPasswordWithOtp(
        phone: _sentPhone,
        code: _otp.text,
        newPassword: _newPassword.text,
      );
      if (mounted) {
        _snack(AppLocalizations.of(context).authResetSuccess);
        context.pop();
      }
    } catch (error) {
      if (!mounted) return;
      _otp.clear();
      _snack(
        serverMessageOr(
          context,
          error,
          AppLocalizations.of(context).authResetError,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchTab(bool phone) {
    setState(() {
      _phoneTab = phone;
      _otpSent = false;
      _emailSent = false;
      _otp.clear();
    });
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
          child: _emailSent ? _emailSentView(l10n) : _formView(l10n),
        ),
      ),
    );
  }

  Widget _emailSentView(AppLocalizations l10n) => Column(
    children: [
      const SizedBox(height: 24),
      const Icon(Icons.mark_email_read_outlined, size: 56),
      const SizedBox(height: 16),
      Text(l10n.authForgotSent, textAlign: TextAlign.center),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: () => context.pop(),
        child: Text(l10n.authBackToSignIn),
      ),
    ],
  );

  Widget _formView(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AuthHeader(
        icon: Icons.mail_outline,
        title: l10n.authForgotTitle,
        subtitle: _phoneTab ? l10n.authForgotPhoneIntro : l10n.authForgotIntro,
      ),
      const SizedBox(height: 24),
      AuthMethodTabs(
        emailLabel: l10n.authMethodEmail,
        phoneLabel: l10n.authMethodPhone,
        phoneSelected: _phoneTab,
        onChanged: _switchTab,
      ),
      const SizedBox(height: 16),
      if (_phoneTab) _phoneSection(l10n) else _emailSection(l10n),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _busy ? null : () => context.pop(),
        child: Text(l10n.authBackToSignIn),
      ),
    ],
  );

  Widget _emailSection(AppLocalizations l10n) => Form(
    key: _emailFormKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthField(
          controller: _email,
          icon: Icons.mail_outline,
          hint: l10n.authEmailHint,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          validator: (v) => Validators.email(context, v),
          onSubmitted: (_) => _submitEmail(),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _submitEmail,
          child: _busy ? const ButtonSpinner() : Text(l10n.authForgotSubmit),
        ),
      ],
    ),
  );

  Widget _phoneSection(AppLocalizations l10n) => Form(
    key: _phoneFormKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhoneNumberField(
          controller: _phone,
          hint: l10n.authPhoneHint,
          enabled: !_otpSent,
          validator: (v) => Validators.uaePhone(context, v),
          onSubmitted: (_) => _otpSent ? null : _getOtp(),
        ),
        if (!_otpSent) ...[
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _getOtp,
            child: _busy ? const ButtonSpinner() : Text(l10n.authGetOtp),
          ),
        ] else
          _resetSection(l10n),
      ],
    ),
  );

  Widget _resetSection(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 12),
      Text(
        l10n.authOtpSentTo(Phone.maskBidi(_sentPhone)),
        style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
      ),
      const SizedBox(height: 12),
      OtpCodeField(controller: _otp),
      const SizedBox(height: 16),
      Form(
        key: _resetFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthField(
              controller: _newPassword,
              icon: Icons.lock_outline,
              hint: l10n.fieldNewPassword,
              obscureText: _obscureNew,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureNew
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.inkFaint,
                ),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
              validator: (v) => Validators.password(context, v),
            ),
            const SizedBox(height: 12),
            AuthField(
              controller: _confirmPassword,
              icon: Icons.lock_outline,
              hint: l10n.fieldConfirmPassword,
              obscureText: _obscureConfirm,
              textInputAction: TextInputAction.done,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.inkFaint,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              validator: (v) =>
                  Validators.confirmPassword(context, v, _newPassword.text),
              onSubmitted: (_) => _resetPassword(),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: (_busy || _otp.text.length != 6) ? null : _resetPassword,
        child: _busy ? const ButtonSpinner() : Text(l10n.authResetPassword),
      ),
    ],
  );
}
