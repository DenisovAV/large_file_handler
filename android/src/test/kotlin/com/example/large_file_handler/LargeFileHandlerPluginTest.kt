package com.example.large_file_handler

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.Test
import org.mockito.Mockito

/*
 * The template test that shipped here called `getPlatformVersion`, which this
 * plugin does not implement — `onMethodCall` falls through to
 * `result.notImplemented()`, so the `verify(success(...))` could never match.
 * It could not have passed; nothing in this repository ran the native tests.
 *
 * Run with `./gradlew testDebugUnitTest` from `example/android/`.
 */

internal class LargeFileHandlerPluginTest {
  @Test
  fun onMethodCall_unknownMethod_reportsNotImplemented() {
    val plugin = LargeFileHandlerPlugin()

    val call = MethodCall("getPlatformVersion", null)
    val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
    plugin.onMethodCall(call, mockResult)

    Mockito.verify(mockResult).notImplemented()
  }
}
