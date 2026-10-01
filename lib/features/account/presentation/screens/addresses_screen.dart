import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/validation/phone.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../core/widgets/hub_bottom_action_bar.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../core/widgets/hub_radio_dot.dart';
import '../../../../core/widgets/hub_top_bar.dart';
import '../../../../l10n/l10n.dart';
import '../../data/account_repository.dart';
import '../../domain/customer_address.dart';
import '../emirate_names.dart';

/// Saved addresses (Figma 24): the customer's address book as radio cards —
/// the default one chosen, navy-ringed and badged — with edit and delete on
/// each and "Add new address" pinned under the list. Choosing another card
/// makes it the default shipping address.
///
/// The frame's "Use my current location / Pin your building on the map" row is
/// not here: the app has no map or location access to pin a building with.
class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key});

  Future<void> _makeDefault(
    BuildContext context,
    WidgetRef ref,
    CustomerAddress address,
  ) async {
    final id = address.id;
    if (id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).errorGeneric;
    try {
      await ref
          .read(accountRepositoryProvider)
          .updateAddress(id, address.asDefaultShipping());
      ref.invalidate(addressesProvider);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final addresses = ref.watch(addressesProvider);

    return Scaffold(
      backgroundColor: groupedPageColor(context),
      appBar: HubTopBar(title: l10n.addressesTitle),
      body: AsyncValueView(
        value: addresses,
        onRetry: () => ref.invalidate(addressesProvider),
        data: (list) => list.isEmpty
            ? EmptyState(icon: HubIcons.mapPin, title: l10n.addressesEmpty)
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  for (final address in list) ...[
                    _AddressCard(
                      address: address,
                      onSelect: () => _makeDefault(context, ref, address),
                      onEdit: () =>
                          context.push(AppRoutes.addressForm, extra: address),
                      onDelete: () async {
                        final id = address.id;
                        if (id == null) return;
                        await ref
                            .read(accountRepositoryProvider)
                            .deleteAddress(id);
                        ref.invalidate(addressesProvider);
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
      ),
      bottomNavigationBar: HubBottomActionBar(
        child: HubButton(
          label: l10n.addressAddNew,
          icon: HubIcons.plus,
          iconSize: 20,
          style: HubButtonStyle.outline,
          onPressed: () => context.push(AppRoutes.addressForm),
        ),
      ),
    );
  }
}

/// One address as the cards show it: "Apt 1204, Marina Gate 2, Dubai Marina,
/// Dubai, UAE". The area is Magento's `city`, left out when it only repeats the
/// emirate (the app fills `city` from the emirate); the country is always shown
/// in its short form.
String _addressLine(AppLocalizations l10n, CustomerAddress a) {
  final region = a.region.trim();
  final city = a.city.trim();
  final emirateName = region.isNotEmpty ? region : city;
  final area = city.isNotEmpty && city.toLowerCase() != emirateName.toLowerCase()
      ? city
      : '';
  final emirate = emirateLabel(l10n, emirateName);
  final country = a.countryCode.toUpperCase() == 'AE'
      ? l10n.countryUaeShort
      : a.countryCode;
  return [
    a.apartment.trim(),
    a.street.trim(),
    area,
    emirate,
    country,
  ].where((part) => part.isNotEmpty).join(l10n.listSeparator);
}

/// Saved-address card (Figma 24 "address/…"): radio, label, Default badge and
/// the edit / delete icons on a row; the recipient and number; the address.
/// Navy 1.5 px ring when it is the default, a 1 px `--hm-subtle` one otherwise.
class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final CustomerAddress address;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final selected = address.defaultShipping;
    final phone = address.telephone.trim();
    final who = [
      address.fullName,
      // The number reads left to right inside Arabic text.
      if (phone.isNotEmpty) '\u2066${Phone.display(phone)}\u2069',
    ].where((part) => part.isNotEmpty).join(' · ');
    final title = (address.labelText ?? '').trim().isNotEmpty
        ? address.labelText!.trim()
        : address.region.trim().isNotEmpty
        ? emirateLabel(l10n, address.region)
        : address.city.trim().isNotEmpty
        ? emirateLabel(l10n, address.city)
        : address.fullName;
    // The icons carry 5 px of tap area beside them; the card gives it back so
    // they sit where the frame draws them.
    const iconSlack = 5.0;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: groupCardColor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.brandPrimary
                : context.isDarkMode
                ? Colors.white12
                : AppColors.borderSubtle,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: selected ? null : onSelect,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              14,
              14,
              14 - iconSlack,
              14,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    HubRadioDot(selected: selected),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.title.copyWith(
                                color: context.scaffoldHeading,
                              ),
                            ),
                          ),
                          if (selected) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accentSubtle,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                l10n.defaultBadge.toUpperCase(),
                                style: t.micro.copyWith(
                                  color: AppColors.accentStrong,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _IconAction(
                      icon: HubIcons.pencil,
                      tooltip: l10n.addressEdit,
                      onTap: onEdit,
                    ),
                    _IconAction(
                      icon: HubIcons.trash2,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).deleteButtonTooltip,
                      onTap: () => onDelete(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: iconSlack),
                  child: Text(
                    who,
                    style: t.bodyStrong.copyWith(color: context.scaffoldHeading),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: iconSlack),
                  child: Text(
                    _addressLine(l10n, address),
                    style: t.body.copyWith(color: context.scaffoldMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An 18 px outline icon (edit / delete) in a 28 px tap box, so the icons sit
/// 10 px apart as the frame draws them and still take a thumb.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    excludeSemantics: true,
    child: InkResponse(
      onTap: onTap,
      radius: 20,
      child: SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: Icon(icon, size: 18, color: context.scaffoldMuted),
        ),
      ),
    ),
  );
}
