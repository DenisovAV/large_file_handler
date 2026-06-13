import 'dart:io';
import 'dart:typed_data';

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
