import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/assets/app_images.dart';
import '../../../core/store/store_controller.dart';
import '../../../core/widgets/brand_lockup.dart';
import '../../../core/widgets/network_image.dart';
import '../../home/domain/hm_home.dart';
import '../../home/presentation/hm_home_providers.dart';
import '../../home/presentation/widgets/hm_hero.dart';
import '../../../l10n/l10n.dart';

/// Welcome (Figma "02 Welcome"): a visual panel, the headline + subtitle, the
/// English | عربي switch, then Create account / Sign in / Continue as guest.
/// Chrome-free. Guests can browse; sign-in is only forced at checkout.
///
/// The panel is the storefront's Hero Banner slides (the guest Home's
/// HERO_BANNERS, Hub Market App API) — each photo with its kicker, the pager
/// below. Without them (Build 1, or no slide with a photo) it is the reversed
/// logo on navy with the "same-day delivery" badge: no marketing photo is
/// bundled with the app.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final activeLocale = ref.watch(
      storeControllerProvider.select((s) => s.activeLocale),
    );
    final isEn = activeLocale != 'ar';
    final slides =
        ref.watch(welcomeSlidesProvider).valueOrNull ?? const <HmHeroBanner>[];

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            child: slides.isEmpty
                ? _BrandPanel(kicker: l10n.welcomeKicker)
                : _SlidesPanel(
                    slides: slides,
                    onPageChanged: (page) => setState(() => _page = page),
                  ),
          ),
          if (slides.length > 1)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 22, 20, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: HmPagerDots(
                  count: slides.length,
                  index: _page.clamp(0, slides.length - 1),
                  activeColor: AppColors.accent,
                  dotSize: 8,
                  activeWidth: 22,
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                slides.length > 1 ? 14 : 20,
                24,
                8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.welcomeHeadline,
                    style: TextStyle(
                      // Playfair Display has no Arabic glyphs — AR keeps the
                      // Arabic face.
                      fontFamily: isEn ? AppTheme.displayFont : null,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkHeading,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.welcomeSubtitle,
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _LanguageSegment(
                    activeLocale: activeLocale,
                    onChanged: (locale) => ref
                        .read(storeControllerProvider.notifier)
                        .switchLocale(locale),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => context.push(AppRoutes.signUp),
                    child: Text(l10n.welcomeCreateAccount),
                  ),
                  const SizedBox(height: 10),
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
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => context.go(AppRoutes.home),
                    child: Text(
                      l10n.welcomeContinueGuest,
                      style: const TextStyle(
                        color: AppColors.accentStrong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Hero Banner slides as the Welcome photo carousel: each image with its
/// kicker pill; advances every few seconds.
class _SlidesPanel extends StatefulWidget {
  const _SlidesPanel({required this.slides, required this.onPageChanged});

  final List<HmHeroBanner> slides;
  final ValueChanged<int> onPageChanged;

  @override
  State<_SlidesPanel> createState() => _SlidesPanelState();
}

class _SlidesPanelState extends State<_SlidesPanel> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (widget.slides.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateToPage(
        (_page + 1) % widget.slides.length,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: PageView.builder(
        controller: _controller,
        itemCount: widget.slides.length,
        onPageChanged: (page) {
          _page = page;
          widget.onPageChanged(page);
          _schedule();
        },
        itemBuilder: (context, i) {
          final slide = widget.slides[i];
          return Stack(
            fit: StackFit.expand,
            children: [
              HubImage(
                url: slide.imageUrl,
                fit: BoxFit.cover,
                shimmer: true,
                semanticLabel: slide.title,
              ),
              if (slide.kicker != null)
                PositionedDirectional(
                  start: 20,
                  bottom: 20,
                  child: HmPill(
                    label: slide.kicker!,
                    color: slide.accent ?? AppColors.successStrong,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.kicker});

  final String kicker;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.brandPrimary, Color(0xFF1E3A6E)],
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned(top: -60, left: -110, child: _ring(300)),
            Positioned(bottom: -90, right: -80, child: _ring(240)),
            Center(
              child: Image.asset(
                AppImages.logoReversed,
                width: 220,
                errorBuilder: (_, __, ___) =>
                    const BrandLockup(color: Colors.white, fontSize: 40),
              ),
            ),
            PositionedDirectional(
              start: 20,
              bottom: 18,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF15803D),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  kicker,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ring(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white10, width: 1.5),
    ),
  );
}

/// The Figma's full-width English | عربي switch: a grey track with the active
/// language on a raised white segment. Labels are the languages' own names.
class _LanguageSegment extends StatelessWidget {
  const _LanguageSegment({required this.activeLocale, required this.onChanged});

  final String activeLocale;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, String locale) {
      final selected = activeLocale == locale;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: GestureDetector(
            onTap: selected ? null : () => onChanged(locale),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                boxShadow: selected
                    ? const [BoxShadow(color: Color(0x1A0F2144), blurRadius: 6, offset: Offset(0, 1))]
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.inkHeading : AppColors.inkMuted,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [seg('English', 'en'), seg('عربي', 'ar')]),
    );
  }
}
