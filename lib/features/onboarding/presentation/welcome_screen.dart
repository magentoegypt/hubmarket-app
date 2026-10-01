import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/assets/app_images.dart';
import '../../../core/store/store_controller.dart';
import '../../../core/widgets/brand_lockup.dart';
import '../../../core/widgets/hub_button.dart';
import '../../../core/widgets/network_image.dart';
import '../../home/domain/hm_home.dart';
import '../../home/presentation/hm_home_providers.dart';
import '../../home/presentation/home_providers.dart';
import '../../home/presentation/widgets/hm_hero.dart';
import '../../../l10n/l10n.dart';

/// Welcome (Figma "02 Welcome"): a visual panel, the pager, the headline +
/// subtitle, the English | عربي switch, then Create account / Sign in /
/// Continue as guest. Chrome-free. Guests can browse; sign-in is only forced at
/// checkout.
///
/// The panel is the storefront's Hero Banner slides (the guest Home's
/// HERO_BANNERS, Hub Market App API) — each photo with its kicker, the pager
/// below. Without them (Build 1, or no slide with a photo) it is the reversed
/// logo on navy, with the storefront's delivery promise (`hm_delivery_promise`)
/// as its pill when the store has one: no marketing photo or claim is bundled
/// with the app.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  /// The frame's gutter, and the rhythm of the text block (pager, headline,
  /// subtitle and the language switch sit 14 apart).
  static const double _gutter = 20;
  static const double _rhythm = 14;

  /// The frame stacks the actions right under the language switch (its content
  /// is taller than the screen, so the spacer between them is down to 1 px).
  static const double _beforeActions = 1;

  /// What the frame leaves under the last button. The frame's own padding is
  /// the 34 px home-indicator zone, which the buttons overlap by 18; a system
  /// bar taller than that zone (an Android navigation bar) pushes them up.
  static const double _afterActions = 16;
  static const double _homeIndicator = 34;

  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final activeLocale = ref.watch(
      storeControllerProvider.select((s) => s.activeLocale),
    );
    final slides =
        ref.watch(welcomeSlidesProvider).valueOrNull ?? const <HmHeroBanner>[];
    // The logo panel's pill is the storefront's delivery promise (CMS block
    // `hm_delivery_promise`, warmed by the splash); none without one.
    final promise = slides.isEmpty ? ref.watch(homePromiseProvider) : '';
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    // An iPhone keeps the frame's spacing (its home indicator is a thin pill);
    // a persistent Android navigation bar (47 dp with three buttons) covers
    // what is under it, so the last button clears all of it.
    final bottom = math.max(
      _afterActions + math.max(0.0, inset - _homeIndicator),
      Theme.of(context).platform == TargetPlatform.android ? inset : 0.0,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Dark status-bar icons on the white strip above the panel.
      value: const SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: slides.isEmpty
                    ? _BrandPanel(kicker: promise.isEmpty ? null : promise)
                    : _SlidesPanel(
                        slides: slides,
                        onPageChanged: (page) => setState(() => _page = page),
                      ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  _gutter,
                  22,
                  _gutter,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (slides.length > 1) ...[
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: HmPagerDots(
                          count: slides.length,
                          index: _page.clamp(0, slides.length - 1),
                          activeColor: AppColors.accent,
                          dotSize: 8,
                          activeWidth: 22,
                        ),
                      ),
                      const SizedBox(height: _rhythm),
                    ],
                    Text(
                      l10n.welcomeHeadline,
                      style: t.display.copyWith(color: AppColors.inkHeading),
                    ),
                    const SizedBox(height: _rhythm),
                    Text(
                      l10n.welcomeSubtitle,
                      style: t.body.copyWith(color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: _rhythm),
                    _LanguageSwitch(
                      activeLocale: activeLocale,
                      onChanged: (locale) => ref
                          .read(storeControllerProvider.notifier)
                          .switchLocale(locale),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: _beforeActions),
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  _gutter,
                  0,
                  _gutter,
                  bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HubButton(
                      label: l10n.welcomeCreateAccount,
                      onPressed: () => context.push(AppRoutes.signUp),
                    ),
                    const SizedBox(height: 10),
                    HubButton(
                      label: l10n.welcomeSignIn,
                      style: HubButtonStyle.outline,
                      onPressed: () => context.push(AppRoutes.signIn),
                    ),
                    const SizedBox(height: 10),
                    HubButton(
                      label: l10n.welcomeContinueGuest,
                      style: HubButtonStyle.ghost,
                      onPressed: () => context.go(AppRoutes.home),
                    ),
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
    return PageView.builder(
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
                end: 20,
                bottom: 20,
                child: Align(
                  alignment: AlignmentDirectional.bottomStart,
                  child: _KickerPill(
                    label: slide.kicker!,
                    color: slide.accent ?? AppColors.successStrong,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Figma "pill" on the panel: Micro text in white on a success-green capsule,
/// 10 px by 5 around the label. Admin text of any length: it hugs the label, up
/// to two lines.
class _KickerPill extends StatelessWidget {
  const _KickerPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.of(context).micro.copyWith(color: Colors.white),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({this.kicker});

  /// The admin's delivery promise; no pill without one.
  final String? kicker;

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
      child: Stack(
        children: [
          PositionedDirectional(top: -60, start: -110, child: _ring(300)),
          PositionedDirectional(bottom: -90, end: -80, child: _ring(240)),
          Center(
            child: Image.asset(
              AppImages.logoReversed,
              width: 220,
              errorBuilder: (_, __, ___) =>
                  const BrandLockup(color: Colors.white, fontSize: 40),
            ),
          ),
          if (kicker != null)
            PositionedDirectional(
              start: 20,
              end: 20,
              bottom: 20,
              child: Align(
                alignment: AlignmentDirectional.bottomStart,
                child: _KickerPill(
                  label: kicker!,
                  color: AppColors.successStrong,
                ),
              ),
            ),
        ],
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

/// The Figma's full-width English | عربي switch: a pale track with the active
/// language on a raised white segment. Labels are the languages' own names, and
/// stay in this order in Arabic too (Figma AR-02 keeps English on the left).
class _LanguageSwitch extends StatelessWidget {
  const _LanguageSwitch({required this.activeLocale, required this.onChanged});

  final String activeLocale;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    Widget segment(String label, String locale) {
      final selected = activeLocale == locale;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: selected ? null : () => onChanged(locale),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                boxShadow: selected
                    ? const [
                        BoxShadow(
                          color: Color(0x1A0F2144),
                          offset: Offset(0, 6),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                label,
                style: t.bodyStrong.copyWith(
                  color: selected ? AppColors.inkHeading : AppColors.inkMuted,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            segment('English', 'en'),
            const SizedBox(width: 4),
            segment('عربي', 'ar'),
          ],
        ),
      ),
    );
  }
}
