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
}
