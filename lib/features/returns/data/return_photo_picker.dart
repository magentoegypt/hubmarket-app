import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// Where a photo for a return comes from.
enum ReturnPhotoSource { camera, library }

/// The system pickers for a return's photos (Figma 23 "Photos", 23c's camera
/// button): the camera, or the photo library through the system photo picker
/// — on Android every version, so the app never asks for storage access; on
/// iOS without the full metadata, so it never asks for the photo library.
///
/// Photos come sized for a message: the long side at most [maxDimension] px,
/// re-encoded at [quality]. The caller checks what they are
/// (`ReturnPhoto.check`).
abstract class ReturnPhotoPicker {
  static const double maxDimension = 2048;
  static const int quality = 85;

  /// The bytes of the photos picked, in order, at most [limit]; empty when
  /// the customer cancels. Throws what the platform throws (no camera, access
  /// denied).
  Future<List<Uint8List>> pick(ReturnPhotoSource source, {required int limit});
}

/// [ReturnPhotoPicker] on `image_picker`.
class ImagePickerReturnPhotoPicker implements ReturnPhotoPicker {
  ImagePickerReturnPhotoPicker([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static bool _photoPickerChosen = false;

  /// Android 13+ uses the system photo picker already; this makes Android 12
  /// and older use it too (Google Play's backport), where the default is the
  /// document browser.
  static void _usePhotoPicker() {
    if (_photoPickerChosen) return;
    _photoPickerChosen = true;
    final platform = ImagePickerPlatform.instance;
    if (platform is ImagePickerAndroid) platform.useAndroidPhotoPicker = true;
  }

  @override
  Future<List<Uint8List>> pick(
    ReturnPhotoSource source, {
    required int limit,
  }) async {
    if (limit < 1) return const <Uint8List>[];
    _usePhotoPicker();
    final List<XFile> files = switch (source) {
      ReturnPhotoSource.camera => [
        ?await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: ReturnPhotoPicker.maxDimension,
          maxHeight: ReturnPhotoPicker.maxDimension,
          imageQuality: ReturnPhotoPicker.quality,
          requestFullMetadata: false,
        ),
      ],
      ReturnPhotoSource.library => await _picker.pickMultiImage(
        maxWidth: ReturnPhotoPicker.maxDimension,
        maxHeight: ReturnPhotoPicker.maxDimension,
        imageQuality: ReturnPhotoPicker.quality,
        limit: limit,
        requestFullMetadata: false,
      ),
    };
    return [for (final file in files.take(limit)) await file.readAsBytes()];
  }
}

/// The photo picker; tests put a fake in its place.
final returnPhotoPickerProvider = Provider<ReturnPhotoPicker>(
  (ref) => ImagePickerReturnPhotoPicker(),
);
