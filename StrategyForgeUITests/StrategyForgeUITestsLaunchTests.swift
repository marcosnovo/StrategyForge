//
//  StrategyForgeUITestsLaunchTests.swift
//  StrategyForgeUITests
//
//  Created by Marcos on 08/07/2026.
//

import XCTest

final class StrategyForgeUITestsLaunchTests: XCTestCase {

    // Run once in the current appearance only. `true` (the Apple template default)
    // re-runs the test in every UI configuration — including Dark — and switches the
    // system appearance to do so, leaving the Mac in Dark Mode after tests.
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
