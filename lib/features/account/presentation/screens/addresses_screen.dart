import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../l10n/l10n.dart';
import '../../data/account_repository.dart';
import '../../domain/customer_address.dart';

class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final addresses = ref.watch(addressesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountAddresses)),
      body: AsyncValueView(
        value: addresses,
        onRetry: () => ref.invalidate(addressesProvider),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 56),
                child: EmptyState(
                  icon: Icons.location_on_outlined,
                  title: l10n.addressesEmpty,
                ),
              )
            else
              for (final address in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AddressCard(
                    address: address,
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
                ),
            const SizedBox(height: 2),
            _AddNewAddressButton(
              onTap: () => context.push(AppRoutes.addressForm),
            ),
          ],
        ),
      ),
    );
  }
}

/// Saved-address card (Figma 64:11): bordered (burgundy when default), a pin +
/// recipient name + Default badge + edit/delete icons, then phone + address.
class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.onEdit,
    required this.onDelete,
  });

  final CustomerAddress address;
  final VoidCallback onEdit;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDefault = address.defaultShipping;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDefault ? AppColors.brandPrimary : AppColors.borderDefault,
          width: isDefault ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 20,
                color: AppColors.brandPrimary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        address.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkHeading,
                        ),
                      ),
                    ),
                    if (isDefault) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceTint,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          l10n.defaultBadge,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brandPrimary,
                          ),
                        ),
                      ),
                    ],
                    // "Save as" label (Home / Office / Other), backend-scoped.
                    if ((address.labelText ?? '').isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.brandPrimary,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          address.labelText!,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _IconAction(icon: Icons.edit_outlined, onTap: onEdit),
              _IconAction(icon: Icons.delete_outline, onTap: () => onDelete()),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (address.telephone.isNotEmpty)
                  Text(
                    address.telephone,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      color: AppColors.inkMuted,
                    ),
                  ),
                Text(
                  address.summary,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small tappable header icon (edit / delete).
class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
    onTap: onTap,
    radius: 20,
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Icon(icon, size: 18, color: AppColors.inkMuted),
    ),
  );
}

/// Burgundy outlined "Add New Address" button (Figma 64:39).
class _AddNewAddressButton extends StatelessWidget {
  const _AddNewAddressButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.add, size: 18),
      label: Text(l10n.addressAddNew),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.brandPrimary,
        side: const BorderSide(color: AppColors.brandPrimary, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }
}
