import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'large_file_handler_platform_interface.dart';

/// An implementation of [LargeFileHandlerPlatform] that uses method channels.
class MethodChannelLargeFileHandler extends LargeFileHandlerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('large_file_handler');

  @visibleForTesting
  final progressChannel = const EventChannel('file_download_progress');

  @override
  Future<void> copyAssetToLocalStorage(
      String assetName, String targetName) async {
    final String targetPath = await _getLocalFilePath(targetName);
    await methodChannel.invokeMethod('copyAssetToLocal', {
      'assetName': 'assets/$assetName',
      'targetPath': targetPath,
    });
  }

  @override
  Future<void> copyUrlToLocalStorage(String url, String targetName) async {
    final String targetPath = await _getLocalFilePath(targetName);
    await methodChannel.invokeMethod('copyUrlToLocal', {
      'url': url,
      'targetPath': targetPath,
    });
  }

  @override
  Stream<int> copyAssetToLocalStorageWithProgress(
          String assetName, String targetName) =>
      _progressStream(
        'copyAssetToLocalWithProgress',
        targetName,
        (targetPath) => {
          'assetName': 'assets/$assetName',
          'targetPath': targetPath,
        },
      );

  @override
  Stream<int> copyUrlToLocalStorageWithProgress(
          String url, String targetName) =>
      _progressStream(
        'copyUrlToLocalWithProgress',
        targetName,
        (targetPath) => {'url': url, 'targetPath': targetPath},
      );

  /// Starts a progress-reporting native call and returns its progress stream.
  ///
  /// The invoke future used to be dropped on the floor. A native failure then
  /// went two ways at once, and BOTH of them are silent to the caller: the
  /// returned stream simply CLOSED, so a listener with an `onError` handler saw
  /// a clean completion and concluded the copy had finished, while the
  /// PlatformException surfaced as an unhandled async error with no connection
  /// to the call site. A caller could not detect the failure at all.
  ///
  /// The error is routed into the stream the caller is already listening to.
  Stream<int> _progressStream(
    String method,
    String targetName,
    Map<String, Object?> Function(String targetPath) arguments,
  ) {
    // Broadcast, because that is what `receiveBroadcastStream()` returned and
    // concurrent copies each listen.
    final controller = StreamController<int>.broadcast();
    StreamSubscription<dynamic>? events;
    var eventsDone = false;
    var invokeSettled = false;

    Future<void> stop() async {
      final subscription = events;
      events = null;
      await subscription?.cancel();
      if (!controller.isClosed) await controller.close();
    }

    // Closing is driven by BOTH signals, and that is the whole subtlety. A
    // first cut closed on the event stream's `onDone`, which the native side
    // reaches BEFORE the failing invoke future rejects — so the error arrived
    // at an already-closed controller and was dropped exactly as before.
    // Closing on the invoke instead truncates the trailing 100 on success.
    Future<void> closeWhenBothFinished() async {
      if (invokeSettled && eventsDone) await stop();
    }

    controller.onListen = () {
      events = progressChannel.receiveBroadcastStream().listen(
            (event) => controller.add(event as int),
            onError: (Object error, StackTrace stackTrace) {
              if (!controller.isClosed) controller.addError(error, stackTrace);
            },
            onDone: () {
              eventsDone = true;
              closeWhenBothFinished();
            },
          );

      unawaited(() async {
        try {
          final targetPath = await _getLocalFilePath(targetName);
          await methodChannel.invokeMethod(method, arguments(targetPath));
          invokeSettled = true;
          await closeWhenBothFinished();
        } catch (error, stackTrace) {
          // The native call failed, so no further progress is coming: report
          // and close without waiting for an `onDone` that may never arrive.
          invokeSettled = true;
          if (!controller.isClosed) controller.addError(error, stackTrace);
          await stop();
        }
      }());
    };

    controller.onCancel = stop;

    return controller.stream;
  }

  @override
  Future<bool> fileExists(String targetName) async {
    final String targetPath = await _getLocalFilePath(targetName);
    final bool exists = await methodChannel.invokeMethod<bool>('fileExists', {
          'targetPath': targetPath,
        }) ??
        false;
    return exists;
  }

  Future<String> _getLocalFilePath(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$fileName';
  }
}
