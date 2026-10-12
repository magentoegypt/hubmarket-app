import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/cms/domain/cms_video.dart';

// QA TC102: a video a seller puts in a product description. The app never plays
// the embed inside itself; it keeps a link to the provider's own page.

void main() {
  group('embeddedVideoUrl: YouTube', () {
    const watch = 'https://www.youtube.com/watch?v=Rl6EvEeN348';

    test('the embed Page Builder writes, with its autoplay and mute', () {
      expect(
        embeddedVideoUrl(
          'https://www.youtube.com/embed/Rl6EvEeN348?autoplay=1&mute=1',
        ),
        watch,
      );
    });

    test('every way a video id is written', () {
      for (final src in [
        'https://www.youtube-nocookie.com/embed/Rl6EvEeN348',
        'https://youtube.com/embed/Rl6EvEeN348',
        'https://m.youtube.com/watch?v=Rl6EvEeN348&feature=share',
        'https://www.youtube.com/watch?feature=share&v=Rl6EvEeN348',
        'https://www.youtube.com/v/Rl6EvEeN348',
        'https://www.youtube.com/shorts/Rl6EvEeN348',
        'https://www.youtube.com/live/Rl6EvEeN348?si=abc',
        'https://youtu.be/Rl6EvEeN348',
        'https://youtu.be/Rl6EvEeN348?si=abc',
        // Protocol-relative, as TinyMCE pastes it.
        '//www.youtube.com/embed/Rl6EvEeN348',
        'http://www.youtube.com/embed/Rl6EvEeN348',
        '  https://www.youtube.com/embed/Rl6EvEeN348  ',
      ]) {
        expect(embeddedVideoUrl(src), watch, reason: src);
      }
    });

    test('a start time survives, as the watch page writes it', () {
      expect(
        embeddedVideoUrl('https://www.youtube.com/embed/Rl6EvEeN348?start=45'),
        '$watch&t=45s',
      );
      expect(embeddedVideoUrl('https://youtu.be/Rl6EvEeN348?t=90'), '$watch&t=90s');
      // Not a number of seconds (1m30s): left out rather than guessed.
      expect(embeddedVideoUrl('https://youtu.be/Rl6EvEeN348?t=1m30s'), watch);
    });

    test('a playlist embed opens the playlist', () {
      expect(
        embeddedVideoUrl(
          'https://www.youtube.com/embed/videoseries?list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG',
        ),
        'https://www.youtube.com/playlist?list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG',
      );
    });

    test('a place on YouTube, or an id that is not one, is not a video', () {
      for (final src in [
        'https://www.youtube.com/channel/UCabcdefghijklmnop',
        'https://www.youtube.com/results?search_query=x',
        'https://www.youtube.com/embed/',
        'https://www.youtube.com/embed/ab',
        'https://www.youtube.com/embed/<script>alert(1)</script>',
        'https://www.youtube.com/watch',
        'https://www.youtube.com/embed/videoseries',
        'https://www.youtube.com/',
      ]) {
        expect(embeddedVideoUrl(src), isNull, reason: src);
      }
    });
  });

  group('embeddedVideoUrl: Vimeo', () {
    test('the player, the page, and a channel page', () {
      expect(
        embeddedVideoUrl('https://player.vimeo.com/video/76979871?autoplay=1'),
        'https://vimeo.com/76979871',
      );
      expect(
        embeddedVideoUrl('https://vimeo.com/76979871'),
        'https://vimeo.com/76979871',
      );
      expect(
        embeddedVideoUrl('https://vimeo.com/channels/staffpicks/76979871'),
        'https://vimeo.com/76979871',
      );
    });

    test('an unlisted video keeps its hash', () {
      expect(
        embeddedVideoUrl('https://player.vimeo.com/video/76979871?h=0a1b2c3d4e'),
        'https://vimeo.com/76979871/0a1b2c3d4e',
      );
      expect(
        embeddedVideoUrl('https://vimeo.com/76979871/0a1b2c3d4e'),
        'https://vimeo.com/76979871/0a1b2c3d4e',
      );
    });

    test('a profile is not a video', () {
      expect(embeddedVideoUrl('https://vimeo.com/someuser'), isNull);
      expect(embeddedVideoUrl('https://player.vimeo.com/'), isNull);
    });
  });

  group('embeddedVideoUrl: everything else stays out', () {
    test('other iframes (maps, forms, adverts) and other schemes', () {
      for (final src in [
        'https://www.google.com/maps/embed?pb=!1m18',
        'https://example.com/embed/Rl6EvEeN348',
        'https://www.facebook.com/plugins/video.php?href=x',
        'javascript:alert(1)',
        'data:text/html,<p>x</p>',
        'ftp://www.youtube.com/embed/Rl6EvEeN348',
        'file:///sdcard/a.mp4',
        '/embed/Rl6EvEeN348',
        'Rl6EvEeN348',
        '',
        '   ',
        null,
      ]) {
        expect(embeddedVideoUrl(src), isNull, reason: '$src');
      }
    });

    test('a look-alike host is not YouTube', () {
      for (final src in [
        'https://youtube.com.evil.example/embed/Rl6EvEeN348',
        'https://evil.example/youtube.com/embed/Rl6EvEeN348',
        'https://notyoutube.com/embed/Rl6EvEeN348',
        'https://www.youtube.com@evil.example/embed/Rl6EvEeN348',
        'https://vimeo.com.evil.example/76979871',
      ]) {
        expect(embeddedVideoUrl(src), isNull, reason: src);
      }
    });
  });
}
