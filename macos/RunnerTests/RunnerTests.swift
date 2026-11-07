import Cocoa
import FlutterMacOS
import XCTest
@testable import GitLama

class RunnerTests: XCTestCase {
  func testAppBundleDisablesImpellerUntilRendererQualificationPasses() {
    let appBundle = Bundle(for: MainFlutterWindow.self)
    let setting = appBundle.object(forInfoDictionaryKey: "FLTEnableImpeller") as? NSNumber
    XCTAssertNotNil(setting)
    XCTAssertEqual(setting?.boolValue, false)
  }

  func testOpenRequestsSurviveUntilTakenAndPreserveOrder() {
    let bridge = ApplicationOpenBridge()
    let paths = ["/work/first repository", "/work/日本語"]
    XCTAssertTrue(bridge.enqueue(paths))
    XCTAssertEqual(bridge.takePaths(), paths)
    XCTAssertTrue(bridge.enqueue(["/work/later"]))
    XCTAssertEqual(bridge.takePaths(), ["/work/later"])
    XCTAssertTrue(bridge.takePaths().isEmpty)
  }

  func testOpenQueueIsBoundedAndRejectsInvalidBatchesAtomically() {
    let bridge = ApplicationOpenBridge()
    XCTAssertFalse(bridge.enqueue(["/work/valid", ""]))
    XCTAssertFalse(bridge.enqueue(["/work/invalid\0path"]))
    XCTAssertFalse(bridge.enqueue([String(repeating: "a", count: 32769)]))
    XCTAssertTrue(bridge.takePaths().isEmpty)
    let paths = (0..<64).map { "/work/\($0)" }
    XCTAssertTrue(bridge.enqueue(paths))
    XCTAssertFalse(bridge.enqueue(["/work/overflow"]))
    for offset in stride(from: 0, to: 64, by: 8) {
      XCTAssertEqual(bridge.takePaths(), Array(paths[offset..<offset + 8]))
    }
    XCTAssertTrue(bridge.takePaths().isEmpty)
  }
}
