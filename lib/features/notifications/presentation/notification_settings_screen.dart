import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/shell/hub_scaffold.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/hub_icons.dart';
import '../../../app/theme/theme_x.dart';
import '../../../core/config/store_features.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/failure_message.dart';
import '../../../core/widgets/grouped_list.dart';
import '../../../core/widgets/hub_button.dart';
import '../../../core/widgets/hub_checkbox.dart';
import '../../../core/widgets/hub_footer_bar.dart';
import '../../../core/widgets/hub_switch.dart';
import '../../../l10n/l10n.dart';
import '../../account/presentation/newsletter_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import 'notification_settings_controller.dart';

/// Notification settings (Figma 20h): push and the e-mail newsletter, saved
/// together with Save.
///
/// * Push shows only when FCM is available ([pushNotificationsAvailableProvider]);
///   Hub Market has no Firebase config yet, so today it is hidden. Only the
///   promotions topic exists — per-type order / return / price-drop pushes
///   need the device registered with the backend (`DeviceTokenSync`).
/// * The newsletter is the account's `is_subscribed`, shown for a signed-in
///   customer when storeConfig `newsletter_enabled` is on.
/// * Left out of the frame: its SMS section (the backend has no SMS
///   preferences) and the Orders & delivery, Returns & refunds and Price drops
///   switches (a push cannot be told apart by kind without per-device
///   registration); the one switch is the promotions topic, the frame's
///   "Deals & offers".
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
      // Figma: a pushed page, no tab bar.
      showTabBar: false,
      appBar: subpageAppBar(context, l10n.notificationSettingsTitle),
      bottomBar: hasSettings
          ? HubFooterBar(
              child: HubButton(
                label: l10n.actionSave,
                loading: _saving,
                onPressed: dirty && !_saving ? _save : null,
              ),
            )
          : null,
      body: ColoredBox(
        color: groupedPageColor(context),
        child: hasSettings
            ? ListView(
                // Figma body: 14 under the bar, 18 between the groups.
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                children: [
                  if (pushAvailable) ...[
                    GroupLabel(l10n.notificationsPushSection, top: 0),
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
                    GroupLabel(
                      l10n.newsletterTitle,
                      top: pushAvailable ? 18 : 0,
                    ),
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

/// Figma `setting/…`: a title (EN/Body Strong) over its description
/// (EN/Caption, muted) and the switch, 14 px of padding at the sides and 12
/// above and below; the whole row toggles.
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
  Widget build(BuildContext context) => InkWell(
    onTap: onChanged == null ? null : () => onChanged!(!value),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: _Texts(title: title, subtitle: subtitle),
          ),
          const SizedBox(width: 12),
          HubSwitch(value: value, onChanged: onChanged, semanticLabel: title),
        ],
      ),
    ),
  );
}

/// The newsletter row (Figma `row` with the 22 px checkbox): the box at the
/// start, the text beside it.
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            loading
                ? const SizedBox(
                    width: HubCheckbox.size,
                    height: HubCheckbox.size,
                    child: Padding(
                      padding: EdgeInsets.all(2),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : HubCheckbox(value: value, onChanged: onChanged),
            const SizedBox(width: 12),
            Expanded(
              child: _Texts(title: title, subtitle: subtitle),
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
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: t.bodyStrong.copyWith(color: context.scaffoldHeading),
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: t.caption.copyWith(color: context.scaffoldMuted)),
      ],
    );
  }
}
