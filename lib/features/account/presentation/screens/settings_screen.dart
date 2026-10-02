import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/theme_mode_controller.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/app_info.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../notifications/presentation/notification_settings_controller.dart';
import '../delete_account_action.dart';
import '../../../../app/theme/hub_icons.dart';

/// App settings: language toggle (EN/AR) + notification preferences, plus a
/// shortcut to Help. This screen is the language switch's home (Account's
/// Language row opens it, signed in or out: the menu drawer that once held a
/// second copy is gone).
///
/// Not in the Figma frames; laid out with the Account pages' pieces (the
/// sub-page app bar, grouped cards under small labels).
///
/// The dev and staging builds add developer tools: the theme switch (the
/// design is light only) and the connection test.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final store = ref.watch(storeControllerProvider);
    final promoEnabled = ref.watch(notificationSettingsProvider);
    final developerTools = ref.watch(developerToolsProvider);
    final pushAvailable = ref.watch(pushNotificationsAvailableProvider);
    final isAuthenticated = ref.watch(
      authControllerProvider.select((s) => s.isAuthenticated),
    );

    return Scaffold(
      backgroundColor: groupedPageColor(context),
      appBar: subpageAppBar(context, l10n.settingsTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          if (developerTools) ...[
            GroupLabel(l10n.settingsTheme, top: 0),
            GroupCard(
              padding: const EdgeInsets.all(14),
              children: [
                SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(l10n.themeWhite),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(l10n.themeBlack),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(l10n.themeSystem),
                    ),
                  ],
                  selected: {ref.watch(themeModeProvider)},
                  onSelectionChanged: (s) =>
                      ref.read(themeModeProvider.notifier).set(s.first),
                ),
              ],
            ),
          ],

          GroupLabel(l10n.languageToggleLabel, top: developerTools ? 18 : 0),
          GroupCard(
            padding: const EdgeInsets.all(14),
            children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'en', label: Text(l10n.languageEnglish)),
                  ButtonSegment(value: 'ar', label: Text(l10n.languageArabic)),
                ],
                selected: {store.activeLocale == 'ar' ? 'ar' : 'en'},
                onSelectionChanged: (selection) => ref
                    .read(storeControllerProvider.notifier)
                    .switchLocale(selection.first),
              ),
            ],
          ),

          // Push only exists with FCM (no Firebase config ships yet), and
          // order pushes need backend device tokens — so no promise about
          // them either.
          if (pushAvailable) ...[
            GroupLabel(l10n.notificationsTitle),
            GroupCard(
              children: [
                _onCard(
                  SwitchListTile.adaptive(
                    value: promoEnabled,
                    onChanged: (v) => ref
                        .read(notificationSettingsProvider.notifier)
                        .setPromotions(v),
                    title: Text(l10n.notificationsPromoTitle),
                    subtitle: Text(l10n.notificationsPromoBody),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 18),
          GroupCard(
            children: [
              _onCard(
                ListTile(
                  leading: const Icon(HubIcons.circleHelp),
                  title: Text(l10n.accountHelp),
                  trailing: const Icon(HubIcons.chevronRight),
                  onTap: () => context.push(AppRoutes.help),
                ),
              ),
              // Live on-device connection probe (runs storeConfig against the
              // active store view) — lets us tell a network/WAF problem apart
              // from an empty catalogue when content isn't loading on a real
              // device. A developer tool (its screen is English only), so not
              // in the customer build.
              if (developerTools)
                _onCard(
                  ListTile(
                    leading: const Icon(HubIcons.wifi),
                    title: Text(l10n.settingsConnectionTest),
                    subtitle: Text(l10n.settingsConnectionTestSubtitle),
                    trailing: const Icon(HubIcons.chevronRight),
                    onTap: () => context.push(AppRoutes.diagnostics),
                  ),
                ),
              // Account deletion must be reachable from inside the app
              // whenever an account exists (App Store Review Guideline
              // 5.1.1(v)) — hidden for guests, who have nothing to delete.
              if (isAuthenticated) _onCard(const _DeleteAccountTile()),
            ],
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                ref
                    .watch(appVersionProvider)
                    .maybeWhen(
                      data: (v) => v == null ? '' : '${l10n.versionLabel} $v',
                      orElse: () => '',
                    ),
                style: t.caption.copyWith(color: context.scaffoldMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A list tile on a [GroupCard]: in a Material of its own, because the card's
/// white would otherwise hide the tile's ink.
Widget _onCard(Widget tile) =>
    Material(type: MaterialType.transparency, child: tile);

/// Destructive account deletion. Confirms first, spelling out exactly what is
/// lost, and only clears local state after Magento confirms the delete — a
/// failure leaves the customer signed in rather than pretending it worked.
class _DeleteAccountTile extends ConsumerStatefulWidget {
  const _DeleteAccountTile();

  @override
  ConsumerState<_DeleteAccountTile> createState() => _DeleteAccountTileState();
}

class _DeleteAccountTileState extends ConsumerState<_DeleteAccountTile> {
  bool _busy = false;

  Future<void> _confirmAndDelete() async {
    setState(() => _busy = true);
    // Shared with the Account screen's tile so both routes behave identically.
    await confirmAndDeleteAccount(context, ref);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = Theme.of(context).colorScheme.error;

    return ListTile(
      enabled: !_busy,
      leading: Icon(HubIcons.trash2, color: error),
      title: Text(l10n.deleteAccountTitle, style: TextStyle(color: error)),
      subtitle: Text(l10n.deleteAccountSubtitle),
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _busy ? null : _confirmAndDelete,
    );
  }
}
