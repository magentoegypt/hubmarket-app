import 'audit_scene.dart';
import 'scenes_account.dart' as account;
import 'scenes_checkout.dart' as checkout;
import 'scenes_discovery.dart' as discovery;
import 'scenes_onboarding.dart' as onboarding;
import 'scenes_orders.dart' as orders;
import 'scenes_stores_product.dart' as stores_product;

/// Every scene of the device audit, in the order of the Figma frame map
/// (docs/ui-audit.md section 5).
List<AuditScene> allScenes() => [
  ...onboarding.scenes(),
  ...discovery.scenes(),
  ...stores_product.scenes(),
  ...checkout.scenes(),
  ...account.scenes(),
  ...orders.scenes(),
];
