//
//  ClarissaWatchUITests.swift
//  ClarissaWatchUITests
//
//  Automated screenshot capture for Watch App Store using fastlane snapshot
//  Uses demo mode (-SCREENSHOT_MODE) with scenario arguments for different screenshots
//  Target: Apple Watch Ultra 3 (49mm) - 422x514px or 410x502px
//

import XCTest

@MainActor
final class ClarissaWatchUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helper to launch with specific scenario

    private func launchWithScenario(_ scenario: String) {
        app.launchArguments = ["-SCREENSHOT_MODE", "-DEMO_SCENARIO_\(scenario.uppercased())"]
        setupSnapshot(app)
        app.launch()
    }

    // MARK: - Main Screenshot Test (captures all 10 Watch screenshots)

    /// Capture all Watch screenshots for App Store (10 total)
    func testCaptureAllWatchScreenshots() throws {
        // 01. Welcome - empty state with quick actions
        launchWithScenario("WELCOME")
        sleep(2)
        snapshot("01-watch-welcome")
        app.terminate()

        // 02. Response - showing a response
        launchWithScenario("RESPONSE")
        sleep(2)
        snapshot("02-watch-response")
        app.terminate()

        // 03. Quick Actions - grid of quick actions
        launchWithScenario("QUICKACTIONS")
        sleep(2)
        snapshot("03-watch-quick-actions")
        app.terminate()

        // 04. Voice Input - listening state (sheet)
        launchWithScenario("VOICEINPUT")
        sleep(3)  // Extra time for sheet animation
        snapshot("04-watch-voice-input")
        app.terminate()

        // 05. Processing - thinking state
        launchWithScenario("PROCESSING")
        sleep(2)
        snapshot("05-watch-processing")
        app.terminate()

        // 06. History - response history list (sheet)
        launchWithScenario("HISTORY")
        sleep(3)  // Extra time for sheet animation
        snapshot("06-watch-history")
        app.terminate()

        // 07. History Detail - single response detail view
        launchWithScenario("HISTORYDETAIL")
        sleep(3)  // Extra time for navigation
        snapshot("07-watch-history-detail")
        app.terminate()

        // 08. Error - error state with recovery option
        launchWithScenario("ERROR")
        sleep(2)
        snapshot("08-watch-error")
        app.terminate()

        // 09. Connected - connected to iPhone with responses
        launchWithScenario("CONNECTED")
        sleep(2)
        snapshot("09-watch-connected")
        app.terminate()

        // 10. Sending - sending query state
        launchWithScenario("SENDING")
        sleep(2)
        snapshot("10-watch-sending")
    }
}

