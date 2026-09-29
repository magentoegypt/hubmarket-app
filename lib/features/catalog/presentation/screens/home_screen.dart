import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/marketing_footer.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/assets/app_images.dart';
import '../../../../core/util/image_prefetch.dart';
import '../../../../core/util/store_time.dart';
import '../../../../core/widgets/brand_logo.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/web_view_screen.dart';
import '../../../../l10n/l10n.dart';
import '../../data/blog_posts_provider.dart';
import '../../data/brands_provider.dart';
import '../../data/hero_slides_provider.dart';
import '../../data/home_config_provider.dart';
import '../../data/home_sections_provider.dart';
import '../../data/special_offer_provider.dart';
import '../../domain/blog_post.dart';
import '../../domain/brand.dart';
import '../../domain/hero_slide.dart';
import '../../domain/home_config.dart';
import '../../domain/product.dart';
import '../../domain/promo_split_banner.dart';
import '../catalog_providers.dart';
import '../product_navigation.dart';
import '../storefront_links.dart';
import '../widgets/product_card.dart';
import '../widgets/product_skeletons.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the admin-configured announcement is shown — no hardcoded fallback
    // (QA: the default "free shipping" line isn't on the site). Empty → the
    // strip is omitted entirely (the app bar shrinks to just the header).
    final announcement = ref
        .watch(announcementMessageProvider)
        .maybeWhen(data: (m) => m.trim(), orElse: () => '');

    return HubScaffold(
      currentTab: AppTab.home,
      // The home body already has a search bar — no app-bar search icon.
      showSearch: false,
      // Figma: the burgundy announcement strip sits above the HUB MARKET header.
      appBar: _HomeAppBar(announcement: announcement),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(shopByCategoriesProvider);
          ref.invalidate(newArrivalsProvider);
          ref.invalidate(bestsellersProvider);
          // Keep the indicator up until the real reload finishes; a failed feed
          // just collapses its section, so nothing is surfaced here.
          try {
            await ref.read(shopByCategoriesProvider.future);
          } catch (_) {
            /* ignore: the section hides itself */
          }
        },
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _SearchField(onTap: () => context.push(AppRoutes.search)),
            const _Hero(),
            const _ShopByCategorySection(),
            // New order mirrors live hub-market.magento2.click (see docs/FIGMA_DESIGN.md,
            // 2026-07-13). Each new section is backend-driven and collapses to
            // nothing when its source is absent — Explore Brands has moved down
            // to sit after the reviews rail.
            const _LimitedTimeOffer(),
            const _DealsOfTheDaySection(),
            const _NewArrivalsSection(),
            const _EditorialBanners(),
            const _SpecialOffer(),
            const _ExclusiveOffers(),
            const _BestsellersSection(),
            const _WhyShoppersTrust(),
            const _ExploreBrands(),
            const _HubJournal(),
            const _TrustBadges(),
            const MarketingFooter(),
          ],
        ),
      ),
    );
  }
}

/// Home app bar (Figma): the burgundy announcement strip on top, then the
/// centered HUB MARKET lockup with a hamburger that opens the drawer.
class _HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _HomeAppBar({required this.announcement});

  /// The resolved announcement message; empty → the strip is omitted.
  final String announcement;

  static const double _announcementHeight = 30;
  static const double _headerHeight = 56;

  @override
  Size get preferredSize {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final top = view.viewPadding.top / view.devicePixelRatio;
    final strip = announcement.isEmpty ? 0.0 : _announcementHeight;
    return Size.fromHeight(top + strip + _headerHeight);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (announcement.isNotEmpty) _AnnouncementBar(message: announcement),
            SizedBox(
              height: _headerHeight,
              // Hamburger then logo, both against the leading edge — the
              // storefront header (CL042-DEV16). A Row rather than a centred
              // Stack, so the pair reads as one unit and mirrors together in
              // Arabic: hamburger on the right, logo just inside it.
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu, color: AppColors.brandPrimary),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                  const BrandLogo(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thin burgundy top strip (Figma) — single line. The [message] is the
/// admin-configured announcement (magentoegypt_beauty/announcement/message);
/// the caller omits this strip entirely when there's no configured message.
class _AnnouncementBar extends StatelessWidget {
  const _AnnouncementBar({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: _HomeAppBar._announcementHeight,
      color: AppColors.brandPrimary,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      // One line at a readable size — centered when it fits, auto-scrolling
      // (marquee) when it doesn't, instead of shrinking to an unreadable size.
      child: _AnnouncementText(message: message),
    );
  }
}

/// The announcement message at a fixed readable size. Centers short messages;
/// long ones scroll horizontally on a gentle loop so nothing is clipped or
/// shrunk (QA: the old FittedBox scaled the text down until it was too small).
class _AnnouncementText extends StatefulWidget {
  const _AnnouncementText({required this.message});
  final String message;

  @override
  State<_AnnouncementText> createState() => _AnnouncementTextState();
}

class _AnnouncementTextState extends State<_AnnouncementText> {
  static const TextStyle _style = TextStyle(
    color: Colors.white,
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
  );

  final ScrollController _scroll = ScrollController();
  bool _looping = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeScroll());
  }

  @override
  void didUpdateWidget(covariant _AnnouncementText old) {
    super.didUpdateWidget(old);
    if (old.message != widget.message) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeScroll());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _maybeScroll() async {
    if (_looping) return;
    _looping = true;
    try {
      while (mounted && _scroll.hasClients) {
        final max = _scroll.position.maxScrollExtent;
        if (max <= 0) break; // Message fits — nothing to scroll.
        await _scroll.animateTo(
          max,
          duration: Duration(milliseconds: 2500 + (max * 22).round()),
          curve: Curves.linear,
        );
        if (!mounted || !_scroll.hasClients) break;
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (!mounted || !_scroll.hasClients) break;
        await _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
        );
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    } finally {
      _looping = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: widget.message, style: _style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        final text = Text(widget.message, maxLines: 1, style: _style);
        if (tp.width <= constraints.maxWidth) {
          return Center(child: text);
        }
        return SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: text,
        );
      },
    );
  }
}

