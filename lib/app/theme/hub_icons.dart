import 'package:flutter/widgets.dart';

/// The Hub Market icon set: Figma "Icons (24px · stroke 2)", which is Lucide.
/// The glyphs come from `assets/fonts/Lucide.ttf` (the official Lucide icon font,
/// ISC licence, `assets/fonts/licenses/Lucide-ISC.txt`); `flutter build` keeps
/// only the glyphs this file's constants name.
///
/// Use them like any icon, at the size the frame asks for (24 in the tab bar and
/// headers, 20 in a field, 18 on a card button, 14 beside a caption):
///
///     Icon(HubIcons.mail, size: 20, color: AppColors.inkMuted)
///
/// Lucide draws outlines only. A filled heart, star or radio dot stays a Material
/// icon (`Icons.star_rounded`, `Icons.favorite`). The arrows and chevrons carry
/// `matchTextDirection`, so a back arrow points to the start edge in both languages
/// without any flipping at the call site.
///
/// To add an icon: find its codepoint in Lucide's `font/lucide.css` (lucide-static),
/// and add a constant named after the Lucide icon in camelCase.
abstract final class HubIcons {
  static const String _family = 'Lucide';

  /// `armchair`
  static const IconData armchair = IconData(0xe2c0, fontFamily: _family);

  /// `arrow-left` — mirrors in a right-to-left layout.
  static const IconData arrowLeft = IconData(
    0xe048,
    fontFamily: _family,
    matchTextDirection: true,
  );

  /// `arrow-right` — mirrors in a right-to-left layout.
  static const IconData arrowRight = IconData(
    0xe049,
    fontFamily: _family,
    matchTextDirection: true,
  );

  /// `arrow-up-down`
  static const IconData arrowUpDown = IconData(0xe37d, fontFamily: _family);

  /// `badge-check`
  static const IconData badgeCheck = IconData(0xe241, fontFamily: _family);

  /// `ban`
  static const IconData ban = IconData(0xe051, fontFamily: _family);

  /// `banknote`
  static const IconData banknote = IconData(0xe052, fontFamily: _family);

  /// `bell`
  static const IconData bell = IconData(0xe059, fontFamily: _family);

  /// `box` — the plain cube. The frames' "icon/package" (the Orders tile, the
  /// help topics) draws this one; [package] is the strapped parcel.
  static const IconData box = IconData(0xe061, fontFamily: _family);

  /// `camera`
  static const IconData camera = IconData(0xe064, fontFamily: _family);

  /// `check`
  static const IconData check = IconData(0xe06c, fontFamily: _family);

  /// `chevron-down`
  static const IconData chevronDown = IconData(0xe06d, fontFamily: _family);

  /// `chevron-left` — mirrors in a right-to-left layout.
  static const IconData chevronLeft = IconData(
    0xe06e,
    fontFamily: _family,
    matchTextDirection: true,
  );

  /// `chevron-right` — mirrors in a right-to-left layout.
  static const IconData chevronRight = IconData(
    0xe06f,
    fontFamily: _family,
    matchTextDirection: true,
  );

  /// `chevron-up`
  static const IconData chevronUp = IconData(0xe070, fontFamily: _family);

  /// `circle-alert`
  static const IconData circleAlert = IconData(0xe077, fontFamily: _family);

  /// `circle-check`
  static const IconData circleCheck = IconData(0xe226, fontFamily: _family);

  /// `circle-help`
  static const IconData circleHelp = IconData(0xe082, fontFamily: _family);

  /// `circle-pause`
  static const IconData circlePause = IconData(0xe07f, fontFamily: _family);

  /// `circle-x`
  static const IconData circleX = IconData(0xe084, fontFamily: _family);

  /// `clock`
  static const IconData clock = IconData(0xe087, fontFamily: _family);

  /// `cloud-off`
  static const IconData cloudOff = IconData(0xe08d, fontFamily: _family);

  /// `construction`
  static const IconData construction = IconData(0xe3b4, fontFamily: _family);

