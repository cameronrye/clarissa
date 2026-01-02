import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Control Center Widgets (iOS 18+)

#if os(iOS)

/// Control Center button to open Clarissa
@available(iOS 18.0, *)
public struct ClarissaControlWidget: ControlWidget {
    public init() {}

    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.rye.clarissa.control.open") {
            ControlWidgetButton(action: ClarissaOpenControlIntent()) {
                Label("Clarissa", systemImage: "sparkles")
            }
        }
        .displayName("Open Clarissa")
        .description("Quick access to Clarissa")
    }
}

/// Control Center button for voice mode
@available(iOS 18.0, *)
public struct VoiceModeControlWidget: ControlWidget {
    public init() {}

    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.rye.clarissa.control.voice") {
            ControlWidgetButton(action: ClarissaVoiceModeControlIntent()) {
                Label("Voice", systemImage: "waveform")
            }
        }
        .displayName("Voice Mode")
        .description("Start voice conversation with Clarissa")
    }
}

/// Control Center button to start a new conversation
@available(iOS 18.0, *)
public struct NewChatControlWidget: ControlWidget {
    public init() {}

    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.rye.clarissa.control.newchat") {
            ControlWidgetButton(action: ClarissaNewChatControlIntent()) {
                Label("New Chat", systemImage: "plus.bubble")
            }
        }
        .displayName("New Conversation")
        .description("Start a new conversation with Clarissa")
    }
}

// MARK: - Control Widget Intents

/// Intent to open Clarissa from Control Center
/// Note: openAppWhenRun=true means the app opens automatically, no custom action needed
@available(iOS 18.0, *)
public struct ClarissaOpenControlIntent: ControlConfigurationIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Open Clarissa"
    public static let description = IntentDescription("Open the Clarissa app")
    public static let isDiscoverable = true
    public static let openAppWhenRun = true

    public func perform() async throws -> some IntentResult {
        return .result()
    }
}

/// Intent to start voice mode from Control Center
/// Opens app via URL scheme to trigger voice mode
@available(iOS 18.0, *)
public struct ClarissaVoiceModeControlIntent: ControlConfigurationIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Voice Mode"
    public static let description = IntentDescription("Start voice conversation with Clarissa")
    public static let isDiscoverable = true
    public static let openAppWhenRun = false

    public func perform() async throws -> some IntentResult & OpensIntent {
        // Use URL scheme to open app in voice mode
        return .result(opensIntent: OpenURLIntent(URL(string: "clarissa://voice")!))
    }
}

/// Intent to start a new conversation from Control Center
/// Opens app via URL scheme to start new conversation
@available(iOS 18.0, *)
public struct ClarissaNewChatControlIntent: ControlConfigurationIntent {
    public init() {}

    public static let title: LocalizedStringResource = "New Conversation"
    public static let description = IntentDescription("Start a new conversation with Clarissa")
    public static let isDiscoverable = true
    public static let openAppWhenRun = false

    public func perform() async throws -> some IntentResult & OpensIntent {
        // Use URL scheme to open app with new conversation
        return .result(opensIntent: OpenURLIntent(URL(string: "clarissa://new")!))
    }
}

#endif

