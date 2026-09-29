import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/hm_link_navigation.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/network_image.dart';
import '../../domain/hm_home.dart';

/// The Hero Banner carousel (Figma 07 "Hero carousel"): a 220 pt slide per
/// banner — the admin's image under its tone scrim, kicker pill, headline,
/// supporting line and CTA in the accent colour — with the pager below.
/// Advances every [interval]; a swipe restarts the wait.
class HmHeroCarousel extends ConsumerStatefulWidget {
  const HmHeroCarousel({
    super.key,
    required this.slides,
    this.interval = const Duration(seconds: 6),
  });

  final List<HmHeroBanner> slides;
  final Duration interval;

  @override
  ConsumerState<HmHeroCarousel> createState() => _HmHeroCarouselState();
}

class _HmHeroCarouselState extends ConsumerState<HmHeroCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(HmHeroCarousel old) {
    super.didUpdateWidget(old);
    if (old.slides.length != widget.slides.length) {
      _page = 0;
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (widget.slides.length < 2) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_page + 1) % widget.slides.length;
      _controller.animateToPage(
        next,
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
    final slides = widget.slides;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 220,
          child: NotificationListener<ScrollStartNotification>(
            onNotification: (n) {
              if (n.dragDetails != null) _schedule();
              return false;
            },
            child: PageView.builder(
              controller: _controller,
              itemCount: slides.length,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: HmHeroSlide(
                  banner: slides[i],
                  onTap: () => openHmLink(
                    context,
                    ref,
                    slides[i].link,
                    title: slides[i].title,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (slides.length > 1) ...[
          const SizedBox(height: 10),
          HmPagerDots(count: slides.length, index: _page),
        ],
      ],
    );
  }
}

/// One hero slide (Figma 07 "hero-slide/…").
class HmHeroSlide extends StatelessWidget {
  const HmHeroSlide({super.key, required this.banner, this.onTap});

  final HmHeroBanner banner;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final tone = banner.tone ?? AppColors.brandPrimary;
    final accent = banner.accent ?? AppColors.accentStrong;
    return Semantics(
      button: onTap != null,
      label: banner.title,
      child: Material(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        color: tone,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if ((banner.imageUrl ?? '').isNotEmpty)
                HubImage(url: banner.imageUrl, fit: BoxFit.cover, shimmer: true),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: [
                      tone.withValues(alpha: 0.9),
                      tone.withValues(alpha: 0.15),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (banner.kicker != null) ...[
                      HmPill(label: banner.kicker!, color: accent),
                      const SizedBox(height: 8),
                    ],
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 250),
                      child: Text(
                        banner.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.heading1.copyWith(color: Colors.white),
                      ),
                    ),
                    if (banner.subtitle != null) ...[
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Text(
                          banner.subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.caption.copyWith(
                            color: const Color(0xFFCBD3E2),
                          ),
                        ),
                      ),
                    ],
                    if (banner.ctaLabel != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              banner.ctaLabel!,
                              style: t.captionStrong.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.arrow_forward,
                              size: 14,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ],
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

/// The side tiles of the Hero Banner band (Figma 07 "Promo tiles"): 168×100
/// cards — an image under its tone scrim, or a solid accent card with a
/// kicker line.
class HmPromoTiles extends ConsumerWidget {
  const HmPromoTiles({super.key, required this.tiles});

  final List<HmHeroBanner> tiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) => HmPromoTile(
          banner: tiles[i],
          onTap: () =>
              openHmLink(context, ref, tiles[i].link, title: tiles[i].title),
        ),
      ),
    );
  }
}

class HmPromoTile extends StatelessWidget {
  const HmPromoTile({super.key, required this.banner, this.onTap});

  final HmHeroBanner banner;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final hasImage = (banner.imageUrl ?? '').isNotEmpty;
    final tone = banner.tone ?? AppColors.brandPrimary;
    final solid = banner.accent ?? banner.tone ?? AppColors.accent;
    return SizedBox(
      width: 168,
      child: Semantics(
        button: onTap != null,
        label: banner.title,
        child: Material(
          color: hasImage ? tone : solid,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasImage) ...[
                  HubImage(url: banner.imageUrl, fit: BoxFit.cover),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: AlignmentDirectional.centerStart,
                        end: AlignmentDirectional.centerEnd,
                        colors: [
                          tone.withValues(alpha: 0.95),
                          tone.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (banner.kicker != null)
                        Text(
                          banner.kicker!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.micro.copyWith(color: Colors.white),
                        ),
                      Text(
                        banner.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.title.copyWith(color: Colors.white),
                      ),
                      if (banner.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          banner.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.caption.copyWith(
                            color: hasImage
                                ? const Color(0xFFCBD3E2)
                                : Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded label pill (the hero kicker): white Micro text on [color].
class HmPill extends StatelessWidget {
  const HmPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.of(context).micro.copyWith(color: Colors.white),
    ),
  );
}

/// The carousel pager: a 20×6 pill for the current page, 6 pt dots for the
/// rest.
class HmPagerDots extends StatelessWidget {
  const HmPagerDots({
    super.key,
    required this.count,
    required this.index,
    this.activeColor = AppColors.brandPrimary,
  });

  final int count;
  final int index;
  final Color activeColor;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < count; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: i == index ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: i == index ? activeColor : AppColors.borderStrong,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    ],
  );
}
