import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/store_features.dart';
import '../../../../core/validation/validators.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/auth_error.dart';
import '../../domain/password_reset_ticket.dart';
import '../auth_controller.dart';
import '../auth_error_text.dart';
import '../auth_navigation.dart';
import '../widgets/auth_field.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_widgets.dart';

/// The new-password step of a reset, in the 06 layout. Reached two ways with
/// the same kind of token: from "05 Verify WhatsApp code" (a
/// [PasswordResetTicket] from the accepted code) and from the reset e-mail's
/// link (`hubmarket://app/reset-password?email=…&token=…`). When the link
/// arrives without them, the e-mail and token fields are shown to fill in.
/// On success the customer is signed in with the new password.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.initialEmail, this.initialToken});

  ResetPasswordScreen.fromTicket(PasswordResetTicket ticket, {Key? key})
    : this(key: key, initialEmail: ticket.email, initialToken: ticket.token);

  final String? initialEmail;
  final String? initialToken;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  late final TextEditingController _token = TextEditingController(
    text: widget.initialToken ?? '',
  );
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  /// Both halves of the token came with the route — nothing to type.
  late final bool _ticketed =
      (widget.initialEmail?.isNotEmpty ?? false) &&
      (widget.initialToken?.isNotEmpty ?? false);

  bool _busy = false;
  bool _obscure = true;
  bool _submitted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    _password.removeListener(_onPasswordChanged);
    _email.dispose();
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _onPasswordChanged() => setState(() {});

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .resetPassword(
            email: _email.text.trim(),
            token: _token.text.trim(),
            newPassword: _password.text,
          );
      if (mounted) completeAuthFlow(context);
    } catch (error) {
      if (!mounted) return;
      final authError = AuthError.from(error);
      setState(() {
        // The token's refusal arrives as an auth failure with no text.
        _error = authError.kind == AuthErrorKind.wrongCredentials
            ? l10n.authResetError
            : authError.message(l10n, fallback: l10n.authResetError);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The store's password rules (core storeConfig), once read.
    final policy = ref.watch(passwordPolicyProvider);
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
            title: l10n.authResetTitle,
            subtitle: l10n.authResetIntro,
            gap: 8,
          ),
          if (_error != null) AuthErrorBanner(title: _error!),
          if (!_ticketed) ...[
            AuthField(
              controller: _email,
              label: l10n.authEmailHint,
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              ltrInput: true,
              validator: (v) => Validators.email(context, v),
            ),
            AuthField(
              controller: _token,
              label: l10n.fieldResetCode,
              ltrInput: true,
              validator: (v) => Validators.required(context, v),
            ),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthField(
                controller: _password,
                label: l10n.fieldNewPassword,
                icon: Icons.lock_outline_rounded,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                trailing: PasswordVisibilityToggle(
                  obscured: _obscure,
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                validator: (v) =>
                    Validators.newPassword(context, v, policy: policy),
              ),
              const SizedBox(height: 10),
              AuthHelperLine.rule(
                Validators.passwordRuleText(l10n, policy),
                met: Validators.meetsPasswordRule(_password.text, policy),
                failed: _submitted,
              ),
            ],
          ),
          AuthField(
            controller: _confirm,
            label: l10n.fieldConfirmPassword,
            icon: Icons.lock_outline_rounded,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            validator: (v) =>
                Validators.confirmPassword(context, v, _password.text),
            onSubmitted: (_) => _submit(),
          ),
        ],
        bottom: [
          AuthButton.primary(
            label: l10n.authResetPassword,
            busy: _busy,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
