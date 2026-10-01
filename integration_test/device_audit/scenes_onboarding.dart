import 'audit_scene.dart';

/// Onboarding and auth, and the app-wide states: A01 Splash, A01a Launch, A02 Welcome, A03 Sign in, A04 Register, A05 Verify code, A06 Forgot password; F_S3 Offline, F_S4 Loading (home / cart / orders skeletons), F_S6 Sign-in errors, F_S7 Not found.
///
/// One scene per frame state, ported from the widget test that renders it (see
/// docs/ui-audit.md, `PAIRS` in tool/ui_audit/pairs.py names the captures).
List<AuditScene> scenes() => [];
