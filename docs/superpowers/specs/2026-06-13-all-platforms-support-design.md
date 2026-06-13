# Design: Support all 6 platforms in `large_file_handler`

**Date:** 2026-06-13
**Status:** Approved (pending user review of this spec)

## Goal

The plugin currently supports Android + iOS only. Extend it to all six Flutter
platforms (add macOS, Windows, Linux, Web) to widen reach and discoverability.

**Important framing:** the pub.dev score is already 160/160. The "Platform
support" category awards full 20/20 points for 2+ platforms, so adding platforms
does **not** increase the score. The motivation is reach / popularity / search
visibility — and, for web, simply "don't crash when compiled for web".

## Decisions (locked)

| Platform | Approach | Rationale |
|----------|----------|-----------|
| Android  | unchanged (Kotlin, native) | works, published — do not touch |
| iOS      | unchanged (Swift, native)  | works, published — do not touch |
| macOS    | native Swift via PR #2     | API near-identical to iOS; streams assets via `InputStream`/`OutputStream`; PR already implements all 5 methods |
| Windows  | Dart-only (`dartPluginClass`) | desktop has full `dart:io`; no native code to maintain |
| Linux    | Dart-only (`dartPluginClass`) | same Dart impl shared with Windows |
| Web      | `UnsupportedError` on every method | no app-documents directory in a browser; honest failure, not a silent no-op |

### Why native is still required on mobile (and why Dart-only can't replace it)

Flutter assets on **mobile** are packed inside the APK/IPA (`flutter_assets`),
not laid out as real files. The only Dart way to read them is `rootBundle`,
which loads the **entire** asset into memory as `ByteData`. For *large* files
that risks OOM. The native side (Kotlin `AssetManager` / Swift `Bundle` +
`InputStream`/`OutputStream`) **streams** the asset to disk in chunks without
holding it all in RAM. This is the core reason the package exists. Therefore the
existing native Android/iOS implementations are kept as-is and NOT rewritten in
Dart.

### Desktop asset trade-off (accepted)

On desktop, network download in Dart is fully correct (streams `http` response
chunks straight to disk via `dart:io`, no RAM blow-up). Asset copy, however,
must go through `rootBundle.load()` which loads into RAM — the path to the
desktop asset bundle is not a stable public API, so streaming from it is not
reliable. **Accepted:** desktop asset copy uses `rootBundle` (RAM). Pragmatic
for the common case; very large assets will momentarily occupy memory.

## Architecture

The federated structure is unchanged. The public `LargeFileHandler` and the
`LargeFileHandlerPlatform` interface (5 methods) stay exactly as they are. Three
new platform implementations are added.

```
LargeFileHandler  (public API — unchanged)
   └── LargeFileHandlerPlatform  (interface — unchanged)
        ├── MethodChannelLargeFileHandler   → Android, iOS, macOS  (native, method+event channel)
        ├── LargeFileHandlerDesktop          → Windows, Linux       (NEW, pure Dart)
        └── LargeFileHandlerWeb              → Web                   (NEW, throws UnsupportedError)
```

`pubspec.yaml` platform registration:

```yaml
plugin:
  platforms:
    android: { package: com.example.large_file_handler, pluginClass: LargeFileHandlerPlugin }
    ios:     { pluginClass: LargeFileHandlerPlugin }
    macos:   { pluginClass: LargeFileHandlerPlugin }                                  # NEW
    windows: { dartPluginClass: LargeFileHandlerDesktop }                             # NEW (Dart-only)
    linux:   { dartPluginClass: LargeFileHandlerDesktop }                             # NEW (Dart-only)
    web:     { pluginClass: LargeFileHandlerWeb, fileName: large_file_handler_web.dart } # NEW
```

- `dartPluginClass` registers a Dart class as the platform instance with no
  MethodChannel — this is what lets Windows+Linux run in pure Dart. The class
  MUST expose a `static void registerWith()` that Flutter calls automatically;
  inside it assigns `LargeFileHandlerPlatform.instance = LargeFileHandlerDesktop()`.
- Web uses `pluginClass` + a dedicated `fileName`; web plugins compile to JS and
  also register via a `static void registerWith(Registrar registrar)`
  (from `flutter_web_plugins`) that sets the platform instance.

## Behavior per implementation

### Web (`LargeFileHandlerWeb`) — all methods fail honestly

