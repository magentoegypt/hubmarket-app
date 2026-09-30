import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/returns/domain/return_photo.dart';
import 'package:hubmarket_app/features/returns/domain/returns.dart';
import 'package:hubmarket_app/features/returns/presentation/widgets/return_photos.dart';

import '../../support/returns_fakes.dart';

Uint8List _bytes(List<int> head, [int length = 64]) =>
    Uint8List.fromList([...head, ...List.filled(length - head.length, 0)]);

void main() {
  group('what a picked file is', () {
    test('told from its first bytes, whatever its name says', () {
      expect(
        ReturnPhotoFormat.sniff(_bytes([0xFF, 0xD8, 0xFF, 0xE0])),
        ReturnPhotoFormat.jpeg,
      );
      expect(ReturnPhotoFormat.sniff(kGreenPhoto), ReturnPhotoFormat.png);
      expect(
        ReturnPhotoFormat.sniff(_bytes(ascii.encode('GIF89a'))),
        ReturnPhotoFormat.gif,
      );
      expect(
        ReturnPhotoFormat.sniff(
          _bytes([...ascii.encode('RIFF'), 0, 0, 0, 0, ...ascii.encode('WEBP')]),
        ),
        ReturnPhotoFormat.webp,
      );
      expect(ReturnPhotoFormat.sniff(kHeicPhoto), isNull);
      expect(ReturnPhotoFormat.sniff(Uint8List(0)), isNull);
    });
  });

  group('a photo the store takes', () {
    const extensions = ['jpg', 'jpeg', 'png', 'gif', 'pdf'];

    test('is named with the extension the store allows', () {
      final (photo, problem) = ReturnPhoto.check(
        _bytes([0xFF, 0xD8, 0xFF]),
        extensions: extensions,
        maxBytes: 1024,
        baseName: 'photo-1-1',
      );
      expect(problem, isNull);
      expect(photo!.name, 'photo-1-1.jpg');
      expect(photo.mimeType, 'image/jpeg');

      // Only "jpeg" allowed: the name follows.
      final (jpeg, _) = ReturnPhoto.check(
        _bytes([0xFF, 0xD8, 0xFF]),
        extensions: const ['JPEG'],
        maxBytes: null,
        baseName: 'p',
      );
      expect(jpeg!.name, 'p.jpeg');
    });

    test('a format it doesn’t take, or a photo over its limit, is refused', () {
      expect(
        ReturnPhoto.check(
          kHeicPhoto,
          extensions: extensions,
          maxBytes: null,
          baseName: 'p',
        ).$2,
        ReturnPhotoProblem.format,
      );
      expect(
        ReturnPhoto.check(
          kGreenPhoto,
          extensions: const ['jpg', 'pdf'],
          maxBytes: null,
          baseName: 'p',
        ).$2,
        ReturnPhotoProblem.format,
      );
      expect(
        ReturnPhoto.check(
          _bytes([0xFF, 0xD8, 0xFF], 2048),
          extensions: extensions,
          maxBytes: 1024,
          baseName: 'p',
        ).$2,
        ReturnPhotoProblem.size,
      );
    });

    test('goes as an HmReturnAttachmentInput', () {
      final photo = ReturnPhoto(
        name: 'a.png',
        mimeType: 'image/png',
        bytes: kGreenPhoto,
      );
      expect(photo.toInput(), {
        'name': 'a.png',
        'mime_type': 'image/png',
        'content_base64': base64Encode(kGreenPhoto),
      });
    });

    test('photos are offered only when the store takes an image format', () {
      expect(kSampleReturnConfig.acceptsPhotos, isFalse);
      expect(kPhotoReturnConfig.acceptsPhotos, isTrue);
      expect(
        const ReturnConfig(
          attachmentExtensions: ['pdf', 'zip'],
          attachmentMaxFiles: 5,
        ).acceptsPhotos,
        isFalse,
      );
      expect(
        const ReturnConfig(
          attachmentExtensions: ['png'],
          attachmentMaxFiles: 0,
        ).acceptsPhotos,
        isFalse,
      );
    });

    test('the size limit reads in MB, rounded down', () {
      expect(returnMegabytes(2097152), '2');
      expect(returnMegabytes(10485760), '10');
      expect(returnMegabytes(2621440), '2.5');
      expect(returnMegabytes(100), '0.1');
    });
  });

  group('status tone', () {
    test('resolved and rejected read apart, by the status code first', () {
      expect(ReturnTone.of(ReturnState.closed, 'resolved'), ReturnTone.resolved);
      expect(ReturnTone.of(ReturnState.canceled, 'canceled'), ReturnTone.rejected);
      // A status the store added, whatever state it maps to.
      expect(ReturnTone.of(ReturnState.closed, 'rejected'), ReturnTone.rejected);
      expect(ReturnTone.of(ReturnState.closed, 'declined'), ReturnTone.rejected);
      expect(ReturnTone.of(ReturnState.open, 'pending'), ReturnTone.pending);
      expect(ReturnTone.of(ReturnState.open, 'awaiting'), ReturnTone.pending);
      // Without a code, the state decides.
      expect(ReturnTone.of(ReturnState.closed, ''), ReturnTone.resolved);
      expect(ReturnTone.of(ReturnState.canceled, ''), ReturnTone.rejected);
    });
  });
}
