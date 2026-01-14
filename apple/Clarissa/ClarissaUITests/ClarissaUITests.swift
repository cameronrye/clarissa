//
//  ClarissaUITests.swift
//  ClarissaUITests
//
//  Automated screenshot capture for App Store using fastlane snapshot
//  Uses demo mode (-SCREENSHOT_MODE) with scenario arguments for different screenshots
//  Captures 10 screenshots per platform for App Store requirements
//

import XCTest

@MainActor
final class ClarissaUITests: XCTestCase {
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

        #if os(macOS)
        // Wait for the app window to appear
        let window = app.windows.firstMatch
        _ = window.waitForExistence(timeout: 10)

        // Activate the app to bring it to foreground
        app.activate()

        // Give time for the app to render
        sleep(2)

        // Click on the window to ensure it's focused and in foreground
        if window.exists {
            window.click()
            sleep(1)
        }
        #endif
    }

    // MARK: - Main Screenshot Test (captures all 10)

    /// Capture all 10 screenshots for App Store in sequence
    func testCaptureAllScreenshots() throws {
        // 01. Welcome - empty state with suggestions
        launchWithScenario("WELCOME")
        sleep(2)
        snapshot("01-welcome")
        app.terminate()

        // 02. Conversation - calendar query
        launchWithScenario("CONVERSATIONCALENDAR")
        sleep(2)
        snapshot("02-conversation-calendar")
        app.terminate()

        // 03. Conversation - weather with tool result
        launchWithScenario("CONVERSATIONWEATHER")
        sleep(2)
        snapshot("03-conversation-weather")
        app.terminate()

        // 04. Conversation - reminder creation
        launchWithScenario("CONVERSATIONREMINDER")
        sleep(2)
        snapshot("04-conversation-reminder")
        app.terminate()

        // 05. Voice mode active
        launchWithScenario("VOICEMODE")
        sleep(2)
        snapshot("05-voice-mode")
        app.terminate()

        // 06. Tool execution in progress
        launchWithScenario("TOOLEXECUTION")
        sleep(2)
        snapshot("06-tool-execution")
        app.terminate()

        // 07. Context visualizer
        launchWithScenario("CONTEXT")
        sleep(2)
        openContextVisualizer()
        sleep(1)
        snapshot("07-context-visualizer")
        app.terminate()

        // 08. History view
        // App auto-presents history sheet when launched with HISTORY scenario
        launchWithScenario("HISTORY")
        sleep(3)  // Extra time for sheet to auto-present
        snapshot("08-history")
        app.terminate()

        // 09. Settings - provider selection
        // App auto-shows Settings in main window when launched with SETTINGSPROVIDER scenario
        launchWithScenario("SETTINGSPROVIDER")
        sleep(3)
        snapshot("09-settings-provider")
        app.terminate()

        // 10. Settings - tool configuration
        // App auto-shows Settings with Tools tab when launched with SETTINGSVOICE scenario
        launchWithScenario("SETTINGSVOICE")
        sleep(3)
        snapshot("10-settings-tools")
    }

    // MARK: - Navigation Helpers

    private func openContextVisualizer() {
        let contextButton = app.buttons["ContextIndicator"].firstMatch
        if contextButton.waitForExistence(timeout: 5) {
            contextButton.tap()
        } else {
            let contextIndicator = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'Context usage'")
            ).firstMatch
            if contextIndicator.waitForExistence(timeout: 3) {
                contextIndicator.tap()
            }
        }
    }

    private func navigateToSettings() {
        #if os(macOS)
        // On macOS, open the Settings window via keyboard shortcut Cmd+,
        app.typeKey(",", modifierFlags: .command)
        sleep(2)
        // The Settings window uses a TabView with tabs at the top
        // General tab is selected by default, so just wait for the window
        let settingsWindow = app.windows.matching(NSPredicate(format: "title CONTAINS 'Settings'")).firstMatch
        if settingsWindow.waitForExistence(timeout: 5) {
            settingsWindow.click()
        }
        #else
        // iPhone uses tab bar, iPad uses sidebar
        let settingsTab = app.tabBars.buttons["Settings"]
        if settingsTab.waitForExistence(timeout: 3) {
            settingsTab.tap()
        } else {
            // iPad: Settings is in the sidebar, not the overflow menu
            // The sidebar has a Settings button that navigates to SettingsTabContent
            let sidebarSettingsButton = app.buttons["Settings"]
            if sidebarSettingsButton.waitForExistence(timeout: 5) {
                sidebarSettingsButton.tap()
            } else {
                // Fallback: try static text or other element types
                let settingsText = app.staticTexts["Settings"]
                if settingsText.waitForExistence(timeout: 3) {
                    settingsText.tap()
                }
            }
        }
        #endif
    }

    private func navigateToHistory() {
        #if os(macOS)
        // On macOS, use keyboard shortcut Cmd+Shift+H to show history sheet
        app.typeKey("h", modifierFlags: [.command, .shift])
        sleep(1)
        #else
        // iPhone uses tab bar, iPad uses overflow menu for history popup modal
        let historyTab = app.tabBars.buttons["History"]
        if historyTab.waitForExistence(timeout: 3) {
            historyTab.tap()
        } else {
            // iPad: Open overflow menu and tap History to show history sheet
            let overflowMenu = app.buttons["More options"]
            if overflowMenu.waitForExistence(timeout: 5) {
                overflowMenu.tap()
                sleep(1)
                // In SwiftUI Menu, items appear as buttons in the popover
                // Try finding the History button/menu item
                let historyMenuItem = app.buttons["History"]
                if historyMenuItem.waitForExistence(timeout: 3) {
                    historyMenuItem.tap()
                } else {
                    // Fallback: try menuItems
                    let historyItem = app.menuItems["History"]
                    if historyItem.waitForExistence(timeout: 2) {
                        historyItem.tap()
                    }
                }
            }
        }
        #endif
    }

    private func navigateToToolSettings() {
        #if os(macOS)
        // On macOS, Settings window should already be open
        // Click the "Tools" tab in the TabView at the top of the Settings window
        let toolsTab = app.buttons["Tools"]
        if toolsTab.waitForExistence(timeout: 3) {
            toolsTab.tap()
        } else {
            // Fallback: try using the radio button/tab item
            let toolsTabItem = app.radioButtons["Tools"]
            if toolsTabItem.waitForExistence(timeout: 3) {
                toolsTabItem.tap()
            }
        }
        #else
        // On iOS, tap the "Configure Tools" row in settings
        let configureToolsButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Configure Tools'")
        ).firstMatch
        if configureToolsButton.waitForExistence(timeout: 5) {
            configureToolsButton.tap()
        } else {
            // Fallback: try tapping any cell/row containing "Tools"
            let toolsCell = app.cells.matching(
                NSPredicate(format: "label CONTAINS[c] 'Tools'")
            ).firstMatch
            if toolsCell.waitForExistence(timeout: 3) {
                toolsCell.tap()
            } else {
                // Last fallback: try static texts
                let toolsText = app.staticTexts["Configure Tools"]
                if toolsText.waitForExistence(timeout: 3) {
                    toolsText.tap()
                }
            }
        }
        #endif
    }

    private func navigateToChat() {
        #if os(macOS)
        let chatButton = app.buttons["New Chat"]
        if chatButton.waitForExistence(timeout: 5) {
            chatButton.tap()
        }
        #else
        let chatTab = app.tabBars.buttons["Chat"]
        if chatTab.waitForExistence(timeout: 5) {
            chatTab.tap()
        }
        #endif
    }
}
