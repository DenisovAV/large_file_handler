import Flutter
import UIKit
import XCTest


@testable import large_file_handler

/// The template test that shipped here called `getPlatformVersion`, which this
/// plugin does not implement — `handle` answered `FlutterMethodNotImplemented`
/// and `result as! String` crashed the test target. It could never have passed;
/// nothing in this repository ran the native tests, which is the same reason
/// issue #10 reached a user.
class RunnerTests: XCTestCase {

  func testUnknownMethodIsReportedAsNotImplemented() {
    let plugin = LargeFileHandlerPlugin()
    let call = FlutterMethodCall(methodName: "getPlatformVersion", arguments: [])

    let answered = expectation(description: "result block must be called")
    plugin.handle(call) { result in
      XCTAssertTrue(
        result is NSObject && result as? NSObject == FlutterMethodNotImplemented,
        "an unimplemented method must answer FlutterMethodNotImplemented, got \(String(describing: result))")
      answered.fulfill()
    }
    waitForExpectations(timeout: 1)
  }
}

/// Unit tests for asset-key resolution, mirroring
/// `macos/RunnerTests/RunnerTests.swift`.
///
/// iOS was never the platform that failed — issue #10 was macOS-only. These
/// exist because the two plugins carry the SAME resolver in two source trees
/// that cannot share code, and the pair had already drifted once. Covering only
/// the platform that broke would leave the copy free to rot until it broke too.
///
/// The lookups are injected because only one branch is reachable on a real
/// host: `lookupKey(forAsset:)` picks the key shape, the caller does not.
class AssetPathResolutionTests: XCTestCase {

  /// The branch iOS actually takes, and the previous implementation verbatim.
  func testResourcesRelativeKeyResolvesThroughPathForResource() throws {
    var fileExistsCalled = false
    let resolved = try LargeFileHandlerPlugin.resolveAssetPath(
      "flutter_assets/assets/example.json",
      resourceLookup: { _ in "/App.app/flutter_assets/assets/example.json" },
      bundleRoot: "/App.app",
      fileExists: { _ in
        fileExistsCalled = true
        return true
      })

    XCTAssertEqual(resolved, "/App.app/flutter_assets/assets/example.json")
    XCTAssertFalse(
      fileExistsCalled,
      "the bundle-root branch ran even though path(forResource:) had already resolved the key")
  }

  /// The shape that broke macOS. Unreachable on iOS today — which is exactly
  /// why it needs a test rather than a comment.
  func testBundleRootKeyResolvesByJoiningOntoBundlePath() throws {
    let key = "Contents/Frameworks/App.framework/Resources/flutter_assets/assets/example.json"
    var probed: [String] = []

    let resolved = try LargeFileHandlerPlugin.resolveAssetPath(
      key,
      resourceLookup: { _ in nil },
      bundleRoot: "/App.app",
      fileExists: { path in
        probed.append(path)
        return path == "/App.app/" + key
      })

    XCTAssertEqual(resolved, "/App.app/" + key)
    XCTAssertEqual(probed, ["/App.app/" + key])
  }

  func testPathForResourceWinsWhenBothWouldResolve() throws {
    let resolved = try LargeFileHandlerPlugin.resolveAssetPath(
      "flutter_assets/assets/example.json",
      resourceLookup: { _ in "/from-resources.json" },
      bundleRoot: "/App.app",
      fileExists: { _ in true })

    XCTAssertEqual(resolved, "/from-resources.json")
  }

  func testMissingAssetThrows404NamingTheKeyAndThePathTried() {
    XCTAssertThrowsError(
      try LargeFileHandlerPlugin.resolveAssetPath(
        "flutter_assets/assets/absent.json",
        resourceLookup: { _ in nil },
        bundleRoot: "/App.app",
        fileExists: { _ in false })
    ) { error in
      let ns = error as NSError
      XCTAssertEqual(ns.code, 404)
      let message = ns.localizedDescription
      XCTAssertTrue(
        message.contains("flutter_assets/assets/absent.json"),
        "the error does not name the key it failed on: \(message)")
      XCTAssertTrue(
        message.contains("/App.app/flutter_assets/assets/absent.json"),
        "the error does not name the path it tried: \(message)")
    }
  }

  func testTrailingSeparatorInBundleRootDoesNotDoubleUp() throws {
    let resolved = try LargeFileHandlerPlugin.resolveAssetPath(
      "flutter_assets/a.json",
      resourceLookup: { _ in nil },
      bundleRoot: "/App.app/",
      fileExists: { _ in true })

    XCTAssertEqual(resolved, "/App.app/flutter_assets/a.json")
    XCTAssertFalse(resolved.contains("//"), "the join produced a doubled separator")
  }
}
