import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testConsumePendingSharedFileReturnsSupportedEmptyState() {
    let delegate = AppDelegate()
    let expectation = expectation(description: "method result")
    delegate.handleSystemToolsCall(
      FlutterMethodCall(methodName: "consumePendingSharedFile", arguments: nil)
    ) { value in
      XCTAssertNil(value)
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 1)
  }

  func testDeepLinkIsConsumedOnlyOnce() throws {
    let delegate = AppDelegate()
    let url = try XCTUnwrap(URL(string: "mobilecode://github/oauth?code=redacted"))
    delegate.captureDeepLink(url)

    let first = expectation(description: "first result")
    delegate.handleSystemToolsCall(
      FlutterMethodCall(methodName: "consumeInitialDeepLink", arguments: nil)
    ) { value in
      XCTAssertEqual(value as? String, url.absoluteString)
      first.fulfill()
    }
    wait(for: [first], timeout: 1)

    let second = expectation(description: "second result")
    delegate.handleSystemToolsCall(
      FlutterMethodCall(methodName: "consumeInitialDeepLink", arguments: nil)
    ) { value in
      XCTAssertNil(value)
      second.fulfill()
    }
    wait(for: [second], timeout: 1)
  }

  func testPhoneUseReportsExternalProviderRequirement() {
    let delegate = AppDelegate()
    let expectation = expectation(description: "method result")
    delegate.handleSystemToolsCall(
      FlutterMethodCall(methodName: "getPhoneUseAccessibilityStatus", arguments: nil)
    ) { value in
      let status = value as? [String: Any]
      XCTAssertEqual(status?["platform"] as? String, "ios")
      XCTAssertEqual(status?["supported"] as? Bool, false)
      XCTAssertEqual(
        status?["blockedReason"] as? String,
        "ios_requires_external_xctest_provider"
      )
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 1)
  }

}
