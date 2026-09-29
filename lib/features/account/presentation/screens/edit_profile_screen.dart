import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/config/store_features.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/validation/validators.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/hub_back_button.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../notifications/presentation/notification_settings_controller.dart';
import '../../data/account_repository.dart';
import '../newsletter_controller.dart';
import '../widgets/mobile_number_editor.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _profileKey = GlobalKey<FormState>();
  final _passwordKey = GlobalKey<FormState>();
  late final TextEditingController _fullName;
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  bool _savingProfile = false;
  bool _savingPassword = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    final customer = ref.read(authControllerProvider).customer;
    _fullName = TextEditingController(text: customer?.fullName ?? '');
  }

  @override
  void dispose() {
    _fullName.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_profileKey.currentState!.validate()) return;
    setState(() => _savingProfile = true);
    final l10n = AppLocalizations.of(context);
    try {
      // Single Full Name field (Figma) → split for Magento's first/last. Last
      // token is the surname; a single token fills both so validation passes.
      final parts = _fullName.text
          .trim()
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .toList();
      final first = parts.isEmpty
          ? ''
          : (parts.length == 1
                ? parts.first
                : parts.sublist(0, parts.length - 1).join(' '));
      final last = parts.isEmpty ? '' : parts.last;
      await ref
          .read(accountRepositoryProvider)
          .updateProfile(firstName: first, lastName: last);
      await ref.read(authControllerProvider.notifier).refreshCustomer();
      _snack(l10n.profileSaved);
    } catch (_) {
      _snack(l10n.errorGeneric);
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _changePassword() async {
    if (!_passwordKey.currentState!.validate()) return;
    setState(() => _savingPassword = true);
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(accountRepositoryProvider)
          .changePassword(_currentPassword.text, _newPassword.text);
      _currentPassword.clear();
      _newPassword.clear();
      _snack(l10n.passwordChanged);
    } catch (_) {
      _snack(l10n.errorGeneric);
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  void _snack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Saves the newsletter opt-in on the account at once, like the push
  /// switch beside it.
  Future<void> _setEmailOffers(bool value) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await ref
          .read(newsletterProvider.notifier)
          .setSubscribed(value);
      if (value && !saved) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.footerSubscribeConfirm)),
        );
      }
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(serverMessageOr(context, error, l10n.errorGeneric)),
        ),
      );
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.take(2).map((p) => p.substring(0, 1).toUpperCase());
    final joined = letters.join();
    return joined.isEmpty ? '?' : joined;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final customer = ref.watch(authControllerProvider).customer;
    final isAr =
        ref.watch(storeControllerProvider.select((s) => s.activeLocale)) ==
        'ar';
    final pushEnabled = ref.watch(notificationSettingsProvider);
    // Push only exists with FCM; e-mail offers are the account's newsletter
    // flag (is_subscribed), shown while the store has the newsletter on.
    final pushAvailable = ref.watch(pushNotificationsAvailableProvider);
    final newsletterEnabled =
        ref.watch(storeFeaturesProvider).valueOrNull?.newsletterEnabled ??
        false;
    final emailOffers = ref.watch(newsletterProvider);

    return HubScaffold(
      currentTab: AppTab.account,
      showSearch: false,
      appBar: AppBar(
        centerTitle: true,
        leading: const HubBackButton(),
        title: Text(l10n.profileTitle),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 24),
          // Initials avatar. No photo upload: the backend has no
          // customer-photo endpoint (the app's first client had a custom
          // `uploadCustomerAvatar` module that Hub Market doesn't).
          Center(
            child: _AvatarBadge(initials: _initials(customer?.fullName ?? '')),
          ),
          const SizedBox(height: 16),
          _SectionHeader(l10n.profilePersonalInfo),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Form(
              key: _profileKey,
              child: Column(
                children: [
                  _ProfileField(
                    controller: _fullName,
                    label: l10n.fieldFullName,
                    icon: Icons.person_outline,
                    validator: (v) => Validators.required(context, v),
                  ),
                  const SizedBox(height: 12),
                  _ProfileField(
                    initialValue: customer?.email ?? '',
                    label: l10n.fieldEmail,
                    icon: Icons.mail_outline,
                    enabled: false,
                  ),
                  const SizedBox(height: 12),
                  // Mobile number — OTP-gated in-place editor (WhatsApp verify).
                  const MobileNumberEditor(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _SectionHeader(l10n.profilePreferences),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Column(
              children: [
                _PrefRow(
                  label: l10n.languageToggleLabel,
                  onTap: () => ref
                      .read(storeControllerProvider.notifier)
                      .switchLocale(isAr ? 'en' : 'ar'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isAr ? 'AR' : 'EN',
                        style: TextStyle(color: context.scaffoldMuted),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right,
                        color: context.scaffoldMuted,
                        size: 20,
                      ),
                    ],
                  ),
                ),
                if (pushAvailable) ...[
                  const SizedBox(height: 12),
                  _PrefToggleRow(
                    label: l10n.profilePushNotifications,
                    value: pushEnabled,
                    onChanged: (v) => ref
                        .read(notificationSettingsProvider.notifier)
                        .setPromotions(v),
                  ),
                ],
                if (newsletterEnabled) ...[
                  const SizedBox(height: 12),
                  _PrefToggleRow(
                    label: l10n.profileEmailOffers,
                    value: emailOffers.valueOrNull ?? false,
                    onChanged: emailOffers.isLoading
                        ? null
                        : (v) => _setEmailOffers(v),
                  ),
                ],
                const SizedBox(height: 12),
                _PrefRow(
                  label: l10n.profilePasswordSection,
                  onTap: () => setState(() => _showPassword = !_showPassword),
                  trailing: Icon(
                    _showPassword ? Icons.expand_less : Icons.chevron_right,
                    color: context.scaffoldMuted,
                    size: 20,
                  ),
                ),
                if (_showPassword) ...[
                  const SizedBox(height: 12),
                  Form(
                    key: _passwordKey,
                    child: Column(
                      children: [
                        _ProfileField(
                          controller: _currentPassword,
                          label: l10n.fieldCurrentPassword,
                          icon: Icons.lock_outline,
                          obscureText: true,
                          validator: (v) => Validators.required(context, v),
                        ),
                        const SizedBox(height: 12),
                        _ProfileField(
                          controller: _newPassword,
                          label: l10n.fieldNewPassword,
                          icon: Icons.lock_reset_outlined,
                          obscureText: true,
                          validator: (v) => Validators.password(context, v),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _savingPassword ? null : _changePassword,
                            child: _savingPassword
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(l10n.profilePasswordSection),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Save Changes (Figma) — full-width navy.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _savingProfile ? null : _saveProfile,
                child: _savingProfile
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.profileSaveChanges),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Circular initials avatar with a navy ring (Figma).
class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.brandPrimary, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: AppColors.brandPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 26,
        ),
      ),
    );
  }
}

/// Muted uppercase section header (Figma "PERSONAL INFORMATION" / "PREFERENCES").
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(24, 16, 24, 8),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: context.scaffoldMuted,
      ),
    ),
  );
}

/// Filled, rounded text field with a leading icon (Figma personal-info rows).
class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.icon,
    this.controller,
    this.initialValue,
    this.validator,
    this.enabled = true,
    this.obscureText = false,
  });

  final String label;
  final IconData icon;
  final TextEditingController? controller;
  final String? initialValue;
  final String? Function(String?)? validator;
  final bool enabled;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      validator: validator,
      enabled: enabled,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        // Dark mode: a light fill hid the (light) input text (QA "Profile page").
        fillColor: context.fieldFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// A tappable preference row (filled, rounded): label + trailing widget.
class _PrefRow extends StatelessWidget {
  const _PrefRow({
    required this.label,
    required this.trailing,
    required this.onTap,
  });

  final String label;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.fieldFill,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.scaffoldHeading,
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// A preference row with a trailing switch (filled, rounded).
class _PrefToggleRow extends StatelessWidget {
  const _PrefToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.fieldFill,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.scaffoldHeading,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.brandPrimary,
          ),
        ],
      ),
    );
  }
}
