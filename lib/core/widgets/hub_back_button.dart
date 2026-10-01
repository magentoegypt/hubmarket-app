import 'package:flutter/material.dart';

import '../../app/theme/hub_icons.dart';
import 'hub_icon_button.dart';

/// Shared back button (Figma `icon-btn/arrow-left`): a 40 px round target with
/// the 22 px `arrow-left` outline. The icon mirrors itself in Arabic/RTL
/// (`HubIcons.arrowLeft` sets `matchTextDirection`); never wrap it in a manual
/// `Transform`/direction flip — that double-mirrors it (see the
/// rtl-arrow-double-flip lesson).
class HubBackButton extends StatelessWidget {
  const HubBackButton({super.key, this.color, this.onPressed});

  /// Icon colour. Defaults to ink; pass white for navy surfaces.
  final Color? color;

  /// Overrides the default `Navigator.maybePop` behaviour when set.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return HubIconButton(
      icon: HubIcons.arrowLeft,
      color: color,
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed ?? () => Navigator.maybePop(context),
    );
  }
}
