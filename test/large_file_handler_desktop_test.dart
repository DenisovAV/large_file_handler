import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:large_file_handler/large_file_handler_desktop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LargeFileHandlerDesktop desktop;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lfh_test');
    desktop = LargeFileHandlerDesktop()
      ..directoryProvider = (() async => tempDir);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('fileExists returns false when the file is absent', () async {
    expect(await desktop.fileExists('missing.json'), isFalse);
  });

  test('fileExists returns true when the file is present', () async {
    File('${tempDir.path}/present.json').writeAsStringSync('{}');
    expect(await desktop.fileExists('present.json'), isTrue);
  });

  http.Client clientStreaming(List<int> body, {int? contentLength}) {
    return MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream.value(body),
        200,
        contentLength: contentLength,
      );
    });
  }

  test('copyUrlToLocalStorage writes the downloaded bytes to disk', () async {
    final bytes = Uint8List.fromList(List.generate(2048, (i) => i % 256));
    desktop.httpClient = clientStreaming(bytes, contentLength: bytes.length);

    await desktop.copyUrlToLocalStorage('https://x/file.bin', 'file.bin');

    final written = File('${tempDir.path}/file.bin').readAsBytesSync();
    expect(written, equals(bytes));
  });

  test('copyUrlToLocalStorageWithProgress emits 0..100 ending at 100',
      () async {
    final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));
    desktop.httpClient = clientStreaming(bytes, contentLength: bytes.length);

    final progress = await desktop
        .copyUrlToLocalStorageWithProgress('https://x/file.bin', 'file.bin')
        .toList();

    expect(progress.first, greaterThanOrEqualTo(0));
    expect(progress.last, equals(100));
    expect(progress, equals(progress.toList()..sort()));
    expect(File('${tempDir.path}/file.bin').existsSync(), isTrue);
  });

  test('copyUrlToLocalStorageWithProgress emits 0 then 100 when length unknown',
      () async {
    final bytes = Uint8List.fromList(List.generate(500, (i) => i % 256));
    desktop.httpClient = clientStreaming(bytes, contentLength: null);

    final progress = await desktop
        .copyUrlToLocalStorageWithProgress('https://x/file.bin', 'file.bin')
        .toList();

    expect(progress, equals(<int>[0, 100]));
  });

  test('copyUrlToLocalStorageWithProgress forwards stream errors', () async {
    desktop.httpClient = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream<List<int>>.error(const SocketException('boom')),
        200,
        contentLength: 10,
      );
    });

    Object? caught;
    await desktop
        .copyUrlToLocalStorageWithProgress('https://x/file.bin', 'file.bin')
        .listen(null, onError: (Object e) => caught = e)
        .asFuture<void>()
        .catchError((Object e) => caught = e);
    expect(caught, isA<SocketException>());
  });

  test('copyUrlToLocalStorage throws on HTTP error status', () async {
    desktop.httpClient = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream.value(utf8.encode('Not Found')),
        404,
      );
    });

    await expectLater(
      desktop.copyUrlToLocalStorage('https://x/missing.bin', 'missing.bin'),
      throwsA(isA<HttpException>()),
    );
    expect(File('${tempDir.path}/missing.bin').existsSync(), isFalse);
  });

  test('copyUrlToLocalStorageWithProgress forwards HTTP error status',
      () async {
    desktop.httpClient = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream.value(utf8.encode('Server Error')),
        500,
        contentLength: 12,
      );
    });

    await expectLater(
      desktop
          .copyUrlToLocalStorageWithProgress('https://x/err.bin', 'err.bin')
          .toList(),
      throwsA(isA<HttpException>()),
    );
    expect(File('${tempDir.path}/err.bin').existsSync(), isFalse);
  });

  ByteData byteDataOf(List<int> bytes) =>
      ByteData.view(Uint8List.fromList(bytes).buffer);

  test('copyAssetToLocalStorage writes asset bytes to disk', () async {
    final bytes = List.generate(128, (i) => i);
    desktop.assetLoader = (key) async {
      expect(key, equals('assets/data.json'));
      return byteDataOf(bytes);
    };

    await desktop.copyAssetToLocalStorage('data.json', 'data.json');

    final written = File('${tempDir.path}/data.json').readAsBytesSync();
    expect(written, equals(bytes));
  });

  test('a missing asset surfaces as PlatformException, not FlutterError',
      () async {
    // `rootBundle.load` throws a FlutterError, and this implementation used to
    // let it through. Every native platform reports through a method channel,
    // so the handler this package documents is `on PlatformException` — which
    // meant that on Windows and Linux the README's own example never caught the
    // failure and it escaped unhandled.
    desktop.assetLoader = (key) async => throw FlutterError(
          'Unable to load asset: "$key". The asset does not exist.',
        );

    await expectLater(
      desktop.copyAssetToLocalStorage('absent.json', 'absent.json'),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.message,
          'message',
          contains('absent.json'),
        ),
      ),
    );
  });

  test('the progress variant reports the same failure', () async {
    // Same contract on the other entry point: the two paths shared a bug once
    // and can share a regression again.
    desktop.assetLoader = (key) async => throw FlutterError('nope');

    await expectLater(
      desktop.copyAssetToLocalStorageWithProgress('absent.json', 'absent.json'),
      emitsThrough(emitsError(isA<PlatformException>())),
    );
  });

  test('copyAssetToLocalStorageWithProgress emits 0 then 100', () async {
    final bytes = List.generate(64, (i) => i);
    desktop.assetLoader = (key) async => byteDataOf(bytes);

    final progress = await desktop
        .copyAssetToLocalStorageWithProgress('data.json', 'data.json')
        .toList();

    expect(progress, equals(<int>[0, 100]));
    expect(File('${tempDir.path}/data.json').readAsBytesSync(), equals(bytes));
  });
}
