/// Web is the one platform where the asset copy is NOT expected to work.
///
/// Run (web is the documented exception to "never use flutter drive" — the
/// Flutter SDK supports no other runner for integration_test on web):
///   chromedriver --port=4444 &
///   cd example
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/copy_asset_web_test.dart -d chrome
///
/// A browser has no application documents directory, so `LargeFileHandlerWeb`
/// fails every file-system method with `UnsupportedError` rather than silently
/// doing nothing. That is a CONTRACT, and it is the half a native-only suite
/// can never check: this file exists so "unsupported" cannot quietly decay into
/// "returns normally and copies nothing".
///
/// Deliberately no `dart:io` import — this file is compiled by dart2js, and the
/// native suite's `File`/`Platform` use is exactly why the two cannot be one.
@TestOn('chrome')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:large_file_handler/large_file_handler.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('copyAssetToLocalStorage is refused, not silently skipped', (
    _,
  ) async {
    await expectLater(
      LargeFileHandler().copyAssetToLocalStorage(
        assetName: 'example.json',
        targetPath: 'example.json',
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          allOf(contains('copyAssetToLocalStorage'), contains('web')),
        ),
      ),
    );
  });

  testWidgets('the progress stream errors rather than completing empty', (
    _,
  ) async {
    // A `Stream.error` and an empty stream look identical to a caller that only
    // awaits `.last` inside a try — assert the error reaches the listener.
    await expectLater(
      LargeFileHandler().copyAssetToLocalStorageWithProgress(
        assetName: 'example.json',
        targetPath: 'example.json',
      ),
      emitsError(isA<UnsupportedError>()),
    );
  });

  testWidgets('fileExists is refused too', (_) async {
    // Not decoration: `fileExists` returning `false` on web instead of throwing
    // would read as "the file is not there yet" and send a caller into a copy
    // loop that can never succeed.
    await expectLater(
      LargeFileHandler().fileExists(targetPath: 'example.json'),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
