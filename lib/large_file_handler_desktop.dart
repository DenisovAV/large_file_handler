import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:http/http.dart' as http;
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

  /// Seam for tests: HTTP client used for network downloads.
  @visibleForTesting
  http.Client httpClient = http.Client();

  /// Seam for tests: loads asset bytes by key (e.g. `assets/foo.json`).
  @visibleForTesting
  Future<ByteData> Function(String key) assetLoader = rootBundle.load;

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

  @override
  Future<void> copyUrlToLocalStorage(String url, String targetName) async {
    final resolved = await _resolve(targetName);
    final request = http.Request('GET', Uri.parse(url));
    final response = await httpClient.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw HttpException(
        'HTTP ${response.statusCode} downloading $url',
        uri: Uri.parse(url),
      );
    }
    final sink = File(resolved).openWrite();
    try {
      await response.stream.pipe(sink);
    } finally {
      await sink.close();
    }
  }

  @override
  Stream<int> copyAssetToLocalStorageWithProgress(
      String assetName, String targetName) {
    final controller = StreamController<int>();

    Future<void> run() async {
      controller.add(0);
      await copyAssetToLocalStorage(assetName, targetName);
      controller.add(100);
    }

    unawaited(run()
        .then((_) {}, onError: controller.addError)
        .whenComplete(controller.close));
    return controller.stream;
  }

  @override
  Stream<int> copyUrlToLocalStorageWithProgress(String url, String targetName) {
    final controller = StreamController<int>();

    Future<void> run() async {
      final resolved = await _resolve(targetName);
      final request = http.Request('GET', Uri.parse(url));
      final response = await httpClient.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw HttpException(
          'HTTP ${response.statusCode} downloading $url',
          uri: Uri.parse(url),
        );
      }
      final total = response.contentLength;
      final sink = File(resolved).openWrite();
      try {
        if (total == null || total == 0) {
          controller.add(0);
          await response.stream.pipe(sink);
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
        if (lastPercent != 100) {
          controller.add(100);
        }
      } finally {
        await sink.close();
      }
    }

    unawaited(run()
        .then((_) {}, onError: controller.addError)
        .whenComplete(controller.close));
    return controller.stream;
  }
}
