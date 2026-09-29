import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/assets/app_images.dart';
import '../../../core/store/store_controller.dart';
import '../../../core/widgets/brand_lockup.dart';
import '../../../core/widgets/language_toggle.dart';
import '../../../l10n/l10n.dart';

/// Welcome screen (Figma "Splash — Welcome"): EN/AR language pill, brand lockup,
/// circular flatlay visual, headline + subtitle, and the Get Started / Sign In /
/// guest actions. Chrome-free (no bottom nav, no drawer, no footer).
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final activeLocale = ref.watch(
      storeControllerProvider.select((s) => s.activeLocale),
    );
    final isEn = activeLocale != 'ar';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              // Language switcher — first-launch language choice. Flips the
              // Store header + Directionality via the atomic store switch.
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: LanguageToggle(
                  activeLocale: activeLocale,
                  onChanged: (locale) => ref
                      .read(storeControllerProvider.notifier)
                      .switchLocale(locale),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Brand logo (burgundy on transparent → reads on the light
                    // background); falls back to the wordmark if absent. Sized
                    // up to match Figma — the 48px version read as too small.
                    Image.asset(
                      AppImages.logo,
                      height: 84,
                      errorBuilder: (_, __, ___) =>
                          const BrandLockup(fontSize: 44),
                    ),
                    const SizedBox(height: 32),
                    // Circular flatlay visual (Figma uses a contained circle,
                    // not a full-bleed rectangle).
                    ClipOval(
                      child: SizedBox(
                        width: 240,
                        height: 240,
                        child: Image.asset(
                          AppImages.banner,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: AppColors.surfaceTint),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      l10n.welcomeHeadline,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        // Playfair Display (Latin display face) for EN only —
                        // it has no Arabic glyphs, so AR keeps Cairo.
                        fontFamily: isEn ? AppTheme.displayFont : null,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkHeading,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.welcomeSubtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () => context.go(AppRoutes.home),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.welcomeGetStarted),
                    const SizedBox(width: 8),
                    // arrow_forward auto-mirrors under RTL (matchTextDirection:
                    // true), so it points "forward" in both LTR and AR. The old
                    // manual rtl→arrow_back flip double-mirrored and pointed the
                    // wrong way in Arabic.
                    const Icon(Icons.arrow_forward, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // "Already have an account? Sign In" — muted prefix + burgundy link.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    l10n.authHaveAccount,
                    style: const TextStyle(color: AppColors.inkMuted),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => context.push(AppRoutes.signIn),
                    child: Text(
                      l10n.welcomeSignIn,
                      style: const TextStyle(
                        color: AppColors.brandPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.go(AppRoutes.home),
                child: Text(
                  l10n.welcomeContinueGuest,
                  style: const TextStyle(color: AppColors.inkMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
