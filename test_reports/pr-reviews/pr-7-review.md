# PR Review: #7 — Add macOS, Windows, Linux, and Web platform support (0.5.0)

**Branch:** feature/all-platforms
**Date:** 2026-06-14
**Reviewers:** 8 agents (3 platform-specific + 5 general), per flutter_gemma `review-pr` skill (adapted to this plugin)
**Platforms affected:** macOS (native Swift), Windows/Linux (pure Dart), Web (UnsupportedError), shared federated wiring

**Tooling:** `flutter analyze` clean · `flutter test` 8/8 · `dart format` clean · `pub publish --dry-run` 0 warnings · `pana` 160/160 · macOS + web example builds succeed.

---

## Critical Issues (must fix before merge)

### C1. Desktop download never checks HTTP status — 404/500 body written to disk as "success"
`lib/large_file_handler_desktop.dart:56-65` (`copyUrlToLocalStorage`), `91-119` (`copyUrlToLocalStorageWithProgress`)
`response.statusCode` is never read. A 404/500 response body (HTML/JSON error) is streamed to the target file and the Future/Stream completes successfully; the progress stream even reports 0→100. **Silent data corruption** — newly introduced in this PR. Fix: check `statusCode` is 2xx, else drain stream and throw.

### C2. macOS download never checks HTTP status — same silent corruption
`macos/.../LargeFileHandlerPlugin.swift:200-219` (`downloadFile`/dataTask), `243-275` (`downloadFileWithProgress`)
Neither path casts to `HTTPURLResponse` / reads `statusCode`. Same class of silent corruption as C1, on macOS. (Mirrors a pre-existing iOS gap, but shipped fresh in macOS.) Fix: validate `(200..<300)`, else fail.

### C3. macOS `downloadFileWithProgress` — 3 early-return error paths never close the event stream → Dart progress stream hangs forever
`macos/.../LargeFileHandlerPlugin.swift:236-240, 244-248, 251-255`
Invalid-URL, transport-error, and no-tempURL paths call `result(FlutterError(...))` but never send `FlutterEndOfEventStream` / nil `eventSink`. A caller awaiting the progress stream blocks permanently (no timeout). (Success + catch paths were already fixed earlier this session; these three remain.) Fix: close the event stream — ideally emit a `FlutterError` to the sink — on every early return.

### C4. macOS `copyAssetWithProgress` — force-unwrapped streams crash the app, bypassing catch
`macos/.../LargeFileHandlerPlugin.swift:146-147`
`InputStream(fileAtPath:)!` / `OutputStream(toFileAtPath:)!` return nil if the path/parent dir is invalid → fatal `EXC_BAD_ACCESS`, not a catchable error; `result` never called, stream never closed. Fix: `guard let ... else { throw }` (iOS already does this).

### C5. macOS `downloadFileWithProgress` — `moveItem` fails on every re-download
`macos/.../LargeFileHandlerPlugin.swift:258-260`
`FileManager.moveItem(at:to:)` throws if the destination exists. Other write paths remove-first (`copyFile`, `saveData`); this one doesn't. First download to a path succeeds, every subsequent one throws `DOWNLOAD_ERROR`. Fix: remove existing file before move.

### C6. macOS `copyAssetWithProgress` — silent corrupt file: `outputStream.write` return ignored + division by zero on 0-byte asset
`macos/.../LargeFileHandlerPlugin.swift:160` (write return), `140/162` (÷0)
`write(...)` returns -1 on error (disk full) but is ignored → truncated file reported as success. Separately, a 0-byte asset makes `Double(n)/Double(0)=inf`, and `Int(inf)` traps. Fix: check write return; guard `totalBytes > 0`.

---

## Important Issues (should fix before publishing 0.5.0)

### I1. Web `Future`-returning methods throw synchronously → `.catchError()` never fires
`lib/large_file_handler_web.dart:22-30`
`_unsupported()` is `Never`/throws and the three Future methods are not `async`, so the throw escapes before a Future exists. `foo().catchError(...)` gets an unhandled sync exception; only `try/await` works. Stream methods (correctly) use `Stream.error`. Fix: mark the three methods `async` (or return `Future.error(...)`).

### I2. macOS KVO observer added but never removed → crash on dealloc + duplicate progress events
`macos/.../LargeFileHandlerPlugin.swift:279`
`task.progress.addObserver(...)` with no matching `removeObserver`. Crashes when Progress notifies a freed observer; repeated calls stack observers → duplicate emissions. (Also pre-existing in iOS.) Fix: use `NSKeyValueObservation` token cleared in completion, or `removeObserver`.

### I3. macOS uses strong `self` capture in URLSession closures (iOS uses `[weak self]`)
`macos/.../LargeFileHandlerPlugin.swift:243` — newly introduced divergence from iOS. Combined with I2, keeps the plugin alive after teardown.

### I4. macOS `copyAssetWithProgress` missing parent-dir creation (`ensureDirectoryExists`)
`macos/.../LargeFileHandlerPlugin.swift` — iOS creates intermediate dirs; macOS doesn't. A `targetPath` with a subdir silently fails to open the OutputStream. Related: directory-creation is inconsistent across all 6 impls — either support nested `targetPath` everywhere or document it as flat-filename-only.

