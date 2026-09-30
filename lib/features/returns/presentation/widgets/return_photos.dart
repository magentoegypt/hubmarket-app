import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/util/launch.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../data/return_photo_picker.dart';
import '../../domain/return_photo.dart';
import '../../domain/returns.dart';
import 'return_form_widgets.dart';
import 'return_widgets.dart';

/// Photos on a return (Figma 23 "Photos (optional)", 65:2855), its replies
/// (23c's camera button) and its escalation, and the files the thread shows.

/// Asks where the photos come from (camera or library), picks at most
/// [room] of them, and keeps those the store takes ([config]'s upload rules).
/// A photo it can't take is left out with a message saying why. Empty when
/// the customer cancels or the picker fails.
Future<List<ReturnPhoto>> pickReturnPhotos(
  BuildContext context,
  WidgetRef ref, {
  required ReturnConfig config,
  required int room,
}) async {
  if (room < 1 || !config.acceptsPhotos) return const <ReturnPhoto>[];
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final source = await showModalBottomSheet<ReturnPhotoSource>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReturnSheetTitle(l10n.returnsAddPhotos),
            ListTile(
              leading: const Icon(
                Icons.photo_camera_outlined,
                color: AppColors.inkHeading,
              ),
              title: Text(
                l10n.returnsTakePhoto,
                style: const TextStyle(color: AppColors.inkHeading),
              ),
              onTap: () => Navigator.pop(sheetContext, ReturnPhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: AppColors.inkHeading,
              ),
              title: Text(
                l10n.returnsChoosePhotos,
                style: const TextStyle(color: AppColors.inkHeading),
              ),
              onTap: () =>
                  Navigator.pop(sheetContext, ReturnPhotoSource.library),
            ),
          ],
        ),
      ),
    ),
  );
  if (source == null || !context.mounted) return const <ReturnPhoto>[];

  final List<Uint8List> picked;
  try {
    picked = await ref.read(returnPhotoPickerProvider).pick(source, limit: room);
  } on Object {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.returnsPhotoPickFailed)));
    return const <ReturnPhoto>[];
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final photos = <ReturnPhoto>[];
  final problems = <ReturnPhotoProblem>{};
  for (var i = 0; i < picked.length && photos.length < room; i++) {
    final (photo, problem) = ReturnPhoto.check(
      picked[i],
      extensions: config.attachmentExtensions,
      maxBytes: config.attachmentMaxBytes,
      baseName: 'photo-$stamp-${i + 1}',
    );
    if (photo != null) photos.add(photo);
    if (problem != null) problems.add(problem);
  }
  if (problems.isNotEmpty) {
    final maxBytes = config.attachmentMaxBytes;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            problems.contains(ReturnPhotoProblem.size) && maxBytes != null
                ? l10n.returnsPhotoTooLarge(returnMegabytes(maxBytes))
                : l10n.returnsPhotoUnsupported,
          ),
        ),
      );
  }
  return photos;
}

/// A size limit in MB for a message: whole, else one decimal, rounded down
/// so a photo of that size fits.
String returnMegabytes(int bytes) {
  final megabytes = bytes / (1024 * 1024);
  if (megabytes == megabytes.roundToDouble()) return '${megabytes.round()}';
  return (math.max(0.1, (megabytes * 10).floorToDouble() / 10)).toStringAsFixed(1);
}

/// "Photos (optional)": the photos picked so far, each with a remove button,
/// and the dashed Add tile while there is room for more.
class ReturnPhotoField extends StatelessWidget {
  const ReturnPhotoField({
    super.key,
    required this.photos,
    required this.maxPhotos,
    required this.onAdd,
    required this.onRemove,
    this.label,
  });

  final List<ReturnPhoto> photos;
  final int maxPhotos;
  final VoidCallback? onAdd;
  final ValueChanged<int> onRemove;

