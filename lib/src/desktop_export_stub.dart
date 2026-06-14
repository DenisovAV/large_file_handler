/// Web stub: the desktop implementation imports `dart:io`, which is not
/// available on web. On web this exposes a placeholder so the package's main
/// library can be imported without pulling `dart:io` into the web (and WASM)
/// compilation graph. The desktop class is never used on web.
///
/// This class is intentionally never registered or instantiated on web.
class LargeFileHandlerDesktop {
  /// No-op on web. The real implementation lives in
  /// `large_file_handler_desktop.dart` and is only loaded on platforms with
  /// `dart:io` (Windows and Linux via `dartPluginClass`).
  static void registerWith() {}
}
