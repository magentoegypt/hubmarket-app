import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/validation/phone.dart';
import '../../../../core/widgets/button_spinner.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/otp_code_field.dart';
import '../../../../core/widgets/resend_countdown.dart';
import '../../../../l10n/l10n.dart';
import '../checkout_controller.dart';

/// Guest-checkout "Verify Mobile Number" card, shown only when
/// `BackendCapabilities.guestCheckoutOtp` is on: auto-requests a WhatsApp OTP
/// to the submitted delivery phone on appear, then 6 boxes → Verify + Resend.
/// On success the checkout controller flips `guestOtpVerified`, which both
/// re-renders this card to the verified state and unlocks the payment step.
class GuestVerifyCard extends ConsumerStatefulWidget {
  const GuestVerifyCard({super.key, required this.phone});

  final String phone;

  @override
  ConsumerState<GuestVerifyCard> createState() => _GuestVerifyCardState();
}

class _GuestVerifyCardState extends ConsumerState<GuestVerifyCard> {
  final _otp = TextEditingController();
  bool _busy = false;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    _otp.addListener(_onOtp);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _request(initial: true),
    );
  }

  @override
  void dispose() {
    _otp.removeListener(_onOtp);
    _otp.dispose();
    super.dispose();
  }

  void _onOtp() => setState(() {});

  CheckoutController get _controller =>
      ref.read(checkoutControllerProvider.notifier);

  Future<void> _request({bool initial = false}) async {
    // The initial call is a post-frame callback — bail if the card was unmounted
    // (e.g. reset() dropped it) before it ran, so no stray live OTP is sent.
    if (!mounted) return;
    // Send the code once automatically; a manual Resend re-sends and clears.
    if (initial && _requested) return;
    // The card is rebuilt whenever the shopper comes back to step 1; a number
    // already verified, or already sent a code, gets no new one on its own.
    if (initial) {
      final state = ref.read(checkoutControllerProvider);
      if (state.guestOtpVerified || state.guestOtpSentTo == widget.phone) {
        _requested = true;
        return;
      }
    }
    _requested = true;
    if (!initial) _otp.clear();
    try {
      await _controller.requestGuestOtp(resend: !initial);
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

  Future<void> _verify() async {
    if (_otp.text.length != 6) return;
    setState(() => _busy = true);
    try {
      await _controller.verifyGuestOtp(_otp.text);
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

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final verified = ref.watch(
      checkoutControllerProvider.select((s) => s.guestOtpVerified),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: verified ? _verifiedView(l10n) : _entryView(l10n),
    );
  }

  Widget _verifiedView(AppLocalizations l10n) => Row(
    children: [
      const Icon(Icons.check_circle, color: AppColors.successStrong, size: 20),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          l10n.authMobileVerified,
          style: const TextStyle(
            color: AppColors.successStrong,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );

  Widget _entryView(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        l10n.checkoutVerifyMobileTitle,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.inkHeading,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        l10n.checkoutVerifyMobileIntro(Phone.maskBidi(widget.phone)),
        style: const TextStyle(color: AppColors.inkMuted, fontSize: 12.5),
      ),
      const SizedBox(height: 14),
      OtpCodeField(
        controller: _otp,
        autofocus: false,
        onCompleted: (_) => _verify(),
      ),
      const SizedBox(height: 14),
      FilledButton(
        onPressed: (_busy || _otp.text.length != 6) ? null : _verify,
        child: _busy ? const ButtonSpinner() : Text(l10n.authVerify),
      ),
      Center(
        child: ResendCountdown(
          onResend: () => _request(),
          resendLabel: l10n.authResendCode,
          countingLabel: l10n.authResendIn,
        ),
      ),
    ],
  );
}