  /// The field's label; none when the field sits under another heading.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          ReturnFieldLabel(label),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (photos.length < maxPhotos) ReturnAddPhotoTile(onTap: onAdd),
            for (var i = 0; i < photos.length; i++)
              ReturnPhotoTile(photo: photos[i], onRemove: () => onRemove(i)),
          ],
        ),
      ],
    );
  }
}

/// The dashed Add tile (Figma 65:2804): 72 square, camera and "Add".
class ReturnAddPhotoTile extends StatelessWidget {
  const ReturnAddPhotoTile({super.key, required this.onTap, this.size = 72});

  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.returnsAddPhotos,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: CustomPaint(
            painter: const _DashedBorderPainter(
              color: AppColors.borderControl,
              radius: 12,
            ),
            child: SizedBox(
              width: size,
              height: size,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.photo_camera_outlined,
                    size: 22,
                    color: AppColors.inkMuted,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.returnsAddPhoto,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 14 / 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A picked photo (Figma 65:2805): the picture, and a remove button.
class ReturnPhotoTile extends StatelessWidget {
  const ReturnPhotoTile({
    super.key,
    required this.photo,
    required this.onRemove,
    this.size = 72,
  });

  final ReturnPhoto photo;
  final VoidCallback onRemove;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: AppColors.surfaceSubtle,
                child: Image.memory(
                  photo.bytes,
                  fit: BoxFit.cover,
                  cacheWidth: (size * 3).round(),
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.image_outlined, color: AppColors.inkMuted),
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 4,
            end: 4,
            child: Material(
              color: AppColors.brandPrimary.withValues(alpha: 0.72),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: Tooltip(
                  message: l10n.returnsRemovePhoto,
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The files of a message or an escalation (Figma 65:3019): pictures as
/// thumbnails that open full screen, any other file as a chip that opens in
/// the browser.
class ReturnAttachmentStrip extends ConsumerWidget {
  const ReturnAttachmentStrip({
    super.key,
    required this.attachments,
    this.onDark = false,
  });

  final List<ReturnAttachment> attachments;

  /// On the customer's navy bubble.
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final attachment in attachments)
          if (attachment.isImage)
            Semantics(
              button: true,
              label: l10n.returnsPhoto,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => showReturnPhoto(context, attachment),
                child: ReturnThumb(
                  url: attachment.url,
                  size: 64,
                  radius: 8,
                  icon: Icons.image_outlined,
                ),
              ),
            )
          else
            ActionChip(
              avatar: Icon(
                Icons.insert_drive_file_outlined,
                size: 16,
                color: onDark ? Colors.white : AppColors.inkHeading,
              ),
              label: Text(
                attachment.name.isEmpty ? l10n.returnsAttachment : attachment.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: onDark ? Colors.white : AppColors.inkHeading,
                ),
              ),
              backgroundColor: onDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : AppColors.surfaceSubtle,
              side: BorderSide.none,
              onPressed: () {
                final uri = Uri.tryParse(attachment.url);
                if (uri != null) ref.read(externalUriLauncherProvider)(uri);
              },
            ),
      ],
    );
  }
}

/// A picture from the thread, full screen, to zoom in on.
Future<void> showReturnPhoto(BuildContext context, ReturnAttachment photo) {
  final l10n = AppLocalizations.of(context);
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (routeContext) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            leading: IconButton(
              tooltip: MaterialLocalizations.of(routeContext).closeButtonTooltip,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(routeContext),
            ),
            title: Text(
              photo.name.isEmpty ? l10n.returnsPhoto : photo.name,
              style: const TextStyle(fontSize: 14, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: HubImage(
                url: photo.url,
                fit: BoxFit.contain,
                placeholder: (_) => const SizedBox.shrink(),
                error: (_) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 48,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A dashed rounded outline (Figma's dashed border, 1 px).
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const double _dash = 4;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(0.5);
    final path = Path()..addRRect(rect);
    for (final PathMetric metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + _dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
