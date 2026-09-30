import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/shell/hub_scaffold.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/theme_x.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/grouped_list.dart';
import '../../../l10n/l10n.dart';
import '../../account/presentation/order_format.dart';
import '../domain/store_credit.dart';
import 'buy_credit_card.dart';
import 'store_credit_providers.dart';

/// Figma `text/subtle` (#535D70): the transaction's second line.
const Color _inkSubtle = Color(0xFF535D70);

/// 20d My credit: the balance on the navy card, whether it can be spent at
/// checkout, "Buy credit" when the store sells credit ([BuyCreditCard]), and
/// every transaction newest first (`hmStoreCredit`, paged as the list
/// scrolls), each opening the order it records.
///
/// Not built from the frame: the "All" link (this list already pages through
/// every transaction).
class MyCreditScreen extends ConsumerStatefulWidget {
  const MyCreditScreen({super.key});

  @override
  ConsumerState<MyCreditScreen> createState() => _MyCreditScreenState();
}

class _MyCreditScreenState extends ConsumerState<MyCreditScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      ref.read(myCreditControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(myCreditControllerProvider);
    // Shown once it has loaded, and only when the store sells credit.
    final topUp = ref.watch(storeCreditTopUpProvider).valueOrNull;
    return HubScaffold(
      currentTab: AppTab.account,
      appBar: subpageAppBar(context, l10n.myCreditTitle),
      body: ColoredBox(
        color: groupedPageColor(context),
        child: AsyncValueView<MyCreditState>(
          value: state,
          onRetry: () => ref.invalidate(myCreditControllerProvider),
          data: (data) => RefreshIndicator(
            onRefresh: () {
              ref.invalidate(storeCreditTopUpProvider);
              return ref.refresh(myCreditControllerProvider.future);
            },
            child: ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                CreditBalanceCard(account: data.account),
                if (topUp != null) ...[
                  const SizedBox(height: 16),
                  BuyCreditCard(key: ObjectKey(topUp), topUp: topUp),
                ],
                const SizedBox(height: 16),
                Text(
                  l10n.myCreditTransactions,
                  style: AppTextStyles.of(
                    context,
                  ).title.copyWith(color: context.scaffoldHeading),
                ),
                const SizedBox(height: 8),
                if (data.account.transactions.isEmpty)
                  const _NoTransactions()
                else
                  _TransactionsCard(transactions: data.account.transactions),
                if (data.loadingMore)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The navy balance card: "Credit balance", the amount, and whether it can be
/// spent at checkout (the website's customer-group rule).
class CreditBalanceCard extends StatelessWidget {
  const CreditBalanceCard({super.key, required this.account});

  final StoreCreditAccount account;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.brandPrimary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.card_giftcard_outlined,
                size: 18,
                color: AppColors.accentOnDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.myCreditBalanceLabel,
                  style: t.captionStrong.copyWith(
                    color: AppColors.borderStrong,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // "AED 120.00" keeps its order inside the Arabic layout.
          Text(
            account.balance.formatted(),
            textDirection: TextDirection.ltr,
            style: t.display.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            account.canUseAtCheckout
                ? l10n.myCreditUseAtCheckout
                : l10n.myCreditNotUsable,
            style: t.caption.copyWith(color: AppColors.borderStrong),
          ),
        ],
      ),
    );
  }
}

class _NoTransactions extends StatelessWidget {
  const _NoTransactions();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: groupCardColor(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.myCreditNoTransactions,
            style: t.bodyStrong.copyWith(color: context.scaffoldHeading),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.myCreditNoTransactionsBody,
            style: t.caption.copyWith(color: context.scaffoldMuted),
          ),
        ],
      ),
    );
  }
}

class _TransactionsCard extends StatelessWidget {
  const _TransactionsCard({required this.transactions});

  final List<StoreCreditTransaction> transactions;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: groupCardColor(context),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < transactions.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 1,
              color: context.isDarkMode
                  ? Colors.white12
                  : AppColors.borderSubtle,
            ),
          CreditTransactionRow(transaction: transactions[i]),
        ],
      ],
    ),
  );
}

/// One transaction: the kind's icon, the server's label, description and
/// date, then the signed amount and the balance it left. A transaction that
/// records one of the customer's orders opens it (`/orders/<number>`).
class CreditTransactionRow extends StatelessWidget {
  const CreditTransactionRow({super.key, required this.transaction});

  final StoreCreditTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final orderNumber = transaction.orderNumber;
    final content = _content(context);
    if (orderNumber == null) return content;
    return Semantics(
      button: true,
      hint: AppLocalizations.of(context).myCreditOpenOrder(orderNumber),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => context.push(AppRoutes.orderByNumber(orderNumber)),
          child: content,
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final tx = transaction;
    final date = tx.createdAt.isEmpty ? '' : orderFmtDate(tx.createdAt, locale);
    final sign = tx.isCredit ? '+' : '\u2212';
    final positive = context.isDarkMode
        ? AppColors.success
        : AppColors.successStrong;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KindIcon(kind: tx.kind),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.typeLabel,
                  style: t.bodyStrong.copyWith(color: context.scaffoldHeading),
                ),
                if (tx.description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    tx.description!,
                    style: t.caption.copyWith(
                      color: context.isDarkMode
                          ? context.scaffoldMuted
                          : _inkSubtle,
                    ),
                  ),
                ],
                if (date.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    date,
                    style: t.micro.copyWith(color: context.scaffoldMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$sign ${tx.magnitude.formatted()}',
                textDirection: TextDirection.ltr,
                style: t.bodyStrong.copyWith(
                  color: tx.isCredit ? positive : context.scaffoldHeading,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.myCreditBalanceAfter(
                  '\u2066${tx.balanceAfter.formatted()}\u2069',
                ),
                style: t.micro.copyWith(color: context.scaffoldMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The 36px tinted disc of Figma 20d: refund green, checkout blue, top-up
/// amber, a deduction grey.
class _KindIcon extends StatelessWidget {
  const _KindIcon({required this.kind});

  final StoreCreditTransactionKind kind;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, Color fill) = switch (kind) {
      StoreCreditTransactionKind.refunded => (
        Icons.replay_rounded,
        AppColors.successStrong,
        AppColors.successSubtle,
      ),
      StoreCreditTransactionKind.spent => (
        Icons.shopping_cart_outlined,
        AppColors.info,
        AppColors.infoSubtle,
      ),
      StoreCreditTransactionKind.added => (
        Icons.add_rounded,
        AppColors.warning,
        AppColors.warningSubtle,
      ),
      StoreCreditTransactionKind.deducted => (
        Icons.remove_rounded,
        AppColors.inkMuted,
        AppColors.surfaceMuted,
      ),
    };
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Icon(icon, size: 18, color: color),
    );
  }
}
