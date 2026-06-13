import 'package:flutter_test/flutter_test.dart';
import 'package:large_file_handler/large_file_handler_web.dart';

void main() {
  final web = LargeFileHandlerWeb();

  test('copyAssetToLocalStorage throws UnsupportedError', () {
    expect(() => web.copyAssetToLocalStorage('a.json', 'a.json'),
        throwsUnsupportedError);
  });

  test('copyUrlToLocalStorage throws UnsupportedError', () {
    expect(() => web.copyUrlToLocalStorage('https://x/a.json', 'a.json'),
        throwsUnsupportedError);
  });

  test('fileExists throws UnsupportedError', () {
    expect(() => web.fileExists('a.json'), throwsUnsupportedError);
  });

  test('copyAssetToLocalStorageWithProgress emits UnsupportedError', () {
    expect(web.copyAssetToLocalStorageWithProgress('a.json', 'a.json'),
        emitsError(isUnsupportedError));
  });

  test('copyUrlToLocalStorageWithProgress emits UnsupportedError', () {
    expect(web.copyUrlToLocalStorageWithProgress('https://x/a.json', 'a.json'),
        emitsError(isUnsupportedError));
  });
}
