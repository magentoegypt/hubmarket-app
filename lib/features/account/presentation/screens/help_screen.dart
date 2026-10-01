import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
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
    final t = AppTextStyles.of(context);
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
          tint: AppColors.successSubtle,
          color: AppColors.successStrong,
          label: l10n.helpWhatsApp,
          // The service hours the admin set (`hmAppConfig.contact.hours`);
          // no hours claim without them.
          caption: contact.hours.trim().isEmpty ? null : contact.hours.trim(),
          onTap: () => _open(Uri.parse(contact.whatsapp!)),
        ),
      if (contact.phone != null)
        _ContactTile(
          icon: HubIcons.phone,
          tint: AppColors.infoSubtle,
          color: AppColors.info,
          label: l10n.helpCallUs,
          caption: contact.phoneDisplay ?? contact.phone!,
          ltrCaption: true,
          onTap: () => _open(Uri(scheme: 'tel', path: contact.phone)),
        ),
      if (contact.email != null)
        _ContactTile(
          icon: HubIcons.mail,
          tint: AppColors.warningSubtle,
          color: AppColors.warning,
          label: l10n.helpEmailUs,
          caption: contact.email!,
          ltrCaption: true,
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
          // Figma body: 14 under the bar, 18 between its parts.
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            _SearchField(
              controller: _search,
              label: l10n.helpHowCanWeHelp,
              hint: l10n.helpSearchHint,
              clearTooltip: l10n.searchClearField,
              showClear: _query.isNotEmpty,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              onClear: () {
                _search.clear();
                setState(() => _query = '');
              },
            ),
            if (channels.isNotEmpty) ...[
              const SizedBox(height: 18),
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
                  padding: const EdgeInsets.all(14),
                  children: [
                    Text(
                      l10n.helpNoResults,
                      style: t.body.copyWith(color: context.scaffoldMuted),
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
              const SizedBox(height: 18),
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
                  style: t.caption.copyWith(color: context.scaffoldMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "How can we help?": the label (EN/Caption Strong) over a white 52 px search
/// field — a 20 px search icon, EN/Body text, the hint in `text/muted` — with a
/// clear button once something is typed.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.clearTooltip,
    required this.showClear,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String clearTooltip;
  final bool showClear;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    // A 52 px field whatever the locale's line height (EN 20, AR 22).
    final vertical = (52 - t.body.fontSize! * t.body.height!) / 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: t.captionStrong.copyWith(color: context.scaffoldHeading),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          style: t.body.copyWith(color: AppColors.inkHeading),
          cursorColor: AppColors.brandPrimary,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: t.body.copyWith(color: AppColors.inkMuted),
            contentPadding: EdgeInsetsDirectional.fromSTEB(
              0,
              vertical,
              showClear ? 0 : 16,
              vertical,
            ),
            prefixIcon: const Padding(
              padding: EdgeInsetsDirectional.only(start: 16, end: 10),
              child: Icon(HubIcons.search, size: 20, color: AppColors.inkMuted),
            ),
            prefixIconConstraints: const BoxConstraints(),
            suffixIcon: showClear
                ? IconButton(
                    icon: const Icon(HubIcons.x, size: 20),
                    tooltip: clearTooltip,
                    color: AppColors.inkMuted,
                    onPressed: onClear,
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

/// One contact channel card (Figma `contact/…`): a 40 px tinted icon chip, the
/// channel (EN/Caption Strong) and a caption (EN/Micro, muted).
class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.icon,
    required this.tint,
    required this.color,
    required this.label,
    required this.caption,
    required this.onTap,
    this.ltrCaption = false,
  });

  final IconData icon;
  final Color tint;
  final Color color;
  final String label;

  /// The number, address or hours under the label; none when null.
  final String? caption;

  /// A number or an address reads left to right in Arabic too.
  final bool ltrCaption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Material(
      color: groupCardColor(context),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
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
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: t.captionStrong.copyWith(color: context.scaffoldHeading),
              ),
              if (caption != null) ...[
                const SizedBox(height: 6),
                Text(
                  caption!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textDirection: ltrCaption ? TextDirection.ltr : null,
                  style: t.micro.copyWith(color: context.scaffoldMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
