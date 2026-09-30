import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Photos on a return, its replies and its escalation (Figma 23 / 23c): what
/// the customer picked, checked against the store's upload rules
/// (`HmReturnConfig.attachment_*`) before it is sent as an
/// `HmReturnAttachmentInput`. The server checks it all again.

/// The image formats the app can send, told apart by their first bytes: the
/// pickers re-encode photos and may keep a name (IMG_0001.HEIC) that no longer
/// says what the file is.
enum ReturnPhotoFormat {
  jpeg(['jpg', 'jpeg'], 'image/jpeg'),
  png(['png'], 'image/png'),
  gif(['gif'], 'image/gif'),
  webp(['webp'], 'image/webp');

  const ReturnPhotoFormat(this.extensions, this.mimeType);

  /// The file extensions of the format, the usual one first.
  final List<String> extensions;
  final String mimeType;

  /// The format of [bytes], or null when it is none of these (HEIC, a video,
  /// a document …).
  static ReturnPhotoFormat? sniff(Uint8List bytes) {
    bool starts(List<int> signature, [int offset = 0]) {
      if (bytes.length < offset + signature.length) return false;
      for (var i = 0; i < signature.length; i++) {
        if (bytes[offset + i] != signature[i]) return false;
      }
      return true;
    }

    if (starts(const [0xFF, 0xD8, 0xFF])) return ReturnPhotoFormat.jpeg;
    if (starts(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return ReturnPhotoFormat.png;
    }
    if (starts(ascii.encode('GIF87a')) || starts(ascii.encode('GIF89a'))) {
      return ReturnPhotoFormat.gif;
    }
    if (starts(ascii.encode('RIFF')) && starts(ascii.encode('WEBP'), 8)) {
      return ReturnPhotoFormat.webp;
    }
    return null;
  }
}

/// Why a picked photo can't go with the message.
enum ReturnPhotoProblem {
  /// Not a format the store takes (HEIC, a video …).
  format,

  /// Larger than the store's upload limit.
  size,
}

/// A photo ready to send.
@immutable
class ReturnPhoto {
  const ReturnPhoto({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  /// Checks [bytes] against the formats the store takes ([extensions], lower
  /// case) and its size limit ([maxBytes], none when null), and names the
  /// photo `<baseName>.<extension>` with the extension the store allows.
  static (ReturnPhoto?, ReturnPhotoProblem?) check(
    Uint8List bytes, {
    required Iterable<String> extensions,
    required int? maxBytes,
    required String baseName,
  }) {
    final format = ReturnPhotoFormat.sniff(bytes);
    final allowed = extensions.map((e) => e.toLowerCase()).toSet();
    final extension = format?.extensions.where(allowed.contains).firstOrNull;
    if (format == null || extension == null) {
      return (null, ReturnPhotoProblem.format);
    }
    if (maxBytes != null && bytes.length > maxBytes) {
      return (null, ReturnPhotoProblem.size);
    }
    return (
      ReturnPhoto(
        name: '$baseName.$extension',
        mimeType: format.mimeType,
        bytes: bytes,
      ),
      null,
    );
  }

  /// File name with its extension, e.g. photo-1727712345123-1.jpg.
  final String name;
  final String mimeType;
  final Uint8List bytes;

  /// The `HmReturnAttachmentInput` for this photo.
  Map<String, dynamic> toInput() => <String, dynamic>{
    'name': name,
    'mime_type': mimeType,
    'content_base64': base64Encode(bytes),
  };
}
