/// End-to-end asset copy, on the real platform channel (issue #10).
///
/// Run:
///   cd example
///   flutter test integration_test/copy_asset_test.dart -d macos
///   flutter test integration_test/copy_asset_test.dart -d <ios-device>
///
/// WHY THIS FILE EXISTS
///
/// `copyAssetToLocalStorage` threw `Asset not found error 404` on every macOS
/// run while iOS, with the same asset and the same call, worked. The native
/// lookup resolved the key from `FlutterDartProject.lookupKey(forAsset:)` with
/// `Bundle.main.path(forResource:ofType:)`, which only ever searches the
/// bundle's `Resources` directory — but on macOS that key is a path relative to
/// the .app ROOT:
///   Contents/Frameworks/App.framework/Resources/flutter_assets/assets/x.json
/// so it could never resolve, and nothing in this package ran on macOS to say so.
///
/// Both entry points are covered because the resolution used to be duplicated
/// in `copyAsset` and `copyAssetWithProgress`; fixing one and not the other
/// would leave the progress variant broken under a green suite.
///
/// What this file CANNOT cover is the resources-relative key shape — the engine
/// chooses the shape, not the caller. That branch is the one that already
/// worked and must not regress, and it is covered in
/// `macos/RunnerTests/RunnerTests.swift`, where the lookups are injected.
library;

import 'dart:io';

import 'package:flutter/services.dart' show PlatformException, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:large_file_handler/large_file_handler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _assetName = 'example.json';
const _assetKey = 'assets/$_assetName';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // No setUp: everything that can fail lives in a test body, so a failure is
  // reported as a failing test rather than as an absent one.

  // A fresh target per run. With a fixed name the file left behind by an
  // earlier PASSING run satisfies every assertion after a run that copied
  // nothing at all.
  String freshTarget(String tag) =>
      'lfh_${tag}_${DateTime.now().microsecondsSinceEpoch}.json';

  Future<File> copiedFile(String targetPath) async =>
      File(p.join((await getApplicationDocumentsDirectory()).path, targetPath));

  Future<List<int>> expectedBytes() async =>
      (await rootBundle.load(_assetKey)).buffer.asUint8List();

  testWidgets('copyAssetToLocalStorage writes the asset bytes', (_) async {
    final targetPath = freshTarget('plain');

    await LargeFileHandler().copyAssetToLocalStorage(
      assetName: _assetName,
      targetPath: targetPath,
    );

    expect(
      await LargeFileHandler().fileExists(targetPath: targetPath),
      isTrue,
      reason: 'the copy reported success but nothing landed at $targetPath',
    );

    // Existence is not the assertion that matters: a truncated or empty file
    // satisfies it. The bytes are what the caller asked for.
    final file = await copiedFile(targetPath);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    expect(
      file.readAsBytesSync(),
      await expectedBytes(),
      reason: 'the copied file does not match the bundled asset',
    );
  });

  testWidgets('copyAssetToLocalStorageWithProgress writes the asset bytes', (
    _,
  ) async {
    final targetPath = freshTarget('progress');

    final progress = await LargeFileHandler()
        .copyAssetToLocalStorageWithProgress(
          assetName: _assetName,
          targetPath: targetPath,
        )
        .toList();

    expect(
      progress,
      isNotEmpty,
      reason: 'the progress stream closed without emitting anything',
    );
    expect(
      progress.last,
      100,
      reason: 'the stream ended without reporting completion',
    );
    expect(
      progress,
      everyElement(allOf(greaterThanOrEqualTo(0), lessThanOrEqualTo(100))),
    );

    final file = await copiedFile(targetPath);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    expect(
      file.readAsBytesSync(),
      await expectedBytes(),
      reason: 'the copied file does not match the bundled asset',
    );
  });

  testWidgets('a missing asset fails the same way on every platform', (
    _,
  ) async {
    // One contract, asserted uniformly — which it was NOT before this change.
    // Windows and Linux let `rootBundle`'s FlutterError through, so README's
    // own `on PlatformException` handler never matched there and the failure
    // escaped unhandled; macOS and iOS threw a bare `Asset not found` that
    // named neither the key nor where it looked, which is most of why #10
    // needed a bundle-layout dump to diagnose.
    //
    // Asserting BOTH halves is deliberate: the type is what callers catch, the
    // message is what they can act on. A platform that regresses either one
    // fails here rather than drifting quietly.
    await expectLater(
      LargeFileHandler().copyAssetToLocalStorage(
        assetName: 'definitely_absent.json',
        targetPath: freshTarget('absent'),
      ),
      throwsA(
        isA<PlatformException>().having(
          (e) => '${e.message} ${e.details}',
          'message',
          contains('definitely_absent.json'),
        ),
      ),
    );
  });

  testWidgets('the progress variant fails the same way too', (_) async {
    // The two entry points had duplicated resolution AND duplicated error
    // construction; both are shared per platform now, and this says so.
    await expectLater(
      LargeFileHandler().copyAssetToLocalStorageWithProgress(
        assetName: 'definitely_absent.json',
        targetPath: freshTarget('absent-progress'),
      ),
      emitsThrough(
        emitsError(
          isA<PlatformException>().having(
            (e) => '${e.message} ${e.details}',
            'message',
            contains('definitely_absent.json'),
          ),
        ),
      ),
    );
  });
}
