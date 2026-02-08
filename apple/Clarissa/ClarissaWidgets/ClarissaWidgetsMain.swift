import SwiftUI
import WidgetKit
import ClarissaKit

/// Main entry point for the Clarissa Widget Extension
/// Uses the ClarissaWidgetBundle defined in ClarissaKit
@available(iOS 17.0, macOS 14.0, *)
@main
struct ClarissaWidgetsMain: WidgetBundle {
    var body: some Widget {
        QuickAskWidget()
        ConversationWidget()
        MorningWidget()
        MemorySpotlightWidget()

        #if os(iOS)
        // Control Center widgets (iOS 18+)
        ClarissaControlWidget()
        VoiceModeControlWidget()
        NewChatControlWidget()

        #if canImport(ActivityKit)
        // Live Activity for multi-tool execution
        ClarissaLiveActivityWidget()
        #endif

        // StandBy mode widget (iOS only)
        StandByWidget()
        #endif
    }
}

