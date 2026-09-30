import 'package:flutter/material.dart';

/// [showModalBottomSheet] for every bottom sheet of the app: the sheet's content
/// is kept clear of the system navigation bar.
///
/// The app targets Android 15+, where apps draw edge-to-edge: the sheet's
/// bottom edge is the bottom of the screen, under a 3-button navigation bar or
/// the gesture handle. `showModalBottomSheet` only handles the top and sides
/// (`useSafeArea`), so the last row of a sheet ended up hidden behind the bar —
/// the seller offers sheet on a phone with 3-button navigation lost its second
/// offer. Wrapping the builder in a bottom [SafeArea] lifts the content by the
/// inset while the sheet's own background still reaches the screen edge.
/// A sheet that already has its own [SafeArea] is not padded twice: [SafeArea]
/// removes the padding it applied from the [MediaQuery] below it.
///
/// The parameters are the subset of [showModalBottomSheet] the app uses.
Future<T?> showHubBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool? showDragHandle,
  ShapeBorder? shape,
  Color? backgroundColor,
  Color? barrierColor,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  useSafeArea: useSafeArea,
  showDragHandle: showDragHandle,
  shape: shape,
  backgroundColor: backgroundColor,
  barrierColor: barrierColor,
  builder: (sheetContext) => SafeArea(top: false, child: builder(sheetContext)),
);
