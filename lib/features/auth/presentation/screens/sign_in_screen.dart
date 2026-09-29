import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/backend_capabilities.dart';
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
import '../widgets/auth_method_tabs.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _phoneFormKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _otp = TextEditingController();

  bool _phoneTab = false;
  bool _otpSent = false;
  String _sentPhone = '';
  bool _busy = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _otp.addListener(_onOtpChanged);
  }

  @override
  void dispose() {
    _otp.removeListener(_onOtpChanged);
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  void _onOtpChanged() => setState(() {});

  AuthController get _controller => ref.read(authControllerProvider.notifier);

  Future<void> _submitEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _controller.login(_email.text.trim(), _password.text);
      if (mounted) context.go(AppRoutes.home);
    } catch (_) {
      if (mounted) _snack(AppLocalizations.of(context).authSignInError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _getOtp() async {
    if (!_phoneFormKey.currentState!.validate()) return;
    final phone = Phone.normalizeUae(_phone.text);
    setState(() => _busy = true);
    try {
      await _controller.requestLoginOtp(phone);
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

  Future<void> _resendOtp() async {
    _otp.clear();
    try {
      await _controller.requestLoginOtp(_sentPhone);
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

  Future<void> _verifyOtp() async {
    if (_otp.text.length != 6) return;
    setState(() => _busy = true);
    try {
      await _controller.loginWithOtp(_sentPhone, _otp.text);
      if (mounted) context.go(AppRoutes.home);
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

  void _switchTab(bool phone) {
    setState(() {
      _phoneTab = phone;
      _otpSent = false;
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
    // Phone sign-in needs a backend endpoint that trades a code for a token;
    // without one the screen is e-mail + password only.
    final phoneLogin = ref.watch(
      backendCapabilitiesProvider.select((c) => c.whatsappOtpLogin),
    );
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
                icon: Icons.lock_outline,
                title: l10n.authSignInWelcome,
                subtitle: l10n.authSignInSubtitle,
              ),
              const SizedBox(height: 24),
              if (phoneLogin) ...[
                AuthMethodTabs(
                  emailLabel: l10n.authMethodEmail,
                  phoneLabel: l10n.authMethodPhone,
                  phoneSelected: _phoneTab,
                  onChanged: _switchTab,
                ),
                const SizedBox(height: 16),
              ],
              if (phoneLogin && _phoneTab)
                _phoneSection(l10n)
              else
                _emailSection(l10n),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(l10n.authNoAccount),
                  TextButton(
                    onPressed: () => context.push(AppRoutes.signUp),
                    child: Text(l10n.authSignUpLink),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emailSection(AppLocalizations l10n) {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            textInputAction: TextInputAction.done,
            suffixIcon: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppColors.inkFaint,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            validator: (v) => Validators.required(context, v),
            onSubmitted: (_) => _submitEmail(),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => context.push(AppRoutes.forgotPassword),
              child: Text(l10n.authForgotLink),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _submitEmail,
            child: _busy
                ? const ButtonSpinner()
                : Text(l10n.authSignInTitle),
          ),
        ],
      ),
    );
  }

  Widget _phoneSection(AppLocalizations l10n) {
    return Form(
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
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _getOtp,
              child: _busy ? const ButtonSpinner() : Text(l10n.authGetOtp),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              l10n.authOtpSentTo(Phone.maskBidi(_sentPhone)),
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.authOtpEnter,
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            OtpCodeField(controller: _otp, onCompleted: (_) => _verifyOtp()),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: (_busy || _otp.text.length != 6) ? null : _verifyOtp,
              child: _busy
                  ? const ButtonSpinner()
                  : Text(l10n.authVerifyAndSignIn),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ResendCountdown(
                  onResend: _resendOtp,
                  resendLabel: l10n.authResendCode,
                  countingLabel: l10n.authResendIn,
                ),
                TextButton(
                  onPressed: () => context.push(AppRoutes.forgotPassword),
                  child: Text(l10n.authForgotLink),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
