import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/routes.dart';
import '../../../app/shell/hub_scaffold.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/theme_x.dart';
import '../../../core/config/app_config.dart';
import '../../../core/store/store_controller.dart';
import '../../../core/store/store_urls.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/grouped_list.dart';
import '../../../core/widgets/hub_icon_button.dart';
import '../../../core/widgets/web_view_screen.dart';
import '../../../l10n/l10n.dart';
import '../domain/cms_document.dart';
import '../domain/cms_page.dart';
import 'cms_navigation.dart';
import 'cms_providers.dart';
import 'widgets/cms_html_view.dart';
import '../../../app/theme/hub_icons.dart';

/// A storefront CMS page drawn natively (Figma 28 "Content page"): About,
/// the policies, customer service — whatever an admin publishes under
/// Content › Pages, in the active store view's language.
///
/// Opened by CMS [identifier] (`cmsPage`) or by a storefront [url] path
/// (`route`), e.g. from a footer link or a deep link. The page's `<h2>`s
/// become jump chips; its links open the matching app screen (see
/// [openCmsHref]). There is no "Last updated" line: `CmsPage` has no date.
class CmsPageScreen extends ConsumerStatefulWidget {
  const CmsPageScreen({super.key, this.identifier, this.url, this.title});

  final String? identifier;

  /// Store-relative path, e.g. `privacy-policy-cookie-restriction-mode`.
  final String? url;

  /// Shown in the app bar until the page (and its own title) loads.
  final String? title;

  @override
  ConsumerState<CmsPageScreen> createState() => _CmsPageScreenState();
}

class _CmsPageScreenState extends ConsumerState<CmsPageScreen> {
  final Map<int, GlobalKey> _keys = <int, GlobalKey>{};
  int? _activeSection;

  CmsPageRef get _pageRef => (identifier: widget.identifier, url: widget.url);

  GlobalKey _keyFor(int index) =>
      _keys.putIfAbsent(index, () => GlobalKey(debugLabel: 'cms-$index'));

  void _scrollTo(int index) {
    final target = _keys[index]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }

  Future<void> _share(CmsPage page) async {
    final l10n = AppLocalizations.of(context);
    final path = page.urlKey.isNotEmpty ? page.urlKey : (widget.url ?? '');
    final url = storeUrl(ref.read(storeControllerProvider), path);
    if (url == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
      return;
    }
    await SharePlus.instance.share(
      ShareParams(text: '${page.displayTitle}\n$url'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final page = ref.watch(cmsPageProvider(_pageRef));
    final loaded = page.valueOrNull;
    final title = (loaded != null && loaded.displayTitle.isNotEmpty)
        ? loaded.displayTitle
        : (widget.title ?? '');

    return HubScaffold(
      currentTab: AppTab.account,
      // Figma: a pushed page, no tab bar.
      showTabBar: false,
      appBar: subpageAppBar(
        context,
        title,
        // The 1 px rule under the bar of the white content page (Figma 28).
        divider: true,
        actions: [
          if (loaded != null)
            HubIconButton(
              icon: HubIcons.share2,
              tooltip: l10n.actionShare,
              onPressed: () => _share(loaded),
            ),
        ],
      ),
      body: AsyncValueView<CmsPage?>(
        value: page,
        onRetry: () => ref.invalidate(cmsPageProvider(_pageRef)),
        data: (p) => p == null ? _notFound(l10n) : _content(p),
      ),
    );
  }

  Widget _content(CmsPage page) {
    final blocks = page.blocks;
    final sections = CmsDocument.sections(blocks);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sections.isNotEmpty) ...[
            _SectionChips(
              sections: sections,
              active: _activeSection,
              onTap: (index) {
                setState(() => _activeSection = index);
                _scrollTo(index);
              },
            ),
            const SizedBox(height: 16),
          ],
          CmsHtmlView(
            page: true,
            blocks: blocks,
            blockKeys: {
              for (var i = 0; i < blocks.length; i++)
                if (blocks[i] is CmsHeading) i: _keyFor(i),
            },
            mediaBase: Uri.parse(
              ref.read(appConfigProvider).graphqlEndpoint,
            ).origin,
            onLink: (href) => openCmsHref(
              context,
              ref,
              href,
              onAnchor: (anchor) {
                final index = CmsDocument.anchorIndex(blocks, anchor);
                if (index != null) _scrollTo(index);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// No CMS page at this address. A URL may still be a real storefront page
  /// the app has no screen for, so offer it in the in-app browser.
  Widget _notFound(AppLocalizations l10n) {
    final path = widget.url?.trim() ?? '';
    final web = path.isEmpty
        ? null
        : storeUrl(ref.read(storeControllerProvider), path);
    return EmptyState(
      icon: HubIcons.link2Off,
      title: l10n.linkNotFoundTitle,
      body: l10n.linkNotFoundBody,
      action: web == null
          ? null
          : OutlinedButton(
              onPressed: () => context.push(
                AppRoutes.webview,
                extra: WebViewArgs(url: web, title: widget.title ?? ''),
              ),
              child: Text(l10n.webviewOpenInBrowser),
            ),
    );
  }
}

/// Horizontal jump chips for the page's sections (Figma 28).
class _SectionChips extends StatelessWidget {
  const _SectionChips({
    required this.sections,
    required this.active,
    required this.onTap,
  });

  final List<CmsSection> sections;
  final int? active;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final current = active ?? sections.first.index;
    // A page has a handful of sections, so the row is built whole.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _chip(context, sections[i], sections[i].index == current),
          ],
        ],
      ),
    );
  }

  /// Figma `on-this-page` chip: 28 px (12 / 6 px of padding), the title in
  /// EN/Caption Strong — navy with white when it is the section in view, the
  /// page's grey with ink otherwise.
  Widget _chip(BuildContext context, CmsSection section, bool selected) {
    final t = AppTextStyles.of(context);
    return Material(
      color: selected
          ? AppColors.brandPrimary
          : (context.isDarkMode ? Colors.white10 : AppColors.surfaceSubtle),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(section.index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            section.title,
            maxLines: 1,
            style: t.captionStrong.copyWith(
              color: selected ? Colors.white : context.scaffoldHeading,
            ),
          ),
        ),
      ),
    );
  }
}
