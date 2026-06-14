import '../large_file_handler_platform_interface.dart';

/// Returns null on web. The actual instance is set by [LargeFileHandlerWeb]
/// before any public method is called.
LargeFileHandlerPlatform? buildDefaultInstance() => null;
