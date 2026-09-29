import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/assets/app_images.dart';
import '../../../core/config/app_config.dart';
import '../../../core/storage/secure_token_store.dart';
import '../../../core/util/image_prefetch.dart';
import '../../../core/widgets/network_image.dart';
import '../../catalog/data/hero_slides_provider.dart';
import '../../catalog/data/home_config_provider.dart';
import '../../catalog/domain/category.dart';
import '../../catalog/domain/home_config.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../../../core/widgets/brand_lockup.dart';
import '../../../l10n/l10n.dart';
import 'intro_video_screen.dart';

/// Launch splash: full Hub Market logo (tinted white on burgundy) + tagline. While
/// it shows, we read the saved session: a returning signed-in customer skips
/// Welcome/Sign In and lands on Home; everyone else goes to Welcome. Chrome-free.
///
/// The intro video (CL042-DEV41) takes the place of that static branding on
/// **every cold start** — the client's explicit instruction (CL042-QA01,
/// 2026-09-27), reversing the once-only behaviour shipped first. It ends on the
/// same logo the splash shows, so playing both would show the logo twice.
/// Everything else is unchanged: the same warm-up runs behind it and the same
/// routing decision follows.
///
/// Cold start only. This screen is the router's entry point, so returning from
/// the background does not rebuild it and the intro does not replay on resume —
/// which would be genuinely disruptive and is not what was asked for.
class LaunchSplashScreen extends ConsumerStatefulWidget {
  const LaunchSplashScreen({super.key});

  @override
  ConsumerState<LaunchSplashScreen> createState() => _LaunchSplashScreenState();
}

/// Backstop for the intro gate. Generous enough never to clip the 13.5s video
/// on a slow device, short enough that a wedged decoder can't strand a user on
/// a black screen — startup must not be able to hang behind a promo. It now
/// guards every launch, not just the first.
const Duration _introMaxHold = Duration(seconds: 25);

class _LaunchSplashScreenState extends ConsumerState<LaunchSplashScreen> {
  /// Whether this launch shows the intro instead of the static branding.
  /// Decided once, before first paint, so the body never swaps mid-launch.
  late final bool _playIntro;

  /// Completes when the intro ends, is skipped, or fails to start.
  final _introGate = Completer<void>();

  @override
  void initState() {
    super.initState();
    _playIntro = AppConfig.introVideoEnabled;
    _warmHome();
    _routeOnboarding();
  }

  /// Releases the gate. Idempotent: end-of-video, Skip and an init failure can
  /// all arrive, and only the first matters.
  void _finishIntro() {
    if (_introGate.isCompleted) return;
    _introGate.complete();
  }

  /// The splash deliberately holds for 2.6s. Spend it fetching what Home needs
  /// first, so it paints on arrival instead of starting from nothing.
  ///
  /// Strictly fire-and-forget: nothing here is awaited on the routing path, and
  /// every failure is swallowed — a cold or offline start must still leave the
  /// splash after 2.6s. These three providers keepAlive(), so the results
  /// survive until Home reads them.
  void _warmHome() {
    unawaited(
      Future(() async {
        try {
          // The product rails await the category tree before they can even
          // issue their own query, so this removes a serial round-trip.
          unawaited(ref.read(categoryTreeProvider.future).catchError((_) {
            return const <Category>[];
          }));
          unawaited(ref.read(homeConfigProvider.future).catchError((_) {
            return HomeConfig.empty;
          }));
          final slides = await ref.read(heroSlidesProvider.future);
          if (!mounted || slides.isEmpty) return;
          // Only the first slide — the one Home paints immediately.
          await prefetchImages(
            context,
            [slides.first.imageUrl],
            decodeWidth: HubImage.decodePixels(
              context,
              MediaQuery.sizeOf(context).width,
            ),
            limit: 1,
          );
        } catch (_) {
          // A warm-up failure is not a startup failure.
        }
      }),
    );
  }

  Future<void> _routeOnboarding() async {
    // Hold the splash long enough for the branding to register (QA: it flashed
    // by in under a second) while reading the persisted token. On an intro
    // launch the hold is the video instead — bounded, so a stalled decoder
    // still lets the app through.
    final hold = _playIntro
        ? _introGate.future.timeout(_introMaxHold, onTimeout: () {})
        : Future<void>.delayed(const Duration(milliseconds: 2600));
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
    if (_playIntro) {
      return IntroVideoView(
        onFinished: _finishIntro,
        // Couldn't decode: drop straight through to routing rather than hold
        // a black frame. This matters more now the intro runs on every launch
        // — a decode failure would otherwise block every single start, not
        // just the first.
        onFailed: _finishIntro,
      );
    }
    return Scaffold(
      backgroundColor: AppColors.brandPrimary,
      body: Stack(
        children: [
          // Faint circular outlines behind the logo (Figma 52:2 background
          // ellipses) — partly off-screen at three corners.
          Positioned(top: -80, left: -120, child: _ring(360)),
          Positioned(top: 120, right: -30, child: _ring(120)),
          Positioned(bottom: -60, right: -120, child: _ring(260)),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Reversed lockup (white + orange) on the navy splash — the
                // Figma "01 Splash". Not tinted: the cart must stay orange.
                Image.asset(
                  AppImages.logoReversed,
                  width: 232,
                  errorBuilder: (_, __, ___) =>
                      const BrandLockup(color: Colors.white, fontSize: 44),
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.launchTagline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
          // Loading dots pinned near the bottom of the screen (shared PNG
          // position) — replaces the centered round spinner.
          const Align(
            alignment: Alignment(0, 0.72),
            child: _DotsLoader(),
          ),
          Align(
            alignment: const Alignment(0, 0.84),
            child: Text(
              l10n.launchFooter,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// A faint circular outline used as a soft background decoration on the splash.
  Widget _ring(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white10, width: 1.5),
    ),
  );
}

/// Three pulsing dots used as the splash loading indicator (shared PNG) — the
/// highlight sweeps left→right across the dots. White on the burgundy splash.
class _DotsLoader extends StatefulWidget {
  const _DotsLoader();

  @override
  State<_DotsLoader> createState() => _DotsLoaderState();
}

class _DotsLoaderState extends State<_DotsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsetsDirectional.only(start: i == 0 ? 0 : 9),
              child: _dot(i),
            ),
        ],
      ),
    );
  }

  Widget _dot(int index) {
    // Each dot leads the next by a third of the cycle so the highlight travels
    // across them. `%` on a positive divisor stays non-negative in Dart.
    final phase = (_controller.value - index / 3) % 1.0;
    final t = (1 - (phase * 2 - 1).abs()).clamp(0.0, 1.0); // triangle 0→1→0
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.3 + 0.7 * t),
      ),
    );
  }
}