  /// `copy`
  static const IconData copy = IconData(0xe09e, fontFamily: _family);

  /// `credit-card`
  static const IconData creditCard = IconData(0xe0aa, fontFamily: _family);

  /// `download`
  static const IconData download = IconData(0xe0b2, fontFamily: _family);

  /// `dumbbell`
  static const IconData dumbbell = IconData(0xe3a1, fontFamily: _family);

  /// `external-link`
  static const IconData externalLink = IconData(0xe0b9, fontFamily: _family);

  /// `eye`
  static const IconData eye = IconData(0xe0ba, fontFamily: _family);

  /// `eye-off`
  static const IconData eyeOff = IconData(0xe0bb, fontFamily: _family);

  /// `file-text`
  static const IconData fileText = IconData(0xe0cc, fontFamily: _family);

  /// `gift`
  static const IconData gift = IconData(0xe0e1, fontFamily: _family);

  /// `globe`
  static const IconData globe = IconData(0xe0e8, fontFamily: _family);

  /// `headset`
  static const IconData headset = IconData(0xe5bd, fontFamily: _family);

  /// `heart`
  static const IconData heart = IconData(0xe0f2, fontFamily: _family);

  /// `house`
  static const IconData house = IconData(0xe0f5, fontFamily: _family);

  /// `image`
  static const IconData image = IconData(0xe0f6, fontFamily: _family);

  /// `image-off`
  static const IconData imageOff = IconData(0xe1c0, fontFamily: _family);

  /// `images`
  static const IconData images = IconData(0xe5c4, fontFamily: _family);

  /// `info`
  static const IconData info = IconData(0xe0f9, fontFamily: _family);

  /// `landmark`
  static const IconData landmark = IconData(0xe23a, fontFamily: _family);

  /// `laptop`
  static const IconData laptop = IconData(0xe1cd, fontFamily: _family);

  /// `layout-grid`
  static const IconData layoutGrid = IconData(0xe0ff, fontFamily: _family);

  /// `leaf`
  static const IconData leaf = IconData(0xe2de, fontFamily: _family);

  /// `lightbulb`
  static const IconData lightbulb = IconData(0xe1c2, fontFamily: _family);

  /// `link-2-off`
  static const IconData link2Off = IconData(0xe104, fontFamily: _family);

  /// `lock`
  static const IconData lock = IconData(0xe10b, fontFamily: _family);

  /// `log-in`
  static const IconData logIn = IconData(0xe10d, fontFamily: _family);

  /// `log-out`
  static const IconData logOut = IconData(0xe10e, fontFamily: _family);

  /// `mail`
  static const IconData mail = IconData(0xe10f, fontFamily: _family);

  /// `mail-check`
  static const IconData mailCheck = IconData(0xe361, fontFamily: _family);

  /// `map-pin`
  static const IconData mapPin = IconData(0xe111, fontFamily: _family);

  /// `map-pin-plus`
  static const IconData mapPinPlus = IconData(0xe613, fontFamily: _family);

  /// `message-circle`
  static const IconData messageCircle = IconData(0xe116, fontFamily: _family);

  /// `message-square-text`
  static const IconData messageSquareText = IconData(0xe575, fontFamily: _family);

  /// `minus`
  static const IconData minus = IconData(0xe11c, fontFamily: _family);

  /// `monitor-smartphone`
  static const IconData monitorSmartphone = IconData(0xe3a2, fontFamily: _family);

  /// `package`
  static const IconData package = IconData(0xe129, fontFamily: _family);

  /// `party-popper`
  static const IconData partyPopper = IconData(0xe343, fontFamily: _family);

  /// `pen` (the font's legacy `edit-2`) — the plain pencil. The frames'
  /// "icon/edit" draws this one; [pencil] has the ferrule line.
  static const IconData pen = IconData(0xe12f, fontFamily: _family);

  /// `pencil`
  static const IconData pencil = IconData(0xe1f9, fontFamily: _family);

