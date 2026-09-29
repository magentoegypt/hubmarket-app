import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/widgets/web_view_screen.dart';

/// The in-app browser must not become a general-purpose browser: that is a bad
/// experience (our chrome over someone else's site) and, to Apple,
/// "unrestricted web access", which forces a 17+ age rating. See
/// docs/appstore/app-information.md.
void main() {
  const allowed = 'hub-market.magento2.click';

  bool stays(String url, {bool isMainFrame = true}) => staysInApp(
    url: url,
    isMainFrame: isMainFrame,
    allowedDomain: allowed,
  );

  group('registrableDomain', () {
    test('reduces a host to its last two labels', () {
      expect(registrableDomain('www.hub-market.magento2.click'), 'hub-market.magento2.click');
      expect(registrableDomain('uae-en.hub-market.magento2.click'), 'hub-market.magento2.click');
      expect(registrableDomain('hub-market.magento2.click'), 'hub-market.magento2.click');
    });

    test('is case-insensitive', () {
      expect(registrableDomain('WWW.Hub Market.COM'), 'hub-market.magento2.click');
    });
  });

  group('staysInApp', () {
    test('keeps the store and its subdomains in the app', () {
      expect(stays('https://hub-market.magento2.click/uae-en/about-us'), isTrue);
      expect(stays('https://www.hub-market.magento2.click/uae-ar/faq'), isTrue);
      expect(stays('http://hub-market.magento2.click/terms'), isTrue);
    });

    test('sends other sites to the platform browser', () {
      expect(stays('https://instagram.com/hubmarket'), isFalse);
      expect(stays('https://google.com'), isFalse);
    });

    // The whole point of the guard: a lookalike host must not read as ours.
    test('is not fooled by a host that merely contains the domain', () {
      expect(stays('https://hub-market.magento2.click.evil.example'), isFalse);
      expect(stays('https://nothub-market.magento2.click'), isFalse);
    });

    test('hands non-http schemes to the platform', () {
      expect(stays('mailto:hello@hub-market.magento2.click'), isFalse);
      expect(stays('tel:+97141234567'), isFalse);
    });

    test('never blocks sub-frames, whatever the host', () {
      // Embedded maps/video inside a CMS page are not the user navigating
      // away; blocking them renders the page broken.
      expect(stays('https://youtube.com/embed/x', isMainFrame: false), isTrue);
    });

    test('blocks an unparseable url rather than following it', () {
      expect(stays('::::not a url'), isFalse);
    });
  });
}