| Method | Web behavior |
|--------|--------------|
| `copyAssetToLocalStorage` | `throw UnsupportedError('<method> is not supported on web')` |
| `copyNetworkAssetToLocalStorage` | same |
| `fileExists` | `throw UnsupportedError(...)` |
| `copyAssetToLocalStorageWithProgress` | returns `Stream<int>.error(UnsupportedError(...))` |
| `copyNetworkAssetToLocalStorageWithProgress` | returns `Stream<int>.error(UnsupportedError(...))` |

Stream-returning methods must surface the error via `Stream.error(...)` (not a
synchronous `throw`) so consumers catch it uniformly in `.listen(onError:)`.
Error messages name the specific method.

### Windows / Linux (`LargeFileHandlerDesktop`) — pure Dart, real functionality

Path resolution matches `MethodChannelLargeFileHandler`:
`getApplicationDocumentsDirectory()/<targetPath>`; asset names prefixed with
`assets/`. Semantics identical to native — consumer code is the same across all
5 functional platforms.

| Method | Dart implementation |
|--------|---------------------|
| `fileExists` | `File(resolvedPath).exists()` |
| `copyNetworkAssetToLocalStorage` | `http.Client().send()` → stream `response.stream` into an `IOSink` in chunks (no RAM build-up) |
| `copyNetworkAssetToLocalStorageWithProgress` | same + compute progress from `contentLength`; if absent → emit 0 then 100 (matches Android) |
| `copyAssetToLocalStorage` | `rootBundle.load('assets/$name')` → `File.writeAsBytes()` (RAM, accepted) |
| `copyAssetToLocalStorageWithProgress` | `rootBundle.load()` then write; emit 0 then 100 (asset already in memory, no meaningful intermediate progress) |

Network progress is integer percent = accumulated bytes ÷ `contentLength` × 100.
This is actually more accurate than Android (which makes a separate HEAD request
for `Content-Length`); here the length is already in the main response headers.

### macOS

Native Swift from PR #2, parity with iOS (all 5 methods implemented, asset
streaming via `InputStream`/`OutputStream`). PR #2 podspec needs cleanup of
template placeholders before merge (`version 0.0.1`, `summary/description`
"A new Flutter plugin project", `homepage http://example.com`, author
"Your Company") to match the iOS podspec.

## Dependencies

- Add `http: ^1.2.0` to `dependencies` (desktop network download). Official Dart
  team package, lightweight. `path_provider` already present.

## Testing & verification

| What | How |
|------|-----|
| Web throws `UnsupportedError` | Dart unit test: instance = `LargeFileHandlerWeb`, assert `throwsUnsupportedError` on all 5 methods (stream methods via `emitsError`) |
| Desktop network download | Dart unit test with `MockClient` (`package:http/testing.dart`): assert streaming, write, progress 0→100, and the "no contentLength" branch |
| Desktop `fileExists` | unit test against a temp directory |
| Desktop asset copy | test with mocked `rootBundle` (`TestDefaultBinaryMessengerBinding`) |
| Plugin registration | `flutter analyze` + `flutter pub publish --dry-run` validate pubspec for all platforms |
| macOS | `cd example && flutter build macos` (darwin machine — verifiable end-to-end) |

**Honest limitation:** Windows/Linux cannot be built on this darwin machine.
`pub publish --dry-run` + `flutter analyze` validate the pubspec and Dart code,
but real on-hardware behavior for Win/Linux is left untested here and will be
noted as such — not silently claimed as verified.

## Files created / changed

- NEW `lib/large_file_handler_web.dart` (`LargeFileHandlerWeb`)
- NEW `lib/large_file_handler_desktop.dart` (`LargeFileHandlerDesktop`)
- NEW `macos/...` (from PR #2, after podspec cleanup)
- EDIT `pubspec.yaml` (platforms + `http` dependency)
- EDIT `README.md` (Supported Platforms: add the 4 new; document web limitation)
- EDIT `CHANGELOG.md` (new version entry)
- NEW tests under `test/`

## README contract for web

State explicitly: on web the plugin does not perform file operations — it throws
`UnsupportedError`. Apps should guard with `kIsWeb` or catch the error. This is
an explicit contract, not fake "supported on web".

## Out of scope

- Rewriting Android/iOS native code in Dart (would reintroduce the OOM problem
  the package exists to solve).
- A real web storage backend (IndexedDB cache) — explicitly declined; no concrete
  use case, and it would create a leaky abstraction where `targetPath` reads
  differently on web than on `dart:io` platforms.
- Native (C++) Windows/Linux implementations — Dart-only chosen for download
  streaming; asset RAM trade-off accepted.