/// Tappable search field (routes to the search screen) — Figma's full-width
/// search bar below the header.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 44,
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsetsDirectional.only(start: 16, end: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: AppColors.inkMuted, size: 22),
              const SizedBox(width: 12),
              Text(
                l10n.searchHint,
                style: const TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fixed hero height (Figma node 3:2 is 390×250).
const double _kHeroHeight = 250;

/// Warm-beige hero background (Figma `#f6efe8`).
const Color _kHeroBg = Color(0xFFF6EFE8);

/// The full-width hero layout (Figma node 3:2): beige background, text on the
/// start side, a circular image bleeding off the end side. Shared by the static
/// fallback and each carousel slide.
class _HeroBannerView extends StatelessWidget {
  const _HeroBannerView({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.onCta,
    required this.imageProvider,
    this.hasTarget = true,
    this.videoUrl,
    this.isActive = true,
    this.onVideoCompleted,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final VoidCallback onCta;
  final ImageProvider imageProvider;

  /// Whether [onCta] leads anywhere. False for a slide the merchant published
  /// with no CTA URL — the card then renders inert instead of eating taps.
  final bool hasTarget;

  /// When set, the video fills the whole banner (poster = [imageProvider])
  /// instead of showing a static play badge in the circle.
  final String? videoUrl;

  /// True when this slide is the carousel's current slide (drives playback).
  final bool isActive;

  /// Called when the banner's video finishes (lets the carousel advance).
  final VoidCallback? onVideoCompleted;

  @override
  Widget build(BuildContext context) {
    final hasVideo = videoUrl != null && videoUrl!.isNotEmpty;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final banner = Container(
      color: _kHeroBg,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Background media fills the whole banner (BoxFit.cover), matching
          // the website: a video when the slide has one, otherwise the image.
          if (hasVideo)
            Positioned.fill(
              child: _HeroVideo(
                url: videoUrl!,
                poster: imageProvider,
                isActive: isActive,
                onCompleted: onVideoCompleted,
              ),
            )
          else
            Positioned.fill(
              child: Image(
                image: imageProvider,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(color: _kHeroBg),
              ),
            ),
          // Beige→transparent scrim on the start side so the overlaid text
          // stays readable over the media (image or video).
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
                  end: rtl ? Alignment.centerLeft : Alignment.centerRight,
                  colors: [
                    _kHeroBg,
                    _kHeroBg.withValues(alpha: 0.55),
                    _kHeroBg.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.5, 0.85],
                ),
              ),
            ),
          ),
          // Text block on the start side.
          PositionedDirectional(
            start: 48,
            end: 108,
            top: 0,
            bottom: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (eyebrow.isNotEmpty) ...[
                    Text(
                      eyebrow.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.brandPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        letterSpacing: 1.54,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                      color: AppColors.inkHeading,
                      height: 1.06,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (ctaLabel.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: onCta,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(ctaLabel),
                          const SizedBox(width: 8),
                          // Auto-mirrors under RTL (matchTextDirection) so it
                          // points forward in both EN and AR.
                          const Icon(Icons.arrow_forward, size: 16),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
    // The whole banner is the tap target, not just the CTA button: a slide
    // published without a `cta_label` renders no button at all and so was
    // completely dead to touch (CL042-DEV19). The editorial and exclusive-offer
    // banners are already card-wide. A GestureDetector rather than an InkWell
    // so the CTA button beneath keeps its own press feedback and wins taps on
    // itself; the carousel's prev/next arrows sit above this in _HeroCarousel's
    // Stack, and PageView drag still beats the tap recogniser.
    if (!hasTarget) return banner;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onCta,
      child: banner,
    );
  }
}

/// White circular prev/next arrow overlaid on the hero (Figma).
class _NavArrow extends StatelessWidget {
  const _NavArrow({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: const CircleBorder(side: BorderSide(color: Color(0xFFE5E7EB))),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Icon(icon, size: 18, color: AppColors.inkHeading),
      ),
    ),
  );
}

/// Static hero fallback — full-width [_HeroBannerView] with the bundled flatlay,
/// shown while [heroSlides] loads or when none are configured.
class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: _kHeroHeight,
      child: _HeroBannerView(
        eyebrow: l10n.homeHeroEyebrow,
        title: l10n.homeHeroTitle,
        subtitle: l10n.homeHeroSubtitle,
        ctaLabel: l10n.homeHeroCta,
        onCta: () => context.go(AppRoutes.categories),
        imageProvider: const AssetImage(AppImages.banner),
      ),
    );
  }
}

/// Home hero: the admin-managed [heroSlides] carousel, falling back to the
/// static [_HeroBanner] while loading or when no slides are configured.
class _Hero extends ConsumerWidget {
  const _Hero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(heroSlidesProvider)
        .maybeWhen(
          data: (slides) => slides.isEmpty
              ? const _HeroBanner()
              : _HeroCarousel(slides: slides),
          orElse: () => const _HeroBanner(),
        );
  }
}

