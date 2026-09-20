import 'package:integration_test/integration_test.dart';

import 'specs.dart';

/// The specs on a real device or emulator, where platform channels, the real
/// asset bundle and the real file system are in play. Run nightly by
/// `android-e2e.yml`, or locally with `ANDROID_E2E=1 ./run-tests.sh`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerAppSpecs();
}
