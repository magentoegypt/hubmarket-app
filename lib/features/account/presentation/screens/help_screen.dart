import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/app_info.dart';
import '../../../../core/config/store_contact.dart';
import '../../../../core/config/store_features.dart';
import '../../../../core/util/launch.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../l10n/l10n.dart';
import '../../../cms/domain/faq.dart';
import '../../../cms/presentation/cms_navigation.dart';
import '../../../cms/presentation/cms_providers.dart';
import '../../../returns/presentation/returns_providers.dart';
import '../help_faq.dart';
import '../widgets/contact_form_card.dart';
import '../widgets/faq_tile.dart';
import '../../../../app/theme/hub_icons.dart';

/// Help centre (Figma 27): a search over the FAQ, the contact channels the
/// store publishes, the FAQ topics, the contact form and the About & legal
/// pages.
///
/// Everything is backend-driven: the FAQ comes from the CMS block
/// `hm_app_faq` (the storefront has no FAQ page) with the bundled FAQ as the
/// fallback; channels from [storeContactProvider]; the form from core
/// `contactUs` when `contact_enabled` is on; the legal rows from the footer
/// block `hm_footer_legal`.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    if (!await launchExternalUri(uri)) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final contact = ref.watch(storeContactProvider);
    final features =
        ref.watch(storeFeaturesProvider).valueOrNull ?? StoreFeatures.none;
    final legal = ref.watch(legalLinksProvider).valueOrNull ?? const [];
    final version = ref
        .watch(appVersionProvider)
        .maybeWhen(data: (v) => v, orElse: () => null);
    final topics =
        ref.watch(cmsFaqProvider).valueOrNull ??
        bundledHelpFaq(
          l10n,
          returnsInApp: ref.watch(returnsAvailableProvider),
        );

    final channels = <Widget>[
      if (contact.whatsapp != null)
        _ContactTile(
          icon: HubIcons.messageCircle,
          tint: const Color(0xFFE8F7EE),
          color: const Color(0xFF15803D),
          label: l10n.helpWhatsApp,
          // The service hours the admin set (`hmAppConfig.contact.hours`);
          // no hours claim without them.
          caption: contact.hours.trim().isEmpty ? null : contact.hours.trim(),
          onTap: () => _open(Uri.parse(contact.whatsapp!)),
        ),
      if (contact.phone != null)
        _ContactTile(
          icon: HubIcons.phone,
          tint: AppColors.surfaceTint,
          color: const Color(0xFF1D4ED8),
          label: l10n.helpCallUs,
          caption: contact.phoneDisplay ?? contact.phone!,
          onTap: () => _open(Uri(scheme: 'tel', path: contact.phone)),
        ),
      if (contact.email != null)
        _ContactTile(
          icon: HubIcons.mail,
          tint: const Color(0xFFFFF1E6),
          color: AppColors.accentStrong,
          label: l10n.helpEmailUs,
          caption: contact.email!,
          onTap: () => _open(mailtoUri(contact.email!)),
        ),
    ];

    final titled = topics.where((t) => t.title != null).toList();
    final loose = [
      for (final t in topics)
        if (t.title == null) ...t.items,
    ];
    final results = _query.isEmpty
        ? const <FaqItem>[]
        : [
            for (final t in topics)
              for (final item in t.items)
                if (item.matches(_query)) item,
          ];

    return HubScaffold(
      currentTab: AppTab.account,
      appBar: subpageAppBar(context, l10n.helpCentreTitle),
      body: ColoredBox(
        color: groupedPageColor(context),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            Text(
              l10n.helpHowCanWeHelp,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.scaffoldHeading,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              onChanged: (v) =>
                  setState(() => _query = v.trim().toLowerCase()),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.helpSearchHint,
                prefixIcon: const Icon(HubIcons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(HubIcons.x),
                        tooltip: l10n.searchClearField,
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: groupCardColor(context),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: _fieldBorder(context),
                enabledBorder: _fieldBorder(context),
              ),
            ),
            if (channels.isNotEmpty) ...[
              const SizedBox(height: 16),
              // Three equal slots as in the frame, so a store publishing one
              // channel shows one tile rather than a full-width banner. Equal
              // heights too: a tile without a caption (WhatsApp with no hours
              // set) keeps its neighbours' size.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: i < channels.length
                            ? channels[i]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (_query.isNotEmpty) ...[
              GroupLabel(l10n.helpFrequentlyAsked),
              if (results.isEmpty)
                GroupCard(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      l10n.helpNoResults,
                      style: TextStyle(color: context.scaffoldMuted),
                    ),
                  ],
                )
              else
                FaqAccordion(items: results),
            ] else ...[
              if (titled.isNotEmpty) ...[
                GroupLabel(l10n.helpPopularTopics),
                GroupCard(
                  children: [
                    for (final topic in titled)
                      GroupRow(
                        icon: faqTopicIcon(topic.icon),
                        label: topic.title!,
                        onTap: () =>
                            context.push(AppRoutes.helpTopic, extra: topic),
                      ),
                  ],
                ),
              ],
              if (loose.isNotEmpty) ...[
                GroupLabel(l10n.helpFrequentlyAsked),
                FaqAccordion(items: loose),
              ],
            ],
            if (features.contactEnabled) ...[
              const SizedBox(height: 20),
              const ContactFormCard(),
            ],
            GroupLabel(l10n.helpAboutLegal),
            GroupCard(
              children: [
                GroupRow(
                  icon: HubIcons.info,
                  label: l10n.accountAbout,
                  onTap: () => context.push(AppRoutes.about),
                ),
                for (final link in legal)
                  GroupRow(
                    icon: legalLinkIcon(link),
                    label: link.label,
                    onTap: () => openStorePageLink(context, ref, link),
                  ),
              ],
            ),
            if (version != null) ...[
              const SizedBox(height: 18),
              Center(
                child: Text(
                  l10n.helpAppVersion(version),
                  style: TextStyle(fontSize: 12, color: context.scaffoldFaint),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  OutlineInputBorder _fieldBorder(BuildContext context) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: context.hairline),
  );
}

/// One contact channel card: a tinted icon chip, the channel and a caption.
class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.icon,
    required this.tint,
    required this.color,
    required this.label,
    required this.caption,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final Color color;
  final String label;

  /// The number, address or hours under the label; none when null.
  final String? caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: groupCardColor(context),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 12),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.scaffoldHeading,
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 4),
                Text(
                  caption!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: context.scaffoldMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
