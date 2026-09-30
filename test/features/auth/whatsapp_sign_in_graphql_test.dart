import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/config/hubapp_account.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/data/hubapp_whatsapp_sign_in.dart';
import 'package:hubmarket_app/features/auth/data/whatsapp_otp_api.dart';
import 'package:hubmarket_app/features/auth/domain/auth_error.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/verify_code_screen.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/presentation/cart_controller.dart';
import 'package:hubmarket_app/l10n/l10n.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';
import '../../support/store_credit_fakes.dart';

const _mobile = '+971501234567';

// The backend's own words (HubAppAccount i18n), in both store views.
const _throttleEn = 'Too many code requests. Please try again in 5 minutes.';
const _throttleAr =
    'طلبات رموز كثيرة جدًا. يرجى المحاولة مرة أخرى بعد 5 دقيقة.';
const _uniformEn =
    'That code is incorrect or has expired. Check it, or ask for a new code.';
const _uniformAr =
    'الرمز غير صحيح أو انتهت صلاحيته. تحقق منه أو اطلب رمزًا جديدًا.';
const _noAccountEn = 'No account uses this mobile number.';
const _noAccountAr = 'لا يوجد حساب يستخدم رقم الهاتف المحمول هذا.';
const _sharedEn =
    'This mobile number is linked to more than one account. Please sign in '
    'with your email address.';

Map<String, dynamic> _sent({
  bool sent = true,
  String message =
      'If this number belongs to an account, we have sent a sign-in code to '
      'it on WhatsApp.',
  int resendAfter = 30,
}) => {
  'hmSendWhatsAppCode': {
    '__typename': 'HmSendWhatsAppCodeOutput',
    'sent': sent,
    'message': message,
    'resend_after_seconds': resendAfter,
  },
};

Map<String, dynamic> _token([String token = 'hub-token']) => {
  'hmSignInWithWhatsAppCode': {'__typename': 'CustomerToken', 'token': token},
};

/// Magento's answer to a refused code: GraphQlAuthenticationException.
Response _refused(String message) => Response(
  errors: [
    GraphQLError(
      message: message,
      extensions: const {'category': 'graphql-authentication'},
    ),
  ],
  response: const <String, dynamic>{},
);

/// SmsExtend's REST pair; records what the app posts to it.
class _Rest {
  final List<http.Request> requests = [];

