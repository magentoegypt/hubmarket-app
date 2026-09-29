import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/validation/validators.dart';
import '../../../../core/widgets/brand_logo.dart';
import '../../../../core/widgets/hub_back_button.dart';
import '../widgets/auth_header.dart';
import '../../../../l10n/l10n.dart';
import '../auth_controller.dart';

/// Completes a password reset using the token from the reset email. Reached via
/// the deep link in that email (which pre-fills the email + token query params).
/// Magento sends a reset *link*, not an in-app code, so there is intentionally
/// no "I have a reset code" entry point. On success the customer is signed in
/// with the new password.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.initialEmail, this.initialToken});

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
  final TextEditingController _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _token.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .resetPassword(
            email: _email.text.trim(),
            token: _token.text.trim(),
            newPassword: _password.text,
          );
      if (mounted) context.go(AppRoutes.home);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).authResetError)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthHeader(
                  icon: Icons.lock_reset,
                  title: l10n.authResetTitle,
                  subtitle: l10n.authResetIntro,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: l10n.fieldEmail,
                    prefixIcon: const Icon(Icons.mail_outline),
                  ),
                  validator: (v) => Validators.email(context, v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _token,
                  decoration: InputDecoration(labelText: l10n.fieldResetCode),
                  validator: (v) => Validators.required(context, v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(labelText: l10n.fieldNewPassword),
                  validator: (v) => Validators.password(context, v),
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.authForgotTitle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
