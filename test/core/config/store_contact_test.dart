import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/config/store_contact.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';

import '../../support/fakes.dart';

/// The shape of the live `hm_footer_customer` block: the website footer's
/// "Customer" column, whose last link is the WhatsApp support chat.
const _footerBlock = '<h3>Customer</h3>\n<ul>\n'
    '  <li><a href="https://hub-market.magento2.click/en/customer/account/">My Account</a></li>\n'
    '  <li><a href="https://hub-market.magento2.click/en/customer-service/">Help Center</a></li>\n'
    '  <li><a href="https://wa.me/971500000000">WhatsApp</a></li>\n'
    '</ul>\n';

/// A client answering `cmsBlocks` with [content] (or an error when null).
GraphQLClient _cmsClient(String? content) => GraphQLClient(
  link: Link.function((request, [forward]) {
    if (content == null) {
      return Stream<Response>.error(Exception('offline (test)'));
    }
    return Stream<Response>.value(
      Response(
        data: <String, dynamic>{
          '__typename': 'Query',
          'cmsBlocks': <String, dynamic>{
            '__typename': 'CmsBlocks',
            'items': [
              <String, dynamic>{
                '__typename': 'CmsBlock',
                'identifier': supportCmsBlockId,
                'content': content,
              },
            ],
          },
        },
        response: const <String, dynamic>{},
        context: const Context(),
      ),
    );
  }),
  cache: GraphQLCache(),
);

ProviderContainer _container(GraphQLClient client) {
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      graphqlClientProvider.overrideWithValue(client),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Reads the contact once the CMS request has settled.
Future<StoreContact> _settled(ProviderContainer container) async {
  container.listen(storeContactProvider, (_, __) {});
  await pumpEventQueue();
  return container.read(storeContactProvider);
}

void main() {
  group('whatsappLinkFromHtml', () {
    test('finds the wa.me link in the footer block', () {
      expect(whatsappLinkFromHtml(_footerBlock), 'https://wa.me/971500000000');
    });

    test('normalises the api.whatsapp.com form', () {
      expect(
        whatsappLinkFromHtml(
          '<a href="https://api.whatsapp.com/send?phone=+971500000000">Chat</a>',
        ),
        'https://wa.me/971500000000',
      );
    });

    test('is null without a WhatsApp link', () {
      expect(whatsappLinkFromHtml(null), isNull);
      expect(whatsappLinkFromHtml(''), isNull);
      expect(
        whatsappLinkFromHtml('<a href="https://example.com/wa.me">x</a>'),
        isNull,
      );
    });
  });

  group('storeContactProvider', () {
    test('publishes WhatsApp from the CMS block and nothing invented', () async {
      final contact = await _settled(_container(_cmsClient(_footerBlock)));

      expect(contact.whatsapp, 'https://wa.me/971500000000');
      // Not published by Hub Market — must stay unset rather than fall back to
      // someone else's details.
      expect(contact.phone, isNull);
      expect(contact.email, isNull);
      expect(contact.address, isNull);
      expect(contact.company, isNull);
      expect(contact.socials, isEmpty);
      expect(contact.website, 'https://hub-market.magento2.click');
    });

    test('a failed block request leaves every channel unset', () async {
      final contact = await _settled(_container(_cmsClient(null)));

      expect(contact.whatsapp, isNull);
      expect(contact.phone, isNull);
      expect(contact.email, isNull);
      expect(contact.website, 'https://hub-market.magento2.click');
    });
  });
}