  /// `phone`
  static const IconData phone = IconData(0xe133, fontFamily: _family);

  /// `pill`
  static const IconData pill = IconData(0xe3bd, fontFamily: _family);

  /// `plus`
  static const IconData plus = IconData(0xe13d, fontFamily: _family);

  /// `puzzle`
  static const IconData puzzle = IconData(0xe29c, fontFamily: _family);

  /// `receipt`
  static const IconData receipt = IconData(0xe3d3, fontFamily: _family);

  /// `receipt-text`
  static const IconData receiptText = IconData(0xe5ac, fontFamily: _family);

  /// `refresh-cw`
  static const IconData refreshCw = IconData(0xe145, fontFamily: _family);

  /// `refrigerator`
  static const IconData refrigerator = IconData(0xe37b, fontFamily: _family);

  /// `rotate-ccw`
  static const IconData rotateCcw = IconData(0xe148, fontFamily: _family);

  /// `rotate-ccw-key`
  static const IconData rotateCcwKey = IconData(0xe650, fontFamily: _family);

  /// `scroll-text`
  static const IconData scrollText = IconData(0xe45f, fontFamily: _family);

  /// `search`
  static const IconData search = IconData(0xe151, fontFamily: _family);

  /// `search-x`
  static const IconData searchX = IconData(0xe4ad, fontFamily: _family);

  /// `settings`
  static const IconData settings = IconData(0xe154, fontFamily: _family);

  /// `share-2`
  static const IconData share2 = IconData(0xe156, fontFamily: _family);

  /// `shield`
  static const IconData shield = IconData(0xe158, fontFamily: _family);

  /// `shield-check`
  static const IconData shieldCheck = IconData(0xe1ff, fontFamily: _family);

  /// `shirt`
  static const IconData shirt = IconData(0xe1ca, fontFamily: _family);

  /// `shopping-bag`
  static const IconData shoppingBag = IconData(0xe15b, fontFamily: _family);

  /// `shopping-basket`
  static const IconData shoppingBasket = IconData(0xe4ea, fontFamily: _family);

  /// `shopping-cart`
  static const IconData shoppingCart = IconData(0xe15c, fontFamily: _family);

  /// `sliders-horizontal`
  static const IconData slidersHorizontal = IconData(0xe29a, fontFamily: _family);

  /// `smartphone`
  static const IconData smartphone = IconData(0xe163, fontFamily: _family);

  /// `sparkles`
  static const IconData sparkles = IconData(0xe412, fontFamily: _family);

  /// `square`
  static const IconData square = IconData(0xe167, fontFamily: _family);

  /// `square-check`
  static const IconData squareCheck = IconData(0xe559, fontFamily: _family);

  /// `star` — the outline; a filled star stays `Icons.star_rounded`.
  static const IconData star = IconData(0xe176, fontFamily: _family);

  /// `store`
  static const IconData store = IconData(0xe3e4, fontFamily: _family);

  /// `tag`
  static const IconData tag = IconData(0xe17f, fontFamily: _family);

  /// `trash-2`
  static const IconData trash2 = IconData(0xe18e, fontFamily: _family);

  /// `triangle-alert`
  static const IconData triangleAlert = IconData(0xe193, fontFamily: _family);

  /// `trophy`
  static const IconData trophy = IconData(0xe373, fontFamily: _family);

  /// `truck`
  static const IconData truck = IconData(0xe194, fontFamily: _family);

  /// `user`
  static const IconData user = IconData(0xe19f, fontFamily: _family);

  /// `wallet`
  static const IconData wallet = IconData(0xe204, fontFamily: _family);

  /// `wifi`
  static const IconData wifi = IconData(0xe1ae, fontFamily: _family);

  /// `wifi-off`
  static const IconData wifiOff = IconData(0xe1af, fontFamily: _family);

  /// `x`
  static const IconData x = IconData(0xe1b2, fontFamily: _family);
}
