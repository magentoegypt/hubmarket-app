import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/validation/validators.dart';
import '../../../../core/widgets/button_spinner.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/hub_back_button.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/widgets/auth_field.dart';
import '../guest_orders_controller.dart';
import '../../../../app/theme/hub_icons.dart';

/// Look up any order without signing in, using the details on the confirmation
/// e-mail (order number + billing e-mail + last name). Backed by Magento's
/// native `guestOrder` query; a match is remembered on this device and opens
/// the same Track Order screen customers get.
class GuestTrackOrderScreen extends ConsumerStatefulWidget {
  const GuestTrackOrderScreen({super.key, this.initialNumber});

  /// The order number to start with: an order a guest opened from a push or
  /// a link (`/track-order?number=`).
  final String? initialNumber;

  @override
  ConsumerState<GuestTrackOrderScreen> createState() =>
      _GuestTrackOrderScreenState();
}

class _GuestTrackOrderScreenState extends ConsumerState<GuestTrackOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _number = TextEditingController(
    text: widget.initialNumber?.trim() ?? '',
  );
  final _email = TextEditingController();
  final _lastname = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _number.dispose();
    _email.dispose();
    _lastname.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    try {
      final order = await ref
          .read(guestOrdersControllerProvider.notifier)
          .lookup(
            number: _number.text.trim(),
            email: _email.text.trim(),
            lastname: _lastname.text.trim(),
          );
      if (!mounted) return;
      context.pushReplacement(AppRoutes.orderTracking, extra: order);
    } catch (error) {
      if (!mounted) return;
      // Magento answers an unknown order with its own message ("We couldn't
      // locate an order with the information provided.") — surface it rather
      // than a generic failure, so the user knows *what* to correct.
      _snack(serverMessageOr(context, error, l10n.guestTrackNotFound));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HubScaffold(
      currentTab: AppTab.account,
      appBar: AppBar(
        centerTitle: true,
        leading: const HubBackButton(),
        title: Text(l10n.guestTrackTitle),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.guestTrackIntro,
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  AuthField(
                    controller: _number,
                    icon: HubIcons.receiptText,
                    hint: l10n.guestTrackOrderNumber,
                    keyboardType: TextInputType.number,
                    validator: (v) => Validators.required(context, v),
                  ),
                  const SizedBox(height: 12),
                  AuthField(
                    controller: _email,
                    icon: HubIcons.mail,
                    hint: l10n.guestTrackEmail,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => Validators.email(context, v),
                  ),
                  const SizedBox(height: 12),
                  AuthField(
                    controller: _lastname,
                    icon: HubIcons.user,
                    hint: l10n.guestTrackLastname,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => Validators.required(context, v),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const ButtonSpinner()
                        : Text(l10n.guestTrackSubmit),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
