## 0.5.2
Documentation: the README progress examples wrapped `listen` in `try`/`on PlatformException`, which never fires for a stream error — both now pass `onError`. Adds an error-handling section stating the contract 0.5.1 made uniform.

## 0.5.1
Fixed `copyAssetToLocalStorage` failing with "Asset not found error 404" on every macOS run: the asset key returned by `FlutterDartProject.lookupKey(forAsset:)` is relative to the app bundle root and `pathForResource:` only searches Resources, so it could never resolve (#10, thanks @wilinz).

A missing asset now fails the same way on every platform: Windows and Linux reported `rootBundle`'s FlutterError, which the documented `on PlatformException` handler never caught, and the error message now names the asset instead of a bare 404.

A native failure in the `WithProgress` variants now reaches the returned stream. The `invokeMethod` future was dropped, so the stream simply closed and the error surfaced as an unhandled async error elsewhere — a listener could not detect the failure at all.

## 0.5.0
Added macOS, Windows, and Linux support; web now throws UnsupportedError instead of failing to compile. macOS now supports the Swift Package Manager, and the package is WASM-compatible.

Hardened native downloads: iOS now streams non-progress downloads to disk (no longer buffers the whole file in memory) and checks the HTTP status code; Android reads Content-Length from the download response instead of making a separate HEAD request. Migrated Android to Flutter's built-in Kotlin.

Breaking: minimum supported version is now Flutter 3.44 / Dart 3.12 (required by built-in Kotlin). Earlier Flutter versions should use 0.4.x.
## 0.4.1
Shortened package description and added dartdoc comments to the public API
## 0.4.0
Added iOS Swift Package Manager support
## 0.1.0
Initial release
## 0.2.0
Added progress tracking
## 0.2.1
Fixed issues
## 0.2.2
Fixed stream issues
## 0.2.3
Async fixes
## 0.3.0
FileExists method added
## 0.3.1
Download with progress method issue fixes for ios