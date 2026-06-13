import 'dart:async';
import 'large_file_handler_platform_interface.dart';

/// Copies large files from Flutter assets or the network to the device's
/// local file system, with optional progress tracking.
///
/// All `targetPath` values are resolved relative to the application's
/// documents directory before being handed to the native implementation.
class LargeFileHandler {
  /// Copies the asset [assetName] (relative to the `assets/` directory) to
  /// [targetPath] on the local file system.
  ///
  /// Completes when the copy finishes. Throws a `PlatformException` if the
  /// asset cannot be found or the copy fails.
  Future<void> copyAssetToLocalStorage(
          {required String assetName, required String targetPath}) =>
      LargeFileHandlerPlatform.instance
          .copyAssetToLocalStorage(assetName, targetPath);

  /// Downloads the file at [assetUrl] to [targetPath] on the local file system.
  ///
  /// Completes when the download finishes. Throws a `PlatformException` if the
  /// URL is invalid or the download fails.
  Future<void> copyNetworkAssetToLocalStorage(
          {required String assetUrl, required String targetPath}) =>
      LargeFileHandlerPlatform.instance
          .copyUrlToLocalStorage(assetUrl, targetPath);

  /// Copies the asset [assetName] to [targetPath], emitting copy progress.
  ///
  /// Returns a [Stream] of integers from 0 to 100 representing the percentage
  /// completed. The stream closes once the copy is finished.
  Stream<int> copyAssetToLocalStorageWithProgress(
          {required String assetName, required String targetPath}) =>
      LargeFileHandlerPlatform.instance
          .copyAssetToLocalStorageWithProgress(assetName, targetPath);

  /// Downloads the file at [assetUrl] to [targetPath], emitting download progress.
  ///
  /// Returns a [Stream] of integers from 0 to 100 representing the percentage
  /// completed. The stream closes once the download is finished.
  Stream<int> copyNetworkAssetToLocalStorageWithProgress(
          {required String assetUrl, required String targetPath}) =>
      LargeFileHandlerPlatform.instance
          .copyUrlToLocalStorageWithProgress(assetUrl, targetPath);

  /// Returns whether a file already exists at [targetPath] on the local
  /// file system.
  Future<bool> fileExists({required String targetPath}) =>
      LargeFileHandlerPlatform.instance.fileExists(targetPath);
}
