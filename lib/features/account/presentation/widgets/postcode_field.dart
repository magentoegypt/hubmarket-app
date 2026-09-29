import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/validation/validators.dart';
import '../../../../l10n/l10n.dart';
import '../../data/address_rules.dart';

/// The postcode input the address forms (checkout, address book) add under the
/// shared `AddressForm` when the store requires a postcode for the UAE
/// ([postcodeRequiredProvider]); nothing otherwise. Styled like the
/// `AddressForm` fields: label above the box.
class PostcodeField extends ConsumerWidget {
  const PostcodeField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final required = ref.watch(postcodeRequiredProvider).valueOrNull ?? false;
    if (!required) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 6, start: 2),
            child: Text(
              l10n.fieldPostcode,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.inkMuted,
              ),
            ),
          ),
          TextFormField(
            controller: controller,
            textInputAction: TextInputAction.next,
            validator: (v) => Validators.required(context, v),
          ),
        ],
      ),
    );
  }
}
