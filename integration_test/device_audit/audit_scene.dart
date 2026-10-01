import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/returns/data/returns_repository.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';

/// The fakes one scene runs with, on top of the audit harness's own
/// (`auditOverrides` in test/support/audit_pump.dart: signed in, the sample
/// stores and customer, empty cart / catalog / wishlist / account / returns,
/// the Hub Market App available). Whatever is left null keeps the harness's.
class AuditSetup {
  const AuditSetup({
    this.account,
    this.returns,
    this.wishlist,
    this.features,
    this.hubApp,
    this.overrides = const [],
  });

  final AccountRepository? account;
  final ReturnsRepository? returns;
  final WishlistRepository? wishlist;
  final StoreFeatures? features;
  final HubAppState? hubApp;

  /// Any other provider the screen reads (reviews, CMS, checkout, stores,
  /// deals ...). Applied last, so they win.
  final List<Override> overrides;
}

/// One screen of the app in one state — what the device audit mounts, settles
/// and captures, in English and Arabic, on the phone itself (and, at the
/// phone's size, in a plain `flutter test` for a quick overflow check). The
/// scene is the unit the audit compares with a Figma frame.
///
/// Ported one-to-one from the widget test that already renders the frame
/// (`captureScreen(tester, key, 'audit_<frame>_<locale>')`): the same screen
/// widget, the same fixtures, the same taps that open a sheet.
class AuditScene {
  AuditScene({
    required this.frame,
    required this.name,
    required this.screen,
    this.setup,
    this.act,
    this.scrolls = 0,
    this.signedIn = true,
    this.pushed = true,
    this.settleMs = 1500,
    this.locales = const ['en', 'ar'],
  });

  /// The Figma frame this shows, as a key of `PAIRS` in tool/ui_audit/pairs.py
  /// (`E21_orders`, `C14_pdp`, `F_S3_offline` ...). A frame with several states
  /// has one scene per state, told apart by [name].
  final String frame;

  /// Tells the states of one [frame] apart: `default`, `empty`, `sheet` ...
  final String name;

  /// The screen widget, as the route builds it.
  final Widget Function(String locale) screen;

  /// The fakes the screen reads (see [AuditSetup]); none keeps the harness's.
  final AuditSetup Function(String locale)? setup;

  /// Runs once the screen has settled and before the capture: tap a button to
  /// open a sheet, type into a field, switch a tab. It must leave the tree
  /// settled (`pumpFor(tester, 400)` after a tap).
  final Future<void> Function(WidgetTester tester, String locale)? act;

  /// How many further captures to take, scrolling the longest vertical
  /// scrollable down by about a screen each time (a tall Figma frame shows the
  /// whole scroll; the phone shows one screen at a time).
  final int scrolls;

  final bool signedIn;

  /// Pushed over Home (an app bar with a back button) or mounted as a tab root.
  final bool pushed;

  /// How long to let the screen settle before the capture, in milliseconds.
  /// Network images in the fixtures need a second or two on the phone.
  final int settleMs;

  final List<String> locales;

  /// `E21_orders__default`: what the capture files are called after the locale
  /// (`en-E21_orders__default.png`).
  String get id => '${frame}__$name';
}
