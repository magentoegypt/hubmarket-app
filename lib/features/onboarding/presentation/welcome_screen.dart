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

/// Welcome (Figma "02 Welcome"): EN/AR language pill, the Hub Market logo and
/// app mark, the "same-day delivery" kicker, headline + subtitle, then Create
/// account / Sign in / Continue as guest. Chrome-free (no bottom nav, no
/// drawer). Guests can browse; sign-in is only forced at checkout.
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
              // First-launch language choice. Flips the Store header +
              // Directionality via the atomic store switch.
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
                    Image.asset(
                      AppImages.logo,
                      height: 72,
                      errorBuilder: (_, __, ___) =>
                          const BrandLockup(fontSize: 40),
                    ),
                    const SizedBox(height: 28),
                    ClipOval(
                      child: Image.asset(
                        AppImages.appIcon,
                        width: 168,
                        height: 168,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 168,
                          height: 168,
                          color: AppColors.logoNavy,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4EC),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        l10n.welcomeKicker,
                        style: const TextStyle(
                          color: AppColors.accentStrong,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.welcomeHeadline,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        // Playfair Display has no Arabic glyphs — AR keeps the
                        // Arabic face.
                        fontFamily: isEn ? AppTheme.displayFont : null,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkHeading,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.welcomeSubtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () => context.push(AppRoutes.signUp),
                child: Text(l10n.welcomeCreateAccount),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.push(AppRoutes.signIn),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  foregroundColor: AppColors.brandPrimary,
                  side: const BorderSide(color: AppColors.brandPrimary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(l10n.welcomeSignIn),
              ),
              const SizedBox(height: 6),
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
