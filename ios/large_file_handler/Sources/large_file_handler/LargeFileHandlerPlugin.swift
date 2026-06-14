import Flutter
import UIKit

public class LargeFileHandlerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

  private var eventSink: FlutterEventSink?
  private var progressObservation: NSKeyValueObservation?

  private enum FileError: Error {
    case invalidArguments
    case assetNotFound
    case invalidURL
    case downloadFailed

    var flutterError: FlutterError {
      switch self {
      case .invalidArguments:
        return FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil)
      case .assetNotFound:
        return FlutterError(code: "NOT_FOUND", message: "Asset not found", details: nil)
      case .invalidURL:
        return FlutterError(code: "INVALID_URL", message: "Invalid URL provided", details: nil)
      case .downloadFailed:
        return FlutterError(code: "DOWNLOAD_ERROR", message: "Failed to download file", details: nil)
      }
    }
  }

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
        throw FileError.assetNotFound
      }

      try ensureDirectoryExists(for: targetPath)
      try removeExistingFile(at: targetPath)

      try copyFileWithProgress(from: bundleAssetPath, to: targetPath) { progress in
        self.reportProgress(progress)
      }

      completeProgress(result: result)
    } catch {
      DispatchQueue.main.async {
        self.failProgress(result: result, error: FlutterError(code: "ERROR", message: "Failed to copy asset", details: error.localizedDescription))
      }
    }
  }

  private func copyFileWithProgress(from sourcePath: String, to targetPath: String, progressCallback: (Int) -> Void) throws {
    let totalBytes = try FileManager.default.attributesOfItem(atPath: sourcePath)[.size] as? Int64 ?? 0
    var bytesWritten: Int64 = 0

    let bufferSize = 1024 * 1024 // Increased buffer size to 1MB for better performance
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    guard let inputStream = InputStream(fileAtPath: sourcePath),
          let outputStream = OutputStream(toFileAtPath: targetPath, append: false) else {
      throw FileError.downloadFailed
    }

    inputStream.open()
    outputStream.open()
    defer {
      inputStream.close()
      outputStream.close()
    }

    while inputStream.hasBytesAvailable {
      let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
      if bytesRead <= 0 { break }
      outputStream.write(buffer, maxLength: bytesRead)
      bytesWritten += Int64(bytesRead)
      let progress = Int((Double(bytesWritten) / Double(totalBytes)) * 100)
      progressCallback(progress)
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
        self.failProgress(result: result, error: FileError.invalidURL.flutterError)
      }
      return
    }

    let task = URLSession.shared.downloadTask(with: downloadUrl) { [weak self] (tempURL, response, error) in
      guard let self = self else { return }

      if let error = error {
        DispatchQueue.main.async {
          self.failProgress(result: result, error: FlutterError(code: "DOWNLOAD_ERROR", message: error.localizedDescription, details: nil))
        }
        return
      }

      guard let tempURL = tempURL else {
        DispatchQueue.main.async {
          self.failProgress(result: result, error: FileError.downloadFailed.flutterError)
        }
        return
      }

      do {
        try self.ensureDirectoryExists(for: targetPath)
        try self.removeExistingFile(at: targetPath)
        try FileManager.default.moveItem(at: tempURL, to: URL(fileURLWithPath: targetPath))
        self.completeProgress(result: result)
      } catch {
        DispatchQueue.main.async {
          self.failProgress(result: result, error: FlutterError(code: "DOWNLOAD_ERROR", message: "Error during file download", details: error.localizedDescription))
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

  private func reportProgress(_ progress: Int) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(progress)
    }
  }

  private func completeProgress(result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      self?.progressObservation = nil
      self?.eventSink?(100)
      self?.eventSink?(FlutterEndOfEventStream)
      self?.eventSink = nil
      result(nil)
    }
  }

  private func failProgress(result: @escaping FlutterResult, error: FlutterError) {
    progressObservation = nil
    eventSink?(FlutterEndOfEventStream)
    eventSink = nil
    result(error)
  }

  private func ensureDirectoryExists(for path: String) throws {
    let directory = (path as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
  }

  private func removeExistingFile(at path: String) throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: path) {
      try fileManager.removeItem(atPath: path)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    progressObservation = nil
    eventSink = nil
    return nil
  }

}