/// Swipeable, auto-advancing hero carousel with a dots indicator.
class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel({required this.slides});
  final List<HeroSlide> slides;

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  final PageController _controller = PageController();
  Timer? _timer;
  int _index = 0;

  /// Fixed dwell for an image slide.
  static const Duration _imageDwell = Duration(seconds: 5);

  /// Safety-net dwell for a video slide — used only if the video never loads or
  /// finishes; normally the advance is driven by the video completing (see
  /// [_onVideoCompleted]), so the dwell follows the video's own length.
  static const Duration _videoFallback = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _scheduleDwell();
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmNeighbours());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Pre-warm the slides on either side of the current one — the carousel
  /// auto-advances every 5s, so the next image is always about to be needed.
  /// Bounded to those two; the rest load when they come round.
  void _warmNeighbours() {
    if (!mounted) return;
    final n = widget.slides.length;
    if (n < 2) return;
    unawaited(
      prefetchImages(
        context,
        [
          widget.slides[(_index + 1) % n].imageUrl,
          widget.slides[(_index - 1 + n) % n].imageUrl,
        ],
        decodeWidth: HubImage.decodePixels(
          context,
          MediaQuery.sizeOf(context).width,
        ),
        limit: 2,
      ),
    );
  }

  /// (Re)arm the auto-advance for the current slide: a fixed timer for image
  /// slides; for a video slide we wait for playback to finish and only keep a
  /// long fallback timer. Single-slide heroes never auto-advance.
  void _scheduleDwell() {
    _timer?.cancel();
    if (widget.slides.length < 2) return;
    final current = _index;
    final dwell = widget.slides[current].hasVideo ? _videoFallback : _imageDwell;
    _timer = Timer(dwell, () => _advanceFrom(current));
  }

  void _advanceFrom(int i) {
    if (!mounted || i != _index) return;
    _go(1);
  }

  /// The current slide's video finished — advance now (dynamic timing that
  /// follows the video's own timeline).
  void _onVideoCompleted(int i) {
    if (!mounted || i != _index) return;
    _go(1);
  }

  void _go(int delta) {
    if (!_controller.hasClients) return;
    final n = widget.slides.length;
    _controller.animateToPage(
      (_index + delta + n) % n,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.slides.length > 1;
    return SizedBox(
      height: _kHeroHeight,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (i) {
              setState(() => _index = i);
              _scheduleDwell();
              _warmNeighbours();
            },
            itemCount: widget.slides.length,
            itemBuilder: (context, i) => _HeroSlideCard(
              slide: widget.slides[i],
              isActive: i == _index,
              onVideoCompleted:
                  widget.slides.length > 1 ? () => _onVideoCompleted(i) : null,
            ),
          ),
          if (multi) ...[
            PositionedDirectional(
              start: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _NavArrow(icon: Icons.chevron_left, onTap: () => _go(-1)),
              ),
            ),
            PositionedDirectional(
              end: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _NavArrow(icon: Icons.chevron_right, onTap: () => _go(1)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < widget.slides.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: i == _index ? 20 : 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i == _index
                              ? AppColors.brandPrimary
                              : const Color(0xFFE5E7EB),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One hero slide — blush card with eyebrow/title/description/CTA and a circular
/// image. A play badge marks a video slide; the poster image is shown until
/// inline video playback is wired.
class _HeroSlideCard extends ConsumerWidget {
  const _HeroSlideCard({
    required this.slide,
    this.isActive = true,
    this.onVideoCompleted,
  });
  final HeroSlide slide;

  /// True when this is the carousel's current slide (drives video playback).
  final bool isActive;

  /// Called when this slide's video finishes, so the carousel can advance.
  final VoidCallback? onVideoCompleted;

  /// Route the CTA inside the app wherever possible. An explicit
  /// `/catalog/category/view/id/N/` URL maps straight to the PLP; any other
  /// storefront URL (a friendly `.html` category or product) is resolved via
  /// Magento's `urlResolver` so a CATEGORY opens the PLP and a PRODUCT the PDP.
  /// Only genuinely external (non-store) links fall out to the browser.
  ///
  /// QA hit "Shop Now" landing on an empty page: the friendly category URLs
  /// (`fragrance/for-her.html`) were being mistaken for a product url_key and
  /// opened a non-existent PDP. Resolving the URL fixes the target.
  Future<void> _onCta(BuildContext context, WidgetRef ref) =>
      openStorefrontUrl(context, ref, slide.ctaUrl, title: slide.title);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hasTarget = slide.ctaUrl.isNotEmpty;
    final ImageProvider provider = slide.imageUrl.isNotEmpty
        ? HubImage.provider(
            slide.imageUrl,
            decodeWidth: HubImage.decodePixels(
              context,
              MediaQuery.sizeOf(context).width,
            ),
          )
        : const AssetImage(AppImages.banner);
    return _HeroBannerView(
      eyebrow: slide.eyebrow,
      title: slide.title,
      subtitle: slide.description,
      // A slide can carry a CTA URL with no label; fall back to the shared
      // "Shop Now" rather than rendering no button, as the editorial banners
      // already do.
      ctaLabel: slide.ctaLabel.isNotEmpty
          ? slide.ctaLabel
          : (hasTarget ? l10n.homeHeroCta : ''),
      onCta: () => _onCta(context, ref),
      imageProvider: provider,
      hasTarget: hasTarget,
      videoUrl: slide.hasVideo ? slide.videoUrl : null,
      isActive: isActive,
      onVideoCompleted: onVideoCompleted,
    );
  }
}

/// Inline, muted, full-bleed playback for a hero slide's video. Shows the
/// [poster] image (with a play badge) while it loads — and leaves it in place if
/// playback fails — then the video (cover-cropped) once it's ready. Plays only
/// while [isActive]; when [onCompleted] is set it plays once and reports the end
/// (so the carousel advances when the video finishes), otherwise it loops.
class _HeroVideo extends StatefulWidget {
  const _HeroVideo({
    required this.url,
    this.poster,
    this.isActive = true,
    this.onCompleted,
  });
  final String url;
  final ImageProvider? poster;

  /// Whether this is the carousel's current slide — the video plays only while
  /// active (and restarts when it becomes active).
  final bool isActive;

  /// Fired once when the video finishes. When null the video loops (e.g. a
  /// single-slide hero with nothing to advance to).
  final VoidCallback? onCompleted;

  @override
  State<_HeroVideo> createState() => _HeroVideoState();
}

class _HeroVideoState extends State<_HeroVideo> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _completed = false;

  /// Loop only when there's no completion handler (nothing to advance to).
  bool get _loop => widget.onCompleted == null;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(_loop);
      await controller.setVolume(0);
      controller.addListener(_onTick);
      if (widget.isActive) await controller.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      // Leave the poster + play badge in place on any playback error; the
      // carousel's fallback timer still advances so it never hangs here.
    }
  }

  /// Detects end-of-playback (non-looping) and reports it once, so the carousel
  /// advances exactly when the video finishes.
  void _onTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_loop || _completed || !widget.isActive) return;
    final v = c.value;
    final atEnd =
        v.duration > Duration.zero &&
        v.position >= v.duration - const Duration(milliseconds: 120);
    if (atEnd && !v.isPlaying) {
      _completed = true;
      widget.onCompleted?.call();
    }
  }

  @override
  void didUpdateWidget(covariant _HeroVideo old) {
    super.didUpdateWidget(old);
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (widget.isActive && !old.isActive) {
      // Became the current slide → restart so its timeline drives the dwell.
      _completed = false;
      c.seekTo(Duration.zero);
      c.play();
    } else if (!widget.isActive && old.isActive) {
      c.pause();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_ready || controller == null || !controller.value.isInitialized) {
      // Poster fills the banner while the video loads (or if it fails), with a
      // play badge to signal it's a video.
      return Stack(
        fit: StackFit.expand,
        children: [
          if (widget.poster != null)
            Image(
              image: widget.poster!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(color: _kHeroBg),
            ),
          const Center(
            child: Icon(
              Icons.play_circle_fill,
              color: Colors.white70,
              size: 48,
            ),
          ),
        ],
      );
    }
    final size = controller.value.size;
    // The clip has a 1–2px green seam baked into its very bottom edge (an
    // Android video-decoder artifact — QA flagged it; it doesn't match the web).
    // Crop a few source rows off the bottom with a ClipRect wrapped directly
    // around the VideoPlayer (Stack/overlay clips don't reliably catch the
    // Texture edge) before cover-fitting, so the seam never reaches the screen.
    // Lossless: the clip carries a beige frame around its content.
    const cropBottom = 8.0;
    final heightFactor = size.height <= cropBottom
        ? 1.0
        : (size.height - cropBottom) / size.height;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: heightFactor,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}

/// "Shop by Category" — the merchant-curated tile grid from the backend
/// `shopByCategories` feed, the same source the website renders. Gated on the
/// `categories` toggle and hidden when the feed is empty.
class _ShopByCategorySection extends ConsumerWidget {
  const _ShopByCategorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref
        .watch(homeConfigProvider)
        .maybeWhen(
          data: (c) => c.sectionEnabled('categories'),
          orElse: () => true,
        );
    if (!enabled) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(shopByCategoriesProvider)
        .when(
          loading: () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionHeader(title: l10n.homeShopByCategory),
              const _CategoryGridSkeleton(),
            ],
          ),
          error: (_, __) => const SizedBox.shrink(),
          data: (tiles) {
            if (tiles.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(title: l10n.homeShopByCategory),
                _CategoryGrid(tiles: tiles),
              ],
            );
          },
        );
  }
}

/// Circular category images in a horizontal carousel (site "Shop by Category").
class _CategoryGrid extends ConsumerWidget {
  const _CategoryGrid({required this.tiles});
  final List<ShopByCategoryTile> tiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final tile = tiles[index];
          return SizedBox(
            width: 80,
            child: _CategoryCircle(
              tile: tile,
              onTap: () => _openTile(context, ref, tile),
            ),
          );
        },
      ),
    );
  }

  /// The uid goes straight to the PLP; only if the backend omits it do we fall
  /// back to resolving the tile's storefront URL.
  void _openTile(BuildContext context, WidgetRef ref, ShopByCategoryTile tile) {
    if (tile.categoryUid.isNotEmpty) {
      context.push(AppRoutes.category(tile.categoryUid), extra: tile.label);
      return;
    }
    openStorefrontUrl(context, ref, tile.url, title: tile.label);
  }
}

