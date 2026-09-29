import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/domain/customer_address.dart';
import '../features/account/presentation/account_screen.dart';
import '../features/account/presentation/screens/address_form_screen.dart';
import '../features/account/presentation/screens/addresses_screen.dart';
import '../features/account/presentation/screens/edit_profile_screen.dart';
import '../features/account/domain/order.dart';
import '../features/account/presentation/screens/about_screen.dart';
import '../features/account/presentation/screens/help_screen.dart';
import '../features/account/presentation/screens/order_detail_screen.dart';
import '../features/account/presentation/screens/order_tracking_screen.dart';
import '../features/account/presentation/screens/guest_track_order_screen.dart';
import '../features/account/presentation/screens/orders_screen.dart';
import '../features/account/presentation/screens/payment_methods_screen.dart';
import '../features/account/presentation/screens/settings_screen.dart';
import '../features/auth/presentation/screens/forgot_password_screen.dart';
import '../features/auth/presentation/screens/reset_password_screen.dart';
import '../features/cart/presentation/screens/cart_screen.dart';
import '../features/checkout/presentation/screens/checkout_screen.dart';
import '../features/checkout/presentation/screens/complete_payment_screen.dart';
import '../features/checkout/presentation/screens/order_success_screen.dart';
import '../features/auth/presentation/screens/sign_in_screen.dart';
import '../features/auth/presentation/screens/sign_up_screen.dart';
import '../features/catalog/domain/brand.dart';
import '../features/catalog/domain/product_preview.dart';
import '../features/catalog/presentation/screens/brands_screen.dart';
import '../features/catalog/presentation/screens/categories_screen.dart';
import '../features/catalog/presentation/screens/all_reviews_screen.dart';
import '../features/catalog/presentation/screens/home_screen.dart';
import '../features/catalog/presentation/screens/plp_screen.dart';
import '../features/catalog/presentation/screens/product_detail_screen.dart';
import '../features/catalog/presentation/screens/search_screen.dart';
import '../features/catalog/presentation/screens/write_review_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/wishlist/presentation/screens/wishlist_screen.dart';
import '../features/diagnostics/presentation/health_check_screen.dart';
import '../features/onboarding/presentation/launch_splash_screen.dart';
import '../features/onboarding/presentation/welcome_screen.dart';
import '../core/widgets/web_view_screen.dart';
import 'deep_link_resolver_screen.dart';
import 'routes.dart';

/// The router's [Navigator], exposed so [AppBackSwipe] can drive pops through
/// [NavigatorState.maybePop] (which honours `PopScope`) from above the router.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');

/// App router. Phase 1 wires the catalogue browse flow + global chrome. Auth
/// guards and payment/push deep links land in later phases.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    // Anything the table can't match — in practice an incoming Android App
    // Link like https://hub-market.magento2.click/uae-en/<slug>.html — is handed to the
    // resolver instead of go_router's raw GoException page (CL042-DEV10).
    errorBuilder: (context, state) =>
        DeepLinkResolverScreen(uri: state.uri),
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const LaunchSplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.categories,
        builder: (context, state) => const CategoriesScreen(),
      ),
      GoRoute(
        path: '/subcategories/:uid',
        builder: (context, state) => SubcategoriesScreen(
          categoryUid: state.pathParameters['uid']!,
          title: state.extra as String?,
        ),
      ),
      GoRoute(
        path: '/category/:uid',
        builder: (context, state) => PlpScreen(
          categoryUid: state.pathParameters['uid']!,
          title: state.extra as String?,
        ),
      ),
      GoRoute(
        path: '/product/:urlKey',
        builder: (context, state) => ProductDetailScreen(
          urlKey: state.pathParameters['urlKey']!,
          // Present only when a listing pushed us here; a deep link, a push
          // notification or a restored route arrives without one.
          preview: state.extra is ProductPreview
              ? state.extra! as ProductPreview
              : null,
        ),
      ),
      GoRoute(
        path: AppRoutes.search,
        builder: (context, state) =>
            SearchScreen(initialQuery: state.extra as String?),
      ),
      GoRoute(
        path: AppRoutes.brands,
        builder: (context, state) => const BrandsScreen(),
      ),
      GoRoute(
        path: AppRoutes.reviews,
        builder: (context, state) => const AllReviewsScreen(),
      ),
      GoRoute(
        path: AppRoutes.brand,
        builder: (context, state) =>
            SearchScreen(brand: state.extra as Brand?),
      ),
      GoRoute(
        path: '/review/:sku',
        builder: (context, state) =>
            WriteReviewScreen(sku: state.pathParameters['sku']!),
      ),
      GoRoute(
        path: AppRoutes.cart,
        builder: (context, state) => const CartScreen(),
      ),
      GoRoute(
        path: AppRoutes.wishlist,
        builder: (context, state) => const WishlistScreen(),
      ),
      GoRoute(
        path: AppRoutes.account,
        builder: (context, state) => const AccountScreen(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        // Deep-link friendly: hubmarket://app/reset-password?email=…&token=…
        builder: (context, state) => ResetPasswordScreen(
          initialEmail: state.uri.queryParameters['email'],
          initialToken: state.uri.queryParameters['token'],
        ),
      ),
      GoRoute(
        path: AppRoutes.orders,
        builder: (context, state) => const OrdersScreen(),
      ),
      // Both carry a fully-hydrated order in `extra`, which is in-process memory
      // only: a cold start or an OS deep link arrives with none. Bounce to the
      // list instead of throwing on the cast.
      GoRoute(
        path: AppRoutes.orderDetail,
        redirect: (context, state) =>
            state.extra is CustomerOrder ? null : AppRoutes.orders,
        builder: (context, state) =>
            OrderDetailScreen(order: state.extra! as CustomerOrder),
      ),
      GoRoute(
        path: AppRoutes.orderTracking,
        redirect: (context, state) =>
            state.extra is CustomerOrder ? null : AppRoutes.orders,
        builder: (context, state) =>
            OrderTrackingScreen(order: state.extra! as CustomerOrder),
      ),
      GoRoute(
        path: AppRoutes.guestTrackOrder,
        builder: (context, state) => const GuestTrackOrderScreen(),
      ),
      GoRoute(
        path: AppRoutes.addresses,
        builder: (context, state) => const AddressesScreen(),
      ),
      GoRoute(
        path: AppRoutes.addressForm,
        builder: (context, state) =>
            AddressFormScreen(initial: state.extra as CustomerAddress?),
      ),
      GoRoute(
        path: AppRoutes.paymentMethods,
        builder: (context, state) => const PaymentMethodsScreen(),
      ),
      GoRoute(
        path: AppRoutes.editProfile,
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.help,
        builder: (context, state) => const HelpScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.checkout,
        builder: (context, state) => const CheckoutScreen(),
      ),
      GoRoute(
        path: AppRoutes.orderSuccess,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return OrderSuccessScreen(
            orderNumber: (extra?['number'] as String?) ?? '',
            pendingPayment: (extra?['pending'] as bool?) ?? false,
            deliveryEta: extra?['eta'] as String?,
            deliveryLocation: extra?['location'] as String?,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.completePayment,
        builder: (context, state) =>
            CompletePaymentScreen(args: state.extra as CompletePaymentArgs),
      ),
      GoRoute(
        path: AppRoutes.diagnostics,
        builder: (context, state) => const HealthCheckScreen(),
      ),
      GoRoute(
        path: AppRoutes.webview,
        builder: (context, state) =>
            WebViewScreen(args: state.extra as WebViewArgs),
      ),
    ],
  );
});