### I5. macOS error path sends only `endOfStream`, not an error event, to progress listeners
`macos/.../LargeFileHandlerPlugin.swift:174-180` — a caller listening only to the stream sees normal completion, not failure. Emit a `FlutterError` to the sink before ending.

### I6. `LargeFileHandlerPlatform.instance` lazy getter: `??=` does not cache `null` on web + bypasses `verifyToken`
`lib/large_file_handler_platform_interface.dart:20`
`_instance ??= buildDefaultInstance()` re-calls the stub on every pre-registration access on web (perf footgun), and writes directly to `_instance`, bypassing the `verifyToken` setter. Fix: use an explicit `_initialized` flag and route through the verified setter; give the `StateError` a web-specific hint (mention `kIsWeb` / registration).

### I7. No tests for `LargeFileHandlerWeb`; no error-path test for desktop asset loader; no partial-file-on-error test
The web test was removed (it can't run on the VM once `flutter_web_plugins` is a real import) and not replaced. Web's Stream-vs-throw contract and desktop asset-load failure forwarding are untested. Also: on download error a partial/0-byte file is left on disk and `fileExists` then returns true (caller footgun) — untested and undocumented.

---

## Minor Issues

- **M1.** `@visibleForTesting` seams (`directoryProvider`/`httpClient`/`assetLoader`) are public fields on `LargeFileHandlerDesktop`, which is exported from the main lib → they appear in `dart doc`/autocomplete for consumers. Acceptable (consumers use the `LargeFileHandler` facade) but document as non-API. `lib/large_file_handler_desktop.dart:21-30`
- **M2.** `http.Client` in desktop is never closed (no `dispose()`). Singleton-for-process lifetime; document or add dispose. `desktop.dart:26`
- **M3.** Desktop known-`contentLength` path doesn't emit an initial `0` (asymmetric with the no-length and asset paths). `desktop.dart:103`
- **M4.** `copyUrlToLocalStorage` double-closes sink (`pipe` closes it, then `finally` closes again — idempotent but obscures intent). `desktop.dart:60-65`
- **M5.** Path built with hardcoded `/` instead of `package:path` `join` (works on Windows but non-idiomatic; pre-existing pattern from method_channel). `desktop.dart:32-34`
- **M6.** Tautological monotonicity assertion `expect(progress, equals(progress.toList()..sort()))`. `test/large_file_handler_desktop_test.dart:67`
- **M7.** macOS generic `"ERROR"` code vs iOS typed codes; macOS 1 KB buffer vs iOS 1 MB (perf); `saveData` leaves empty file + leaks FileHandle on error. `macos/.../LargeFileHandlerPlugin.swift:65,178,143,222-233`
- **M8.** Unused `import 'dart:async'` in `lib/large_file_handler.dart:1`.
- **M9.** Stale `CLAUDE.md` "Adding a New Method" guide still lists only iOS+Android (missing desktop/web). `'assets/'` prefix duplicated without a shared constant.

---

## Pre-existing (NOT introduced by this PR — present in shipped iOS/Android)
Flagged for awareness; out of scope for "add platforms":
- KVO observer leak also in iOS download-with-progress (I2 mirrors it).
- Plain (non-progress) iOS download buffers whole file in RAM via `dataTask` (C2's `downloadFile` copied this from iOS).
- Android makes an extra HEAD request for `Content-Length`; Android may not guarantee a terminal `100` before `endOfStream`.
- `outputStream.write` return ignored in iOS too.

## Passed Checks
- WASM isolation correct (`dart.library.io` guard; web never pulls `dart:io`; `is:wasm-ready`).
- macOS SPM structure correct (`Package.swift` + Sources tree; `is:swiftpm-plugin`).
- Conditional import/export pairs have matching signatures; non-conflicting two-mechanism design.
- Desktop streaming download (no full-body buffering), sink try/finally, progress monotonic-ends-at-100, StreamController error forwarding + always-closed.
- Asset `assets/` prefix + offsetInBytes/lengthInBytes correct; path resolution parity with method_channel.
- Web `Stream.error` (not spurious-success-then-error); `Never`-typed helper; registration via real `Registrar`.
- Version consistency (0.5.0 everywhere); `.pubignore` excludes internal docs; no secrets/artifacts in package.

---

## Summary
- **Critical: 6** · **Important: 7** · **Minor: 9**
- **Recommendation: REQUEST CHANGES.**
  Blockers are concentrated in the **macOS Swift** (ported from PR #2, which predates current iOS) and the **HTTP-status-not-checked** silent-corruption bug shared by macOS + desktop. The fastest fix for macOS is to re-port the current `ios/.../LargeFileHandlerPlugin.swift` (it already has `[weak self]`, `ensureDirectoryExists`, `removeExistingFile`, guarded stream opens, typed `FileError`, 1 MB buffer, stream-close on all paths) to `FlutterMacOS`, then add HTTP-status checks to both macOS and desktop, fix the web `async` throw, and add web + error-path tests.
