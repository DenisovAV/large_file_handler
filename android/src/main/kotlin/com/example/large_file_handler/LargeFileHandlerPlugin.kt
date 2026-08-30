package com.example.large_file_handler

import android.os.Handler
import android.os.Looper
import android.content.res.AssetManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel
import io.flutter.embedding.engine.loader.FlutterLoader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream

class LargeFileHandlerPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
  private data class DownloadStream(val inputStream: InputStream, val contentLength: Long)
  private lateinit var channel: MethodChannel
  private lateinit var assetManager: AssetManager
  private lateinit var flutterLoader: FlutterLoader
  private var eventSink: EventChannel.EventSink? = null
  private val handler = Handler(Looper.getMainLooper())

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "large_file_handler")
    channel.setMethodCallHandler(this)
    EventChannel(flutterPluginBinding.binaryMessenger, "file_download_progress").setStreamHandler(this)
    assetManager = flutterPluginBinding.applicationContext.assets

    flutterLoader = FlutterLoader()
    flutterLoader.startInitialization(flutterPluginBinding.applicationContext)
    flutterLoader.ensureInitializationComplete(flutterPluginBinding.applicationContext, null)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "copyAssetToLocal" -> {
        val assetName = call.argument<String>("assetName")!!
        val targetPath = call.argument<String>("targetPath")!!
        CoroutineScope(Dispatchers.IO).launch {
          try {
            val assetStream = assetManager.open(flutterLoader.getLookupKeyForAsset(assetName))
            copyStreamToFile(assetStream, targetPath)
            handler.post { result.success(null) }
          } catch (e: IOException) {
            handler.post {
              result.error(
                "ERROR",
                "Failed to copy asset \"$assetName\": ${e.message}",
                null
              )
            }
          }
        }
      }
      "copyAssetToLocalWithProgress" -> {
        val assetName = call.argument<String>("assetName")!!
        val targetPath = call.argument<String>("targetPath")!!
        CoroutineScope(Dispatchers.IO).launch {
          try {
            val assetStream = assetManager.open(flutterLoader.getLookupKeyForAsset(assetName))
            val totalBytes = assetStream.available().toLong()
            copyStreamToFileWithProgress(assetStream, targetPath, totalBytes)
            handler.post { result.success(null) }
          } catch (e: IOException) {
            handler.post {
              result.error(
                "ERROR",
                "Failed to copy asset \"$assetName\": ${e.message}",
                null
              )
            }
          }
        }
      }
      "copyUrlToLocal" -> {
        val url = call.argument<String>("url")!!
        val targetPath = call.argument<String>("targetPath")!!
        CoroutineScope(Dispatchers.IO).launch {
          try {
            val download = downloadFileFromUrl(url)
            copyStreamToFile(download.inputStream, targetPath)
            handler.post { result.success(null) }
          } catch (e: Exception) {
            handler.post { result.error("DOWNLOAD_FAILED", "Error during file download: ${e.message}", null) }
          }
        }
      }
      "copyUrlToLocalWithProgress" -> {
        val url = call.argument<String>("url")!!
        val targetPath = call.argument<String>("targetPath")!!
        CoroutineScope(Dispatchers.IO).launch {
          try {
            val download = downloadFileFromUrl(url)
            copyStreamToFileWithProgress(download.inputStream, targetPath, download.contentLength)
            handler.post { result.success(null) }
          } catch (e: Exception) {
            handler.post { result.error("DOWNLOAD_FAILED", "Error during file download: ${e.message}", null) }
          }
        }
      }
      "fileExists" -> {
        val targetPath = call.argument<String>("targetPath")!!
        val file = File(targetPath)
        if (file.exists()) {
          result.success(true)
        } else {
          result.success(false)
        }
      }
      else -> result.notImplemented()
    }
  }

  private fun downloadFileFromUrl(url: String): DownloadStream {
    val client = OkHttpClient()
    val request = Request.Builder().url(url).build()
    val response = client.newCall(request).execute()

    if (!response.isSuccessful) {
      throw IOException("Failed to download file: ${response.code}")
    }

    val body = response.body ?: throw IOException("Response body is null")
    val contentLength = body.contentLength().coerceAtLeast(0)
    return DownloadStream(body.byteStream(), contentLength)
  }

  private fun copyStreamToFile(inputStream: InputStream, targetPath: String) {
    inputStream.use { input ->
      FileOutputStream(File(targetPath)).use { output ->
        val buffer = ByteArray(1024)
        var length: Int
        while (input.read(buffer).also { length = it } > 0) {
          output.write(buffer, 0, length)
        }
      }
    }
  }

  private fun copyStreamToFileWithProgress(inputStream: InputStream, targetPath: String, totalBytes: Long) {
    if (totalBytes == 0L) {
      handler.post { eventSink?.success(0) }
      inputStream.use { input ->
        FileOutputStream(File(targetPath)).use { output ->
          val buffer = ByteArray(1024)
          var bytesRead: Int
          while (input.read(buffer).also { bytesRead = it } > 0) {
            output.write(buffer, 0, bytesRead)
          }
        }
      }
      handler.post {
        eventSink?.success(100)
        eventSink?.endOfStream()
        eventSink = null
      }
      return
    }

    inputStream.use { input ->
      FileOutputStream(File(targetPath)).use { output ->
        val buffer = ByteArray(1024)
        var bytesRead: Int
        var totalRead: Long = 0

        while (input.read(buffer).also { bytesRead = it } > 0) {
          output.write(buffer, 0, bytesRead)
          totalRead += bytesRead
          val progress = (totalRead * 100 / totalBytes).toInt()
          handler.post { eventSink?.success(progress) }
        }
      }
    }

    handler.post {
      eventSink?.endOfStream()
      eventSink = null
    }
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}
