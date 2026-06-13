import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
