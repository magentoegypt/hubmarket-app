import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/shell/hub_scaffold.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/theme_x.dart';
import '../../../core/app_info.dart';
import '../../../core/config/store_features.dart';
import '../../../core/widgets/customer_avatar.dart';
import '../../../core/store/store_controller.dart';
import '../../../l10n/l10n.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../notifications/presentation/notification_settings_controller.dart';
import '../../wishlist/presentation/wishlist_controller.dart';
import '../data/account_repository.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    final Widget body;
    if (auth.status == AuthStatus.unknown) {
      body = const Center(child: CircularProgressIndicator());
    } else if (auth.isAuthenticated) {
      body = _Authenticated(
        name: auth.customer?.fullName ?? '',
        email: auth.customer?.email ?? '',
        avatarUrl: auth.customer?.avatarUrl,
        onSignOut: () => ref.read(authControllerProvider.notifier).logout(),
      );
    } else {
      body = const _Guest();
    }

    return HubScaffold(
      currentTab: AppTab.account,
      showSearch: false,
      body: body,
    );
  }
}

class _Authenticated extends ConsumerWidget {
  const _Authenticated({
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.onSignOut,
  });

  final String name;
  final String email;
  final String? avatarUrl;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final version = ref.watch(appVersionProvider).maybeWhen(
      data: (v) => v,
      orElse: () => null,
    );
    final orders = ref
        .watch(customerOrderCountProvider)
        .maybeWhen(data: (v) => v, orElse: () => 0);
    final wishlist = ref.watch(
      wishlistControllerProvider.select((s) => s.entries.length),
    );
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

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Page title (Figma 50:21).
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 10),
          child: Text(
            l10n.accountHeading,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: context.scaffoldHeading,
            ),
          ),
        ),
        // User row (Figma 42:8): avatar + name + email + member badge.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              CustomerAvatar(
                name: name,
                avatarUrl: avatarUrl,
                diameter: 64,
                initialsFontSize: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: context.scaffoldHeading,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.scaffoldMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceTint,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '★ ${l10n.accountMember}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const _AccountBand(),
        // Quick stats (Figma 42:17). Vouchers has no backend source → 0.
        IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _StatCell(
                  value: '$orders',
                  label: l10n.accountStatOrders,
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: context.hairline,
                indent: 16,
                endIndent: 16,
              ),
              Expanded(
                child: _StatCell(
                  value: '$wishlist',
                  label: l10n.accountStatWishlist,
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: context.hairline,
                indent: 16,
                endIndent: 16,
              ),
              Expanded(
                child: _StatCell(value: '0', label: l10n.accountStatVouchers),
              ),
            ],
          ),
        ),
        const _AccountBand(),
        // Account group (Figma 110:2 / 42:30 …).
        _AccountTile(
          icon: Icons.person_outline,
          label: l10n.profileTitle,
          onTap: () => context.push(AppRoutes.editProfile),
        ),
        const _TileDivider(),
        _AccountTile(
          icon: Icons.receipt_long_outlined,
          label: l10n.accountOrders,
          onTap: () => context.push(AppRoutes.orders),
        ),
        const _TileDivider(),
        _AccountTile(
          icon: Icons.favorite_border,
          label: l10n.wishlistHeading,
          onTap: () => context.go(AppRoutes.wishlist),
        ),
        const _TileDivider(),
        _AccountTile(
          icon: Icons.location_on_outlined,
          label: l10n.accountAddresses,
          onTap: () => context.push(AppRoutes.addresses),
        ),
        const _TileDivider(),
        _AccountTile(
          icon: Icons.credit_card_outlined,
          label: l10n.savedCardsTitle,
          onTap: () => context.push(AppRoutes.paymentMethods),
        ),
        const _TileDivider(),
        _AccountTile(
          icon: Icons.star_outline,
          label: l10n.myReviewsTitle,
          onTap: () => context.push(AppRoutes.myReviews),
        ),
        // Both open Notification settings (Figma 20h); each row only when
        // there is something behind it — push needs FCM, the newsletter the
        // store's newsletter switch.
        if (pushAvailable) ...[
          const _TileDivider(),
          _AccountTile(
            icon: Icons.notifications_none,
            label: l10n.notificationsTitle,
            onTap: () => context.push(AppRoutes.notificationSettings),
          ),
        ],
        if (newsletterEnabled) ...[
          const _TileDivider(),
          _AccountTile(
            icon: Icons.mail_outline,
            label: l10n.newsletterTitle,
            onTap: () => context.push(AppRoutes.notificationSettings),
          ),
        ],
        const _AccountBand(),
        // Preferences group (Figma 43:3 …).
        _AccountTile(
          icon: Icons.language_outlined,
          label: l10n.languageToggleLabel,
          value: languageLabel,
          onTap: () => context.push(AppRoutes.settings),
        ),
        const _TileDivider(),
        // Account deletion has to be findable, not merely present: 1.0.0 (80)
        // was rejected under Guideline 5.1.1(v) as having no option to delete
        // an account, while the option existed in Settings — reachable only by
        // tapping a row labelled "Language". Figma 20 keeps the words "Delete
        // account" on this row, so a customer (or a reviewer) finds it here;
        // Privacy & data holds the action, and Settings keeps its copy too.
        _AccountTile(
          icon: Icons.shield_outlined,
          label: l10n.privacyDataTitle,
          value: l10n.deleteAccountTitle,
          onTap: () => context.push(AppRoutes.privacyData),
        ),
        const _AccountBand(),
        _AccountTile(
          icon: Icons.help_outline,
          label: l10n.helpCentreTitle,
          onTap: () => context.push(AppRoutes.help),
        ),
        const _TileDivider(),
        _AccountTile(
          icon: Icons.info_outline,
          label: l10n.accountAbout,
          onTap: () => context.push(AppRoutes.about),
        ),
        const _AccountBand(),
        // Log out (Figma 43:34) — red, centered.
        InkWell(
          onTap: onSignOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.logout, color: AppColors.accentSale, size: 20),
                const SizedBox(width: 10),
                Text(
                  l10n.accountLogOut,
                  style: const TextStyle(
                    color: AppColors.accentSale,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Center(
            child: Text(
              version != null ? '${l10n.appTitle} · v$version' : l10n.appTitle,
              style: TextStyle(color: context.scaffoldFaint, fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-bleed 8px grey band separating Account sections (Figma 42:16 / 42:29).
class _AccountBand extends StatelessWidget {
  const _AccountBand();

  @override
  Widget build(BuildContext context) =>
      Container(height: 8, color: context.sectionBand);
}

/// Hairline between menu tiles, inset to clear the icon chip.
class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    color: context.hairline,
    indent: 16,
    endIndent: 16,
  );
}

/// One quick-stat cell — bold navy number over a muted label (Figma 42:18).
class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.brandPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: context.scaffoldMuted),
        ),
      ],
    ),
  );
}

/// Account menu row (Figma): blush icon chip, label, optional trailing value,
/// muted chevron.
class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.brandPrimary, size: 20),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.scaffoldHeading,
                ),
              ),
            ),
            if (value != null) ...[
              Text(
                value!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: context.scaffoldFaint,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right, color: context.scaffoldMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

class _Guest extends StatelessWidget {
  const _Guest();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 48,
              backgroundColor: AppColors.surfaceTint,
              child: Icon(
                Icons.person_outline,
                size: 48,
                color: AppColors.brandPrimary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.accountGuestTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.accountGuestBody,
              style: TextStyle(color: context.scaffoldMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.push(AppRoutes.signIn),
                child: Text(l10n.authSignInTitle),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.push(AppRoutes.signUp),
                child: Text(l10n.authSignUpTitle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
