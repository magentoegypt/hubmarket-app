import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/shell/hub_scaffold.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/hub_icons.dart';
import '../../../app/theme/theme_x.dart';
import '../../../core/config/store_contact.dart';
import '../../../core/config/store_features.dart';
import '../../../core/store/store_controller.dart';
import '../../../core/store/store_urls.dart';
import '../../../core/util/launch.dart';
import '../../../core/widgets/grouped_list.dart';
import '../../../core/widgets/web_view_screen.dart';
import '../../../l10n/l10n.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../catalog/domain/money.dart';
import '../../notifications/presentation/notification_settings_controller.dart';
import '../../returns/presentation/returns_providers.dart';
import '../../store_credit/domain/credit_money.dart';
import '../../store_credit/presentation/store_credit_providers.dart';
import '../../wishlist/presentation/wishlist_controller.dart';
import '../data/account_repository.dart';
import '../data/guest_order_store.dart';
import 'account_overview.dart';
import 'widgets/profile_avatar.dart';

/// The Account tab (Figma 20).
///
/// Signed in: the customer's header pinned at the top (avatar, name, what they
/// have, Edit profile), then four quick tiles (Orders, Wishlist, Returns,
/// Addresses), the Shopping stats card, and the grouped lists — My account,
/// Preferences, Privacy, Help — ending in Sign out. Every count, figure and row
/// comes from what the app and the backend really have; what they cannot
/// give is not drawn:
///
/// * the Returns tile and My returns need HubApp's `returns` flag;
/// * the stats card needs the whole order history ([AccountOrdersOverview]);
/// * Stored payment methods needs a card in the vault, My credit store credit,
///   Notifications FCM, Newsletter the store's newsletter switch, WhatsApp the
///   number the store publishes;
/// * the frame's "Country & currency" row is left out: Hub Market serves one
///   market (UAE, AED), so there is nothing to choose and nowhere to go.
///
/// Signed out: sign in / create account, and the guest's way back to their
/// orders — the lookup by order number, e-mail and last name (Figma 26) and,
/// once this device has placed or looked one up, My Orders (see
/// `GuestOrderStore`).
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    if (auth.status == AuthStatus.unknown) {
      return const HubScaffold(
        currentTab: AppTab.account,
        showSearch: false,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!auth.isAuthenticated) {
      return const HubScaffold(
        currentTab: AppTab.account,
        showSearch: false,
        body: _Guest(),
      );
    }
    return HubScaffold(
      currentTab: AppTab.account,
      appBar: _ProfileHeader(name: auth.customer?.fullName ?? ''),
      body: _Authenticated(
        onSignOut: () => ref.read(authControllerProvider.notifier).logout(),
      ),
    );
  }
}

/// The frame's header: the white "profile" block under the status bar — a 56 px
/// avatar, the name (EN/Heading 2) over "7 orders · 5 wishlist items" (EN/Caption,
/// muted) and the Edit profile pill. It is the page's app bar, so it stays put
/// while the page scrolls.
class _ProfileHeader extends ConsumerWidget implements PreferredSizeWidget {
  const _ProfileHeader({required this.name});

  final String name;