class _CategoryCircle extends StatelessWidget {
  const _CategoryCircle({required this.tile, required this.onTap});
  final ShopByCategoryTile tile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = tile.imageUrl;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipOval(
            child: HubImage(
              url: image,
              width: 72,
              height: 72,
              placeholder: (_) => const _CategoryFallback(),
              error: (_) => const _CategoryFallback(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tile.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CategoryFallback extends StatelessWidget {
  const _CategoryFallback();

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surfaceTint,
    child: const Center(
      child: Icon(Icons.spa_outlined, color: AppColors.brandPrimary),
    ),
  );
}

/// Two-column product grid shared by Featured + New Arrivals + Deals. Passing
/// [dealBadge] adds a `DEAL` tag to each card (home "Deals of the Day").
class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.products, this.dealBadge = false});
  final List<Product> products;
  final bool dealBadge;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.58,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return ProductCard(
          product: product,
          dealBadge: dealBadge,
          onTap: () => openProduct(context, product),
        );
      },
    );
  }
}

/// "New Arrivals" — latest products from the new-arrivals category. Hides when
/// the catalogue returns nothing.
class _NewArrivalsSection extends ConsumerWidget {
  const _NewArrivalsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(newArrivalsProvider)
        .when(
          loading: () => _ProductSectionSkeleton(title: l10n.homeNewArrivals),
          error: (_, __) => const SizedBox.shrink(),
          data: (section) => _ProductSection(
            title: l10n.homeNewArrivals,
            section: section,
          ),
        );
  }
}

/// "Bestsellers" — backed by the real Bestsellers category; hidden if absent.
class _BestsellersSection extends ConsumerWidget {
  const _BestsellersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(bestsellersProvider)
        .when(
          loading: () => _ProductSectionSkeleton(title: l10n.homeBestsellers),
          error: (_, __) => const SizedBox.shrink(),
          data: (section) => _ProductSection(
            title: l10n.homeBestsellers,
            section: section,
          ),
        );
  }
}

class _ProductSection extends StatelessWidget {
  const _ProductSection({
    required this.title,
    required this.section,
    this.dealBadge = false,
  });
  final String title;
  final HomeSection section;
  final bool dealBadge;

  @override
  Widget build(BuildContext context) {
    if (section.items.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final category = section.category;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: title),
        _ProductGrid(products: section.items, dealBadge: dealBadge),
        if (category != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Center(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.scaffoldHeading,
                ),
                onPressed: () => context.push(
                  AppRoutes.category(category.uid),
                  extra: category.name.isNotEmpty ? category.name : title,
                ),
                child: Text(l10n.homeSeeMore),
              ),
            ),
          ),
      ],
    );
  }
}

/// "Explore Our Brands" — real brands (logos) from the `brands` query; tapping
/// searches the catalogue for that brand. Hidden when none are returned.
class _ExploreBrands extends ConsumerWidget {
  const _ExploreBrands();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(brandsProvider)
        .when(
          loading: () => const _BrandsRailSkeleton(),
          error: (_, __) => const SizedBox.shrink(),
          data: (brands) => brands.isEmpty
              ? const SizedBox.shrink()
              : _BrandsRail(brands: brands.take(15).toList()),
        );
  }
}

/// The "Explore Our Brands" rail itself (header + horizontal logo cards + See
/// More), shown once real brands have loaded.
///
/// The cards drift continuously on an endless loop (CL042-DEV08). The list is
/// the brand set repeated many times over and the offset wraps back by exactly
/// one lap each time it passes one, so the seam is invisible and the offset
/// never grows unbounded. Scrolling is direction-agnostic: a horizontal
/// [ListView] takes its lead from [Directionality], so the same increasing
/// offset drifts left-to-right in English and right-to-left in Arabic without
/// any manual flipping.
class _BrandsRail extends StatefulWidget {
  const _BrandsRail({required this.brands});
  final List<Brand> brands;

  @override
  State<_BrandsRail> createState() => _BrandsRailState();
}

class _BrandsRailState extends State<_BrandsRail>
    with SingleTickerProviderStateMixin {
  /// Card width + the gap that follows it; fixed so one lap can be measured
  /// exactly rather than read off a laid-out viewport.
  static const double _slotExtent = _BrandCard.width + 12;

  /// Drift speed. A card every ~4.5s — present without being distracting.
  static const double _pixelsPerSecond = 30;

  /// How long after the finger lifts before the drift picks back up, so a
  /// fling settles under its own physics instead of being cut off by a jump.
  static const Duration _resumeDelay = Duration(milliseconds: 900);

  /// Laps rendered. Enough that the far edge is never reachable between wraps,
  /// while staying a bounded (lazily built) list.
  static const int _laps = 200;

  final ScrollController _scroll = ScrollController();
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastTick = Duration.zero;
  Timer? _resume;
  bool _held = false;

  double get _lapExtent => widget.brands.length * _slotExtent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  @override
  void didUpdateWidget(covariant _BrandsRail old) {
    super.didUpdateWidget(old);
    // A store switch swaps the brand set (and so the lap length) underneath us.
    if (old.brands.length != widget.brands.length && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _resume?.cancel();
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _start() {
    // Honour the OS "reduce motion" setting — an endless drift is exactly the
    // kind of animation it exists to switch off.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    if (widget.brands.length < 2 || _ticker.isActive) return;
    _lastTick = Duration.zero;
    // No matching stop: a ticker from [SingleTickerProviderStateMixin] is muted
    // automatically whenever its [TickerMode] goes off-stage (another tab, a
    // pushed route), so the rail idles while it isn't on screen.
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    // First tick only establishes the baseline — there is no delta yet.
    final previous = _lastTick;
    _lastTick = elapsed;
    if (previous == Duration.zero) return;
    if (_held || !_scroll.hasClients || !_scroll.position.hasContentDimensions) {
      return;
    }
    final seconds = (elapsed - previous).inMicroseconds / 1e6;
    // A dropped frame shouldn't teleport the rail; cap the catch-up.
    final delta = _pixelsPerSecond * seconds.clamp(0.0, 0.05);
    var next = _scroll.offset + delta;
    final lap = _lapExtent;
    if (lap > 0 && next >= lap) next -= lap;
    if (next > _scroll.position.maxScrollExtent) return;
    _scroll.jumpTo(next);
  }

  void _onPointerDown(PointerDownEvent _) {
    _resume?.cancel();
    _held = true;
  }

  void _onPointerRelease() {
    _resume?.cancel();
    _resume = Timer(_resumeDelay, () {
      if (mounted) _held = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final brands = widget.brands;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: l10n.homeExploreBrands),
        SizedBox(
          height: 72,
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerUp: (_) => _onPointerRelease(),
            onPointerCancel: (_) => _onPointerRelease(),
            child: ListView.builder(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemExtent: _slotExtent,
              // One brand set is enough when there is nothing to loop.
              itemCount: brands.length < 2 ? brands.length : brands.length * _laps,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: _BrandCard(brand: brands[index % brands.length]),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Center(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: context.scaffoldHeading,
              ),
              onPressed: () => context.push(AppRoutes.brands),
              child: Text(l10n.homeSeeMore),
            ),
          ),
        ),
      ],
    );
  }
}

