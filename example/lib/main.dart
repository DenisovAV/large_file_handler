import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:large_file_handler/large_file_handler.dart';

void main() {
  runApp(const MaterialApp(
    home: MyApp(),
  ));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _statusMessage = 'Preparing to copy asset...';
  StreamSubscription<int>? _progressSubscription;

  @override
  void initState() {
    super.initState();
    checkAndCopyAsset();
  }

  Future<void> checkAndCopyAsset() async {
    const assetName = 'example.json';
    const targetPath = 'example.json';

    // Check if the file already exists
    bool fileExists =
        await LargeFileHandler().fileExists(targetPath: targetPath);

    if (!mounted) return;

    if (fileExists) {
      // If file exists, show dialog asking if it should be overwritten
      bool? shouldOverwrite = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('File Already Exists'),
            content: const Text(
                'The file already exists at the target path. Do you want to overwrite it?'),
            actions: <Widget>[
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(false), // Do not overwrite
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true), // Overwrite
                child: const Text('Yes'),
              ),
            ],
          );
        },
      );

      if (shouldOverwrite == false || shouldOverwrite == null) {
        setState(() {
          _statusMessage = 'Operation cancelled, file already exists.';
        });
        return; // Stop operation if the user declined to overwrite the file
      }
    }

    // If file doesn't exist or the user agrees to overwrite, proceed with the copying
    copyAssetToLocalWithProgress(assetName: assetName, targetPath: targetPath);
  }

  Future<void> copyAssetToLocalWithProgress(
      {required String assetName, required String targetPath}) async {
    try {
      Stream<int> progressStream =
          LargeFileHandler().copyAssetToLocalStorageWithProgress(
        assetName: assetName,
        targetPath: targetPath,
      );

      _progressSubscription = progressStream.listen(
        (progress) {
          setState(() {
            _statusMessage = 'Copying asset... $progress%';
          });
        },
        onDone: () {
          setState(() {
            _statusMessage = 'File copied successfully to $targetPath';
          });
        },
        onError: (error) {
          setState(() {
            _statusMessage = 'Failed to copy asset: $error';
          });
        },
      );
    } on PlatformException catch (e) {
      setState(() {
        _statusMessage = 'Failed to copy asset: ${e.message}';
      });
    }
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plugin Example App'),
      ),
      body: Center(
        child: Text(_statusMessage),
      ),
    );
  }
}
