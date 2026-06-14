import '../large_file_handler_method_channel.dart';
import '../large_file_handler_platform_interface.dart';

/// Returns [MethodChannelLargeFileHandler] as the default instance.
///
/// On Windows/Linux, `dartPluginClass` replaces this with
/// `LargeFileHandlerDesktop` before any public method is called.
LargeFileHandlerPlatform? buildDefaultInstance() =>
    MethodChannelLargeFileHandler();
