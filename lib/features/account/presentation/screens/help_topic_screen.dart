import 'package:flutter/material.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../cms/domain/faq.dart';
import '../widgets/faq_tile.dart';

/// One Help centre topic ("Orders & delivery"): its questions as an
/// accordion, the first one open.
class HelpTopicScreen extends StatelessWidget {
  const HelpTopicScreen({super.key, required this.topic});

  final FaqTopic topic;

  @override
  Widget build(BuildContext context) {
    return HubScaffold(
      currentTab: AppTab.account,
      appBar: subpageAppBar(context, topic.title ?? ''),
      body: ColoredBox(
        color: groupedPageColor(context),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [FaqAccordion(items: topic.items, expandFirst: true)],
        ),
      ),
    );
  }
}
