import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/theme_mode_controller.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/app_info.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../notifications/presentation/notification_settings_controller.dart';
import '../delete_account_action.dart';

/// App settings: language toggle (EN/AR) + notification preferences, plus a
/// shortcut to Help. The same language switch lives in the menu drawer; this
/// screen is the discoverable home for it.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final store = ref.watch(storeControllerProvider);
    final promoEnabled = ref.watch(notificationSettingsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isAuthenticated = ref.watch(
      authControllerProvider.select((s) => s.isAuthenticated),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          _SectionHeader(l10n.settingsTheme),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: ThemeMode.light, label: Text(l10n.themeWhite)),
                ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeBlack)),
                ButtonSegment(value: ThemeMode.system, label: Text(l10n.themeSystem)),
              ],
              selected: {themeMode},
              onSelectionChanged: (s) =>
                  ref.read(themeModeProvider.notifier).set(s.first),
            ),
          ),
          const Divider(height: 32),

          _SectionHeader(l10n.languageToggleLabel),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
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
          ),
          const Divider(height: 32),

          _SectionHeader(l10n.notificationsTitle),
          SwitchListTile.adaptive(
            value: promoEnabled,
            onChanged: (v) =>
                ref.read(notificationSettingsProvider.notifier).setPromotions(v),
            title: Text(l10n.notificationsPromoTitle),
            subtitle: Text(l10n.notificationsPromoBody),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.notificationsOrdersNote,
              style: TextStyle(color: context.scaffoldMuted),
            ),
          ),
          const Divider(height: 32),

          ListTile(
            leading: const Icon(Icons.help_outline),
            title: Text(l10n.accountHelp),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.help),
          ),
          // Live on-device connection probe (runs storeConfig against the active
          // store view) — lets us tell a network/WAF problem apart from an empty
          // catalogue when content isn't loading on a real device.
          ListTile(
            leading: const Icon(Icons.wifi_tethering),
            title: Text(l10n.settingsConnectionTest),
            subtitle: Text(l10n.settingsConnectionTestSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.diagnostics),
          ),
          // Account deletion must be reachable from inside the app whenever an
          // account exists (App Store Review Guideline 5.1.1(v)) — hidden for
          // guests, who have nothing to delete.
          if (isAuthenticated) ...[
            const Divider(height: 32),
            const _DeleteAccountTile(),
          ],
          const Divider(height: 32),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                ref.watch(appVersionProvider).maybeWhen(
                      data: (v) => v == null ? '' : '${l10n.versionLabel} $v',
                      orElse: () => '',
                    ),
                style: TextStyle(color: context.scaffoldMuted, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
      leading: Icon(Icons.delete_forever_outlined, color: error),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        color: context.scaffoldMuted,
        fontWeight: FontWeight.w700,
        fontSize: 12,
        letterSpacing: 1,
      ),
    ),
  );
}
