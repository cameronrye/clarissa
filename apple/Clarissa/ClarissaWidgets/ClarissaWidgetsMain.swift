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

        // Control Center widgets (iOS 18+)
        if #available(iOS 18.0, *) {
            ClarissaControlWidget()
            VoiceModeControlWidget()
            NewChatControlWidget()
        }
    }
}

