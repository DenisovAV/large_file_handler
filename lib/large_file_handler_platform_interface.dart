import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'large_file_handler_method_channel.dart';

abstract class LargeFileHandlerPlatform extends PlatformInterface {
  /// Constructs a LargeFileHandlerPlatform.
  LargeFileHandlerPlatform() : super(token: _token);

  static final Object _token = Object();

  static LargeFileHandlerPlatform _instance = MethodChannelLargeFileHandler();

  /// The default instance of [LargeFileHandlerPlatform] to use.
  ///
  /// Defaults to [MethodChannelLargeFileHandler].
  static LargeFileHandlerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [LargeFileHandlerPlatform] when
  /// they register themselves.
  static set instance(LargeFileHandlerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Downloads the file at [url] to [targetName] on the local file system.
  Future<void> copyUrlToLocalStorage(String url, String targetName);

  /// Copies the asset [assetName] to [targetName] on the local file system.
  Future<void> copyAssetToLocalStorage(String assetName, String targetName);

  /// Copies the asset [assetName] to [targetName], emitting copy progress
  /// as integers from 0 to 100.
  Stream<int> copyAssetToLocalStorageWithProgress(
      String assetName, String targetName);

  /// Downloads the file at [url] to [targetName], emitting download progress
  /// as integers from 0 to 100.
  Stream<int> copyUrlToLocalStorageWithProgress(String url, String targetName);

  /// Returns whether a file already exists at [targetPath].
  Future<bool> fileExists(String targetPath);
}
