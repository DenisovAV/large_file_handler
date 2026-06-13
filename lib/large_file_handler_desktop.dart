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
