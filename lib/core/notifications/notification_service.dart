import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Background message handler — runs in its own isolate; keep it minimal.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {}

/// A received notification surfaced to the app for the local inbox.
class NotificationMessage {
  const NotificationMessage({
    this.title,
    this.body,
    this.data = const <String, dynamic>{},
  });

  final String? title;
  final String? body;
  final Map<String, dynamic> data;
}

/// App-side push plumbing. Local notifications work standalone; FCM is enabled
/// only when a Firebase config is bundled — `android/app/google-services.json`
/// (the Gradle build applies the google-services plugin only when that file
/// exists) and `ios/Runner/GoogleService-Info.plist` in the Runner target.
/// Without one, every FCM call degrades to a no-op and the app runs normally.
///
/// Hub Market ships none yet: the previous client's Firebase project was
/// deliberately not carried over, and this app must never register devices
/// with it. Adding Hub Market's own config files turns FCM on with no code
/// change.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _fcmAvailable = false;
  String? _initError;

  bool get fcmAvailable => _fcmAvailable;

  /// The `Firebase.initializeApp` failure reason, if FCM is unavailable. Shown
  /// on the diagnostics screen to tell an init failure apart from a not-yet-
  /// ready APNs token.
  String? get initError => _initError;

  /// The raw APNs device token (iOS/macOS) — null until the OS hands it to
  /// Firebase (requires Push capability in the provisioning profile, granted
  /// notification permission, a physical device, and network). When this is
  /// null but [fcmAvailable] is true, the problem is APNs/provisioning, not
  /// Firebase init.
  Future<String?> apnsToken() async {
    if (!_fcmAvailable) return null;
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      return 'n/a (not iOS)';
    }
    try {
      return await FirebaseMessaging.instance.getAPNSToken();
    } catch (error) {
      return 'error: $error';
    }
  }

  /// The native APNs registration outcome recorded by the AppDelegate
  /// (`registered OK …` or `FAILED: <reason>`), or null if neither callback has
  /// fired yet. Distinguishes a *registration failure* (entitlement/network)
  /// from registration succeeding but the token not reaching Firebase.
  Future<String?> apnsRegistrationStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('apnsRegStatus');
    } catch (_) {
      return null;
    }
  }

  /// The current notification authorization status (`authorized` / `denied` /
  /// `notDetermined` / `provisional`).
  Future<String> permissionStatus() async {
    if (!_fcmAvailable) return 'n/a (FCM off)';
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return settings.authorizationStatus.name;
    } catch (error) {
      return 'error';
    }
  }

  /// Data payloads of notifications the user tapped (foreground-local or a
  /// backgrounded FCM message). The app layer maps these to a route. Stays
  /// UI-agnostic — core doesn't know about app routes.
  final StreamController<Map<String, dynamic>> _opened =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onNotificationOpened => _opened.stream;

  /// Every received notification (foreground push, or a tapped/cold-start one),
  /// for persisting into the local inbox. UI-agnostic.
  final StreamController<NotificationMessage> _received =
      StreamController<NotificationMessage>.broadcast();

  Stream<NotificationMessage> get onNotificationReceived => _received.stream;

  void _ingest(RemoteMessage message) {
    final notification = message.notification;
    final data = Map<String, dynamic>.from(message.data);
    if (notification == null && data.isEmpty) return;
    _received.add(
      NotificationMessage(
        title: notification?.title ?? data['title'] as String?,
        body: notification?.body ?? data['body'] as String?,
        data: data,
      ),
    );
  }

  Map<String, dynamic>? _initial;

  /// The notification that cold-started the app, if any. Consumed once (so the
  /// app navigates to it exactly once, after the first frame).
  Map<String, dynamic>? takeInitialMessage() {
    final message = _initial;
    _initial = null;
    return message;
  }

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'hubmarket_default',
    'General',
    description: 'Order updates and promotions',
    importance: Importance.high,
  );

  /// Sets up local notifications (silently) and, when a Firebase config is
  /// bundled, FCM — and only then asks for notification permission.
  ///
  /// Local notifications exist here to show foreground pushes, so without FCM
  /// there is nothing to ask permission for: no "Allow notifications?" dialog
  /// over the splash of a build that cannot receive a push, and
  /// `FirebaseMessaging` is never touched.
  Future<void> init() async {
    await _initLocal();
    await _initFirebase();
  }

  Future<void> _initLocal() async {
    const settings = InitializationSettings(
      // White status-bar silhouette (res/drawable/ic_stat_notify) — the colour
      // launcher icon would render as a white square in the status bar.
      android: AndroidInitializationSettings('ic_stat_notify'),
      // The Darwin defaults request permission on initialize — i.e. at launch.
      // Permission is requested with FCM instead (see _initFirebase).
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _local.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onLocalTap,
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
  }

  /// Initialises Firebase from the bundled platform config only — never from
  /// options compiled into the app, so there is no path by which a build could
  /// talk to another client's Firebase project. With no config bundled (the
  /// state of this app today) `initializeApp` throws, FCM stays off, and
  /// nothing else depends on it.
  Future<void> _initFirebase() async {
    try {
      await Firebase.initializeApp();
      _fcmAvailable = true;
    } catch (error) {
      // No Firebase config bundled — FCM stays disabled.
      _fcmAvailable = false;
      _initError = error.toString();
      debugPrint('FCM disabled (Firebase.initializeApp failed): $error');
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // With a real config, iOS init still fails if GoogleService-Info.plist
        // isn't in the Runner target's Copy Bundle Resources, or the running
        // flavor's bundle id doesn't match the plist's BUNDLE_ID.
        debugPrint(
          'iOS: add GoogleService-Info.plist to the Runner target (matching '
          'the flavor bundle id) to enable FCM.',
        );
      }
      return;
    }
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      // The one permission prompt: iOS alert/badge/sound, and POST_NOTIFICATIONS
      // on Android 13+ (which also covers the local notifications that show
      // foreground pushes). Only reached with a working FCM setup.
      await FirebaseMessaging.instance.requestPermission();
      FirebaseMessaging.onMessage.listen(_showRemote);
      // Tapped while backgrounded → navigate (and record in the inbox). Cold-
      // start tap is captured once via getInitialMessage and replayed after the
      // first frame.
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        _ingest(m);
        _emit(m.data);
      });
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _ingest(initial);
        if (initial.data.isNotEmpty) {
          _initial = Map<String, dynamic>.from(initial.data);
        }
      }
    } catch (error) {
      debugPrint('FCM setup error: $error');
    }
  }

  void _onLocalTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) _emit(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // Non-JSON payload — ignore.
    }
  }

  void _emit(Map<String, dynamic> data) {
    if (data.isNotEmpty) _opened.add(data);
  }

  Future<void> _showRemote(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _local.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      // Carry the data so tapping the foreground notification routes too.
      payload: message.data.isEmpty ? null : jsonEncode(message.data),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_notify',
          color: Color(0xFF9E1B3F),
        ),
        // Present a banner/sound even while the app is foregrounded (iOS
        // suppresses foreground pushes by default).
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
    );
    // Surface to the local inbox.
    _ingest(message);
  }

  Future<void> subscribeToTopic(String topic) async {
    if (!_fcmAvailable) return;
    await FirebaseMessaging.instance.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    if (!_fcmAvailable) return;
    await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
  }

  /// The FCM registration token, or null when unavailable.
  ///
  /// On iOS/macOS `getToken()` cannot resolve until APNs has handed Firebase a
  /// device token — calling it too early (e.g. at app launch, right after
  /// login) throws `apns-token-not-set` or returns null, which is why the
  /// device token wasn't registering on iOS. So we wait briefly for the APNs
  /// token first and never throw; if it's still not ready, [onTokenRefresh]
  /// drives a later registration. Android has no APNs step and is unaffected.
  Future<String?> token() async {
    if (!_fcmAvailable) return null;
    final messaging = FirebaseMessaging.instance;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        var apns = await messaging.getAPNSToken();
        for (var i = 0; i < 5 && apns == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          apns = await messaging.getAPNSToken();
        }
        if (apns == null) return null; // not ready yet — onTokenRefresh catches up
      }
      return await messaging.getToken();
    } catch (error) {
      debugPrint('FCM getToken unavailable: $error');
      return null;
    }
  }

  /// Emits whenever FCM rotates the device token, so the app can re-register it
  /// with the backend. Empty stream when FCM is unavailable.
  Stream<String> get onTokenRefresh => _fcmAvailable
      ? FirebaseMessaging.instance.onTokenRefresh
      : const Stream<String>.empty();
}
