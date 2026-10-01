import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/config/store_features.dart';
import '../../../../core/validation/password_policy.dart';
import '../../../../core/validation/validators.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../core/widgets/hub_footer_bar.dart';
import '../../../../core/widgets/hub_switch.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../auth/presentation/widgets/auth_field.dart';
import '../../data/account_repository.dart';
import '../profile_extras_provider.dart';
import '../widgets/mobile_number_editor.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_value_field.dart';

/// Profile details (Figma 20c): the avatar, first and last name, e-mail,
/// mobile number, date of birth and the Change password card, with one Save
/// changes for all of it.
///
/// Built from what the backend holds:
/// * the avatar is initials — the backend has no customer-photo endpoint, so
///   the frame's "Change photo" is left out;
/// * "Verified" under the e-mail shows only when the store confirmed the
///   address (`confirmation_status`); under the mobile number it is left out —
///   nothing says whether a number was verified, only that the app changes it
///   through a code (see [MobileNumberEditor]);
/// * the date of birth is the account's `date_of_birth` (optional);
/// * the new password follows the store's own rule ([PasswordPolicy]); the
///   strength bar fills with what the typed password satisfies.
///
/// The language, push and e-mail-offer rows this page used to carry are on
/// Account (Language, Notifications, Newsletter), as the frame has them.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _profileKey = GlobalKey<FormState>();
  final _passwordKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  /// The Change password card is open (the switch is on).
  bool _changePassword = false;

  /// Whether each of the three password fields hides its characters.
  final List<bool> _hidden = [true, true, true];

  /// The date picked on this page; until one is, the account's own shows.
  DateTime? _birthDate;
  bool _birthDatePicked = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final customer = ref.read(authControllerProvider).customer;
    _firstName = TextEditingController(text: customer?.firstName ?? '');
    _lastName = TextEditingController(text: customer?.lastName ?? '');
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Saves the profile and, when the card is open, the new password: the
  /// profile first, then the password, whose refusal is the store's own words.
  Future<void> _save(DateTime? birthDate) async {
    final profileOk = _profileKey.currentState?.validate() ?? true;
    final passwordOk =
        !_changePassword || (_passwordKey.currentState?.validate() ?? true);
    if (!profileOk || !passwordOk) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(accountRepositoryProvider);
    try {
      await repository.updateProfile(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        dateOfBirth: birthDate == null
            ? null
            : DateFormat('yyyy-MM-dd').format(birthDate),
      );
    } catch (_) {
      _snack(l10n.errorGeneric);
      if (mounted) setState(() => _saving = false);
      return;
    }
    var message = l10n.profileSaved;
    try {
      if (_changePassword) {
        await repository.changePassword(
          _currentPassword.text,
          _newPassword.text,
        );
        message = l10n.passwordChanged;
        _currentPassword.clear();
        _newPassword.clear();
        _confirmPassword.clear();
        if (mounted) setState(() => _changePassword = false);
      }
      await ref.read(authControllerProvider.notifier).refreshCustomer();
      _snack(message);
    } catch (error) {
      // The store's own (localized) words — a wrong current password, a new
      // one it won't take — like the other forms; generic only when it gave
      // none.
      if (mounted) _snack(serverMessageOr(context, error, l10n.errorGeneric));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickBirthDate(DateTime? current) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() {
        _birthDate = picked;
        _birthDatePicked = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final customer = ref.watch(authControllerProvider).customer;
    final extras = ref.watch(profileExtrasProvider).valueOrNull;
    final policy = ref.watch(passwordPolicyProvider);
    final birthDate = _birthDatePicked
        ? _birthDate
        : DateTime.tryParse(extras?.dateOfBirth ?? '');

    // The session may still be restoring when the page opens: fill the names
    // when the customer arrives, as long as nothing was typed.
    ref.listen(authControllerProvider.select((s) => s.customer), (_, next) {
      if (next != null &&
          _firstName.text.isEmpty &&
          _lastName.text.isEmpty) {
        _firstName.text = next.firstName;
        _lastName.text = next.lastName;
      }
    });

    return HubScaffold(
      currentTab: AppTab.account,
      // Figma: a pushed page, no tab bar.
      showTabBar: false,
      appBar: subpageAppBar(context, l10n.profileTitle, divider: true),
      bottomBar: HubFooterBar(
        child: HubButton(
          label: l10n.profileSaveChanges,
          loading: _saving,
          onPressed: _saving ? null : () => _save(birthDate),
        ),
      ),
      body: ListView(
        // Figma body: 12 under the bar, 14 between the fields.
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          // The avatar: 8 above, 4 below. No photo upload (see the class doc).
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Center(
              child: ProfileAvatar(
                name: customer?.fullName ?? '',
                diameter: 84,
                // 28 in DM Sans; the Arabic frame keeps the hub avatar's 18.
                fontSize: AppTextStyles.of(context).arabic ? 18 : 28,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Form(
            key: _profileKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AuthField(
                        controller: _firstName,
                        label: l10n.fieldFirstName,
                        icon: HubIcons.user,
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => Validators.required(context, v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AuthField(
                        controller: _lastName,
                        label: l10n.fieldLastName,
                        icon: HubIcons.user,
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => Validators.required(context, v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ProfileValueField(
                  label: l10n.profileEmailAddress,
                  icon: HubIcons.mail,
                  value: customer?.email,
                  ltr: true,
                ),
                if (extras?.emailConfirmed ?? false) ...[
                  const SizedBox(height: 6),
                  _Verified(label: l10n.profileVerified),
                ],
                const SizedBox(height: 14),
                // Mobile number — OTP-gated in-place editor (WhatsApp verify).
                const MobileNumberEditor(),
                const SizedBox(height: 14),
                ProfileValueField(
                  label: l10n.profileBirthDate,
                  icon: HubIcons.gift,
                  value: birthDate == null ? null : _dateLabel(birthDate, locale),
                  placeholder: l10n.profileBirthDatePick,
                  onTap: () => _pickBirthDate(birthDate),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _passwordCard(context, l10n, policy),
        ],
      ),
    );
  }

  /// "12 Mar 1994".
  static String _dateLabel(DateTime date, String locale) {
    try {
      return DateFormat('d MMM yyyy', locale).format(date);
    } catch (_) {
      return DateFormat('d MMM yyyy').format(date);
    }
  }

  /// Figma `password`: a 1 px `border/subtle` card at radius 14, 14 px of
  /// padding, 12 between its parts; the switch opens the three fields.
  Widget _passwordCard(
    BuildContext context,
    AppLocalizations l10n,
    PasswordPolicy? policy,
  ) {
    final t = AppTextStyles.of(context);
    final strength = profilePasswordStrength(_newPassword.text, policy);
    Widget field(
      TextEditingController controller,
      String label,
      int index, {
      String? Function(String)? validator,
      TextInputAction action = TextInputAction.next,
      ValueChanged<String>? onChanged,
    }) => AuthField(
      controller: controller,
      label: label,
      icon: HubIcons.lock,
      obscureText: _hidden[index],
      textInputAction: action,
      validator: validator,
      onChanged: onChanged,
      trailing: PasswordVisibilityToggle(
        obscured: _hidden[index],
        onPressed: () => setState(() => _hidden[index] = !_hidden[index]),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _changePassword = !_changePassword),
            child: Row(
              children: [
                const Icon(
                  HubIcons.lock,
                  size: 20,
                  color: AppColors.inkSubtle,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.profilePasswordSection,
                    style: t.title.copyWith(color: AppColors.inkHeading),
                  ),
                ),
                HubSwitch(
                  value: _changePassword,
                  onChanged: (v) => setState(() => _changePassword = v),
                  semanticLabel: l10n.profilePasswordSection,
                ),
              ],
            ),
          ),
          if (_changePassword)
            Form(
              key: _passwordKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  field(
                    _currentPassword,
                    l10n.fieldCurrentPassword,
                    0,
                    validator: (v) => Validators.required(context, v),
                  ),
                  const SizedBox(height: 12),
                  field(
                    _newPassword,
                    l10n.fieldNewPassword,
                    1,
                    validator: (v) =>
                        Validators.newPassword(context, v, policy: policy),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  _StrengthMeter(
                    score: strength,
                    rule: Validators.passwordRuleText(l10n, policy),
                  ),
                  const SizedBox(height: 12),
                  field(
                    _confirmPassword,
                    l10n.profileConfirmNewPassword,
                    2,
                    action: TextInputAction.done,
                    validator: (v) => Validators.confirmPassword(
                      context,
                      v,
                      _newPassword.text,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// How many of four things a new password has: the store's minimum length, a
/// letter, a digit and a symbol (0–4) — what the strength bar fills with. The
/// bar only shows progress; whether the password is accepted is the store's
/// rule ([PasswordPolicy]), checked on save.
int profilePasswordStrength(String value, [PasswordPolicy? policy]) {
  if (value.isEmpty) return 0;
  var score = 0;
  if (value.runes.length >= (policy?.minLength ?? 8)) score++;
  if (RegExp('[a-zA-Z]').hasMatch(value)) score++;
  if (RegExp('[0-9]').hasMatch(value)) score++;
  if (RegExp('[^a-zA-Z0-9]').hasMatch(value)) score++;
  return score;
}

/// The strength bar of Figma 20c: four 4 px segments 4 apart, the lit ones
/// green (red for one, amber for two), then the store's rule in EN/Caption.
class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.score, required this.rule});

  final int score;
  final String rule;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final lit = switch (score) {
      <= 1 => AppColors.danger,
      2 => AppColors.warning,
      _ => AppColors.successStrong,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i < score ? lit : AppColors.borderSubtle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(rule, style: t.caption.copyWith(color: AppColors.inkMuted)),
      ],
    );
  }
}

/// "Verified": the badge-check and EN/Caption in `success`.
class _Verified extends StatelessWidget {
  const _Verified({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(HubIcons.badgeCheck, size: 13, color: AppColors.successStrong),
      const SizedBox(width: 4),
      Text(
        label,
        style: AppTextStyles.of(
          context,
        ).caption.copyWith(color: AppColors.successStrong),
      ),
    ],
  );
}
