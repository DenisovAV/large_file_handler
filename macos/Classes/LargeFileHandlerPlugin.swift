import Cocoa
import FlutterMacOS

public class LargeFileHandlerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

  private var eventSink: FlutterEventSink?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "large_file_handler", binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(name: "file_download_progress", binaryMessenger: registrar.messenger())
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

  private func copyAsset(assetName: String, targetPath: String) throws {
    let flutterAssetPath = FlutterDartProject.lookupKey(forAsset: assetName)
    guard let bundleAssetPath = Bundle.main.path(forResource: flutterAssetPath, ofType: nil) else {
      throw NSError(domain: "Asset not found", code: 404, userInfo: nil)
    }

    try copyFile(from: bundleAssetPath, to: targetPath)
  }

  private func copyAssetWithProgress(assetName: String, targetPath: String, result: @escaping FlutterResult) {
    do {
      let flutterAssetPath = FlutterDartProject.lookupKey(forAsset: assetName)
      guard let bundleAssetPath = Bundle.main.path(forResource: flutterAssetPath, ofType: nil) else {
        throw NSError(domain: "Asset not found", code: 404, userInfo: nil)
      }

      let totalBytes = try FileManager.default.attributesOfItem(atPath: bundleAssetPath)[.size] as? Int64 ?? 0
      var bytesWritten: Int64 = 0

      let bufferSize = 1024
      let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)

      let inputStream = InputStream(fileAtPath: bundleAssetPath)!
      let outputStream = OutputStream(toFileAtPath: targetPath, append: false)!
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
        outputStream.write(buffer, maxLength: bytesRead)
        bytesWritten += Int64(bytesRead)
        let progress = (Double(bytesWritten) / Double(totalBytes)) * 100
        DispatchQueue.main.async {
          self.eventSink?(Int(progress))
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
        result(FlutterError(code: "DOWNLOAD_ERROR", message: "Invalid URL", details: nil))
      }
      return
    }

    let task = URLSession.shared.downloadTask(with: downloadUrl) { (tempURL, response, error) in
      if let error = error {
        DispatchQueue.main.async {
          result(FlutterError(code: "DOWNLOAD_ERROR", message: error.localizedDescription, details: nil))
        }
        return
      }

      guard let tempURL = tempURL else {
        DispatchQueue.main.async {
          result(FlutterError(code: "DOWNLOAD_ERROR", message: "Download failed", details: nil))
        }
        return
      }

      let totalBytes = response?.expectedContentLength ?? 0
      var bytesWritten: Int64 = 0

      do {
        let fileURL = URL(fileURLWithPath: targetPath)
        try FileManager.default.moveItem(at: tempURL, to: fileURL)

        bytesWritten = totalBytes
        DispatchQueue.main.async {
          self.eventSink?(100)
          result(nil)
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "DOWNLOAD_ERROR", message: "Error during file download", details: error.localizedDescription))
        }
      }
    }

    task.resume()

    task.progress.addObserver(self, forKeyPath: #keyPath(Progress.fractionCompleted), options: [.new], context: nil)
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    if keyPath == #keyPath(Progress.fractionCompleted), let progress = object as? Progress {
      DispatchQueue.main.async {
        let percentage = Int(progress.fractionCompleted * 100)
        self.eventSink?(percentage)
      }
    }
  }
}
