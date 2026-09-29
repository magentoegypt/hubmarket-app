import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../l10n/l10n.dart';
import '../wishlist_controller.dart';

/// Heart toggle that reflects and mutates wishlist membership for [sku].
/// Prompts sign-in (snackbar) when the user is a guest.
class WishlistHeart extends ConsumerWidget {
  const WishlistHeart({
    super.key,
    required this.sku,
    this.color,
    this.compact = false,
  });

  final String sku;
  final Color? color;

  /// Tight 26×26 button with a 15px heart — fits the product card's circular
  /// action chip. Default is the standard 48px tap target.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inWishlist = ref.watch(
      wishlistControllerProvider.select((s) => s.contains(sku)),
    );
    return IconButton(
      iconSize: compact ? 15 : null,
      padding: compact ? EdgeInsets.zero : null,
      constraints: compact
          ? const BoxConstraints.tightFor(width: 26, height: 26)
          : null,
      icon: Icon(
        inWishlist ? Icons.favorite : Icons.favorite_border,
        color: inWishlist
            ? AppColors.brandPrimary
            : (color ?? AppColors.inkHeading),
      ),
      onPressed: () async {
        final ok = await ref
            .read(wishlistControllerProvider.notifier)
            .toggle(sku);
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).wishlistSignInPrompt),
            ),
          );
        }
      },
    );
  }
}
