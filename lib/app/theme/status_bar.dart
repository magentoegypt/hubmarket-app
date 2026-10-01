import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The two status-bar looks of the app, as annotated regions set them. Unlike
/// `SystemUiOverlayStyle.light` / `.dark` they leave the navigation bar alone
/// (those two paint Android's black), which matters for a region that spans the
/// whole screen.
abstract final class StatusBar {
  /// Dark icons, for a light page or header.
  static const SystemUiOverlayStyle onLight = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );

  /// Light icons, for a navy header, the splash or a photo.
  static const SystemUiOverlayStyle onDark = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );
}
