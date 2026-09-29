import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/store_contact.dart';
import '../../core/error/failure.dart';
import '../../core/store/store_controller.dart';
import '../../core/util/launch.dart';
import '../../core/validation/validators.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../../core/widgets/failure_message.dart';
import '../../core/widgets/social_icon.dart';
import '../../core/widgets/web_view_screen.dart';
import '../../features/newsletter/data/newsletter_repository.dart';
import '../../l10n/l10n.dart';
import '../routes.dart';
import '../theme/app_colors.dart';

/// Marketing footer shown on content screens (home, PLP, PDP, cart, …) in both
/// EN and AR. Social links + website come from admin config
/// ([storeContactProvider]); other links navigate in-app; the newsletter posts
/// to Magento via [NewsletterRepository], scoped to the active store view.
class MarketingFooter extends ConsumerStatefulWidget {
  const MarketingFooter({super.key});

  @override
  ConsumerState<MarketingFooter> createState() => _MarketingFooterState();
}

class _MarketingFooterState extends ConsumerState<MarketingFooter> {
  final TextEditingController _newsletter = TextEditingController();
  bool _subscribing = false;

  @override
  void dispose() {
    _newsletter.dispose();
    super.dispose();
  }

  Future<void> _subscribe() async {
    if (_subscribing) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final email = _newsletter.text.trim();
    if (Validators.email(context, email) != null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.validationEmail)));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _subscribing = true);
    try {
      final result = await ref
          .read(newsletterRepositoryProvider)
          .subscribe(email);
      if (!mounted) return;
      // Only clear the field once the address is actually on the list —
      // otherwise a failed sign-up loses what the user typed.
      _newsletter.clear();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result == NewsletterSubscription.subscribed
                ? l10n.footerSubscribed
                : l10n.footerSubscribeConfirm,
          ),
        ),
      );
    } on Failure catch (failure) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(context, failure))),
      );
    } finally {
      if (mounted) setState(() => _subscribing = false);
    }
  }

  /// Slug for a store CMS page, relative to the active store's base URL. "About
  /// Us" has an AR-specific slug; the rest are shared. Verified against the live
  /// hub-market.magento2.click footer (uae-en / uae-ar).
  String _cmsSlug(String page, bool isAr) => switch (page) {
    'about' => isAr ? 'about-us-ar' : 'about-us',
    'faqs' => 'faqs',
    'shipping' => 'shipping-delivery',
    'returns' => 'returns-exchanges',
    // AR has its own privacy page under a short slug (`privacy-policy`); the long
    // English slug (`privacy-policy-cookie-restriction-mode`) resolves under
    // `/uae-ar/` but serves English content — so the AR footer would open the
    // wrong (English) page. Match the live site's per-locale slugs (QA 86d3khzup
    // #9, verified against the eg_en / eg_ar footers).
    'privacy' => isAr ? 'privacy-policy' : 'privacy-policy-cookie-restriction-mode',
    'terms' => 'terms-conditions',
    _ => '',
  };

  /// The active store's storefront base URL (`base_link_url`, e.g. `…/uae-ar/`),
  /// TLS-forced. Prefer `base_link_url`: it carries the storefront language path
  /// that content pages live under. `secure_base_url` is the bare Magento base
  /// (`…hub-market.magento2.click/`) with no language, which sends an Arabic path to the
  /// default English store and 404s.
  String _storeBase() {
    final store = ref.read(storeControllerProvider);
    var base = ref.read(storeContactProvider).website;
    for (final s in store.stores) {
      if (s.storeCode == store.activeStoreCode) {
        final b = s.baseLinkUrl.isNotEmpty
            ? s.baseLinkUrl
            : (s.secureBaseUrl.isNotEmpty ? s.secureBaseUrl : s.baseUrl);
        if (b.isNotEmpty) base = b;
        break;
      }
    }
    // base_link_url comes back as http://; force TLS.
    return base.replaceFirst('http://', 'https://');
  }

  /// Opens a storefront [path] (relative to the active store's base URL) in the
  /// in-app WebView.
  ///
  /// The storefront's `webview=1` chrome-hiding flag is deliberately not sent:
  /// it returns HTTP 500 on `shopbrand` pages (CL042-DEV19/QA01), so every
  /// in-app storefront link now loads the page exactly as the browser would.
  /// See `inAppStorefrontUrl` in `features/catalog/presentation/storefront_links.dart`.
  void _openStorePage(String path, String title) {
    final base = _storeBase();
    final sep = base.endsWith('/') ? '' : '/';
    context.push(
      AppRoutes.webview,
      extra: WebViewArgs(url: '$base$sep$path', title: title),
    );
  }

  /// Opens a store CMS page (correct per-locale URL) in the in-app WebView,
  /// instead of leaving the app or dumping the user on the homepage.
  void _openCms(String page, String title) {
    final isAr = ref.read(storeControllerProvider).activeLocale == 'ar';
    _openStorePage('${_cmsSlug(page, isAr)}/', title);
  }

  /// Track Order always lands on the in-app Orders screen — it now serves
  /// guests too (their remembered orders, resolved through Magento's guest
  /// lookups, plus a manual order-number lookup), so the storefront
  /// `sales/guest/form/` WebView fallback is no longer needed.
  void _openTrackOrder() => context.push(AppRoutes.orders);

  Future<void> _openUrl(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    if (!await launchExternalUri(Uri.parse(url))) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final socials = ref.watch(storeContactProvider).socials;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 32),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      color: AppColors.footerSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandWordmark(),
          const SizedBox(height: 16),
          Text(
            l10n.footerTagline,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 20),
          // Social row — admin-configured links (hidden when none are set).
          if (socials.isNotEmpty)
            Row(
              children: [
                for (final s in socials)
                  _SocialButton(
                    onTap: () => _openUrl(s.url),
                    child: socialIconWidget(
                      s.key,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // "About Us" column — matches the website footer grouping.
              Expanded(
                child: _LinkColumn(
                  heading: l10n.footerAboutHeading,
                  links: [
                    (
                      label: l10n.footerAbout,
                      onTap: () => _openCms('about', l10n.footerAbout),
                    ),
                    (
                      label: l10n.footerFaqs,
                      onTap: () => _openCms('faqs', l10n.footerFaqs),
                    ),
                    (
                      // Contact Us opens the storefront's contact page
                      // (`/contact/`, localized per store) in-app — was pointing
                      // at the in-app Help/FAQ screen (QA 86d3khzup #9).
                      label: l10n.footerContact,
                      onTap: () => _openStorePage('contact/', l10n.footerContact),
                    ),
                    (
                      label: l10n.footerTrackOrder,
                      onTap: _openTrackOrder,
                    ),
                  ],
                ),
              ),
              // "Customer Service" column — matches the website footer grouping.
              Expanded(
                child: _LinkColumn(
                  heading: l10n.footerSupport,
                  links: [
                    (
                      label: l10n.footerShipping,
                      onTap: () => _openCms('shipping', l10n.footerShipping),
                    ),
                    (
                      label: l10n.footerReturns,
                      onTap: () => _openCms('returns', l10n.footerReturns),
                    ),
                    (
                      label: l10n.footerPrivacy,
                      onTap: () => _openCms('privacy', l10n.footerPrivacy),
                    ),
                    (
                      label: l10n.footerTerms,
                      onTap: () => _openCms('terms', l10n.footerTerms),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            l10n.footerNewsletterTitle.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.footerNewsletterSubtitle,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newsletter,
                  enabled: !_subscribing,
                  keyboardType: TextInputType.emailAddress,
                  onSubmitted: (_) => _subscribe(),
                  decoration: InputDecoration(
                    hintText: l10n.footerNewsletterHint,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _subscribing ? null : _subscribe,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
                child: _subscribing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.footerSubscribe),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 16),
          // Accepted payment methods — matches the website footer.
          const Center(child: _PaymentBadges()),
          const SizedBox(height: 14),
          // Copyright — centered like the website (was start-aligned).
          Center(
            child: Text(
              l10n.footerRights,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Accepted-payment badges row shown above the footer copyright (Apple Pay ·
/// Samsung Pay · card · tabby · Mastercard · Visa).
///
/// Rendered as lightweight brand chips rather than artwork, matching how the
/// other marks here are drawn; swap in official brand assets when they're
/// provided. That matters most for the two wallets: Apple and Samsung both
/// require their supplied mark artwork rather than a recreation, so these are
/// placeholders for review purposes, not shippable brand marks.
///
/// A [Wrap] rather than a [Row] — six chips no longer fit one line on a narrow
/// screen, and a silent overflow here would be the first thing to break.
class _PaymentBadges extends StatelessWidget {
  const _PaymentBadges();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _PayChip(child: _ApplePayMark()),
        _PayChip(width: 56, child: _SamsungPayMark()),
        _PayChip(
          child: Icon(Icons.credit_card, size: 18, color: Color(0xFF1F2937)),
        ),
        _PayChip(
          child: Text(
            'tabby',
            style: TextStyle(
              color: Color(0xFF3EB34F),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        _PayChip(child: _MastercardMark()),
        _PayChip(
          child: Text(
            'VISA',
            style: TextStyle(
              color: Color(0xFF1A1F71),
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// White rounded chip that hosts one payment mark.
class _PayChip extends StatelessWidget {
  const _PayChip({required this.child, this.width = 42});
  final Widget child;

  /// Wider than the default only where a wordmark needs the room.
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 27,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 3),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(5),
    ),
    // Scale a mark down rather than let it overflow. These are text lockups in
    // a fixed-width chip, so their width moves with the font: Cairo in Arabic
    // and the OS large-text setting both render them wider than Inter does, and
    // the Apple Pay lockup already overflowed by ~10px under the test font.
    child: FittedBox(fit: BoxFit.scaleDown, child: child),
  );
}

/// Apple logo + "Pay". `Icons.apple` is Material's own apple glyph, so no
/// Apple-supplied artwork is embedded in the repo.
class _ApplePayMark extends StatelessWidget {
  const _ApplePayMark();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    // Pinned LTR: a Row takes its order from Directionality, so in Arabic this
    // rendered as "Pay " with the glyph on the wrong side. A brand lockup is
    // not layout — it reads the same in every locale (QA'd on device in AR).
    textDirection: TextDirection.ltr,
    children: [
      Icon(Icons.apple, size: 15, color: Color(0xFF111111)),
      Text(
        'Pay',
        style: TextStyle(
          color: Color(0xFF111111),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    ],
  );
}

/// "Samsung Pay" wordmark in Samsung blue.
class _SamsungPayMark extends StatelessWidget {
  const _SamsungPayMark();

  @override
  Widget build(BuildContext context) => const Text(
    'Samsung Pay',
    maxLines: 1,
    style: TextStyle(
      color: Color(0xFF1428A0),
      fontWeight: FontWeight.w700,
      fontSize: 8.5,
      letterSpacing: -0.1,
    ),
  );
}

/// Mastercard's two overlapping circles.
class _MastercardMark extends StatelessWidget {
  const _MastercardMark();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 26,
    height: 16,
    child: Stack(
      children: [
        Positioned(
          left: 0,
          child: _dot(const Color(0xFFEB001B)),
        ),
        Positioned(
          right: 0,
          child: _dot(const Color(0xFFF79E1B)),
        ),
      ],
    ),
  );

  Widget _dot(Color color) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
    ),
  );
}

/// Circular bordered social button for the footer; [child] is the rendered
/// glyph (see [socialIconWidget], which draws a real Instagram mark).
class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

typedef _FooterLink = ({String label, VoidCallback onTap});

class _LinkColumn extends StatelessWidget {
  const _LinkColumn({required this.heading, required this.links});
  final String heading;
  final List<_FooterLink> links;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        for (final link in links)
          InkWell(
            onTap: link.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                link.label,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
      ],
    );
  }
}