/// A brand logo card; falls back to the brand name if the logo can't load.
class _BrandCard extends StatelessWidget {
  const _BrandCard({required this.brand});

  /// Fixed so the rail can measure one loop of the marquee exactly.
  static const double width = 124;

  final Brand brand;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(AppRoutes.brand, extra: brand),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        alignment: Alignment.center,
        child: brand.imageUrl.isNotEmpty
            ? HubImage(
                url: brand.imageUrl,
                fit: BoxFit.contain,
                placeholder: (_) => _BrandName(title: brand.title),
                error: (_) => _BrandName(title: brand.title),
              )
            : _BrandName(title: brand.title),
      ),
    );
  }
}

class _BrandName extends StatelessWidget {
  const _BrandName({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      title,
      maxLines: 2,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 12,
        color: AppColors.inkHeading,
      ),
    ),
  );
}

/// Promotional offer card — content comes from the admin "Special Offer Banner"
/// store config (enabled / text / coupon). Hidden when disabled or absent.
class _SpecialOffer extends ConsumerWidget {
  const _SpecialOffer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(specialOfferProvider)
        .when(
          loading: () => const _SpecialOfferSkeleton(),
          error: (_, __) => const SizedBox.shrink(),
          data: (offer) => offer.isVisible
              ? _SpecialOfferCard(offer: offer)
              : const SizedBox.shrink(),
        );
  }
}

class _SpecialOfferCard extends StatelessWidget {
  const _SpecialOfferCard({required this.offer});
  final SpecialOffer offer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white,
            child: Icon(Icons.card_giftcard, color: AppColors.brandPrimary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.homeSpecialOfferTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandPrimary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  offer.text,
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 13,
                  ),
                ),
                if (offer.hasCode) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        l10n.homeSpecialOfferCodeLabel,
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: _CopyCouponChip(code: offer.couponCode),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The advertised promo code, as a tappable chip that copies it to the
/// clipboard. The whole chip is the tap target — the trailing icon is the
/// affordance that says so — because a code you can read but not lift out is
/// the thing QA filed this for. Same idiom as the cart coupon field and the
/// order/tracking numbers: [Clipboard.setData] plus a confirming snackbar.
class _CopyCouponChip extends StatelessWidget {
  const _CopyCouponChip({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n.actionCopy,
      child: InkWell(
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          await Clipboard.setData(ClipboardData(text: code));
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.cartCouponCopied)),
          );
        },
        borderRadius: BorderRadius.circular(6),
        child: Semantics(
          button: true,
          label: '${l10n.actionCopy} $code',
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 2, 6, 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.brandPrimary),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    code,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.brandPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.copy_outlined,
                  size: 14,
                  color: AppColors.brandPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── New home sections (mirror live hub-market.magento2.click — docs/FIGMA_DESIGN.md) ────────
// Each is backend-driven (magentoegypt_beauty_config / blogPosts / the live
// category tree) and collapses to nothing when its source is disabled or empty,
// matching the established "hide when absent — never fabricate" pattern.

/// "Limited-Time Offer" — the admin `deals/countdown_*` promo. A daily
/// countdown ticks to local midnight. Hidden when disabled or the `deals`
/// section toggle is off.
class _LimitedTimeOffer extends ConsumerWidget {
  const _LimitedTimeOffer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(homeConfigProvider)
        .when(
          loading: () => const _LimitedTimeOfferSkeleton(),
          error: (_, __) => const SizedBox.shrink(),
          data: (cfg) {
            final offer = cfg.limitedTimeOffer;
            if (!cfg.sectionEnabled('deals') || !offer.isVisible) {
              return const SizedBox.shrink();
            }
            return _LimitedTimeOfferCard(offer: offer);
          },
        );
  }
}

class _LimitedTimeOfferCard extends ConsumerStatefulWidget {
  const _LimitedTimeOfferCard({required this.offer});
  final LimitedTimeOffer offer;

  @override
  ConsumerState<_LimitedTimeOfferCard> createState() =>
      _LimitedTimeOfferCardState();
}

class _LimitedTimeOfferCardState extends ConsumerState<_LimitedTimeOfferCard> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = _computeRemaining();
    if (widget.offer.isDaily) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        final next = _computeRemaining();
        if (mounted) setState(() => _remaining = next);
      });
    }
  }

  /// Time left until the next midnight in the store's timezone (the daily
  /// countdown reset) — the same instant the website counts to.
  Duration _computeRemaining() =>
      untilNextStoreMidnight(widget.offer.timezone);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final offer = widget.offer;
    // Figma (updated 2026-07-13): a BLUSH promo card with burgundy text and
    // burgundy countdown boxes (white numerals) — matching live.
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.homeLimitedOfferEyebrow.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.brandPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            offer.headline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.brandPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          if (offer.subtext.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              offer.subtext,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
            ),
          ],
          if (widget.offer.isDaily) ...[
            const SizedBox(height: 14),
            // Digits keep LTR order (HH:MM:SS) in both languages.
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CountdownBox(
                    value: _two(_remaining.inHours),
                    label: l10n.homeCountdownHours,
                  ),
                  const _CountdownSeparator(),
                  _CountdownBox(
                    value: _two(_remaining.inMinutes % 60),
                    label: l10n.homeCountdownMinutes,
                  ),
                  const _CountdownSeparator(),
                  _CountdownBox(
                    value: _two(_remaining.inSeconds % 60),
                    label: l10n.homeCountdownSeconds,
                  ),
                ],
              ),
            ),
          ],
          if (offer.ctaLabel.isNotEmpty) ...[
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 22),
              ),
              onPressed: () => openStorefrontUrl(context, ref, offer.ctaUrl),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    offer.ctaLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 16),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A single HRS/MINS/SECS box in the countdown — burgundy tile, white numerals,
