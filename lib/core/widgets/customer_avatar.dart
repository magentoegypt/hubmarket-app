import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import 'network_image.dart';
import '../util/media.dart';

/// The signed-in customer's avatar: their uploaded photo when present, falling
/// back to name initials on a blush circle. One shared widget so the photo shows
/// **consistently everywhere** (account screen, menu drawer, edit profile) — not
/// only on Edit Profile (QA: "the profile picture does not appear on the other
/// pages where it is expected").
///
/// [avatarUrl] is the raw `customer.avatar_url` (may be http) — it is upgraded to
/// https here, so callers just pass the model value straight through.
class CustomerAvatar extends StatelessWidget {
  const CustomerAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.diameter = 40,
    this.ring = false,
    this.ringWidth = 2,
    this.initialsFontSize,
    this.background = AppColors.surfaceTint,
  });

  /// Full name — the initials fallback is derived from this.
  final String name;

  /// Raw `customer.avatar_url` (nullable/empty when no photo is set).
  final String? avatarUrl;

  /// Overall diameter of the circle in logical pixels.
  final double diameter;

  /// Draws a navy ring around the avatar (Figma profile/drawer treatment).
  final bool ring;
  final double ringWidth;

  /// Initials size; defaults to ~40% of [diameter] when unset.
  final double? initialsFontSize;

  /// Circle background behind the initials / while the photo loads.
  final Color background;

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = httpsMediaUrl(avatarUrl);
    final hasPhoto = url != null && url.isNotEmpty;
    final initials = Text(
      _initials,
      style: TextStyle(
        color: AppColors.brandPrimary,
        fontWeight: FontWeight.w700,
        fontSize: initialsFontSize ?? diameter * 0.4,
      ),
    );
    return Container(
      width: diameter,
      height: diameter,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: ring
            ? Border.all(color: AppColors.brandPrimary, width: ringWidth)
            : null,
      ),
      child: hasPhoto
          ? HubImage(
              url: url,
              width: diameter,
              height: diameter,
              placeholder: (_) => ColoredBox(color: background),
              error: (_) => initials,
            )
          : initials,
    );
  }
}
