import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/domain/search_facets.dart';
import '../../../cms/domain/cms_document.dart';
import '../../../cms/presentation/cms_navigation.dart';
import '../../../cms/presentation/widgets/cms_html_view.dart';
import '../../domain/store.dart';
import '../stores_providers.dart';
import 'store_widgets.dart';

/// A seller's month and year of joining ("June 2023"), the month in the
/// app's language and the year in Western digits, as prices are.
String storeJoinedLabel(BuildContext context, DateTime joined) {
  final locale = Localizations.localeOf(context).languageCode;
  String month;
  try {
    month = DateFormat.MMMM(locale).format(joined);
  } catch (_) {
    month = DateFormat.MMMM().format(joined);
  }
  return '$month ${joined.year}';
}

/// Figma 13b "About": the seller's About text, the numbers (products, sales,
/// dispatch, rating, reviews, joining date), a summary of the policies, the
/// categories the seller's products are in and "Call" the seller. Sections
/// without data are left out: the Sales figure and Call come only while the
/// server lists HubAppVendors' P3.1 fields and the website's store page
/// shows them (its sales count and telephone).
class StoreAboutTab extends ConsumerWidget {
  const StoreAboutTab({
    super.key,
    required this.profile,
    required this.onPolicies,
    required this.onCategory,
    this.salesCount,
    this.onCall,
  });

  final StoreProfile profile;

  /// Opens the Policies tab.
  final VoidCallback onPolicies;

  /// Lists the seller's products in one of its categories.
  final ValueChanged<SearchCategory> onCategory;

  /// The website's "N Sales"; null leaves the figure out.
  final int? salesCount;

  /// Dials the seller; null leaves the button out.
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final store = profile.card;
    final about = profile.aboutHtml;
    final short = profile.shortDescription;
    final categories =
        ref.watch(storeCategoriesProvider(store.vendorEntityId)).valueOrNull ??
        const <SearchCategory>[];

    final stats = <StoreStat>[
      StoreStat(storeCount(store.productCount), l10n.storeStatProductsListed),
      if (salesCount case final sales?)
        StoreStat(storeCount(sales), l10n.storeStatSales),
      if (store.dispatchTime case final dispatch?)
        StoreStat(dispatch.label, l10n.storeStatDispatch),
      if (store.isRated)
        StoreStat.rating(store.rating!, l10n.storeStatAverageRating),
      if (store.reviewCount > 0)
        StoreStat(storeCount(store.reviewCount), l10n.storeStatCustomerReviews),
      if (store.joinedAt case final joined?)
        StoreStat(
          storeJoinedLabel(context, joined.toLocal()),
          l10n.storeStatSellingSince,
        ),
    ];

    return _GroupedPage(
      children: [
        if (about != null || short != null)
          StoreSectionCard(
            title: l10n.storeAboutTitle,
            child: about != null
                ? StoreHtml(html: about)
                : Text(short!, style: storeBodyStyle(context)),
          ),
        _StatsGrid(stats: stats),
        if (profile.hasPolicies)
          StoreSectionCard(
            title: l10n.storePoliciesTitle,
            child: Column(
              children: [
                if (profile.shippingPolicyHtml case final html?)
                  _PolicySummary(
                    icon: Icons.local_shipping_outlined,
                    title: l10n.storeShippingPolicy,
                    html: html,
                    onTap: onPolicies,
                  ),
                if (profile.shippingPolicyHtml != null &&
                    profile.refundPolicyHtml != null)
                  Divider(height: 1, thickness: 1, color: context.hairline),
                if (profile.refundPolicyHtml case final html?)
                  _PolicySummary(
                    icon: Icons.replay,
                    title: l10n.storeRefundPolicy,
                    html: html,
                    onTap: onPolicies,
                  ),
              ],
            ),
          ),
        if (categories.isNotEmpty)
          StoreSectionCard(
            title: l10n.storeCategoriesTitle,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in categories)
                  StorePill(
                    label: category.name,
                    onTap: () => onCategory(category),
                  ),
              ],
            ),
          ),
        if (onCall case final call?)
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: call,
              icon: const Icon(Icons.phone_outlined, size: 20),
              label: Text(
                l10n.storeCallVendor(store.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }
}

/// Figma 13's Policies tab: the seller's shipping and refund policies in full,
/// drawn by the native CMS renderer; their links open app screens.
class StorePoliciesTab extends StatelessWidget {
  const StorePoliciesTab({super.key, required this.profile});

