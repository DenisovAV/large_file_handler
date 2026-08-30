// Driver for `flutter drive`, needed only by the web suite: the Flutter SDK
// supports no other runner for `integration_test` on web. Native platforms use
// `flutter test integration_test/<file>.dart -d <device>` and never come here.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
