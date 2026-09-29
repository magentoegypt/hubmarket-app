import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/widgets/web_view_screen.dart';

/// The in-app browser must not become a general-purpose browser: that is a bad
/// experience (our chrome over someone else's site) and, to Apple,
/// "unrestricted web access", which forces a 17+ age rating. See
/// docs/zoonze-reference/appstore/app-information.md.
void main() {
  const allowed = 'hub-market.magento2.click';

  bool stays(String url, {bool isMainFrame = true}) => staysInApp(
    url: url,
    isMainFrame: isMainFrame,
    allowedDomain: allowed,
  );

  group('siteHost', () {
    test('drops a leading www. and lower-cases', () {
      expect(siteHost('WWW.Hub-Market.Magento2.Click'), 'hub-market.magento2.click');
      expect(siteHost('hub-market.magento2.click'), 'hub-market.magento2.click');
    });

    test('keeps the store subdomain — never reduces to the shared domain', () {
      expect(siteHost('hub-market.magento2.click'), isNot('magento2.click'));
    });
  });

  group('staysInApp', () {
    test('keeps the store and its subdomains in the app', () {
      expect(stays('https://hub-market.magento2.click/en/about-us'), isTrue);
      expect(stays('https://www.hub-market.magento2.click/ar/customer-service/'), isTrue);
      expect(stays('http://hub-market.magento2.click/terms'), isTrue);
    });

    // magento2.click is a shared staging domain: other stores live next door.
    test('treats other stores on the shared domain as foreign', () {
      expect(stays('https://multi.magento2.click/'), isFalse);
      expect(stays('https://magento2.click/'), isFalse);
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
