import 'large_file_handler_platform_interface.dart';

/// Web implementation of [LargeFileHandlerPlatform].
///
/// A browser has no application documents directory, so the file-system
/// operations this plugin provides cannot be implemented on web. Every method
/// fails with an [UnsupportedError] rather than silently doing nothing.
class LargeFileHandlerWeb extends LargeFileHandlerPlatform {
  /// Registers this class as the default platform instance on web.
  ///
  /// The [registrar] parameter is typed as [dynamic] to avoid importing
  /// `flutter_web_plugins` (which depends on `dart:ui_web` and is not
  /// available on the VM test runner). Flutter's plugin registration
  /// mechanism locates this method by name, so the type is not required.
  // ignore: avoid_annotating_with_dynamic
  static void registerWith(dynamic registrar) {
    LargeFileHandlerPlatform.instance = LargeFileHandlerWeb();
  }

  UnsupportedError _unsupportedError(String method) =>
      UnsupportedError('LargeFileHandler.$method is not supported on web.');

  Never _unsupported(String method) => throw _unsupportedError(method);

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
      Stream<int>.error(
          _unsupportedError('copyAssetToLocalStorageWithProgress'));

  @override
  Stream<int> copyUrlToLocalStorageWithProgress(
          String url, String targetName) =>
      Stream<int>.error(_unsupportedError('copyUrlToLocalStorageWithProgress'));
}
