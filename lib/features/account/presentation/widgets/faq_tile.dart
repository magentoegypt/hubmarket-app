import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../cms/domain/faq.dart';
import '../../../cms/presentation/cms_navigation.dart';
import '../../../cms/presentation/widgets/cms_html_view.dart';

/// FAQ questions as an accordion inside a [GroupCard]. Answers render their
/// CMS markup natively, so links in an answer open the matching screen.
class FaqAccordion extends StatelessWidget {
  const FaqAccordion({super.key, required this.items, this.expandFirst = false});

  final List<FaqItem> items;

  /// Open the first answer — a topic page leads with its first question.
  final bool expandFirst;

  @override
  Widget build(BuildContext context) => GroupCard(
    children: [
      for (var i = 0; i < items.length; i++)
        FaqTile(
          key: ValueKey(items[i].question),
          item: items[i],
          initiallyExpanded: expandFirst && i == 0,
        ),
    ],
  );
}

class FaqTile extends ConsumerWidget {
  const FaqTile({super.key, required this.item, this.initiallyExpanded = false});

  final FaqItem item;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 14),
      childrenPadding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 14),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      iconColor: context.scaffoldMuted,
      collapsedIconColor: context.scaffoldMuted,
      title: Text(
        item.question,
        style: AppTextStyles.of(
          context,
        ).bodyStrong.copyWith(color: context.scaffoldHeading),
      ),
      children: [
        CmsHtmlView(
          blocks: item.answer,
          compact: true,
          mediaBase: Uri.parse(
            ref.read(appConfigProvider).graphqlEndpoint,
          ).origin,
          onLink: (href) => openCmsHref(context, ref, href),
        ),
      ],
    );
  }
}
