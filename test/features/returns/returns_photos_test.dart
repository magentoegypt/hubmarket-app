import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/features/returns/data/return_photo_picker.dart';
import 'package:hubmarket_app/features/returns/domain/returns.dart';
import 'package:hubmarket_app/features/returns/presentation/widgets/return_photos.dart';
import 'package:hubmarket_app/features/returns/presentation/widgets/return_widgets.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/returns_fakes.dart';
import 'returns_harness.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';

final en = lookupAppLocalizations(const Locale('en'));

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Opens the photo source sheet from [button] and picks from the library.
Future<void> _pickFromLibrary(WidgetTester tester, Finder button) async {
  await _tapVisible(tester, button);
  expect(find.text(en.returnsTakePhoto), findsOneWidget);
  await tester.tap(find.text(en.returnsChoosePhotos));
  await tester.pumpAndSettle();
}

/// Fills in the lone line's return (Figma 23) up to its photos.
Future<void> _fillSingleLineForm(WidgetTester tester) async {
  await _tapVisible(tester, find.text(en.returnsChooseReason));
  await tester.tap(find.text('Arrived damaged'));
  await tester.pumpAndSettle();
  await _tapVisible(tester, find.text(en.returnsAnswerYes));
  await tester.enterText(
    find.widgetWithText(TextField, en.returnsCommentHint),
    'The collar is torn.',
  );
  await tester.pump();
}

