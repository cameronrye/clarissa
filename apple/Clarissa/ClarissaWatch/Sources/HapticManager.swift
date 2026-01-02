import WatchKit

/// Manages haptic feedback for the Watch app
/// Uses WKInterfaceDevice for haptic feedback on watchOS
enum HapticManager {
    /// Play haptic for button tap
    static func buttonTap() {
        WKInterfaceDevice.current().play(.click)
    }
    
    /// Play haptic when query is sent
    static func querySent() {
        WKInterfaceDevice.current().play(.start)
    }
    
    /// Play haptic when response is received
    static func responseReceived() {
        WKInterfaceDevice.current().play(.success)
    }
    
    /// Play haptic when an error occurs
    static func error() {
        WKInterfaceDevice.current().play(.failure)
    }
    
    /// Play haptic for status change (subtle)
    static func statusChange() {
        WKInterfaceDevice.current().play(.directionUp)
    }
    
    /// Play haptic when voice input starts
    static func voiceInputStart() {
        WKInterfaceDevice.current().play(.start)
    }
    
    /// Play haptic when voice input ends
    static func voiceInputEnd() {
        WKInterfaceDevice.current().play(.stop)
    }
    
    /// Play haptic for navigation
    static func navigation() {
        WKInterfaceDevice.current().play(.click)
    }
}