  final StoreProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _GroupedPage(
      children: [
        if (profile.shippingPolicyHtml case final html?)
          StoreSectionCard(
            icon: Icons.local_shipping_outlined,
            title: l10n.storeShippingPolicy,
            child: StoreHtml(html: html),
          ),
        if (profile.refundPolicyHtml case final html?)
          StoreSectionCard(
            icon: Icons.replay,
            title: l10n.storeRefundPolicy,
            child: StoreHtml(html: html),
          ),
      ],
    );
  }
}

/// The body copy of the About and policy texts (`--hm-subtle` on white).
TextStyle storeBodyStyle(BuildContext context) => TextStyle(
  fontSize: 14,
  height: 20 / 14,
  color: context.isDarkMode ? const Color(0xFFAEB6C2) : const Color(0xFF535D70),
);

/// A seller's HTML (About, a policy) drawn natively; its links open the
/// matching app screen, the browser only for pages the app has no screen for.
class StoreHtml extends ConsumerWidget {
  const StoreHtml({super.key, required this.html});

  final String html;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocks = CmsDocument.parse(html);
    return CmsHtmlView(
      blocks: blocks,
      compact: true,
      mediaBase: Uri.parse(ref.read(appConfigProvider).graphqlEndpoint).origin,
      onLink: (href) => openCmsHref(context, ref, href),
    );
  }
}

/// The light grey page the 13b cards sit on, stretched to the bottom of the
/// screen when the content is short.
class _GroupedPage extends StatelessWidget {
  const _GroupedPage({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: groupedPageColor(context),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A white rounded card with a title (Figma "card/…").
class StoreSectionCard extends StatelessWidget {
  const StoreSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
  });

  final String title;
  final Widget child;

  /// A leading icon tile, as the policy rows have.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final heading = Text(
      title,
      style: TextStyle(
        fontSize: 16,
        height: 22 / 16,
        fontWeight: FontWeight.w600,
        color: context.scaffoldHeading,
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: groupCardColor(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (icon == null)
            heading
          else
            Row(
              children: [
                _IconTile(icon: icon!),
                const SizedBox(width: 12),
                Expanded(child: heading),
              ],
            ),
          SizedBox(height: icon == null ? 8 : 12),
          child,
        ],
      ),
    );
  }
}

/// The accent-tinted 36 pt square behind a policy's icon.
class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: context.isDarkMode ? Colors.white10 : AppColors.accentSubtle,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: 18, color: AppColors.accentStrong),
  );
}

/// One policy in the About tab's "Store policies" card: its title and the
/// start of its text; a tap opens the Policies tab.
class _PolicySummary extends StatelessWidget {
  const _PolicySummary({
    required this.icon,
    required this.title,
    required this.html,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String html;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final excerpt = CmsDocument.plainText(CmsDocument.parse(html));
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconTile(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      height: 20 / 14,
                      fontWeight: FontWeight.w600,
                      color: context.scaffoldHeading,
                    ),
                  ),
                  if (excerpt.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      excerpt,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: storeBodyStyle(
                        context,
                      ).copyWith(fontSize: 12, height: 16 / 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One figure of a store: its value (a rating gets the star) and label.
class StoreStat {
  const StoreStat(this.value, this.label) : rating = null;

  const StoreStat.rating(double this.rating, this.label) : value = '';

  final String value;
  final String label;
  final double? rating;

  /// The value, in [style] — a rating as "4.8 ★".
  Widget valueText(TextStyle style, {int maxLines = 1}) => rating == null
      ? Text(
          value,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: style,
        )
      : Text.rich(
          ratingSpan(
            rating!,
            size: (style.fontSize ?? 16) * 0.9,
            color: style.color ?? AppColors.inkHeading,
          ),
          maxLines: 1,
          style: style,
        );
}

/// The About tab's figures as white tiles, two to a row.
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final List<StoreStat> stats;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < stats.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _StatTile(stat: stats[i])),
              const SizedBox(width: 8),
              Expanded(
                child: i + 1 < stats.length
                    ? _StatTile(stat: stats[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final StoreStat stat;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: groupCardColor(context),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        stat.valueText(
          TextStyle(
            fontSize: 16,
            height: 22 / 16,
            fontWeight: FontWeight.w600,
            color: context.scaffoldHeading,
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 2),
        Text(
          stat.label,
          style: TextStyle(
            fontSize: 12,
            height: 16 / 12,
            color: context.scaffoldMuted,
          ),
        ),
      ],
    ),
  );
}