void main() {
  group('23 Photos (optional)', () {
    testWidgets('photos are added, removed and sent with the return', (
      tester,
    ) async {
      final repo = FakeReturnsRepository(config: kPhotoReturnConfig);
      final picker = FakeReturnPhotoPicker(photos: [kGreenPhoto, kGreyPhoto]);
      await pumpReturns(
        tester,
        location: AppRoutes.returnRequest,
        extra: kSingleLineOrder,
        returns: repo,
        photoPicker: picker,
      );
      expect(find.text(en.returnsPhotos), findsOneWidget);
      await _fillSingleLineForm(tester);

      await _pickFromLibrary(tester, find.byType(ReturnAddPhotoTile));
      expect(picker.calls.single, (
        source: ReturnPhotoSource.library,
        limit: 5,
      ));
      expect(find.byType(ReturnPhotoTile), findsNWidgets(2));

      await _tapVisible(tester, find.byTooltip(en.returnsRemovePhoto).first);
      expect(find.byType(ReturnPhotoTile), findsOneWidget);

      await _tapVisible(tester, find.text(en.returnsSubmit));
      final attachments =
          repo.createInputs.single['attachments'] as List<dynamic>;
      final sent = attachments.single as Map<String, dynamic>;
      expect(sent['mime_type'], 'image/png');
      expect(sent['name'], matches(RegExp(r'^photo-\d+-2\.png$')));
      expect(sent['content_base64'], isNotEmpty);
    });

    testWidgets('the camera is offered too, one photo at a time left', (
      tester,
    ) async {
      final picker = FakeReturnPhotoPicker(photos: [kGreenPhoto]);
      await pumpReturns(
        tester,
        location: AppRoutes.returnRequest,
        extra: kSingleLineOrder,
        returns: FakeReturnsRepository(config: kPhotoReturnConfig),
        photoPicker: picker,
      );
      await _tapVisible(tester, find.byType(ReturnAddPhotoTile));
      await tester.tap(find.text(en.returnsTakePhoto));
      await tester.pumpAndSettle();
      expect(picker.calls.single.source, ReturnPhotoSource.camera);
      expect(find.byType(ReturnPhotoTile), findsOneWidget);
      // Room for four more.
      await _pickFromLibrary(tester, find.byType(ReturnAddPhotoTile));
      expect(picker.calls.last.limit, 4);
    });

    testWidgets('the Add tile goes once the store’s limit is reached', (
      tester,
    ) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returnRequest,
        extra: kSingleLineOrder,
        returns: FakeReturnsRepository(
          config: const ReturnConfig(
            attachmentExtensions: ['png'],
            attachmentMaxBytes: 2097152,
            attachmentMaxFiles: 2,
          ),
        ),
        photoPicker: FakeReturnPhotoPicker(
          photos: [kGreenPhoto, kGreyPhoto, kGreenPhoto],
        ),
      );
      await _pickFromLibrary(tester, find.byType(ReturnAddPhotoTile));
      expect(find.byType(ReturnPhotoTile), findsNWidgets(2));
      expect(find.byType(ReturnAddPhotoTile), findsNothing);
    });

    testWidgets('a photo the store doesn’t take is left out, saying why', (
      tester,
    ) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returnRequest,
        extra: kSingleLineOrder,
        returns: FakeReturnsRepository(config: kPhotoReturnConfig),
        photoPicker: FakeReturnPhotoPicker(photos: [kHeicPhoto]),
      );
      await _pickFromLibrary(tester, find.byType(ReturnAddPhotoTile));
      expect(find.byType(ReturnPhotoTile), findsNothing);
      expect(find.text(en.returnsPhotoUnsupported), findsOneWidget);
    });

    testWidgets('a photo over the store’s limit is left out, saying why', (
      tester,
    ) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returnRequest,
        extra: kSingleLineOrder,
        returns: FakeReturnsRepository(
          config: const ReturnConfig(
            attachmentExtensions: ['png'],
            attachmentMaxBytes: 10,
            attachmentMaxFiles: 5,
          ),
        ),
        photoPicker: FakeReturnPhotoPicker(photos: [kGreenPhoto]),
      );
      await _pickFromLibrary(tester, find.byType(ReturnAddPhotoTile));
      expect(find.byType(ReturnPhotoTile), findsNothing);
      expect(find.text(en.returnsPhotoTooLarge('0.1')), findsOneWidget);
    });

    testWidgets('a picker that fails says so', (tester) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returnRequest,
        extra: kSingleLineOrder,
        returns: FakeReturnsRepository(config: kPhotoReturnConfig),
        photoPicker: FakeReturnPhotoPicker(
          failure: PlatformException(code: 'camera_access_denied'),
        ),
      );
      await _pickFromLibrary(tester, find.byType(ReturnAddPhotoTile));
      expect(find.text(en.returnsPhotoPickFailed), findsOneWidget);
      expect(find.byType(ReturnPhotoTile), findsNothing);
    });

    testWidgets('no photos when the store takes no image', (tester) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returnRequest,
        extra: kSingleLineOrder,
        returns: FakeReturnsRepository(
          config: const ReturnConfig(
            attachmentExtensions: ['pdf', 'zip'],
            attachmentMaxFiles: 5,
          ),
        ),
      );
      expect(find.text(en.returnsPhotos), findsNothing);
      expect(find.byType(ReturnAddPhotoTile), findsNothing);
    });
  });

  group('23c photos', () {
    testWidgets('a reply takes photos from the camera button', (tester) async {
      final repo = FakeReturnsRepository(
        config: kPhotoReturnConfig,
        details: {31: sampleReturnDetail(photo: false)},
      );
      await pumpReturns(
        tester,
        location: AppRoutes.returnDetail(31),
        returns: repo,
        photoPicker: FakeReturnPhotoPicker(photos: [kGreenPhoto]),
      );
      expect(find.byType(ReturnAttachmentStrip), findsNothing);

      await _pickFromLibrary(tester, find.byTooltip(en.returnsAddPhotos));
      expect(find.byType(ReturnPhotoTile), findsOneWidget);
      // Text is still required, as on the website.
      final send = find.byTooltip(en.returnsSendReply);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, HubIcons.arrowRight),
            )
            .onPressed,
        isNull,
      );

      await tester.enterText(find.byType(TextField), 'Here is the damage.');
      await tester.pump();
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(repo.replies, [(returnId: 31, message: 'Here is the damage.')]);
      expect(repo.replyPhotos.single.single.mimeType, 'image/png');
      // The reply is in the thread with its photo; the bar is empty again.
      expect(find.text('Here is the damage.'), findsOneWidget);
      expect(find.byType(ReturnAttachmentStrip), findsOneWidget);
      expect(find.byType(ReturnPhotoTile), findsNothing);
    });

    testWidgets('a reply without photos sends none', (tester) async {
      final repo = FakeReturnsRepository(
        config: kPhotoReturnConfig,
        details: {31: sampleReturnDetail()},
      );
      await pumpReturns(
        tester,
        location: AppRoutes.returnDetail(31),
        returns: repo,
      );
      await tester.enterText(find.byType(TextField), 'Any news?');
      await tester.pump();
      await tester.tap(find.byTooltip(en.returnsSendReply));
      await tester.pumpAndSettle();
      expect(repo.replyPhotos.single, isEmpty);
    });

    testWidgets('no camera button until the store takes photos', (
      tester,
    ) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returnDetail(31),
        returns: FakeReturnsRepository(details: {31: sampleReturnDetail()}),
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip(en.returnsAddPhotos), findsNothing);
    });

    testWidgets('a photo in the thread opens full screen; a file opens '
        'outside the app', (tester) async {
      final launched = <Uri>[];
      await pumpReturns(
        tester,
        location: AppRoutes.returnDetail(31),
        launched: launched,
        returns: FakeReturnsRepository(
          details: {
            31: sampleReturnDetail(
              messages: const [
                ReturnMessage(
                  id: 1,
                  author: ReturnActor.seller,
                  authorName: 'loly store',
                  bodyText: 'Please sign the attached form.',
                  attachments: [
                    ReturnAttachment(
                      name: 'label.png',
                      url:
                          'https://hub-market.magento2.click/media/rma/request/label.png',
                    ),
                    ReturnAttachment(
                      name: 'form.pdf',
                      url:
                          'https://hub-market.magento2.click/media/rma/request/form.pdf',
                    ),
                  ],
                  createdAt: '2026-09-25T05:15:00Z',
                ),
              ],
            ),
          },
        ),
      );
      await tester.tap(find.text('form.pdf'));
      await tester.pumpAndSettle();
      expect(launched, [
        Uri.parse(
          'https://hub-market.magento2.click/media/rma/request/form.pdf',
        ),
      ]);

      await tester.tap(
        find.descendant(
          of: find.byType(ReturnAttachmentStrip),
          matching: find.byType(ReturnThumb),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('label.png'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byIcon(HubIcons.x).last);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
    });
  });
}
