import 'audit_scene.dart';

/// Cart and checkout: D16 Cart, D17 Shipping, D17a Guest checkout, D18 Payment, D18b Review, D19 Order placed, F_S1 Empty cart, F_S5 Payment failed.
///
/// One scene per frame state, ported from the widget test that renders it (see
/// docs/ui-audit.md, `PAIRS` in tool/ui_audit/pairs.py names the captures).
List<AuditScene> scenes() => [];
