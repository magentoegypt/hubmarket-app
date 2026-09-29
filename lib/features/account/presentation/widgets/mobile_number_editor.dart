import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/validation/phone.dart';
import '../../../../core/validation/validators.dart';
import '../../../../core/widgets/button_spinner.dart';
import '../../../../core/widgets/phone_number_field.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/domain/auth_error.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../auth/presentation/auth_error_text.dart';
import '../../../auth/presentation/screens/verify_code_screen.dart';
import '../../data/account_repository.dart';

/// Edit-Profile mobile-number editor. Shows the current mobile and, on
/// "Change", sends a WhatsApp code to the NEW number (the registration send,
/// `customerRegisterSendOtp`, which also refuses a number another account
/// holds). The code is typed on "05 Verify WhatsApp code", which saves the
/// number with `saveMobileToCustomer` — the Vnecoms SMS change the website
/// uses, which checks the code server-side before writing `mobilenumber`.
class MobileNumberEditor extends ConsumerStatefulWidget {
  const MobileNumberEditor({super.key});

  @override
  ConsumerState<MobileNumberEditor> createState() => _MobileNumberEditorState();
}

class _MobileNumberEditorState extends ConsumerState<MobileNumberEditor> {
  final _phoneKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  bool _editing = false;
  bool _busy = false;
  String? _phoneError;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  AuthController get _auth => ref.read(authControllerProvider.notifier);

  void _startEdit() => setState(() {
    _editing = true;
    _phoneError = null;
    _phone.clear();
  });

  void _cancel() => setState(() {
    _editing = false;
    _phoneError = null;
    _phone.clear();
  });

  /// The change-mobile use of the Verify screen: resends go through the
  /// registration send; accepting the code saves the number.
  VerifyCodeFlow _flow(String e164) {
    final account = ref.read(accountRepositoryProvider);
    final auth = _auth;
    return VerifyCodeFlow(
      phone: e164,
      resend: () => auth.requestRegistrationOtp(e164, resend: true),
      verify: (code) async {
        // One call verifies and saves: the backend checks the code against
        // the one it sent to this number and only then writes it.
        await account.saveMobileNumber(e164, code);
        await auth.refreshCustomer();
        return null;
      },
    );
  }

  Future<void> _sendCode() async {
    if (!_phoneKey.currentState!.validate()) return;
    final e164 = Phone.normalizeUae(_phone.text);
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _phoneError = null;
    });
    try {
      await _auth.requestRegistrationOtp(e164);
      if (!mounted) return;
      setState(() => _busy = false);
      final outcome = await context.push<VerifyCodeOutcome>(
        AppRoutes.verifyCode,
        extra: _flow(e164),
      );
      if (!mounted || outcome != VerifyCodeOutcome.verified) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.profileMobileUpdated)));
      _cancel();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phoneError = AuthError.from(
          error,
        ).message(l10n, fallback: l10n.authOtpRequestError);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
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
              enabled: !_busy,
              errorText: _phoneError,
              validator: (v) => Validators.uaePhone(context, v),
              onChanged: (_) {
                if (_phoneError != null) setState(() => _phoneError = null);
              },
              onSubmitted: (_) => _sendCode(),
            ),
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
          ],
        ),
      ),
    );
  }
}
