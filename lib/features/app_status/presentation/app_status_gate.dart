import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/app_info.dart';
import '../../../core/hubapp/hubapp.dart';
import '../../../core/util/launch.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../l10n/l10n.dart';

/// What the Hub Market App settings say about using the app right now.
enum AppGate { open, maintenance, updateRequired }

/// [AppGate] from `hmAppConfig`: maintenance first, then a build below the
/// platform's `min_version`. Open while the settings are unknown — the gate
/// never locks anyone out on missing information.
final appGateProvider = Provider<AppGate>((ref) {
  final config = ref.watch(hmAppConfigProvider);
  if (config == null) return AppGate.open;
  if (config.maintenance.enabled) return AppGate.maintenance;
  final policy = config.versionFor(HmPlatform.current);
  final version = ref.watch(appSemverProvider).valueOrNull;
  if (policy != null && policy.requiresUpdate(version)) {
    return AppGate.updateRequired;
  }
  return AppGate.open;
});

/// Holds the whole app behind [MaintenanceScreen] or [UpdateRequiredScreen]
/// while the settings ask for it; otherwise shows [child] (the router) as is.
/// Sits in `MaterialApp.builder`, so it covers every route.
class AppStatusGate extends ConsumerWidget {
  const AppStatusGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(appGateProvider);
    final config = ref.watch(hmAppConfigProvider);
    // The router stays mounted underneath, so lifting the gate returns the
    // customer to where they were.
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(offstage: gate != AppGate.open, child: child),
        if (gate == AppGate.maintenance)
          MaintenanceScreen(
            maintenance: config?.maintenance ?? const HmMaintenance(),
            onRetry: () => ref.read(hubAppProvider.notifier).refresh(),
          ),
        if (gate == AppGate.updateRequired)
          UpdateRequiredScreen(
            policy: config?.versionFor(HmPlatform.current),
          ),
      ],
    );
  }
}

/// Maintenance mode (`hmAppConfig.maintenance`): the admin's message, or the
/// app's own, and "Try again".
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({
    super.key,
    required this.maintenance,
    required this.onRetry,
  });

  final HmMaintenance maintenance;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final minutes = maintenance.retryAfterMinutes;
    return _StatusPage(
      icon: Icons.construction_rounded,
      iconColor: AppColors.accentStrong,
      discColor: AppColors.accentSubtle,
      title: l10n.maintenanceTitle,
      body: maintenance.message ?? l10n.maintenanceBody,
      note: minutes == null ? null : l10n.maintenanceRetryAfter(minutes),
      action: l10n.offlineTryAgain,
      onAction: onRetry,
    );
  }
}

/// A build below the platform's `min_version`: the admin's message, or the
/// app's own, and "Update now" to the store listing when there is one.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, this.policy});

  final HmVersionPolicy? policy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final storeUrl = Uri.tryParse(policy?.storeUrl ?? '');
    return _StatusPage(
      icon: Icons.system_update_rounded,
      iconColor: AppColors.brandPrimary,
      discColor: AppColors.surfaceTint,
      title: l10n.updateRequiredTitle,
      body: policy?.message ?? l10n.updateRequiredBody,
      action: storeUrl == null || !storeUrl.hasScheme
          ? null
          : l10n.updateRequiredAction,
      onAction: storeUrl == null ? null : () => launchExternalUri(storeUrl),
    );
  }
}

class _StatusPage extends StatelessWidget {
  const _StatusPage({
    required this.icon,
    required this.iconColor,
    required this.discColor,
    required this.title,
    required this.body,
    this.note,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final Color iconColor;
  final Color discColor;
  final String title;
  final String body;
  final String? note;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: BrandLogo(height: 40),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          color: discColor,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 48, color: iconColor),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: t.heading1.copyWith(color: AppColors.inkHeading),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        body,
                        textAlign: TextAlign.center,
                        style: t.body.copyWith(color: AppColors.inkMuted),
                      ),
                      if (note != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          note!,
                          textAlign: TextAlign.center,
                          style: t.bodyStrong.copyWith(
                            color: AppColors.inkHeading,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (action != null && onAction != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    textStyle: t.button,
                  ),
                  child: Text(action!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
