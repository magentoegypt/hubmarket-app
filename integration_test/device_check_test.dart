import 'device_audit_test.dart' as audit;
import 'screenshots_test.dart' as shots;

/// The device audit (every Figma screen on the phone, with fixtures) and the
/// store-listing screenshots (the live catalogue, in the language of
/// SHOT_LOCALE), in ONE run: the Android phone's OS asks for a tap on Install
/// every time an app is installed, so one run is one tap. The two tests run one
/// after the other; their captures share SHOT_OUT_DIR, told apart by name
/// (`en-E21_orders__default.png` against `en-01-home.png`).
///
///   TARGET=integration_test/device_check_test.dart bash tool/device_audit.sh
///
/// To run only the screenshots, give AUDIT_ONLY a value no scene id contains.
void main() {
  audit.main();
  shots.main();
}
