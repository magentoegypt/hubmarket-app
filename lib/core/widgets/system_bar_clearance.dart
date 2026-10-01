import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How far above the bottom edge of the screen the bottom of a pinned control
/// (a footer's button, a buy bar, a composer) has to stay, for what the system
/// draws there.
///
/// The Figma footers leave 28-30 px under their button: an iPhone's home
/// indicator zone, 34 px. The indicator is a thin pill the button never needs
/// to clear, so on iOS the frame's space stands and only a taller zone gives way
/// ([iosGap] is how much of the inset the frame already keeps). A persistent
/// Android navigation bar is another thing: the three-button bar is 47 dp tall
/// (a gesture bar a pill of about 24) and covers whatever is under it, so a
/// button there is half hidden and cannot be tapped where it is — it has to clear
/// the whole inset. (Found on a phone: the Save button of Profile details lay 35 dp
/// under the bar, which the iPhone-sized audit could not show.)
///
/// Callers keep their own floor: `math.max(floor, systemBarClearance(context))`.
double systemBarClearance(BuildContext context, {double iosGap = 4}) {
  // The system's own inset: `viewPadding`, which a SafeArea or a Scaffold above
  // does not consume (the two are equal for a bar in a scaffold's bottom slot).
  final inset = math.max(
    MediaQuery.viewPaddingOf(context).bottom,
    MediaQuery.paddingOf(context).bottom,
  );
  return switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => math.max(0.0, inset - iosGap),
    _ => inset,
  };
}
