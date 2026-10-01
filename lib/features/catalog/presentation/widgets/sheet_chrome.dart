import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// The bottom sheets of the listing pages (Figma 11 "Bottom sheet"): white,
/// 20 pt top corners, a navy-tinted scrim, and a 40 × 4 handle drawn by the
/// sheet itself ([SheetHandle]) — so the sheet is opened with
/// [showCatalogSheet], which does not ask Material for its own handle.
///
/// Sheets draw their own bottom safe area ([SheetFooter], [SheetBottomSpace]):
/// they own the space under their last row, which the frame measures from the
/// screen's edge.
Future<T?> showCatalogSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  backgroundColor: Colors.white,
  barrierColor: sheetScrim,
  shape: sheetShape,
  clipBehavior: Clip.antiAlias,
  builder: builder,
);

/// `rgba(15, 33, 68, 0.55)`: the frame's scrim.
const Color sheetScrim = Color(0x8C0F2144);

/// The sheet's 20 pt top corners.
const RoundedRectangleBorder sheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
);

/// Gap between the status bar and a full sheet's top edge, in the frame.
const double sheetTopGap = 40;

/// The grab handle row: 10 above, the 40 × 4 bar, 4 below.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 10, bottom: 4),
    child: Center(
      child: SizedBox(
        width: 40,
        height: 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.borderStrong,
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
        ),
      ),
    ),
  );
}

/// The sheet's title row: Heading 2 and an optional action at the end (Reset),
/// 8 above and 12 below on 16 pt sides, over a 1 pt rule.
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    // A Container, whose rule takes room: the frame's row is 45 pt with it.
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.heading2.copyWith(color: AppColors.inkHeading),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// The space under a sheet's last row: the system's bottom inset, at least 16.
class SheetBottomSpace extends StatelessWidget {
  const SheetBottomSpace({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.only(bottom: 16),
    child: const SizedBox(width: double.infinity),
  );
}
