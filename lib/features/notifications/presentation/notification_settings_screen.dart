import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/shell/hub_scaffold.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/theme_x.dart';
import '../../../core/config/store_features.dart';
import '../../../core/widgets/button_spinner.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/failure_message.dart';
import '../../../core/widgets/grouped_list.dart';
import '../../../l10n/l10n.dart';
import '../../account/presentation/newsletter_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import 'notification_settings_controller.dart';
import '../../../app/theme/hub_icons.dart';

/// Notification settings (Figma 20h): push and the e-mail newsletter, saved
/// together with Save.
///
/// * Push shows only when FCM is available ([pushNotificationsAvailableProvider]);
///   Hub Market has no Firebase config yet, so today it is hidden. Only the
///   promotions topic exists — per-type order / return / price-drop pushes
///   need the device registered with the backend (`DeviceTokenSync`).
/// * The newsletter is the account's `is_subscribed`, shown for a signed-in
///   customer when storeConfig `newsletter_enabled` is on.
/// * The frame's SMS section is left out: the backend has no SMS preferences.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  /// Unsaved changes; null = as saved.
  bool? _promo;
  bool? _newsletter;
  bool _saving = false;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final promo = _promo;
    final newsletter = _newsletter;
    setState(() => _saving = true);
    var message = l10n.notificationSettingsSaved;
    try {
      if (promo != null && promo != ref.read(notificationSettingsProvider)) {
        await ref
            .read(notificationSettingsProvider.notifier)
            .setPromotions(promo);
      }
      if (newsletter != null &&
          newsletter != ref.read(newsletterProvider).valueOrNull) {
        final saved = await ref
            .read(newsletterProvider.notifier)
            .setSubscribed(newsletter);
        if (newsletter && !saved) message = l10n.footerSubscribeConfirm;
      }
      if (!mounted) return;
      setState(() {
        _promo = null;
        _newsletter = null;
      });
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(serverMessageOr(context, error, l10n.errorGeneric)),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pushAvailable = ref.watch(pushNotificationsAvailableProvider);
    final signedIn = ref.watch(
      authControllerProvider.select((s) => s.isAuthenticated),
    );
    final features =
        ref.watch(storeFeaturesProvider).valueOrNull ?? StoreFeatures.none;
    final showNewsletter = signedIn && features.newsletterEnabled;
    final subscription = ref.watch(newsletterProvider);
    final promoSaved = ref.watch(notificationSettingsProvider);

    final promo = _promo ?? promoSaved;
    final newsletter = _newsletter ?? subscription.valueOrNull ?? false;
    final dirty =
        (_promo != null && _promo != promoSaved) ||
        (_newsletter != null && _newsletter != subscription.valueOrNull);
    final hasSettings = pushAvailable || showNewsletter;

    return HubScaffold(
      currentTab: AppTab.account,
      appBar: subpageAppBar(context, l10n.notificationSettingsTitle),
      bottomBar: hasSettings
          ? _SaveBar(
              saving: _saving,
              onSave: dirty && !_saving ? _save : null,
            )
          : null,
      body: ColoredBox(
        color: groupedPageColor(context),
        child: hasSettings
            ? ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  if (pushAvailable) ...[
                    GroupLabel(l10n.notificationsPushSection),
                    GroupCard(
                      children: [
                        _SwitchRow(
                          title: l10n.notificationsPromoTitle,
                          subtitle: l10n.notificationsPromoBody,
                          value: promo,
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _promo = v),
                        ),
                      ],
                    ),
                  ],
                  if (showNewsletter) ...[
                    GroupLabel(l10n.newsletterTitle),
                    GroupCard(
                      children: [
                        _CheckRow(
                          title: l10n.newsletterGeneral,
                          subtitle: l10n.newsletterGeneralBody,
                          value: newsletter,
                          loading: subscription.isLoading,
                          failed: subscription.hasError,
                          onRetry: () => ref.invalidate(newsletterProvider),
                          onChanged: _saving || subscription.isLoading
                              ? null
                              : (v) => setState(() => _newsletter = v),
                        ),
                      ],
                    ),
                  ],
                ],
              )
            : EmptyState(
                icon: HubIcons.bell,
                title: l10n.notificationSettingsTitle,
                body: signedIn
                    ? l10n.notificationSettingsNone
                    : l10n.notificationSettingsSignIn,
                action: signedIn
                    ? null
                    : FilledButton(
                        onPressed: () => context.push(AppRoutes.signIn),
                        child: Text(l10n.authSignInTitle),
                      ),
              ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 10),
    child: Row(
      children: [
        Expanded(child: _Texts(title: title, subtitle: subtitle)),
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

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.loading,
    required this.failed,
    required this.onRetry,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool loading;
  final bool failed;
  final VoidCallback onRetry;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 8, 14, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              height: 40,
              child: loading
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Checkbox(
                      value: value,
                      activeColor: AppColors.brandPrimary,
                      onChanged: onChanged == null
                          ? null
                          : (v) => onChanged!(v ?? false),
                    ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _Texts(title: title, subtitle: subtitle),
              ),
            ),
            if (failed)
              TextButton(onPressed: onRetry, child: Text(l10n.actionRetry)),
          ],
        ),
      ),
    );
  }
}

class _Texts extends StatelessWidget {
  const _Texts({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: context.scaffoldHeading,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        subtitle,
        style: TextStyle(fontSize: 12, height: 1.4, color: context.scaffoldMuted),
      ),
    ],
  );
}

/// The pinned Save button (Figma 20h).
class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.saving, required this.onSave});

  final bool saving;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: context.hairline)),
      ),
      child: FilledButton(
        onPressed: onSave,
        child: saving
            ? const ButtonSpinner()
            : Text(
                l10n.actionSave,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
      ),
    );
  }
}