  WhatsAppOtpApi get api => WhatsAppOtpApi(
    client: MockClient((request) async {
      requests.add(request);
      final action = request.url.pathSegments.last;
      return http.Response(
        jsonEncode(
          action == 'verify'
              ? {'status': 'success', 'message': 'OK', 'token': 'rest-token'}
              : {'status': 'success', 'message': 'OK'},
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
    endpoint: (action) =>
        Uri.parse('https://store.test/rest/en/V1/whatsapp/otp/$action'),
    userAgent: 'HubMarketApp-test',
  );

  List<String> get actions => [
    for (final r in requests) r.url.pathSegments.last,
  ];
}

AuthError _classify(Object error) => AuthError.from(error);

void main() {
  // Real glyphs: the Arabic countdown line is measured as the device lays it
  // out, not in the test font's wide boxes.
  setUpAll(loadAppFonts);

  group('HubAppWhatsAppSignIn', () {
    test('sends the number and reads the resend cooldown', () async {
      final client = fakeHubAppClient({'HmSendWhatsAppCode': _sent()});
      expect(await HubAppWhatsAppSignIn(client).sendCode(_mobile), 30);
      final request = client.requests.single;
      expect(request.variables, {'mobile': _mobile});
      expect(
        request.operation.document.definitions
            .whereType<OperationDefinitionNode>()
            .single
            .type,
        OperationType.mutation,
      );
    });

    test('trades the code for a customer token', () async {
      final client = fakeHubAppClient({'HmSignInWithWhatsAppCode': _token()});
      expect(
        await HubAppWhatsAppSignIn(client).signIn(_mobile, '123456'),
        'hub-token',
      );
      expect(client.requests.single.variables, {
        'mobile': _mobile,
        'code': '123456',
      });
    });

    for (final (lang, message) in [('en', _throttleEn), ('ar', _throttleAr)]) {
      test(
        'a send over the limits reads as too many attempts ($lang)',
        () async {
          final client = fakeHubAppClient({
            'HmSendWhatsAppCode': _sent(
              sent: false,
              message: message,
              resendAfter: 300,
            ),
          });
          final error = await HubAppWhatsAppSignIn(client)
              .sendCode(_mobile)
              .then<Object>((_) => fail('should refuse'), onError: (e) => e);
          expect(error, isA<Failure>());
          expect((error as Failure).detail, message);
          expect(_classify(error).kind, AuthErrorKind.tooManyAttempts);
        },
      );
    }

    for (final (lang, message) in [
      ('en', _noAccountEn),
      ('ar', _noAccountAr),
    ]) {
      test(
        'a store revealing unknown numbers reads as no account ($lang)',
        () async {
          final client = fakeHubAppClient({
            'HmSendWhatsAppCode': _sent(sent: false, message: message),
          });
          final error = await HubAppWhatsAppSignIn(client)
              .sendCode(_mobile)
              .then<Object>((_) => fail('should refuse'), onError: (e) => e);
          expect(_classify(error).kind, AuthErrorKind.noAccount);
        },
      );
    }

    test('any other refusal keeps the store message', () async {
      final client = fakeHubAppClient({
        'HmSendWhatsAppCode': _sent(sent: false, message: _sharedEn),
      });
      final error = await HubAppWhatsAppSignIn(client)
          .sendCode(_mobile)
          .then<Object>((_) => fail('should refuse'), onError: (e) => e);
      final authError = _classify(error);
      expect(authError.kind, AuthErrorKind.other);
      expect(authError.serverMessage, _sharedEn);
    });

    for (final (lang, message) in [('en', _uniformEn), ('ar', _uniformAr)]) {
      test(
        'the one answer to a refused code reads as a wrong code ($lang)',
        () async {
          final client = fakeHubAppClient({
            'HmSignInWithWhatsAppCode': _refused(message),
          });
          final error = await HubAppWhatsAppSignIn(client)
              .signIn(_mobile, '000000')
              .then<Object>((_) => fail('should refuse'), onError: (e) => e);
          expect(
            error,
            isA<Failure>()
                .having((f) => f.kind, 'kind', FailureKind.auth)
                .having((f) => f.detail, 'detail', message),
          );
          expect(_classify(error).kind, AuthErrorKind.invalidCode);
        },
      );
    }

    test('the refusal sent as HTTP 401 reads the same', () async {
      final client = fakeHubAppClient({
        'HmSignInWithWhatsAppCode': ServerException(
          parsedResponse: _refused(_uniformEn),
        ),
      });
      final error = await HubAppWhatsAppSignIn(client)
          .signIn(_mobile, '000000')
          .then<Object>((_) => fail('should refuse'), onError: (e) => e);
      expect(_classify(error).kind, AuthErrorKind.invalidCode);
    });

    test('no connection reads as offline', () async {
      final client = fakeHubAppClient({
        'HmSendWhatsAppCode': Exception('Connection refused'),
      });
      final error = await HubAppWhatsAppSignIn(client)
          .sendCode(_mobile)
          .then<Object>((_) => fail('should fail'), onError: (e) => e);
      expect(_classify(error).kind, AuthErrorKind.offline);
    });

    test('a server without the module throws HubAppMissing', () async {
      final client = fakeHubAppClient({
        'HmSendWhatsAppCode': hubAppMissingResponse(
          'hmSendWhatsAppCode',
          type: 'Mutation',
        ),
      });
      await expectLater(
        HubAppWhatsAppSignIn(client).sendCode(_mobile),
        throwsA(isA<HubAppMissing>()),
      );
    });

    test('no document declares a variable of an Hm* type', () {
      for (final document in [
        HubAppSignInQueries.sendCode,
        HubAppSignInQueries.signIn,
      ]) {
        expect(document, isNot(matches(RegExp(r'\$\w+\s*:\s*\[?Hm'))));
      }
    });
  });

  group('AuthRepository picks the transport', () {
    test('GraphQL when the server has it; REST is left alone', () async {
      final rest = _Rest();
      final gql = fakeHubAppClient({
        'HmSendWhatsAppCode': _sent(),
        'HmSignInWithWhatsAppCode': _token(),
      });
      final repo = AuthRepository(
        fakeGraphQLClient(),
        rest.api,
        graphqlSignIn: HubAppWhatsAppSignIn(gql),
      );
      expect(await repo.requestLoginOtp(_mobile), 30);
      expect(await repo.loginWithOtp(_mobile, '123456'), 'hub-token');
      expect(gql.requests.map(operationNameOf), [
        'HmSendWhatsAppCode',
        'HmSignInWithWhatsAppCode',
      ]);
      expect(rest.requests, isEmpty);
    });

    test('Build 1: REST, with no cooldown to report', () async {
      final rest = _Rest();
      final repo = AuthRepository(fakeGraphQLClient(), rest.api);
      expect(await repo.requestLoginOtp(_mobile), isNull);
      expect(await repo.loginWithOtp(_mobile, '123456'), 'rest-token');
      expect(rest.actions, ['send', 'verify']);
    });

    test('a server without the GraphQL pair falls back to REST', () async {
      final rest = _Rest();
      var missing = 0;
      final gql = fakeHubAppClient({
        'HmSendWhatsAppCode': hubAppMissingResponse(
          'hmSendWhatsAppCode',
          type: 'Mutation',
        ),
        'HmSignInWithWhatsAppCode': hubAppMissingResponse(
          'hmSignInWithWhatsAppCode',
          type: 'Mutation',
        ),
      });
      final repo = AuthRepository(
        fakeGraphQLClient(),
        rest.api,
        graphqlSignIn: HubAppWhatsAppSignIn(gql),
        onGraphqlMissing: () => missing++,
      );
      expect(await repo.requestLoginOtp(_mobile), isNull);
      expect(await repo.loginWithOtp(_mobile, '123456'), 'rest-token');
      expect(rest.actions, ['send', 'verify']);
      expect(missing, 2);
    });

    test('a refusal is never retried over REST', () async {
      final rest = _Rest();
      final repo = AuthRepository(
        fakeGraphQLClient(),
        rest.api,
        graphqlSignIn: HubAppWhatsAppSignIn(
          fakeHubAppClient({
            'HmSendWhatsAppCode': _sent(sent: false, message: _throttleEn),
            'HmSignInWithWhatsAppCode': _refused(_uniformEn),
          }),
        ),
      );
      await expectLater(repo.requestLoginOtp(_mobile), throwsA(isA<Failure>()));
      await expectLater(
        repo.loginWithOtp(_mobile, '000000'),
        throwsA(isA<Failure>()),
      );
      expect(rest.requests, isEmpty);
    });
  });

  group('authRepositoryProvider', () {
    Future<List<String>> sendWith(Override hubApp) async {
      final rest = _Rest();
      final gql = fakeHubAppClient({'HmSendWhatsAppCode': _sent()});
      final container = ProviderContainer(
        overrides: [
          hubApp,
          guestGraphqlClientProvider.overrideWithValue(gql),
          graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
          whatsAppOtpApiProvider.overrideWithValue(rest.api),
        ],
      );
      addTearDown(container.dispose);
      // The probe has answered by the time anyone signs in (it runs at launch).
      await container.read(hubAppProvider.future);
      await container.read(authRepositoryProvider).requestLoginOtp(_mobile);
      return [
        for (final r in gql.requests) 'graphql:${operationNameOf(r)}',
        for (final action in rest.actions) 'rest:$action',
      ];
    }

    test('GraphQL once HubApp is there with whatsapp_login on', () async {
      expect(
        await sendWith(accountHubApp(storeCredit: false, whatsappLogin: true)),
        ['graphql:HmSendWhatsAppCode'],
      );
    });

    test('REST while the whatsapp_login switch is off', () async {
      expect(await sendWith(accountHubApp(storeCredit: false)), ['rest:send']);
    });

    test('REST on a server without HubApp', () async {
      expect(await sendWith(accountHubApp(deployed: false)), ['rest:send']);
    });

    test('REST while the probe can\'t tell', () async {
      expect(await sendWith(hubAppOverride(const HubAppState.unknown())), [
        'rest:send',
      ]);
    });

    test(
      'REST for the rest of the session once the pair turns out missing',
      () async {
        final rest = _Rest();
        final gql = fakeHubAppClient({
          'HmSendWhatsAppCode': hubAppMissingResponse(
            'hmSendWhatsAppCode',
            type: 'Mutation',
          ),
        });
        final container = ProviderContainer(
          overrides: [
            accountHubApp(storeCredit: false, whatsappLogin: true),
            guestGraphqlClientProvider.overrideWithValue(gql),
            graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
            whatsAppOtpApiProvider.overrideWithValue(rest.api),
          ],
        );
        addTearDown(container.dispose);
        await container.read(hubAppProvider.future);
        await container.read(authRepositoryProvider).requestLoginOtp(_mobile);
        await container.read(authRepositoryProvider).requestLoginOtp(_mobile);
        expect(gql.requests, hasLength(1));
        expect(rest.actions, ['send', 'send']);
        expect(
          container.read(hubAppAccountFeaturesProvider).whatsappSignIn,
          isFalse,
        );
      },
    );
  });

  group('03 → 05 over GraphQL', () {
    Future<({FakeCartRepository cart, FakeHubAppClient gql, _Rest rest})> pump(
      WidgetTester tester, {
      String locale = 'en',
      Map<String, Object>? answers,
    }) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rest = _Rest();
      final gql = fakeHubAppClient(
        answers ??
            {
              'HmSendWhatsAppCode': _sent(),
              'HmSignInWithWhatsAppCode': _token(),
            },
      );
      final cart = FakeCartRepository();
      final cache = FakeLocalCache()..writeString('guest_cart_id', 'guest-1');
      final router = GoRouter(
        initialLocation: AppRoutes.signIn,
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('HOME'))),
          ),
          GoRoute(
            path: AppRoutes.signIn,
            builder: (_, _) => const SignInScreen(),
          ),
          GoRoute(
            path: AppRoutes.verifyCode,
            builder: (_, state) =>
                VerifyCodeScreen(flow: state.extra! as VerifyCodeFlow),
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          accountHubApp(storeCredit: false, whatsappLogin: true),
          guestGraphqlClientProvider.overrideWithValue(gql),
          graphqlClientProvider.overrideWithValue(
            fakeHubAppClient({
              'CurrentCustomer': {
                'customer': {
                  '__typename': 'Customer',
                  'firstname': 'Layla',
                  'lastname': 'Hassan',
                  'email': 'layla@example.com',
                  'mobilenumber': _mobile,
                },
              },
            }),
          ),
          whatsAppOtpApiProvider.overrideWithValue(rest.api),
          secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
          localCacheProvider.overrideWithValue(cache),
          localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
          cartRepositoryProvider.overrideWithValue(cart),
        ],
      );
      addTearDown(container.dispose);
      // The shell keeps the cart alive in the app; here the test does. The
      // HubApp probe has answered by then too (it runs at launch).
      container.listen(cartControllerProvider, (_, _) {});
      await tester.runAsync(() => container.read(hubAppProvider.future));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.light(locale),
            locale: Locale(locale),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (cart: cart, gql: gql, rest: rest);
    }

    Future<void> sendCode(WidgetTester tester, AppLocalizations l10n) async {
      await tester.tap(find.text(l10n.authMethodPhone));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '050 123 4567');
      await tester.tap(find.text(l10n.authSendWhatsappCode));
      await tester.pumpAndSettle();
    }

    testWidgets('signs in with the code, then merges the guest cart', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final fakes = await pump(tester);
      await sendCode(tester, l10n);

      expect(find.byType(VerifyCodeScreen), findsOneWidget);
      // The countdown follows the backend's cooldown (30 s), not 60.
      expect(find.text('00:30'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
      expect(fakes.gql.requests.map(operationNameOf), [
        'HmSendWhatsAppCode',
        'HmSignInWithWhatsAppCode',
      ]);
      expect(fakes.rest.requests, isEmpty);
      expect(fakes.cart.mergeCalls, 1);
    });

    for (final locale in ['en', 'ar']) {
      testWidgets('a send over the limits says so under the number ($locale)', (
        tester,
      ) async {
        final l10n = lookupAppLocalizations(Locale(locale));
        await pump(
          tester,
          locale: locale,
          answers: {
            'HmSendWhatsAppCode': _sent(
              sent: false,
              message: locale == 'ar' ? _throttleAr : _throttleEn,
              resendAfter: 300,
            ),
          },
        );
        await sendCode(tester, l10n);

        expect(find.byType(VerifyCodeScreen), findsNothing);
        expect(find.text(l10n.authErrorTooManyAttempts), findsOneWidget);
      });

      testWidgets('a refused code says so under the boxes ($locale)', (
        tester,
      ) async {
        final l10n = lookupAppLocalizations(Locale(locale));
        final fakes = await pump(
          tester,
          locale: locale,
          answers: {
            'HmSendWhatsAppCode': _sent(),
            'HmSignInWithWhatsAppCode': _refused(
              locale == 'ar' ? _uniformAr : _uniformEn,
            ),
          },
        );
        await sendCode(tester, l10n);
        await tester.enterText(find.byType(TextField), '000000');
        await tester.pumpAndSettle();

        expect(find.byType(VerifyCodeScreen), findsOneWidget);
        expect(find.text(l10n.authErrorInvalidCode), findsOneWidget);
        expect(fakes.cart.mergeCalls, 0);
      });
    }
  });
}