/// muted label beneath (Figma).
class _CountdownBox extends StatelessWidget {
  const _CountdownBox({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.brandPrimary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.inkMuted,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class _CountdownSeparator extends StatelessWidget {
  const _CountdownSeparator();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 8),
    child: Padding(
      padding: EdgeInsets.only(bottom: 14),
      child: Text(
        ':',
        style: TextStyle(
          color: AppColors.brandPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

/// "Deals of the Day" — products from the live `deals-of-the-day` category with
/// a DEAL tag + real discount badges. Gated on the backend `deals` toggle and
/// hidden when the category returns nothing.
class _DealsOfTheDaySection extends ConsumerWidget {
  const _DealsOfTheDaySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref
        .watch(homeConfigProvider)
        .maybeWhen(
          data: (c) => c.sectionEnabled('deals'),
          orElse: () => true,
        );
    if (!enabled) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(dealsOfTheDayProvider)
        .when(
          loading: () => _ProductSectionSkeleton(title: l10n.homeDealsOfTheDay),
          error: (_, __) => const SizedBox.shrink(),
          data: (section) => _ProductSection(
            title: l10n.homeDealsOfTheDay,
            section: section,
            dealBadge: true,
          ),
        );
  }
}

/// "Skincare / Makeup" editorial banners — two image banners bound to the real
/// `skin-care` / `makeup` categories (image + link) with editorial taglines.
/// Gated on the `promo_split` toggle; each banner hides if its category is
/// absent.
class _EditorialBanners extends ConsumerWidget {
  const _EditorialBanners();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref
        .watch(homeConfigProvider)
        .maybeWhen(
          data: (c) => c.sectionEnabled('promo_split'),
          orElse: () => true,
        );
    if (!enabled) return const SizedBox.shrink();
    return ref
        .watch(promoSplitBannersProvider)
        .when(
          loading: () => const _EditorialBannersSkeleton(),
          error: (_, __) => const SizedBox.shrink(),
          data: (banners) => banners.isEmpty
              ? const SizedBox.shrink()
              : _EditorialBannersList(banners: banners),
        );
  }
}

class _EditorialBannersList extends StatelessWidget {
  const _EditorialBannersList({required this.banners});
  final List<PromoSplitBanner> banners;

  @override
  Widget build(BuildContext context) {
    // Figma: inset (16px) rounded banners, 12px apart.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        children: [
          for (var i = 0; i < banners.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _EditorialBanner(banner: banners[i]),
          ],
        ],
      ),
    );
  }
}

class _EditorialBanner extends ConsumerWidget {
  const _EditorialBanner({required this.banner});
  final PromoSplitBanner banner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ctaLabel = banner.ctaLabel.isNotEmpty
        ? banner.ctaLabel
        : l10n.homeHeroCta;
    // Figma: inset rounded banner, ~230px tall.
    return Material(
      color: AppColors.surfaceTint,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: banner.ctaUrl.isEmpty
            ? null
            : () => openStorefrontUrl(
                context,
                ref,
                banner.ctaUrl,
                title: banner.eyebrow.isNotEmpty ? banner.eyebrow : banner.title,
              ),
        child: SizedBox(
          height: 230,
          child: Stack(
            children: [
              Positioned.fill(
                child: HubImage(
                  url: banner.imageUrl,
                  shimmer: true,
                  error: (_) => const ColoredBox(color: AppColors.surfaceTint),
                ),
              ),
              // Dark scrim on the start side for text legibility.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: AlignmentDirectional.centerStart,
                      end: AlignmentDirectional.centerEnd,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.black.withValues(alpha: 0.05),
                      ],
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                start: 20,
                top: 0,
                bottom: 0,
                end: 20,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (banner.eyebrow.isNotEmpty) ...[
                      Text(
                        banner.eyebrow.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      banner.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // "Shop Now" pill (Figma) — the whole banner is the tap
                    // target; this reads as a button.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ctaLabel,
                            style: const TextStyle(
                              color: AppColors.brandPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.arrow_forward,
                            size: 15,
                            color: AppColors.brandPrimary,
                          ),
                        ],
                      ),
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

/// "Exclusive Offers" — the `homeBanners` discount rail ("Save More Every
/// Order"). Hides when the query returns nothing; gated on the `banners` toggle.
class _ExclusiveOffers extends ConsumerWidget {
  const _ExclusiveOffers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref
        .watch(homeConfigProvider)
        .maybeWhen(
          data: (c) => c.sectionEnabled('banners'),
          orElse: () => true,
        );
    if (!enabled) return const SizedBox.shrink();
    return ref
        .watch(homeBannersProvider)
        .when(
          loading: () => const _ExclusiveOffersSkeleton(),
          error: (_, __) => const SizedBox.shrink(),
          data: (offers) => offers.isEmpty
              ? const SizedBox.shrink()
              : _ExclusiveOffersRail(offers: offers),
        );
  }
}

class _ExclusiveOffersRail extends StatelessWidget {
  const _ExclusiveOffersRail({required this.offers});
  final List<ExclusiveOffer> offers;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Figma (updated 2026-07-13): left-aligned title + subtitle with
        // VIEW ALL on the trailing side (mirrors under RTL via the Row).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.homeExclusiveOffersTitle.toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: context.scaffoldHeading,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.homeExclusiveOffersSubtitle,
                      style: TextStyle(
                        color: context.scaffoldMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => context.go(AppRoutes.categories),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brandPrimary,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.homeViewAll,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward, size: 14),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Figma: three stacked inset image banners.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Column(
            children: [
              for (var i = 0; i < offers.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _ExclusiveOfferBanner(offer: offers[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One "Exclusive Offers" banner (Figma) — a category image with a centered
/// discount + white category pill + terms line, over a dark scrim. Falls back
/// to a blush background when no image is provided.
class _ExclusiveOfferBanner extends ConsumerWidget {
  const _ExclusiveOfferBanner({required this.offer});
  final ExclusiveOffer offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.surfaceTint,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: offer.ctaUrl.isEmpty
            ? null
            : () =>
                  openStorefrontUrl(context, ref, offer.ctaUrl, title: offer.title),
        child: SizedBox(
          height: 200,
          child: Stack(
            children: [
              if (offer.imageUrl.isNotEmpty)
                Positioned.fill(
                  child: HubImage(url: offer.imageUrl, shimmer: true),
                ),
              // Scrim so the centered white text stays legible over any image.
              Positioned.fill(
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (offer.badge.isNotEmpty)
                      Text(
                        offer.badge,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    if (offer.title.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          offer.title,
                          style: const TextStyle(
                            color: AppColors.brandPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    if (offer.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        offer.subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
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

/// "Why Shoppers Trust Hub Market" — the `homeReviews` testimonial rail (real
/// reviews only). Hides when empty; gated on the `reviews` toggle.
class _WhyShoppersTrust extends ConsumerWidget {
  const _WhyShoppersTrust();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref
        .watch(homeConfigProvider)
        .maybeWhen(
          data: (c) => c.sectionEnabled('reviews'),
          orElse: () => true,
        );
    if (!enabled) return const SizedBox.shrink();
    return ref
        .watch(homeReviewsProvider)
        .when(
          loading: () => const _TestimonialsSkeleton(),
          error: (_, __) => const SizedBox.shrink(),
          data: (items) => items.isEmpty
              ? const SizedBox.shrink()
              : _TestimonialsRail(items: items),
        );
  }
}

class _TestimonialsRail extends StatelessWidget {
  const _TestimonialsRail({required this.items});
  final List<Testimonial> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeaderWithSubtitle(
          title: l10n.homeTrustReviewsTitle,
          subtitle: l10n.homeTrustReviewsSubtitle,
        ),
        SizedBox(
          height: 184,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _TestimonialCard(item: items[i]),
          ),
        ),
        // See More → the full customer-reviews screen (matches the live site's
        // "SEE MORE" under this section; the other rails carry the same button).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Center(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: context.scaffoldHeading,
              ),
              onPressed: () => context.push(AppRoutes.reviews),
              child: Text(l10n.homeSeeMore),
            ),
          ),
        ),
      ],
    );
  }
}

class _TestimonialCard extends StatelessWidget {
  const _TestimonialCard({required this.item});
  final Testimonial item;

  String get _initials {
    final parts = item.author.trim().split(RegExp(r'\s+'));
    final letters = parts
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return letters.isEmpty ? '★' : letters;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar + name + gold stars (Figma).
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.surfaceTint,
                child: Text(
                  _initials,
                  style: const TextStyle(
                    color: AppColors.brandPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.author.isNotEmpty) ...[
                      Text(
                        item.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.inkHeading,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    _Stars(rating: item.rating),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Quote, then the product it's about at the bottom.
          Expanded(
            child: Text(
              '“${item.quote}”',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          if (item.product.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.product.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.inkFaint,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A gold 0–5 star row (filled + outlined to five). Auto-mirrors under RTL via
/// the row's directional layout; stars themselves are symmetric.
class _Stars extends StatelessWidget {
  const _Stars({required this.rating});
  final int rating;

  @override
  Widget build(BuildContext context) {
    final full = rating.clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            i < full ? Icons.star : Icons.star_border,
            size: 16,
            color: AppColors.accentGold,
          ),
      ],
    );
  }
}

/// "The Hub Market Journal" — the latest blog posts (`blogPosts`). Gated on the
/// backend `blog` toggle and hidden when the module returns no posts.
class _HubJournal extends ConsumerWidget {
  const _HubJournal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref
        .watch(homeConfigProvider)
        .maybeWhen(
          data: (c) => c.sectionEnabled('blog'),
          orElse: () => true,
        );
    if (!enabled) return const SizedBox.shrink();
    return ref
        .watch(blogPostsProvider)
        .when(
          loading: () => const _JournalSkeleton(),
          error: (_, __) => const SizedBox.shrink(),
          data: (posts) =>
              posts.isEmpty ? const SizedBox.shrink() : _JournalRail(posts: posts),
        );
  }
}

class _JournalRail extends StatelessWidget {
  const _JournalRail({required this.posts});
  final List<BlogPost> posts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Blog index for "See More" — the store-prefixed `.../blog` root derived from
    // a post URL (`.../uae-en/blog/post/…`). Empty when it can't be derived.
    final indexUrl = _blogIndexUrl(posts.first.url);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeaderWithSubtitle(
          title: l10n.homeJournalTitle,
          subtitle: l10n.homeJournalSubtitle,
        ),
        SizedBox(
          // Fits the tallest card (118 image + 2-line title + 2-line excerpt +
          // tag + Read More); 250 clipped the last row and overflowed.
          height: 280,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: posts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _JournalCard(post: posts[i]),
          ),
        ),
        if (indexUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Center(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.scaffoldHeading,
                ),
                onPressed: () => context.push(
                  AppRoutes.webview,
                  extra: WebViewArgs(
                    url: indexUrl,
                    title: l10n.homeJournalTitle,
                  ),
                ),
                child: Text(l10n.homeSeeMore),
              ),
            ),
          ),
      ],
    );
  }
}

class _JournalCard extends StatelessWidget {
  const _JournalCard({required this.post});
  final BlogPost post;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: () => context.push(
        AppRoutes.webview,
        extra: WebViewArgs(url: post.url, title: post.title),
      ),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 260,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderDefault),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 118,
              width: double.infinity,
              child: post.hasImage
                  ? HubImage(
                      url: post.imageUrl,
                      error: (_) => const _JournalImageFallback(),
                    )
                  : const _JournalImageFallback(),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Figma: the BLOGS tag sits in the body, below the image.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      l10n.homeJournalTag,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.25,
                      color: AppColors.inkHeading,
                    ),
                  ),
                  if (post.excerpt.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      post.excerpt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.homeReadMore,
                        style: const TextStyle(
                          color: AppColors.brandPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: AppColors.brandPrimary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalImageFallback extends StatelessWidget {
  const _JournalImageFallback();

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surfaceTint,
    child: const Center(
      child: Icon(Icons.article_outlined, color: AppColors.brandPrimary),
    ),
  );
}

/// The store-prefixed blog index (`.../blog`) derived from a post URL like
/// `https://hub-market.magento2.click/uae-en/blog/post/…`. Returns '' when the URL isn't an
/// absolute http(s) URL containing a `/blog` segment.
String _blogIndexUrl(String postUrl) {
  final uri = Uri.tryParse(postUrl);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return '';
  const marker = '/blog';
  final i = postUrl.indexOf(marker);
  if (i < 0) return '';
  return postUrl.substring(0, i + marker.length);
}

/// Trust seals (live hub-market.magento2.click) — the store's four guarantees on a light-grey
/// band. Content mirrors the website's trust strip exactly (QA: the block must
/// match the site): four seals, where the delivery seal carries a muted
/// sub-line ("Rest Zones in 48 Hours") rather than being a separate seal. The
/// backend `trust/items` config array is currently empty, so — like the website
/// theme — the app renders these as localized defaults; wire them to
/// `trust/items` if/when the backend populates it.
class _TrustBadges extends StatelessWidget {
  const _TrustBadges();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Icons + fills mirror the live site (filled shield/truck/headset, a
    // circular "refresh" arrow for delivery).
    final seals = <({IconData icon, String label, String? sub})>[
      (icon: Icons.verified_user, label: l10n.homeTrustOriginal, sub: null),
      (icon: Icons.local_shipping, label: l10n.homeTrustFreeDelivery, sub: null),
      (
        icon: Icons.refresh,
        label: l10n.homeTrustDelivery3h,
        sub: l10n.homeTrustRestZones,
      ),
      (
        icon: Icons.headset_mic,
        label: l10n.homeTrustCustomerService,
        sub: null,
      ),
    ];
    // Four seals in a 2×2 grid (matches the live desktop row, stacked for a
    // phone). Tops align so the delivery seal's sub-line doesn't shift its row.
    return Container(
      width: double.infinity,
      color: const Color(0xFFF3F4F6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      child: Column(
        children: [
          for (var r = 0; r < seals.length; r += 2) ...[
            if (r > 0) const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in seals.skip(r).take(2))
                  Expanded(
                    child: _TrustBadge(
                      icon: s.icon,
                      label: s.label,
                      sub: s.sub,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  const _TrustBadge({required this.icon, required this.label, this.sub});
  final IconData icon;
  final String label;

  /// Optional muted sub-line beneath the label (live site: "Rest Zones in 48
  /// Hours" under the delivery seal).
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: Colors.white,
          child: Icon(icon, color: AppColors.brandPrimary, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            height: 1.25,
            color: AppColors.inkHeading,
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(
            sub!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontSize: 11,
              height: 1.2,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Loading skeletons ──────────────────────────────────────────────────────
// Shown only while a section's provider resolves. The real sections collapse
// themselves to nothing when empty/disabled, so after load nothing spurious
// renders. Each skeleton mirrors the dimensions of the section it stands in for.

/// Mirrors `_CategoryGrid` (horizontal rail): grey circle + label line per cell.
class _CategoryGridSkeleton extends StatelessWidget {
  const _CategoryGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: SizedBox(
        height: 116,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 6,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, __) => const SizedBox(
            width: 80,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkeletonBox.circle(size: 72),
                SizedBox(height: 8),
                SkeletonBox(width: 52, height: 10, borderRadius: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mirrors `_BrandsRail`: section header + a row of 124×72 logo-card blocks.
class _BrandsRailSkeleton extends StatelessWidget {
  const _BrandsRailSkeleton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: l10n.homeExploreBrands),
        SizedBox(
          height: 72,
          child: Shimmer(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 6,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) =>
                  const SkeletonBox(width: 124, height: 72, borderRadius: 12),
            ),
          ),
        ),
      ],
    );
  }
}

/// Section header + a 2-col product grid (0.58) of card skeletons, for the
/// New Arrivals / Bestsellers loading state.
class _ProductSectionSkeleton extends StatelessWidget {
  const _ProductSectionSkeleton({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: title),
        const ProductGridSkeleton(childAspectRatio: 0.58, count: 4),
      ],
    );
  }
}

/// Mirrors `_SpecialOfferCard`: blush card with a circle avatar + two text
/// lines. The blush surface is drawn outside the [Shimmer]; only the inner
/// blocks shimmer.
class _SpecialOfferSkeleton extends StatelessWidget {
  const _SpecialOfferSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Shimmer(
        child: Row(
          children: [
            SkeletonBox.circle(size: 44),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SkeletonBox(width: 150, height: 14, borderRadius: 4),
                  SizedBox(height: 8),
                  SkeletonBox(height: 11, borderRadius: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mirrors `_LimitedTimeOfferCard`: blush promo card with centered eyebrow /
/// headline / subtext lines, three countdown boxes and a CTA pill. The blush
/// surface is drawn outside the [Shimmer]; only the inner blocks sweep.
class _LimitedTimeOfferSkeleton extends StatelessWidget {
  const _LimitedTimeOfferSkeleton();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 24, 16, 4),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.surfaceTint,
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Shimmer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SkeletonBox(width: 120, height: 10, borderRadius: 4),
          SizedBox(height: 12),
          SkeletonBox(width: 170, height: 26, borderRadius: 6),
          SizedBox(height: 10),
          SkeletonBox(width: 210, height: 12, borderRadius: 4),
          SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SkeletonBox(width: 48, height: 46, borderRadius: 10),
              SizedBox(width: 16),
              SkeletonBox(width: 48, height: 46, borderRadius: 10),
              SizedBox(width: 16),
              SkeletonBox(width: 48, height: 46, borderRadius: 10),
            ],
          ),
          SizedBox(height: 16),
          SkeletonBox(width: 150, height: 42, borderRadius: 21),
        ],
      ),
    ),
  );
}

/// Inset rounded shimmer banners — the loading state for the editorial /
/// exclusive-offer banner stacks. Draws [count] boxes of [height]; an optional
/// [header] (its own shimmer) sits above them.
class _BannerStackSkeleton extends StatelessWidget {
  const _BannerStackSkeleton({
    required this.count,
    required this.height,
    this.header,
  });
  final int count;
  final double height;
  final Widget? header;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (header != null) header!,
      Padding(
        // 20px top when there's no header; the header supplies its own spacing.
        padding: EdgeInsets.fromLTRB(16, header == null ? 20 : 0, 16, 4),
        child: Shimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                SkeletonBox(height: height, borderRadius: 16),
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

/// Loading state for the Skincare / Makeup editorial banners (two banners).
class _EditorialBannersSkeleton extends StatelessWidget {
  const _EditorialBannersSkeleton();

  @override
  Widget build(BuildContext context) =>
      const _BannerStackSkeleton(count: 2, height: 230);
}

/// Loading state for the Exclusive Offers rail (header + three banners).
class _ExclusiveOffersSkeleton extends StatelessWidget {
  const _ExclusiveOffersSkeleton();

  @override
  Widget build(BuildContext context) => const _BannerStackSkeleton(
    count: 3,
    height: 200,
    header: Padding(
      padding: EdgeInsets.fromLTRB(16, 28, 16, 14),
      child: Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 160, height: 14, borderRadius: 4),
            SizedBox(height: 8),
            SkeletonBox(width: 220, height: 12, borderRadius: 4),
          ],
        ),
      ),
    ),
  );
}

/// Mirrors `_TestimonialsRail`: the real header + a row of card-sized skeletons.
class _TestimonialsSkeleton extends StatelessWidget {
  const _TestimonialsSkeleton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeaderWithSubtitle(
          title: l10n.homeTrustReviewsTitle,
          subtitle: l10n.homeTrustReviewsSubtitle,
        ),
        SizedBox(
          height: 184,
          child: Shimmer(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) =>
                  const SkeletonBox(width: 270, height: 184, borderRadius: 14),
            ),
          ),
        ),
      ],
    );
  }
}

/// Mirrors `_JournalRail`: the real header + a row of blog-card skeletons
/// (image block + tag + title/excerpt/read-more lines).
class _JournalSkeleton extends StatelessWidget {
  const _JournalSkeleton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeaderWithSubtitle(
          title: l10n.homeJournalTitle,
          subtitle: l10n.homeJournalSubtitle,
        ),
        SizedBox(
          height: 280,
          child: Shimmer(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => const _JournalCardSkeleton(),
            ),
          ),
        ),
      ],
    );
  }
}

class _JournalCardSkeleton extends StatelessWidget {
  const _JournalCardSkeleton();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 260,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 260, height: 118, borderRadius: 14),
        SizedBox(height: 12),
        SkeletonBox(width: 54, height: 18, borderRadius: 4),
        SizedBox(height: 10),
        SkeletonBox(width: 220, height: 14, borderRadius: 4),
        SizedBox(height: 6),
        SkeletonBox(width: 180, height: 14, borderRadius: 4),
        SizedBox(height: 10),
        SkeletonBox(width: 90, height: 12, borderRadius: 4),
      ],
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 28, 16, 14),
    child: Text(
      title.toUpperCase(),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.82,
        color: context.scaffoldHeading,
      ),
    ),
  );
}

/// Centered section header with a muted subtitle beneath (Figma: Why Shoppers
/// Trust + The Hub Market Journal).
class _SectionHeaderWithSubtitle extends StatelessWidget {
  const _SectionHeaderWithSubtitle({
    required this.title,
    required this.subtitle,
  });
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 28, 16, 14),
    child: Column(
      children: [
        Text(
          title.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.82,
            color: context.scaffoldHeading,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.scaffoldMuted, fontSize: 13),
        ),
      ],
    ),
  );
}
