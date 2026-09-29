# Decision — Push notifications (Phase 5)

App-side plumbing is in `lib/core/notifications/notification_service.dart` and is
started (non-blocking) from `bootstrap()`.

- **Local notifications** (`flutter_local_notifications`) work standalone — a
  default high-importance channel (`zoonze_default`) is created and Android 13+
  notification permission is requested.
- **FCM** (`firebase_messaging`) is enabled **only when a Firebase config is
  bundled**. `Firebase.initializeApp()` is wrapped in a try/catch: with no
  `google-services.json` / `GoogleService-Info.plist`, FCM silently stays
  disabled (`fcmAvailable == false`) and the app still runs. Foreground messages
  are surfaced as local notifications; a background handler is registered.
- **Topics:** the **promotions** topic is opt-in. `notificationSettingsProvider`
  persists the choice (`notif_promotions`, default on) and subscribes /
  unsubscribes `promotions`; `bootstrap()` applies the saved subscription after
  FCM init. Surfaced in **Account → Notifications**
  (`NotificationSettingsScreen`). Order updates are **token-targeted** by the
  backend (not a topic), so they're always delivered.
- **Deep links:** a tapped notification routes into the app. The service emits
  the data payload (`onNotificationOpened` stream + `takeInitialMessage()` for a
  cold-start tap) from `onMessageOpenedApp`, `getInitialMessage`, and the local
  notification tap (data is JSON-encoded into the local payload). `ZoonzeApp`
  listens and navigates via `notificationRoute(data)` (`lib/app/notification_routes.dart`),
  which maps an explicit `route` path or a typed `{type,id}` pair
  (order/product/category/cart/wishlist/promo) to an `AppRoutes` location.
  Platform deep-link config (Android intent-filters / iOS associated domains) is
  the owner step; the routes already exist.

## ⚠️ Owner-provided (Open Q §9)
To turn FCM on:
1. Create/identify the Firebase project.
2. Add `android/app/google-services.json` and apply the Google Services Gradle
   plugin in `android/app/build.gradle` (+ classpath in `android/build.gradle`).
3. Add `ios/Runner/GoogleService-Info.plist` and an **APNs key** in Firebase for
   iOS, plus the Push Notifications + Background Modes capabilities in Xcode.
4. These config files are secrets — keep them out of git (per `.gitignore`).

Once present, no Dart changes are needed; `NotificationService` will detect the
config and enable FCM automatically.
