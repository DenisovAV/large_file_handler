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

  UnsupportedError _unsupportedError(String method) =>
      UnsupportedError('LargeFileHandler.$method is not supported on web.');

  @override
  Future<void> copyAssetToLocalStorage(String assetName, String targetName) =>
      Future.error(_unsupportedError('copyAssetToLocalStorage'));

  @override
  Future<void> copyUrlToLocalStorage(String url, String targetName) =>
      Future.error(_unsupportedError('copyUrlToLocalStorage'));

  @override
  Future<bool> fileExists(String targetPath) =>
      Future.error(_unsupportedError('fileExists'));

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
