import 'package:integration_test/integration_test.dart';
import '../test/city_manager_test.dart' as city_manager;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  city_manager.main();
}
