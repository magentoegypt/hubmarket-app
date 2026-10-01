import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../l10n/l10n.dart';
import '../wishlist_controller.dart';

/// Heart toggle that reflects and mutates wishlist membership for [sku]: an
/// outline heart, a filled orange one once saved (Figma "wishlist").
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

  /// The product card's button: a 36 px white circle holding an 18 px heart,
  /// inside a 44 px tap area (Figma "Touch targets"). Default is a plain
  /// 48 px icon button.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inWishlist = ref.watch(
      wishlistControllerProvider.select((s) => s.contains(sku)),
    );

    Future<void> toggle() async {
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
    }

    final heart = Icon(
      inWishlist ? Icons.favorite : HubIcons.heart,
      size: compact ? 18 : null,
      color: inWishlist
          ? AppColors.accent
          : (color ?? AppColors.inkHeading),
    );

    if (!compact) {
      return IconButton(icon: heart, onPressed: toggle);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: toggle,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: heart,
          ),
        ),
      ),
    );
  }
}
