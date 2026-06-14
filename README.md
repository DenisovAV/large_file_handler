# Large File Handler Plugin

The **Large File Handler Plugin** designed to efficiently work with large files, for example allows you to download large files from network or copy files from the Flutter app's assets to the device's local file system. This is useful when you need to access large files at native part in your plugins.

## Features

- Copy any asset from your Flutter project to the local file system.
- Download files from a network to the local file system.
- Cross-platform support: Android, iOS, macOS, Windows, and Linux.
- Copy files with or without progress tracking.

## Installation

To install the plugin, add the following line to your `pubspec.yaml` under the dependencies section:

```yaml
dependencies:
  large_file_handler: ^0.5.0
```

Then, run:
```shell
flutter pub get
```

## Usage with assets

### 1. Register the asset in `pubspec.yaml`

Make sure the asset file is registered in your Flutter app. Add the following lines to the `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/example.json
```

### 2.  Copy asset to native local file system

#### Without progress tracking:

Use the plugin to copy the asset to a local path on the device:

```dart
import 'package:large_file_handler/large_file_handler.dart';

Future<void> copyAssetToLocal() async {
  String status;
  try {
    const assetName = 'example.json';
    const targetPath = 'example.json';

    await LargeFileHandler().copyAssetToLocalStorage(assetName: assetName, targetPath: targetPath);
    status = 'File copied successfully to $targetPath';
  } on PlatformException catch (e) {
    status = 'Failed to copy asset: ${e.message}';
  }
}
```

#### With progress tracking:

You can also track the progress of copying the asset using the stream:

```dart
import 'package:large_file_handler/large_file_handler.dart';

Future<void> copyAssetToLocalWithProgress() async {
  String status;
  try {
    const assetName = 'example.json';
    const targetPath = 'example.json';

    final progressStream = LargeFileHandler().copyAssetToLocalStorageWithProgress(assetName: assetName, targetPath: targetPath);
    progressStream.listen((progress) {
      print('Progress: $progress%');
    });
  } on PlatformException catch (e) {
    status = 'Failed to copy asset: ${e.message}';
  }
}
```

## Usage with network

### 1. Upload an asset to network storage

Make sure the asset file is uploaded to network or cloud storage.

### 2.  Download asset to native local file system

#### Without progress tracking:

Use the plugin to download the asset to a local path on the device:

```dart
import 'package:large_file_handler/large_file_handler.dart';

Future<void> copyCloudToLocal() async {
  String status;
  try {
    const url = 'https://cloud/example.json';
    const targetPath = 'example.json';

    await LargeFileHandler().copyNetworkAssetToLocalStorage(assetUrl: url, targetPath: targetPath);
    status = 'File downloaded successfully to $targetPath';
  } on PlatformException catch (e) {
    status = 'Failed to download asset: ${e.message}';
  }
}
```

#### With progress tracking:

You can also track the progress of downloading the file:

```dart
import 'package:large_file_handler/large_file_handler.dart';

Future<void> copyCloudToLocal() async {
  String status;
  try {
    const url = 'https://cloud/example.json';
    const targetPath = 'example.json';

    final progressStream = LargeFileHandler().copyNetworkAssetToLocalStorageWithProgress(assetUrl: url, targetPath: targetPath);
    progressStream.listen((progress) {
      print('Download progress: $progress%');
    });
  } on PlatformException catch (e) {
    status = 'Failed to download asset: ${e.message}';
  }
}
```

## Supported Platforms

| Platform | Support |
|----------|---------|
| Android  | ✅ Full (native) |
| iOS      | ✅ Full (native) |
| macOS    | ✅ Full (native) |
| Windows  | ✅ Full (pure Dart) |
| Linux    | ✅ Full (pure Dart) |
| Web      | ⛔ Not supported — see below |

### Web

A browser has no application documents directory, so this plugin cannot copy or
download files to a local file path on web. Every method throws an
`UnsupportedError`. Guard your calls with `kIsWeb`, or catch the error:

```dart
import 'package:flutter/foundation.dart' show kIsWeb;

if (!kIsWeb) {
  await LargeFileHandler().copyAssetToLocalStorage(
    assetName: 'example.json',
    targetPath: 'example.json',
  );
}
```

## License

This plugin is released under the MIT license. See the [LICENSE](LICENSE) file for details.

