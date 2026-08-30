import Cocoa
import FlutterMacOS

public class LargeFileHandlerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

  private var eventSink: FlutterEventSink?
  private var progressObservation: NSKeyValueObservation?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "large_file_handler", binaryMessenger: registrar.messenger)
    let eventChannel = FlutterEventChannel(name: "file_download_progress", binaryMessenger: registrar.messenger)
    let instance = LargeFileHandlerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "copyAssetToLocal":
      handleCopyAsset(call: call, result: result)

    case "copyAssetToLocalWithProgress":
      handleCopyAssetWithProgress(call: call, result: result)

    case "copyUrlToLocal":
      handleCopyUrl(call: call, result: result)

    case "copyUrlToLocalWithProgress":
      handleCopyUrlWithProgress(call: call, result: result)

    case "fileExists":
      handleFileExists(call: call, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

private func handleFileExists(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = extractArguments(call: call, requiredKeys: ["targetPath"]),
          let targetPath = args["targetPath"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
        return
    }

    let fileExists = FileManager.default.fileExists(atPath: targetPath)
    result(fileExists)
}

private func handleCopyAsset(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = extractArguments(call: call, requiredKeys: ["assetName", "targetPath"]),
          let assetName = args["assetName"] as? String,
          let targetPath = args["targetPath"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
      return
    }

    DispatchQueue.global().async {
      do {
        try self.copyAsset(assetName: assetName, targetPath: targetPath)
        DispatchQueue.main.async {
          result(nil)
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "ERROR", message: "Failed to copy asset", details: error.localizedDescription))
        }
      }
    }
  }


  private func handleCopyAssetWithProgress(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = extractArguments(call: call, requiredKeys: ["assetName", "targetPath"]),
          let assetName = args["assetName"] as? String,
          let targetPath = args["targetPath"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
      return
    }

    DispatchQueue.global().async {
      self.copyAssetWithProgress(assetName: assetName, targetPath: targetPath, result: result)
    }
  }

  private func handleCopyUrl(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = extractArguments(call: call, requiredKeys: ["url", "targetPath"]),
          let url = args["url"] as? String,
          let targetPath = args["targetPath"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
      return
    }

    downloadFile(from: url, targetPath: targetPath) { downloadResult in
      switch downloadResult {
      case .success:
        result(nil)
      case .failure(let error):
        result(FlutterError(code: "DOWNLOAD_ERROR", message: "Failed to download file", details: error.localizedDescription))
      }
    }
  }

  private func handleCopyUrlWithProgress(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = extractArguments(call: call, requiredKeys: ["url", "targetPath"]),
          let url = args["url"] as? String,
          let targetPath = args["targetPath"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
      return
    }

    DispatchQueue.global().async {
      self.downloadFileWithProgress(from: url, targetPath: targetPath, result: result)
    }
  }

  private func extractArguments(call: FlutterMethodCall, requiredKeys: [String]) -> [String: Any]? {
    guard let args = call.arguments as? [String: Any] else { return nil }
    for key in requiredKeys {
      if args[key] == nil { return nil }
    }
    return args
  }

  /// Resolves a Flutter asset key to an absolute path inside the app bundle.
  ///
  /// `FlutterDartProject.lookupKey(forAsset:)` documents its result as "the file
  /// name to be used for lookup in the main bundle", but the SHAPE of that key
  /// depends on whether the `io.flutter.flutter.app` bundle exists. On macOS it
  /// does, and the key is then a path relative to the bundle ROOT that routes
  /// through App.framework:
  ///   Contents/Frameworks/App.framework/Resources/flutter_assets/assets/x.json
  /// `path(forResource:ofType:)` only ever searches Contents/Resources, so it
  /// returned nil for that key and every macOS asset copy failed with 404.
  ///
  /// Both shapes are resolved, `path(forResource:)` FIRST so any layout that
  /// already worked keeps resolving through exactly the call it used before.
  ///
  /// The lookups are injected because only ONE of the two branches is reachable
  /// on a real macOS host: the key shape is chosen by the engine, not by the
  /// caller, so the resources-relative branch — the one that must not regress —
  /// cannot be exercised end-to-end and is covered by RunnerTests instead.
  static func resolveAssetPath(
    _ assetKey: String,
    resourceLookup: (String) -> String?,
    bundleRoot: String,
    fileExists: (String) -> Bool
  ) throws -> String {
    if let fromResources = resourceLookup(assetKey) {
      return fromResources
    }
    let fromBundleRoot = (bundleRoot as NSString).appendingPathComponent(assetKey)
    if fileExists(fromBundleRoot) {
      return fromBundleRoot
    }
    throw NSError(
      domain: "Asset not found", code: 404,
      userInfo: [
        NSLocalizedDescriptionKey:
          "no asset for key \(assetKey): not found by path(forResource:) "
          + "and nothing at \(fromBundleRoot)"
      ])
  }

  private func resolveAssetPath(_ assetKey: String) throws -> String {
    try Self.resolveAssetPath(
      assetKey,
      resourceLookup: { Bundle.main.path(forResource: $0, ofType: nil) },
      bundleRoot: Bundle.main.bundlePath,
      fileExists: { FileManager.default.fileExists(atPath: $0) })
  }

  private func copyAsset(assetName: String, targetPath: String) throws {
    let flutterAssetPath = FlutterDartProject.lookupKey(forAsset: assetName)
    let bundleAssetPath = try resolveAssetPath(flutterAssetPath)

    try copyFile(from: bundleAssetPath, to: targetPath)
  }

  private func copyAssetWithProgress(assetName: String, targetPath: String, result: @escaping FlutterResult) {
    do {
      let flutterAssetPath = FlutterDartProject.lookupKey(forAsset: assetName)
      let bundleAssetPath = try resolveAssetPath(flutterAssetPath)

      let totalBytes = try FileManager.default.attributesOfItem(atPath: bundleAssetPath)[.size] as? Int64 ?? 0
      var bytesWritten: Int64 = 0

      let bufferSize = 1024
      let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)

      guard let inputStream = InputStream(fileAtPath: bundleAssetPath),
            let outputStream = OutputStream(toFileAtPath: targetPath, append: false) else {
        throw NSError(domain: "LargeFileHandler", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not open streams for asset copy"])
      }
      inputStream.open()
      outputStream.open()

      defer {
        inputStream.close()
        outputStream.close()
        buffer.deallocate()
      }

      while inputStream.hasBytesAvailable {
        let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
        if bytesRead <= 0 { break }
        let written = outputStream.write(buffer, maxLength: bytesRead)
        if written < 0 {
          throw outputStream.streamError ?? NSError(domain: "LargeFileHandler", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Write failed"])
        }
        bytesWritten += Int64(written)
        let progress = totalBytes > 0 ? Int((Double(bytesWritten) / Double(totalBytes)) * 100) : 0
        DispatchQueue.main.async {
          self.eventSink?(progress)
        }
      }

      DispatchQueue.main.async {
        self.eventSink?(100)
        self.eventSink?(FlutterEndOfEventStream)
        self.eventSink = nil
        result(nil)
      }
    } catch {
      DispatchQueue.main.async {
        self.eventSink?(FlutterEndOfEventStream)
        self.eventSink = nil
        result(FlutterError(code: "ERROR", message: "Failed to copy asset with progress", details: error.localizedDescription))
      }
    }
  }

  private func copyFile(from sourcePath: String, to targetPath: String) throws {
    let fileManager = FileManager.default
    let targetURL = URL(fileURLWithPath: targetPath)

    if fileManager.fileExists(atPath: targetURL.path) {
      try fileManager.removeItem(at: targetURL)
    }

    try fileManager.copyItem(at: URL(fileURLWithPath: sourcePath), to: targetURL)
  }

  private func downloadFile(from url: String, targetPath: String, completion: @escaping (Result<String, Error>) -> Void) {
    guard let downloadUrl = URL(string: url) else {
      completion(.failure(NSError(domain: "", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
      return
    }

    let task = URLSession.shared.dataTask(with: downloadUrl) { data, response, error in
      if let error = error {
        completion(.failure(error))
        return
      }

      guard let data = data else {
        completion(.failure(NSError(domain: "", code: 500, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
        return
      }

      if let httpResponse = response as? HTTPURLResponse,
         !(200..<300).contains(httpResponse.statusCode) {
        let statusCode = httpResponse.statusCode
        completion(.failure(NSError(domain: "LargeFileHandler", code: statusCode,
                                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode)"])))
        return
      }

      do {
        try self.saveData(data, to: targetPath)
        completion(.success(targetPath))
      } catch {
        completion(.failure(error))
      }
    }

    task.resume()
  }

  private func saveData(_ data: Data, to path: String) throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: path) {
      try fileManager.removeItem(atPath: path)
    }

    fileManager.createFile(atPath: path, contents: nil, attributes: nil)

    let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    fileHandle.write(data)
    fileHandle.closeFile()
  }

  private func downloadFileWithProgress(from url: String, targetPath: String, result: @escaping FlutterResult) {
    guard let downloadUrl = URL(string: url) else {
      DispatchQueue.main.async {
        self.eventSink?(FlutterEndOfEventStream)
        self.eventSink = nil
        self.progressObservation = nil
        result(FlutterError(code: "DOWNLOAD_ERROR", message: "Invalid URL", details: nil))
      }
      return
    }

    let task = URLSession.shared.downloadTask(with: downloadUrl) { [weak self] (tempURL, response, error) in
      guard let self = self else { return }

      if let error = error {
        DispatchQueue.main.async {
          self.eventSink?(FlutterEndOfEventStream)
          self.eventSink = nil
          self.progressObservation = nil
          result(FlutterError(code: "DOWNLOAD_ERROR", message: error.localizedDescription, details: nil))
        }
        return
      }

      guard let tempURL = tempURL else {
        DispatchQueue.main.async {
          self.eventSink?(FlutterEndOfEventStream)
          self.eventSink = nil
          self.progressObservation = nil
          result(FlutterError(code: "DOWNLOAD_ERROR", message: "Download failed", details: nil))
        }
        return
      }

      if let httpResponse = response as? HTTPURLResponse,
         !(200..<300).contains(httpResponse.statusCode) {
        let statusCode = httpResponse.statusCode
        DispatchQueue.main.async {
          self.eventSink?(FlutterEndOfEventStream)
          self.eventSink = nil
          self.progressObservation = nil
          result(FlutterError(code: "DOWNLOAD_ERROR", message: "HTTP \(statusCode)", details: nil))
        }
        return
      }

      do {
        let fileURL = URL(fileURLWithPath: targetPath)
        if FileManager.default.fileExists(atPath: fileURL.path) {
          try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: fileURL)

        DispatchQueue.main.async {
          self.eventSink?(100)
          self.eventSink?(FlutterEndOfEventStream)
          self.eventSink = nil
          self.progressObservation = nil
          result(nil)
        }
      } catch {
        DispatchQueue.main.async {
          self.eventSink?(FlutterEndOfEventStream)
          self.eventSink = nil
          self.progressObservation = nil
          result(FlutterError(code: "DOWNLOAD_ERROR", message: "Error during file download", details: error.localizedDescription))
        }
      }
    }

    task.resume()

    progressObservation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
      DispatchQueue.main.async {
        self?.eventSink?(Int(progress.fractionCompleted * 100))
      }
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    progressObservation = nil
    return nil
  }

}
