/// Host-side tests for the method-channel implementation.
///
/// The progress variants used to DROP the `invokeMethod` future. A native
/// failure then went two ways at once, and both were invisible to the caller:
/// the returned stream simply closed — so a listener with an `onError` handler
/// saw a clean completion and concluded the copy had finished — while the
/// PlatformException surfaced as an unhandled async error with no connection to
/// the call site.
///
/// These run on the host with both channels mocked, so the failure path is
/// covered without a device. The end-to-end half lives in
/// `example/integration_test/copy_asset_test.dart`.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:large_file_handler/large_file_handler_method_channel.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async => '/tmp/lfh_test';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const progressChannelName = 'file_download_progress';
  const codec = StandardMethodCodec();

  late MethodChannelLargeFileHandler handler;
  late List<MethodCall> invoked;
  Object? invokeError;

  TestDefaultBinaryMessenger messenger() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    PathProviderPlatform.instance = _FakePathProvider();
    handler = MethodChannelLargeFileHandler();
    invoked = <MethodCall>[];
    invokeError = null;

    messenger().setMockMethodCallHandler(handler.methodChannel, (call) async {
      invoked.add(call);
      if (invokeError != null) throw invokeError!;
      return null;
    });
    // The EventChannel speaks 'listen'/'cancel' over a MethodChannel of the
    // same name; accepting both keeps `receiveBroadcastStream()` alive so the
    // controller stays open and cannot pass by accidentally closing.
    messenger().setMockMethodCallHandler(
      const MethodChannel(progressChannelName, codec),
      (call) async => null,
    );
  });

  tearDown(() {
    messenger().setMockMethodCallHandler(handler.methodChannel, null);
    messenger().setMockMethodCallHandler(
      const MethodChannel(progressChannelName, codec),
      null,
    );
  });

  void emitProgress(int value) {
    messenger().handlePlatformMessage(
      progressChannelName,
      codec.encodeSuccessEnvelope(value),
      (_) {},
    );
  }

  test('a native failure reaches the progress stream', () async {
    // THE regression. Before the fix this future completed normally with an
    // empty list: the stream closed, no error was ever delivered, and the
    // caller had no way to learn the copy had not happened.
    invokeError = PlatformException(code: 'ERROR', message: 'boom');

    await expectLater(
      handler.copyAssetToLocalStorageWithProgress('a.json', 'a.json'),
      emitsThrough(
        emitsError(
          isA<PlatformException>()
              .having((e) => e.message, 'message', 'boom'),
        ),
      ),
    );
  });

  test('the url variant reports its failure too', () async {
    invokeError = PlatformException(code: 'DOWNLOAD_FAILED', message: 'nope');

    await expectLater(
      handler.copyUrlToLocalStorageWithProgress('https://x.invalid/f', 'f'),
      emitsThrough(emitsError(isA<PlatformException>())),
    );
  });

  test('progress events still reach the listener', () async {
    // The fix wraps the event channel in a controller of its own. If that
    // wrapper stopped forwarding, every download would sit at 0% forever —
    // a failure mode with no error attached, so only a delivery test finds it.
    final seen = <int>[];
    final sub = handler
        .copyAssetToLocalStorageWithProgress('a.json', 'a.json')
        .listen(seen.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(Duration.zero);
    emitProgress(0);
    emitProgress(42);
    emitProgress(100);
    await Future<void>.delayed(Duration.zero);

    expect(seen, [0, 42, 100]);
  });

  test('the native call is actually made, with the assets/ prefix', () async {
    // `onListen` now drives the invoke. Building the stream and never listening
    // must not start a copy; listening must.
    final stream =
        handler.copyAssetToLocalStorageWithProgress('a.json', 'a.json');
    await Future<void>.delayed(Duration.zero);
    expect(invoked, isEmpty, reason: 'a copy started before anyone listened');

    final sub = stream.listen((_) {});
    addTearDown(sub.cancel);
    await Future<void>.delayed(Duration.zero);

    expect(invoked.single.method, 'copyAssetToLocalWithProgress');
    expect(
      (invoked.single.arguments as Map)['assetName'],
      'assets/a.json',
    );
  });

  test('the one-shot copy still propagates the platform error', () async {
    invokeError = PlatformException(code: 'ERROR', message: 'boom');

    await expectLater(
      handler.copyAssetToLocalStorage('a.json', 'a.json'),
      throwsA(isA<PlatformException>()),
    );
  });
}
