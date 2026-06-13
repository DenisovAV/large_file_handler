# All-6-Platforms Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `large_file_handler` from Android+iOS to all six Flutter platforms by adding native macOS, pure-Dart Windows/Linux, and an `UnsupportedError`-throwing web implementation, without touching the working Android/iOS native code.

**Architecture:** The federated structure and the public `LargeFileHandler` + `LargeFileHandlerPlatform` interface (5 methods) stay unchanged. macOS reuses the native Swift method/event channels (same `pluginClass`). Windows/Linux register a pure-Dart `LargeFileHandlerDesktop` via `dartPluginClass` (HTTP streaming download, `rootBundle` asset copy). Web registers `LargeFileHandlerWeb` that fails every method honestly.

**Tech Stack:** Dart, `package:http` (desktop download), `package:path_provider` (already present), `flutter_web_plugins` (web Registrar), Swift (macOS, from PR #2), `flutter_test` + `package:http/testing.dart` MockClient.

**Reference spec:** `docs/superpowers/specs/2026-06-13-all-platforms-support-design.md`

**Interface signatures (must match exactly for `@override`):**
```dart
Future<void> copyUrlToLocalStorage(String url, String targetName);
Future<void> copyAssetToLocalStorage(String assetName, String targetName);
Stream<int> copyAssetToLocalStorageWithProgress(String assetName, String targetName);
Stream<int> copyUrlToLocalStorageWithProgress(String url, String targetName);
Future<bool> fileExists(String targetPath);
```

---

## File Structure

- `lib/large_file_handler_web.dart` — NEW. `LargeFileHandlerWeb` + `static registerWith(Registrar)`. Every method throws/streams `UnsupportedError`.
- `lib/large_file_handler_desktop.dart` — NEW. `LargeFileHandlerDesktop` + `static registerWith()`. Pure-Dart impl for Windows/Linux.
- `pubspec.yaml` — MODIFY. Add `http` dep; add macos/windows/linux/web platform entries.
- `macos/` — NEW (from PR #2, podspec cleaned).
- `test/large_file_handler_web_test.dart` — NEW. Web throws.
- `test/large_file_handler_desktop_test.dart` — NEW. Desktop download (MockClient), fileExists, asset copy.
- `README.md` — MODIFY. Supported Platforms + web limitation.
- `CHANGELOG.md` — MODIFY. New version entry.

---

## Task 1: Add `http` dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add http to dependencies**

In `pubspec.yaml`, under `dependencies:`, after the `path_provider` line, add:

```yaml
  http: ^1.2.0
```

So the block reads:
```yaml
dependencies:
  flutter:
    sdk: flutter
  path_provider: ^2.1.4
  plugin_platform_interface: ^2.0.2
  http: ^1.2.0
```

- [ ] **Step 2: Resolve dependencies**

Run: `flutter pub get`
Expected: `Got dependencies!` with no errors.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "build: add http dependency for desktop downloads"
```

---

## Task 2: Web implementation (`LargeFileHandlerWeb`)

**Files:**
- Create: `lib/large_file_handler_web.dart`
- Test: `test/large_file_handler_web_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/large_file_handler_web_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:large_file_handler/large_file_handler_web.dart';

void main() {
  final web = LargeFileHandlerWeb();

  test('copyAssetToLocalStorage throws UnsupportedError', () {
    expect(() => web.copyAssetToLocalStorage('a.json', 'a.json'),
        throwsUnsupportedError);
  });

  test('copyUrlToLocalStorage throws UnsupportedError', () {
    expect(() => web.copyUrlToLocalStorage('https://x/a.json', 'a.json'),
        throwsUnsupportedError);
  });

  test('fileExists throws UnsupportedError', () {
    expect(() => web.fileExists('a.json'), throwsUnsupportedError);
  });

  test('copyAssetToLocalStorageWithProgress emits UnsupportedError', () {
    expect(web.copyAssetToLocalStorageWithProgress('a.json', 'a.json'),
        emitsError(isUnsupportedError));
  });

  test('copyUrlToLocalStorageWithProgress emits UnsupportedError', () {
    expect(web.copyUrlToLocalStorageWithProgress('https://x/a.json', 'a.json'),
        emitsError(isUnsupportedError));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/large_file_handler_web_test.dart`
Expected: FAIL — `large_file_handler_web.dart` does not exist (compile error / target of URI doesn't exist).

- [ ] **Step 3: Write the implementation**

Create `lib/large_file_handler_web.dart`:

```dart
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'large_file_handler_platform_interface.dart';

/// Web implementation of [LargeFileHandlerPlatform].
///
/// A browser has no application documents directory, so the file-system
/// operations this plugin provides cannot be implemented on web. Every method
/// fails with an [UnsupportedError] rather than silently doing nothing.
class LargeFileHandlerWeb extends LargeFileHandlerPlatform {
  /// Registers this class as the default platform instance on web.
  static void registerWith(Registrar registrar) {
    LargeFileHandlerPlatform.instance = LargeFileHandlerWeb();
  }

  Never _unsupported(String method) => throw UnsupportedError(
      'LargeFileHandler.$method is not supported on web.');

  @override
  Future<void> copyAssetToLocalStorage(String assetName, String targetName) =>
      _unsupported('copyAssetToLocalStorage');

  @override
  Future<void> copyUrlToLocalStorage(String url, String targetName) =>
      _unsupported('copyUrlToLocalStorage');

  @override
  Future<bool> fileExists(String targetPath) => _unsupported('fileExists');

  @override
  Stream<int> copyAssetToLocalStorageWithProgress(
          String assetName, String targetName) =>
      Stream<int>.error(UnsupportedError(
          'LargeFileHandler.copyAssetToLocalStorageWithProgress is not supported on web.'));

  @override
  Stream<int> copyUrlToLocalStorageWithProgress(String url, String targetName) =>
      Stream<int>.error(UnsupportedError(
          'LargeFileHandler.copyUrlToLocalStorageWithProgress is not supported on web.'));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/large_file_handler_web_test.dart`
Expected: PASS — all 5 tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/large_file_handler_web.dart test/large_file_handler_web_test.dart
git commit -m "feat(web): add LargeFileHandlerWeb that throws UnsupportedError"
```

---

## Task 3: Desktop — `fileExists` (Windows/Linux)

**Files:**
- Create: `lib/large_file_handler_desktop.dart`
- Test: `test/large_file_handler_desktop_test.dart`

> Note: `LargeFileHandlerDesktop` resolves paths via `getApplicationDocumentsDirectory()`. In unit tests that directory is mocked through the `path_provider` platform channel. To keep tests hermetic, the class exposes a `@visibleForTesting` seam `directoryProvider` defaulting to `getApplicationDocumentsDirectory`.

- [ ] **Step 1: Write the failing test**

Create `test/large_file_handler_desktop_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:large_file_handler/large_file_handler_desktop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LargeFileHandlerDesktop desktop;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lfh_test');
    desktop = LargeFileHandlerDesktop()
      ..directoryProvider = (() async => tempDir);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('fileExists returns false when the file is absent', () async {
    expect(await desktop.fileExists('missing.json'), isFalse);
  });

  test('fileExists returns true when the file is present', () async {
    File('${tempDir.path}/present.json').writeAsStringSync('{}');
    expect(await desktop.fileExists('present.json'), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/large_file_handler_desktop_test.dart`
Expected: FAIL — `large_file_handler_desktop.dart` does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `lib/large_file_handler_desktop.dart`:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'large_file_handler_platform_interface.dart';

/// Pure-Dart implementation of [LargeFileHandlerPlatform] for desktop
/// platforms (Windows and Linux), which have full `dart:io` access.
class LargeFileHandlerDesktop extends LargeFileHandlerPlatform {
  /// Registers this class as the default platform instance.
  static void registerWith() {
    LargeFileHandlerPlatform.instance = LargeFileHandlerDesktop();
  }

  /// Seam for tests: resolves the base directory for relative target paths.
  @visibleForTesting
  Future<Directory> Function() directoryProvider =
      getApplicationDocumentsDirectory;

  Future<String> _resolve(String targetName) async {
    final directory = await directoryProvider();
    return '${directory.path}/$targetName';
  }

  @override
  Future<bool> fileExists(String targetPath) async {
    final resolved = await _resolve(targetPath);
    return File(resolved).exists();
  }

  @override
  Future<void> copyAssetToLocalStorage(String assetName, String targetName) {
    throw UnimplementedError('added in Task 5');
  }

  @override
  Future<void> copyUrlToLocalStorage(String url, String targetName) {
    throw UnimplementedError('added in Task 4');
  }

  @override
  Stream<int> copyAssetToLocalStorageWithProgress(
      String assetName, String targetName) {
    throw UnimplementedError('added in Task 5');
  }

  @override
  Stream<int> copyUrlToLocalStorageWithProgress(String url, String targetName) {
    throw UnimplementedError('added in Task 4');
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/large_file_handler_desktop_test.dart`
Expected: PASS — both fileExists tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/large_file_handler_desktop.dart test/large_file_handler_desktop_test.dart
git commit -m "feat(desktop): add LargeFileHandlerDesktop with fileExists"
```

---

## Task 4: Desktop — network download (with and without progress)

**Files:**
- Modify: `lib/large_file_handler_desktop.dart`
- Test: `test/large_file_handler_desktop_test.dart`

> Uses `package:http`'s `Client` so tests can inject a `MockClient`. The class gets a `@visibleForTesting` `httpClient` seam defaulting to a real `http.Client()`.

- [ ] **Step 1: Write the failing tests**

Append to `test/large_file_handler_desktop_test.dart` (add imports at top):

```dart
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
```

Inside `main()`, add:

```dart
  http.Client clientStreaming(List<int> body, {int? contentLength}) {
    return MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream.value(body),
        200,
        contentLength: contentLength,
      );
    });
  }

  test('copyUrlToLocalStorage writes the downloaded bytes to disk', () async {
    final bytes = Uint8List.fromList(List.generate(2048, (i) => i % 256));
    desktop.httpClient = clientStreaming(bytes, contentLength: bytes.length);

    await desktop.copyUrlToLocalStorage('https://x/file.bin', 'file.bin');

    final written = File('${tempDir.path}/file.bin').readAsBytesSync();
    expect(written, equals(bytes));
  });

  test('copyUrlToLocalStorageWithProgress emits 0..100 ending at 100',
      () async {
    final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));
    desktop.httpClient = clientStreaming(bytes, contentLength: bytes.length);

    final progress = await desktop
        .copyUrlToLocalStorageWithProgress('https://x/file.bin', 'file.bin')
        .toList();

    expect(progress.first, greaterThanOrEqualTo(0));
    expect(progress.last, equals(100));
    expect(progress, equals(progress.toList()..sort()));
    expect(File('${tempDir.path}/file.bin').existsSync(), isTrue);
  });

  test('copyUrlToLocalStorageWithProgress emits 0 then 100 when length unknown',
      () async {
    final bytes = Uint8List.fromList(List.generate(500, (i) => i % 256));
    desktop.httpClient = clientStreaming(bytes, contentLength: null);

    final progress = await desktop
        .copyUrlToLocalStorageWithProgress('https://x/file.bin', 'file.bin')
        .toList();

    expect(progress, equals(<int>[0, 100]));
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/large_file_handler_desktop_test.dart`
Expected: FAIL — `copyUrlToLocalStorage` throws `UnimplementedError`; no `httpClient` field.

- [ ] **Step 3: Implement download**

In `lib/large_file_handler_desktop.dart`, add the import at the top:

```dart
import 'package:http/http.dart' as http;
```

Add the `httpClient` seam after `directoryProvider`:

```dart
  /// Seam for tests: HTTP client used for network downloads.
  @visibleForTesting
  http.Client httpClient = http.Client();
```

Replace the `copyUrlToLocalStorage` method body:

```dart
  @override
  Future<void> copyUrlToLocalStorage(String url, String targetName) async {
    final resolved = await _resolve(targetName);
    final request = http.Request('GET', Uri.parse(url));
    final response = await httpClient.send(request);
    final sink = File(resolved).openWrite();
    try {
      await response.stream.pipe(sink);
    } finally {
      await sink.close();
    }
  }
```

Replace the `copyUrlToLocalStorageWithProgress` method body:

```dart
  @override
  Stream<int> copyUrlToLocalStorageWithProgress(String url, String targetName) {
    final controller = StreamController<int>();

    Future<void> run() async {
      final resolved = await _resolve(targetName);
      final request = http.Request('GET', Uri.parse(url));
      final response = await httpClient.send(request);
      final total = response.contentLength;
      final sink = File(resolved).openWrite();

      if (total == null || total == 0) {
        controller.add(0);
        await response.stream.pipe(sink);
        await sink.close();
        controller.add(100);
        return;
      }

      var received = 0;
      var lastPercent = -1;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        final percent = ((received / total) * 100).floor().clamp(0, 100);
        if (percent != lastPercent) {
          lastPercent = percent;
          controller.add(percent);
        }
      }
      await sink.close();
      if (lastPercent != 100) {
        controller.add(100);
      }
    }

    run().catchError(controller.addError).whenComplete(controller.close);
    return controller.stream;
  }
```

Add the `dart:async` import at the top if not present:

```dart
import 'dart:async';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/large_file_handler_desktop_test.dart`
Expected: PASS — all download tests green (fileExists tests still pass).

- [ ] **Step 5: Commit**

```bash
git add lib/large_file_handler_desktop.dart test/large_file_handler_desktop_test.dart
git commit -m "feat(desktop): stream network downloads with progress"
```

---

## Task 5: Desktop — asset copy (with and without progress)

**Files:**
- Modify: `lib/large_file_handler_desktop.dart`
- Test: `test/large_file_handler_desktop_test.dart`

> Asset bytes come from `rootBundle`. Tests inject a fake loader through an `assetLoader` seam (signature `Future<ByteData> Function(String key)`) defaulting to `rootBundle.load`. Asset names are prefixed with `assets/`, matching `MethodChannelLargeFileHandler`.

- [ ] **Step 1: Write the failing tests**

Append to `test/large_file_handler_desktop_test.dart` (add import at top):

```dart
import 'package:flutter/services.dart' show ByteData;
```

Inside `main()`, add:

```dart
  ByteData byteDataOf(List<int> bytes) =>
      ByteData.view(Uint8List.fromList(bytes).buffer);

  test('copyAssetToLocalStorage writes asset bytes to disk', () async {
    final bytes = List.generate(128, (i) => i);
    desktop.assetLoader = (key) async {
      expect(key, equals('assets/data.json'));
      return byteDataOf(bytes);
    };

    await desktop.copyAssetToLocalStorage('data.json', 'data.json');

    final written = File('${tempDir.path}/data.json').readAsBytesSync();
    expect(written, equals(bytes));
  });

  test('copyAssetToLocalStorageWithProgress emits 0 then 100', () async {
    final bytes = List.generate(64, (i) => i);
    desktop.assetLoader = (key) async => byteDataOf(bytes);

    final progress = await desktop
        .copyAssetToLocalStorageWithProgress('data.json', 'data.json')
        .toList();

    expect(progress, equals(<int>[0, 100]));
    expect(File('${tempDir.path}/data.json').readAsBytesSync(), equals(bytes));
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/large_file_handler_desktop_test.dart`
Expected: FAIL — `copyAssetToLocalStorage` throws `UnimplementedError`; no `assetLoader` field.

- [ ] **Step 3: Implement asset copy**

In `lib/large_file_handler_desktop.dart`, add imports at the top:

```dart
import 'dart:typed_data';

import 'package:flutter/services.dart' show ByteData, rootBundle;
```

Add the `assetLoader` seam after `httpClient`:

```dart
  /// Seam for tests: loads asset bytes by key (e.g. `assets/foo.json`).
  @visibleForTesting
  Future<ByteData> Function(String key) assetLoader = rootBundle.load;
```

Replace the `copyAssetToLocalStorage` method body:

```dart
  @override
  Future<void> copyAssetToLocalStorage(
      String assetName, String targetName) async {
    final resolved = await _resolve(targetName);
    final data = await assetLoader('assets/$assetName');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    await File(resolved).writeAsBytes(bytes);
  }
```

Replace the `copyAssetToLocalStorageWithProgress` method body:

```dart
  @override
  Stream<int> copyAssetToLocalStorageWithProgress(
      String assetName, String targetName) {
    final controller = StreamController<int>();

    Future<void> run() async {
      controller.add(0);
      await copyAssetToLocalStorage(assetName, targetName);
      controller.add(100);
    }

    run().catchError(controller.addError).whenComplete(controller.close);
    return controller.stream;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/large_file_handler_desktop_test.dart`
Expected: PASS — all desktop tests green.

- [ ] **Step 5: Run the full Dart test suite + analyze**

Run: `flutter test`
Expected: PASS — all tests (web + desktop) green.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/large_file_handler_desktop.dart test/large_file_handler_desktop_test.dart
git commit -m "feat(desktop): copy assets via rootBundle with progress"
```

---

## Task 6: macOS native implementation (from PR #2)

**Files:**
- Create: `macos/Classes/LargeFileHandlerPlugin.swift`
- Create: `macos/large_file_handler.podspec`
- Create: `macos/Resources/PrivacyInfo.xcprivacy`
- Create: `macos/Assets/.gitkeep`
- Create: `macos/.gitignore`

> Source the file contents from PR #2 (`gh pr diff 2`). Author them into the working tree directly (do not merge the PR branch, to keep the cleaned podspec). The Swift already implements all 5 methods with asset streaming via `InputStream`/`OutputStream`.

- [ ] **Step 1: Fetch PR #2 file contents**

Run: `gh pr diff 2`
Use the diff to create each `macos/...` file with the `+`-side content.

- [ ] **Step 2: Create the macOS Swift plugin**

Create `macos/Classes/LargeFileHandlerPlugin.swift` with the full Swift content from PR #2 (the `LargeFileHandlerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler` class implementing `copyAssetToLocal`, `copyAssetToLocalWithProgress`, `copyUrlToLocal`, `copyUrlToLocalWithProgress`, `fileExists`).

- [ ] **Step 3: Create the cleaned podspec**

Create `macos/large_file_handler.podspec` based on PR #2 but with placeholders replaced to match `ios/large_file_handler.podspec`:

```ruby
Pod::Spec.new do |s|
  s.name             = 'large_file_handler'
  s.version          = '0.4.1'
  s.summary          = 'Copy large files from assets or download them from the network to local storage.'
  s.description      = <<-DESC
Efficiently copy large files from Flutter assets or download them from the network to the device's local file system, with optional progress tracking.
                       DESC
  s.homepage         = 'https://github.com/DenisovAV/large_file_handler'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Sasha Denisov' => 'denisov.shureg@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
```

> Cross-check against `ios/large_file_handler.podspec` for the exact `version`, `summary`, `description`, `homepage`, and `author` strings, and use those values verbatim if they differ from the above.

- [ ] **Step 4: Create remaining macOS files**

Create `macos/Resources/PrivacyInfo.xcprivacy` (content from PR #2), `macos/Assets/.gitkeep` (empty), and `macos/.gitignore` (content from PR #2).

- [ ] **Step 5: Register macOS in pubspec.yaml**

In `pubspec.yaml`, inside `plugin: platforms:`, after the `ios:` entry, add:

```yaml
      macos:
        pluginClass: LargeFileHandlerPlugin
```

- [ ] **Step 6: Build the example for macOS**

Run: `cd example && flutter pub get && flutter build macos --debug`
Expected: build succeeds (`✓ Built build/macos/.../example.app`).

- [ ] **Step 7: Commit**

```bash
git add macos pubspec.yaml
git commit -m "feat(macos): add native macOS implementation (from PR #2, podspec cleaned)"
```

---

## Task 7: Register Windows/Linux/Web in pubspec.yaml

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the platform entries**

In `pubspec.yaml`, inside `plugin: platforms:`, after the `macos:` entry, add:

```yaml
      windows:
        dartPluginClass: LargeFileHandlerDesktop
      linux:
        dartPluginClass: LargeFileHandlerDesktop
      web:
        pluginClass: LargeFileHandlerWeb
        fileName: large_file_handler_web.dart
```

The full `platforms:` block should now list: android, ios, macos, windows, linux, web.

- [ ] **Step 2: Verify analyze and dry-run**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter pub publish --dry-run`
Expected: `Package has 0 warnings.` and the platforms are recognized.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml
git commit -m "feat: declare windows, linux, and web platforms"
```

---

## Task 8: Documentation (README + CHANGELOG)

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update README Supported Platforms**

In `README.md`, replace the `## Supported Platforms` section:

```markdown
## Supported Platforms

| Platform | Support |
|----------|---------|
| Android  | ✅ Full (native) |
| iOS      | ✅ Full (native) |
| macOS    | ✅ Full (native) |
| Windows  | ✅ Full (pure Dart) |
| Linux    | ✅ Full (pure Dart) |
| Web      | ⛔ Not supported — see below |

### Web

A browser has no application documents directory, so this plugin cannot copy or
download files to a local file path on web. Every method throws an
`UnsupportedError`. Guard your calls with `kIsWeb`, or catch the error:

\```dart
import 'package:flutter/foundation.dart' show kIsWeb;

if (!kIsWeb) {
  await LargeFileHandler().copyAssetToLocalStorage(
    assetName: 'example.json',
    targetPath: 'example.json',
  );
}
\```
```

Also update line 9 of the Features list from `Cross-platform support for both Android and iOS.` to `Cross-platform support: Android, iOS, macOS, Windows, and Linux.`

- [ ] **Step 2: Update CHANGELOG**

In `CHANGELOG.md`, add a new entry at the top:

```markdown
## 0.5.0
Added macOS, Windows, and Linux support; web now throws UnsupportedError instead of failing to compile
```

- [ ] **Step 3: Bump version in pubspec.yaml and podspecs**

In `pubspec.yaml` change `version: 0.4.1` to `version: 0.5.0`.
In `ios/large_file_handler.podspec` and `macos/large_file_handler.podspec` change `s.version` to `'0.5.0'`.

- [ ] **Step 4: Verify**

Run: `flutter pub publish --dry-run`
Expected: `Package has 0 warnings.`

- [ ] **Step 5: Commit**

```bash
git add README.md CHANGELOG.md pubspec.yaml ios/large_file_handler.podspec macos/large_file_handler.podspec
git commit -m "docs: document all-platform support; bump to 0.5.0"
```

---

## Task 9: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Full analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 3: Format check**

Run: `dart format --output=none --set-exit-if-changed .`
Expected: exit 0 (no files need formatting).

- [ ] **Step 4: pana score (must remain 160/160)**

Run: `pana --no-warning --json . > /tmp/pana_final.json 2>/dev/null` then inspect sections.
Expected: TOTAL 160/160; Platform support still 20/20; Static analysis 50/50.

- [ ] **Step 5: macOS example build (darwin only)**

Run: `cd example && flutter build macos --debug`
Expected: build succeeds.

> Note: Windows and Linux builds cannot be verified on this darwin machine. Their Dart implementation is exercised by the hermetic unit tests in Task 3–5; on-hardware Win/Linux behavior is left untested here and should be validated by a contributor on those platforms before relying on it.

---

## Self-Review Notes

- **Spec coverage:** web UnsupportedError (Task 2) ✓; desktop fileExists (Task 3) ✓; desktop download + progress incl. no-contentLength branch (Task 4) ✓; desktop asset copy via rootBundle + 0/100 progress (Task 5) ✓; macOS native from PR #2 with podspec cleanup (Task 6) ✓; pubspec registration for all (Task 6 macos, Task 7 win/linux/web) ✓; http dependency (Task 1) ✓; README web contract + CHANGELOG (Task 8) ✓; pana stays 160 (Task 9) ✓.
- **Type consistency:** seams named `directoryProvider`, `httpClient`, `assetLoader` used identically across Tasks 3–5. Method signatures match the interface (`copyUrlToLocalStorage(String url, String targetName)`, `fileExists(String targetPath)`, etc.).
- **No placeholders:** every code step contains full code; macOS Swift sourced from PR #2 via `gh pr diff 2` (external artifact, content not duplicated here by necessity, but exact source command given).