  @override
  Size get preferredSize => const Size.fromHeight(82);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    // The order count joins once it is known: no "0 orders" while it loads.
    final orders = ref.watch(customerOrderCountProvider).valueOrNull;
    final wishlist = ref.watch(
      wishlistControllerProvider.select((s) => s.entries.length),
    );
    final subtitle = [
      if (orders != null) l10n.accountOrdersCount(orders),
      l10n.accountWishlistItemsCount(wishlist),
    ].join(' · ');
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Material(
        color: Colors.white,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 82,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  ProfileAvatar(name: name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.heading2.copyWith(
                            color: AppColors.inkHeading,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.caption.copyWith(color: AppColors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _EditProfilePill(
                    label: l10n.accountEditProfile,
                    onTap: () => context.push(AppRoutes.editProfile),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Edit profile": a 34 px outlined pill — pencil, then EN/Caption Strong.
class _EditProfilePill extends StatelessWidget {
  const _EditProfilePill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(
        side: BorderSide(color: AppColors.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                HubIcons.pencil,
                size: 14,
                color: AppColors.inkHeading,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: t.captionStrong.copyWith(color: AppColors.inkHeading),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Authenticated extends ConsumerWidget {
  const _Authenticated({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final wishlist = ref.watch(
      wishlistControllerProvider.select((s) => s.entries.length),
    );
    final addresses = ref.watch(addressesProvider).valueOrNull?.length;
    final overview = ref.watch(accountOrdersOverviewProvider).valueOrNull;
    final openReturns = ref.watch(openReturnsCountProvider).valueOrNull;
    final activeLocale = ref.watch(
      storeControllerProvider.select((s) => s.activeLocale),
    );
    final languageLabel = activeLocale == 'ar'
        ? l10n.languageArabic
        : l10n.languageEnglish;
    final pushAvailable = ref.watch(pushNotificationsAvailableProvider);
    final newsletterEnabled =
        ref.watch(storeFeaturesProvider).valueOrNull?.newsletterEnabled ??
        false;
    final creditEnabled = ref.watch(storeCreditEnabledProvider);
    final creditBalance = creditEnabled
        ? ref.watch(storeCreditBalanceProvider).valueOrNull?.balance
        : null;
    // "AED 120.00" in a left-to-right isolate, so it keeps its order in RTL.
    final creditValue = creditBalance == null
        ? null
        : '\u2066${creditBalance.ledger}\u2069';
    final returnsAvailable = ref.watch(returnsAvailableProvider);
    final hasSavedCards =
        ref.watch(savedCardsProvider).valueOrNull?.isNotEmpty ?? false;
    final whatsapp = ref.watch(storeContactProvider).whatsapp;
    final sellUrl = storeUrl(
      ref.watch(storeControllerProvider),
      _sellerRegistrationPath,
    );
    final stats = overview?.stats;

    return ColoredBox(
      color: groupedPageColor(context),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          // Quick tiles (Figma `quick-actions`). The Returns tile is the entry
          // to My returns, so it needs the same HubApp flag.
          _QuickTiles(
            tiles: [
              _QuickTile(
                icon: HubIcons.box,
                label: l10n.accountTileOrders,
                caption: overview == null
                    ? null
                    : l10n.accountTileOrdersActive(overview.activeCount),
                onTap: () => context.push(AppRoutes.orders),
              ),
              _QuickTile(
                icon: HubIcons.heart,
                label: l10n.accountStatWishlist,
                caption: l10n.accountTileWishlistItems(wishlist),
                onTap: () => context.go(AppRoutes.wishlist),
              ),
              if (returnsAvailable)
                _QuickTile(
                  icon: HubIcons.rotateCcw,
                  label: l10n.accountTileReturns,
                  caption: openReturns == null
                      ? null
                      : l10n.accountTileReturnsOpen(openReturns),
                  onTap: () => context.push(AppRoutes.returns),
                ),
              _QuickTile(
                icon: HubIcons.mapPin,
                label: l10n.accountTileAddresses,
                caption: addresses == null
                    ? null
                    : l10n.accountTileAddressesSaved(addresses),
                onTap: () => context.push(AppRoutes.addresses),
              ),
            ],
          ),
          if (stats != null) ...[
            const SizedBox(height: 18),
            _StatsCard(stats: stats),
          ],
          GroupLabel(l10n.accountGroupMyAccount),
          GroupCard(
            children: [
              GroupRow(
                icon: HubIcons.user,
                label: l10n.profileTitle,
                onTap: () => context.push(AppRoutes.editProfile),
              ),
              // Stored payment methods only lists cards the vault already
              // holds: no card gateway is wired into the app, so none can be
              // saved here. No cards, no row.
              if (hasSavedCards)
                GroupRow(
                  icon: HubIcons.creditCard,
                  label: l10n.accountStoredPaymentMethods,
                  onTap: () => context.push(AppRoutes.paymentMethods),
                ),
              // My credit, with the balance, once the backend has store credit
              // (HubAppAccount).
              if (creditEnabled)
                GroupRow(
                  icon: HubIcons.gift,
                  label: l10n.myCreditTitle,
                  value: creditValue,
                  valueColor: AppColors.successStrong,
                  onTap: () => context.push(AppRoutes.myCredit),
                ),
              GroupRow(
                icon: HubIcons.star,
                label: l10n.myReviewsTitle,
                onTap: () => context.push(AppRoutes.myReviews),
              ),
              // Both open Notification settings (Figma 20h); each row only
              // when there is something behind it — push needs FCM, the
              // newsletter the store's newsletter switch.
              if (pushAvailable)
                GroupRow(
                  icon: HubIcons.bell,
                  label: l10n.notificationsTitle,
                  onTap: () => context.push(AppRoutes.notificationSettings),
                ),
              if (newsletterEnabled)
                GroupRow(
                  icon: HubIcons.mail,
                  label: l10n.newsletterTitle,
                  onTap: () => context.push(AppRoutes.notificationSettings),
                ),
            ],
          ),
          GroupLabel(l10n.accountGroupPreferences),
          GroupCard(
            children: [
              GroupRow(
                icon: HubIcons.globe,
                label: l10n.languageToggleLabel,
                value: languageLabel,
                onTap: () => context.push(AppRoutes.settings),
              ),
            ],
          ),
          GroupLabel(l10n.accountGroupPrivacy),
          GroupCard(
            children: [
              // Account deletion has to be findable, not merely present: 1.0.0
              // (80) was rejected under Guideline 5.1.1(v) as having no option
              // to delete an account, while the option existed in Settings —
              // reachable only by tapping a row labelled "Language". Figma 20
              // keeps the words "Delete account" on this row, so a customer
              // (or a reviewer) finds it here; Privacy & data holds the action,
              // and Settings keeps its copy too.
              GroupRow(
                icon: HubIcons.shield,
                label: l10n.privacyDataTitle,
                value: l10n.deleteAccountTitle,
                onTap: () => context.push(AppRoutes.privacyData),
              ),
            ],
          ),
          GroupLabel(l10n.accountGroupHelp),
          GroupCard(
            children: [
              GroupRow(
                icon: HubIcons.circleHelp,
                label: l10n.helpCentreTitle,
                onTap: () => context.push(AppRoutes.help),
              ),
              if (whatsapp != null)
                GroupRow(
                  icon: HubIcons.messageCircle,
                  label: l10n.accountContactWhatsApp,
                  onTap: () => _openLink(context, Uri.parse(whatsapp)),
                ),
              // The website's "Sell on Hub Market" link: the seller
              // registration, in the in-app browser.
              if (sellUrl != null)
                GroupRow(
                  icon: HubIcons.store,
                  label: l10n.accountSellOnHubMarket,
                  onTap: () => context.push(
                    AppRoutes.webview,
                    extra: WebViewArgs(
                      url: sellUrl,
                      title: l10n.accountSellOnHubMarket,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          GroupCard(
            children: [
              GroupRow(
                icon: HubIcons.logOut,
                iconColor: AppColors.danger,
                label: l10n.accountLogOut,
                labelColor: AppColors.danger,
                showChevron: false,
                onTap: onSignOut,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The storefront's seller registration (the website header's "Sell on Hub
  /// Market"), relative to the active store view.
  static const String _sellerRegistrationPath = 'marketplace/seller/register';

  static Future<void> _openLink(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    if (!await launchExternalUri(uri)) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
    }
  }
}

/// The row of quick tiles (Figma `quick-actions`): equal slots with 8 px
/// between them, so a store without returns shows three wider ones.
class _QuickTiles extends StatelessWidget {
  const _QuickTiles({required this.tiles});

  final List<_QuickTile> tiles;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < tiles.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(child: tiles[i]),
      ],
    ],
  );
}

/// One tile: a 40 px blush chip with the orange icon, the label (EN/Caption
/// Strong) and the count under it (EN/Micro, muted). The caption is left blank
/// while the count loads, so the tile keeps its height.
class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.caption,
  });

  final IconData icon;
  final String label;
  final String? caption;
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accentSubtle,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: AppColors.accentStrong),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.captionStrong.copyWith(color: context.scaffoldHeading),
              ),
              const SizedBox(height: 6),
              Text(
                caption ?? ' ',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.micro.copyWith(color: context.scaffoldMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Shopping stats" (Figma `shopping-stats`): total spent, orders this year and
/// the average order, three equal columns split by hairlines. Amounts are
/// rounded to whole dirhams, as the frame prints them.
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final ShoppingStats stats;

  static String _whole(Money money) =>
      Money(amount: money.amount.roundToDouble(), currency: money.currency)
          .formatted();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    Widget column(String value, String label, {bool amount = false}) => Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // "AED 1,284" keeps its order inside the Arabic layout.
            textDirection: amount ? TextDirection.ltr : null,
            style: t.title.copyWith(color: context.scaffoldHeading),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: t.micro.copyWith(color: context.scaffoldMuted),
          ),
        ],
      ),
    );
    final rule = Container(
      width: 1,
      height: 32,
      color: context.isDarkMode ? Colors.white12 : AppColors.borderSubtle,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: groupCardColor(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.accountStatsTitle,
            style: t.title.copyWith(color: context.scaffoldHeading),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              column(
                _whole(stats.totalSpent),
                l10n.accountStatsTotalSpent,
                amount: true,
              ),
              const SizedBox(width: 8),
              rule,
              const SizedBox(width: 8),
              column('${stats.ordersThisYear}', l10n.accountStatsOrdersThisYear),
              const SizedBox(width: 8),
              rule,
              const SizedBox(width: 8),
              column(
                _whole(stats.averageOrder),
                l10n.accountStatsAverageOrder,
                amount: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Signed out: sign in / create account, and the guest's way back to their
/// orders. Not in the Figma frames; built from the same pieces.
class _Guest extends ConsumerWidget {
  const _Guest();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final hasGuestOrders = ref.watch(guestOrderStoreProvider).isNotEmpty;
    return ColoredBox(
      color: groupedPageColor(context),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 20),
        children: [
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.surfaceTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                HubIcons.user,
                size: 48,
                color: AppColors.brandPrimary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.accountGuestTitle,
            style: t.heading2.copyWith(color: context.scaffoldHeading),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.accountGuestBody,
            style: t.body.copyWith(color: context.scaffoldMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.push(AppRoutes.signIn),
            child: Text(l10n.authSignInTitle),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.push(AppRoutes.signUp),
            child: Text(l10n.authSignUpTitle),
          ),
          const SizedBox(height: 18),
          GroupCard(
            children: [
              if (hasGuestOrders)
                GroupRow(
                  icon: HubIcons.receiptText,
                  label: l10n.accountOrders,
                  onTap: () => context.push(AppRoutes.orders),
                ),
              GroupRow(
                icon: HubIcons.truck,
                label: l10n.accountTrackOrder,
                onTap: () => context.push(AppRoutes.guestTrackOrder),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
