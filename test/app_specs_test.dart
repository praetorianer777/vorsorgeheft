import '../integration_test/helpers/app_harness.dart';
import '../integration_test/specs.dart';
import 'support/synchronous_assets.dart';

/// The same end-to-end specs under the ordinary test binding, so they gate
/// every push instead of waiting for the nightly emulator run.
void main() {
  specAssetBundle = SynchronousAssetBundle();
  registerAppSpecs();
}
