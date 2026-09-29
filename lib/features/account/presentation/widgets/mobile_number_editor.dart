import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/validation/phone.dart';
import '../../../../core/validation/validators.dart';
import '../../../../core/widgets/button_spinner.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/otp_code_field.dart';
import '../../../../core/widgets/phone_number_field.dart';
import '../../../../core/widgets/resend_countdown.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/account_repository.dart';

/// Edit-Profile mobile-number editor. Shows the current verified mobile and, on
/// "Change", runs a WhatsApp-OTP flow (reusing the **registration** OTP, since
/// the module exposes no dedicated change-mobile endpoint) to verify a NEW
/// number before writing it to the `mobile_number` attribute via
/// `updateCustomerV2`. There is no server-side change-mobile guard, so the
/// update is a best-effort attribute write that degrades gracefully if the
/// backend rejects it.
class MobileNumberEditor extends ConsumerStatefulWidget {
  const MobileNumberEditor({super.key});

  @override
  ConsumerState<MobileNumberEditor> createState() => _MobileNumberEditorState();
}

class _MobileNumberEditorState extends ConsumerState<MobileNumberEditor> {
  final _phoneKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  bool _editing = false;
  bool _otpSent = false;
  bool _busy = false;
  String _sentPhone = '';

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  AuthController get _auth => ref.read(authControllerProvider.notifier);

  void _startEdit() => setState(() {
    _editing = true;
    _otpSent = false;
    _phone.clear();
    _otp.clear();
  });

  void _cancel() => setState(() {
    _editing = false;
    _otpSent = false;
    _phone.clear();
    _otp.clear();
  });

  Future<void> _sendCode() async {
    if (!_phoneKey.currentState!.validate()) return;
    final e164 = Phone.normalizeUae(_phone.text);
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    try {
      await _auth.requestRegistrationOtp(e164);
      if (!mounted) return;
      setState(() {
        _sentPhone = e164;
        _otpSent = true;
      });
    } catch (error) {
      if (!mounted) return;
      _snack(serverMessageOr(context, error, l10n.authOtpRequestError));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    _otp.clear();
    final l10n = AppLocalizations.of(context);
    try {
      await _auth.requestRegistrationOtp(_sentPhone);
    } catch (error) {
      if (!mounted) return;
      _snack(serverMessageOr(context, error, l10n.authOtpRequestError));
    }
  }

  Future<void> _verifyAndUpdate() async {
    if (_otp.text.length != 6) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    // 1) Verify the new number owns a valid OTP challenge.
    try {
      await _auth.verifyRegistrationOtp(_sentPhone, _otp.text);
    } catch (error) {
      if (!mounted) return;
      _otp.clear();
      _snack(serverMessageOr(context, error, l10n.authOtpVerifyError));
      setState(() => _busy = false);
      return;
    }
    // 2) Persist it. No server-side change-mobile guard exists, so this is a
    // plain attribute write; it may be rejected by the module — surface that
    // rather than crashing.
    try {
      await ref.read(accountRepositoryProvider).updateMobileNumber(_sentPhone);
      await _auth.refreshCustomer();
      if (!mounted) return;
      _snack(l10n.profileMobileUpdated);
      setState(() {
        _editing = false;
        _otpSent = false;
        _phone.clear();
        _otp.clear();
      });
    } catch (error) {
      if (!mounted) return;
      _snack(serverMessageOr(context, error, l10n.profileMobileUpdateError));
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
    final mobile = ref.watch(
      authControllerProvider.select((s) => s.customer?.mobileNumber),
    );
    return _editing ? _editor(l10n) : _display(l10n, mobile);
  }

  Widget _display(AppLocalizations l10n, String? mobile) {
    final hasMobile = mobile != null && mobile.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
      child: Row(
        children: [
          const Icon(
            Icons.smartphone_outlined,
            size: 20,
            color: AppColors.inkMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.fieldMobileNumber,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasMobile ? mobile : l10n.profileMobileNotSet,
                  textDirection: hasMobile ? TextDirection.ltr : null,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: hasMobile ? AppColors.inkHeading : AppColors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _startEdit,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandPrimary,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              hasMobile ? l10n.profileMobileChange : l10n.profileMobileAdd,
            ),
          ),
        ],
      ),
    );
  }

  Widget _editor(AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Form(
        key: _phoneKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.fieldMobileNumber,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 8),
            PhoneNumberField(
              controller: _phone,
              hint: l10n.authPhoneHint,
              enabled: !_otpSent,
              validator: (v) => Validators.uaePhone(context, v),
            ),
            if (!_otpSent) ...[
              const SizedBox(height: 8),
              Text(
                l10n.authSignUpMobileHelp,
                style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _sendCode,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.whatsappGreen,
                      ),
                      icon: _busy
                          ? const ButtonSpinner()
                          : const Icon(Icons.chat_bubble_outline, size: 18),
                      label: Text(l10n.authSendWhatsappCode),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _busy ? null : _cancel,
                    child: Text(l10n.actionCancel),
                  ),
                ],
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
              OtpCodeField(
                controller: _otp,
                onCompleted: (_) => _verifyAndUpdate(),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: (_busy || _otp.text.length != 6)
                    ? null
                    : _verifyAndUpdate,
                child: _busy
                    ? const ButtonSpinner()
                    : Text(l10n.profileMobileVerifyUpdate),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ResendCountdown(
                    onResend: _resend,
                    resendLabel: l10n.authResendCode,
                    countingLabel: l10n.authResendIn,
                  ),
                  TextButton(
                    onPressed: _busy ? null : _cancel,
                    child: Text(l10n.actionCancel),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
