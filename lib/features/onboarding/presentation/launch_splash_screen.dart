import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/assets/app_images.dart';
import '../../../core/storage/secure_token_store.dart';
import '../../catalog/domain/category.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../../../core/hubapp/hubapp_providers.dart';
import '../../home/presentation/hm_home_providers.dart';
import '../../home/presentation/home_providers.dart';
import '../../../core/widgets/brand_lockup.dart';
import '../../../l10n/l10n.dart';

/// Launch splash (Figma "01 Splash"): reversed Hub Market logo on a navy
/// gradient with the tagline under it, the orange progress bar near the foot,
/// an orange glow in the top corner and a faint ring in the bottom one. While
/// it shows, we read the saved session: a returning signed-in customer skips
/// Welcome/Sign In and lands on Home; everyone else goes to Welcome.
/// Chrome-free.
class LaunchSplashScreen extends ConsumerStatefulWidget {
  const LaunchSplashScreen({super.key});

  /// How long the splash holds, which is also what its progress bar counts.
  static const Duration hold = Duration(milliseconds: 2600);

  @override
  ConsumerState<LaunchSplashScreen> createState() => _LaunchSplashScreenState();
}

class _LaunchSplashScreenState extends ConsumerState<LaunchSplashScreen> {
  /// Figma: `bg-gradient-to-b` from `#1B3566` to the brand navy.
  static const Color _gradientTop = Color(0xFF1B3566);

  @override
  void initState() {
    super.initState();
    _warmHome();
    _routeOnboarding();
  }

  /// The splash deliberately holds for [LaunchSplashScreen.hold]. Spend it
  /// fetching what Home needs first, so it paints on arrival instead of
  /// starting from nothing.
  ///
  /// Strictly fire-and-forget: nothing here is awaited on the routing path, and
  /// every failure is swallowed — a cold or offline start must still leave the
  /// splash when the hold is over.
  void _warmHome() {
    // The product rails await the category tree before they can even issue
    // their own query, and the CMS blocks feed the strip, promos and trust
    // row — both keepAlive(), so the results survive until Home reads them.
    unawaited(ref.read(categoryTreeProvider.future).catchError((_) {
      return const <Category>[];
    }));
    unawaited(ref.read(homeCmsBlocksProvider.future).catchError((_) {
      return const <String, String>{};
    }));
    // The Hub Market App probe decides which Home to draw; when it finds the
    // module, the admin's Home (and Welcome's slides) load meanwhile too.
    unawaited(
      ref.read(hubAppProvider.future).then((hubApp) async {
        if (hubApp.isAvailable && mounted) {
          await ref.read(hmHomeProvider.future);
        }
      }).catchError((_) {}),
    );
  }

  Future<void> _routeOnboarding() async {
    // Hold the splash long enough for the branding to register (QA: it flashed
    // by in under a second) while reading the persisted token.
    final hold = Future<void>.delayed(LaunchSplashScreen.hold);
    final results = await Future.wait<Object?>([
      ref.read(secureTokenStoreProvider).read(),
      hold,
    ]);
    if (!mounted) return;
    final token = results.first as String?;
    final loggedIn = token != null && token.isNotEmpty;
    context.go(loggedIn ? AppRoutes.home : AppRoutes.welcome);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    // The frame's caption under the bar ("Across all seven emirates") is not
    // drawn: it is a coverage claim the app can't back (QA02). Its line is
    // kept as empty space so the logo and the bar sit where the frame has them.
    final captionLine = t.caption.fontSize! * t.caption.height!;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light status-bar icons on the navy (the frame's "Status bar / Dark").
      value: const SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.brandPrimary,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_gradientTop, AppColors.brandPrimary],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Both decorations mirror in Arabic (Figma AR-01): the ring sits
              // at the bottom-start corner, the glow at the top-end one.
              const PositionedDirectional(
                end: -240,
                bottom: -176,
                child: _SplashRing(),
              ),
              const PositionedDirectional(
                start: -190,
                top: -170,
                child: _SplashGlow(),
              ),
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    const Spacer(),
                    // Reversed lockup (white + orange) on the navy splash —
                    // the Figma "01 Splash". Not tinted: the cart must stay
                    // orange. 233.8 × 88 is the frame's size for it.
                    Image.asset(
                      AppImages.logoReversed,
                      width: 233.803,
                      height: 88,
                      errorBuilder: (_, __, ___) =>
                          const BrandLockup(color: Colors.white, fontSize: 44),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        l10n.launchTagline,
                        textAlign: TextAlign.center,
                        style: t.body.copyWith(color: AppColors.onInverseMuted),
                      ),
                    ),
                    const Spacer(),
                    // Foot: the progress bar, the caption's space, then 44 to
                    // the screen's edge (the frame's home-indicator zone).
                    const _SplashProgress(),
                    SizedBox(height: 14 + captionLine + 44),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Figma "ring": a 460 px circle, 40 px of 6 % white as its outline.
class _SplashRing extends StatelessWidget {
  const _SplashRing();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 40,
          ),
        ),
        child: const SizedBox.square(dimension: 460),
      ),
    );
  }
}

/// Figma "glow": a 520 px orange radial gradient, 28 % at the centre to
/// nothing at the edge.
class _SplashGlow extends StatelessWidget {
  const _SplashGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              AppColors.accent.withValues(alpha: 0.28),
              AppColors.accent.withValues(alpha: 0),
            ],
          ),
        ),
        child: const SizedBox.square(dimension: 520),
      ),
    );
  }
}

/// Figma "progress": a 120 × 4 track of 16 % white with the orange fill growing
/// from the start edge. It counts the splash's hold, so the bar is full as the
/// splash leaves; the frame shows it 52/120 of the way.
class _SplashProgress extends StatelessWidget {
  const _SplashProgress();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 120,
        height: 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(2),
          ),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: LaunchSplashScreen.hold,
            builder: (context, value, _) => Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: value,
                heightFactor: 1,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
