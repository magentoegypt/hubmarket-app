import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../cms/domain/faq.dart';

/// The FAQ shipped with the app, used until the store publishes its own in
/// the CMS block `hm_app_faq` (see `FaqDocument`).
///
/// It only states what holds on every backend: cash-on-delivery-style methods
/// listed at checkout (no card gateway, no Tabby/Tamara), cancellation only
/// where the store allows it, and returns in the app only when [returnsInApp]
/// (the store has HubApp's returns), otherwise the Help-centre route. Store
/// pages and seller rows depend on HubApp too, so no answer promises them.
List<FaqTopic> bundledHelpFaq(
  AppLocalizations l10n, {
  bool returnsInApp = false,
}) => [
  FaqTopic(
    title: l10n.helpTopicOrders,
    icon: 'orders',
    items: [
      FaqItem.text(l10n.helpQ4, l10n.helpA4),
      FaqItem.text(l10n.helpQ5, l10n.helpA5),
      FaqItem.text(l10n.helpQ7, l10n.helpA7),
      FaqItem.text(l10n.helpQCancel, l10n.helpACancel),
    ],
  ),
  FaqTopic(
    title: l10n.helpTopicReturns,
    icon: 'returns',
    items: [
      FaqItem.text(
        l10n.helpQ8,
        returnsInApp ? l10n.helpA8Returns : l10n.helpA8,
      ),
    ],
  ),
  FaqTopic(
    title: l10n.helpTopicPayments,
    icon: 'payments',
    items: [FaqItem.text(l10n.helpQPayments, l10n.helpAPayments)],
  ),
  FaqTopic(
    title: l10n.helpTopicAccount,
    icon: 'account',
    items: [
      FaqItem.text(l10n.helpQGuest, l10n.helpAGuest),
      FaqItem.text(l10n.helpQLanguage, l10n.helpALanguage),
      FaqItem.text(l10n.helpQDeleteAccount, l10n.helpADeleteAccount),
    ],
  ),
  FaqTopic(
    title: l10n.helpTopicSelling,
    icon: 'selling',
    items: [
      FaqItem.text(l10n.helpQ1, l10n.helpA1),
      FaqItem.text(l10n.helpQ2, l10n.helpA2),
      FaqItem.text(l10n.helpQSell, l10n.helpASell),
    ],
  ),
];

/// Icon for a FAQ topic's `data-icon` key; the generic help icon otherwise.
IconData faqTopicIcon(String? key) => switch (key) {
  'orders' => Icons.inventory_2_outlined,
  'delivery' => Icons.local_shipping_outlined,
  'returns' => Icons.replay,
  'payments' => Icons.credit_card_outlined,
  'account' => Icons.person_outline,
  'selling' => Icons.storefront_outlined,
  _ => Icons.help_outline,
};
