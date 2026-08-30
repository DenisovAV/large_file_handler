import Cocoa
import FlutterMacOS
import XCTest

@testable import large_file_handler

/// Unit tests for macOS asset-key resolution (issue #10).
///
/// `integration_test/copy_asset_test.dart` proves the copy works end to end,
/// but it can only ever exercise ONE of the two branches below:
/// `FlutterDartProject.lookupKey(forAsset:)` decides the key shape, the caller
/// does not, and on a real macOS host it always returns the bundle-root form.
///
/// The resources-relative form is the one that USED to resolve — it is what
/// `path(forResource:)` was written for — so it is the branch a fix could
/// silently regress while every end-to-end test stayed green. That is why the
/// lookups are injected and why these tests exist.
class AssetPathResolutionTests: XCTestCase {

  /// The shape `path(forResource:)` was written for. This branch is the
  /// previous implementation verbatim; if it stops being consulted first, a
  /// layout that worked before this fix starts failing.
  func testResourcesRelativeKeyResolvesThroughPathForResource() throws {
    var fileExistsCalled = false
    let resolved = try LargeFileHandlerPlugin.resolveAssetPath(
      "flutter_assets/assets/example.json",
      resourceLookup: { _ in "/App.app/Contents/Resources/flutter_assets/assets/example.json" },
      bundleRoot: "/App.app",
      fileExists: { _ in
        fileExistsCalled = true
        return true
      })

    XCTAssertEqual(resolved, "/App.app/Contents/Resources/flutter_assets/assets/example.json")
    XCTAssertFalse(
      fileExistsCalled,
      "the bundle-root branch ran even though path(forResource:) had already resolved the key")
  }

  /// The shape macOS actually produces, and the one that threw 404 on every run.
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

  /// Precedence, stated as its own test: when BOTH would resolve, the old call
  /// wins. Anything else changes behaviour for layouts that already worked.
  func testPathForResourceWinsWhenBothWouldResolve() throws {
    let resolved = try LargeFileHandlerPlugin.resolveAssetPath(
      "flutter_assets/assets/example.json",
      resourceLookup: { _ in "/from-resources.json" },
      bundleRoot: "/App.app",
      fileExists: { _ in true })

    XCTAssertEqual(resolved, "/from-resources.json")
  }

  /// A bare `404` is what made this bug expensive to diagnose: it named neither
  /// the key nor where it looked.
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

  /// `bundleRoot` comes from `Bundle.main.bundlePath`, which has no trailing
  /// separator — but string concatenation instead of `appendingPathComponent`
  /// would still pass every test above while producing `//` here.
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
