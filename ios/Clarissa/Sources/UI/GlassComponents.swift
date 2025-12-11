import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Haptic Manager

/// Centralized haptic feedback manager for consistent glass interactions
/// Per Apple HIG: Glass interactive elements should provide haptic feedback
@MainActor
final class HapticManager: Sendable {
    static let shared = HapticManager()

    private init() {}

    /// Light tap feedback for glass button presses
    func lightTap() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    /// Medium tap feedback for primary glass actions
    func mediumTap() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }

    /// Heavy tap feedback for significant glass actions
    func heavyTap() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        #endif
    }

    /// Selection change feedback for glass toggles and pickers
    func selection() {
        #if os(iOS)
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        #endif
    }

    /// Success notification for completed actions
    func success() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    /// Warning notification for confirmations
    func warning() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }

    /// Error notification for failures
    func error() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        #endif
    }
}

// MARK: - Glass Configuration

/// Centralized glass effect configurations for Clarissa
@available(iOS 26.0, macOS 26.0, *)
enum ClarissaGlass {
    /// Standard interactive glass for toolbar buttons
    static var interactive: Glass {
        .regular.interactive()
    }

    /// Glass for primary action buttons
    static var primary: Glass {
        .regular.tint(.accentColor).interactive()
    }

    /// Glass with state-based tinting
    static func stateful(isActive: Bool, tint: Color) -> Glass {
        .regular.tint(isActive ? tint : nil).interactive()
    }

    /// Non-interactive glass for indicators
    static var indicator: Glass {
        .regular
    }

    /// Glass for toolbar containers
    static var toolbar: Glass {
        .regular
    }
}

// MARK: - Clarissa State

/// Represents the current state of the Clarissa assistant
enum ClarissaState: Sendable {
    case idle
    case listening
    case thinking
    case speaking
    
    var iconName: String {
        switch self {
        case .idle: return "sparkles"
        case .listening: return "waveform"
        case .thinking: return "brain"
        case .speaking: return "speaker.wave.2"
        }
    }
    
    var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .thinking: return "Thinking..."
        case .speaking: return "Speaking..."
        }
    }
    
    var tintColor: Color? {
        switch self {
        case .idle: return nil
        case .listening: return .blue
        case .thinking: return .purple
        case .speaking: return .green
        }
    }
}

// MARK: - Glass Button Components

/// A reusable glass-styled icon button with circle shape (per Liquid Glass guide)
/// Supports morphing transitions via optional glassEffectID
@available(iOS 26.0, macOS 26.0, *)
struct ClarissaGlassButton<ID: Hashable & Sendable>: View {
    let icon: String
    let action: () -> Void
    var isActive: Bool = false
    var tint: Color? = nil
    var size: CGFloat = 44

    /// Optional ID for glass morphing transitions
    var glassID: ID?
    /// Optional namespace for glass morphing transitions
    var namespace: Namespace.ID?

    var body: some View {
        let button = Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: size, height: size)
        }
        .glassEffect(
            ClarissaGlass.stateful(isActive: isActive, tint: tint ?? .accentColor),
            in: .circle
        )

        if let glassID = glassID, let namespace = namespace {
            button.glassEffectID(glassID, in: namespace)
        } else {
            button
        }
    }
}

/// Convenience initializer for ClarissaGlassButton without morphing support
@available(iOS 26.0, macOS 26.0, *)
extension ClarissaGlassButton where ID == String {
    init(
        icon: String,
        action: @escaping () -> Void,
        isActive: Bool = false,
        tint: Color? = nil,
        size: CGFloat = 44
    ) {
        self.icon = icon
        self.action = action
        self.isActive = isActive
        self.tint = tint
        self.size = size
        self.glassID = nil
        self.namespace = nil
    }
}

/// A floating action button with glass styling (per Liquid Glass guide)
/// Supports morphing transitions via optional glassEffectID
@available(iOS 26.0, macOS 26.0, *)
struct ClarissaFloatingButton<ID: Hashable & Sendable>: View {
    let icon: String
    let action: () -> Void
    var isActive: Bool = false
    var activeTint: Color = .blue
    var size: CGFloat = 56

    /// Optional ID for glass morphing transitions
    var glassID: ID?
    /// Optional namespace for glass morphing transitions
    var namespace: Namespace.ID?

    var body: some View {
        let button = Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: size, height: size)
        }
        .glassEffect(
            .regular
                .tint(isActive ? activeTint : nil)
                .interactive(),
            in: .circle
        )
        .animation(.bouncy, value: isActive)

        if let glassID = glassID, let namespace = namespace {
            button.glassEffectID(glassID, in: namespace)
        } else {
            button
        }
    }
}

/// Convenience initializer for ClarissaFloatingButton without morphing support
@available(iOS 26.0, macOS 26.0, *)
extension ClarissaFloatingButton where ID == String {
    init(
        icon: String,
        action: @escaping () -> Void,
        isActive: Bool = false,
        activeTint: Color = .blue,
        size: CGFloat = 56
    ) {
        self.icon = icon
        self.action = action
        self.isActive = isActive
        self.activeTint = activeTint
        self.size = size
        self.glassID = nil
        self.namespace = nil
    }
}

/// State indicator with glass backing
@available(iOS 26.0, macOS 26.0, *)
struct ClarissaStateIndicator: View {
    let state: ClarissaState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state.iconName)
            Text(state.displayName)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(state.tintColor))
    }
}

// MARK: - Glass Thinking Indicator

/// A glass-backed thinking/loading indicator pill
/// Replaces plain ProgressView for iOS 26+ with Liquid Glass styling
@available(iOS 26.0, macOS 26.0, *)
struct GlassThinkingIndicator: View {
    let message: String
    var tint: Color = ClarissaTheme.purple
    var showCancel: Bool = false
    var onCancel: (() -> Void)?

    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            // Animated dots or static indicator based on reduce motion
            if reduceMotion {
                ProgressView()
                    .tint(tint)
                    .scaleEffect(0.8)
            } else {
                ThinkingDotsView(tint: tint)
            }

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)

            if showCancel, let onCancel = onCancel {
                Button {
                    HapticManager.shared.lightTap()
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel")
                .accessibilityHint("Stop the current operation")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(tint), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Animated thinking dots for the glass indicator
@available(iOS 26.0, macOS 26.0, *)
private struct ThinkingDotsView: View {
    let tint: Color
    @State private var animationPhase: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .opacity(animationPhase == index ? 1.0 : 0.3)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: false)) {
                startAnimation()
            }
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            animationPhase = (animationPhase + 1) % 3
        }
    }
}

/// Legacy thinking indicator for pre-iOS 26
struct LegacyThinkingIndicator: View {
    let message: String
    var tint: Color = ClarissaTheme.purple
    var showCancel: Bool = false
    var onCancel: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(tint)

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)

            if showCancel, let onCancel = onCancel {
                Button {
                    HapticManager.shared.lightTap()
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(tint.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Accessibility Support

/// Environment-aware glass modifier that respects all accessibility settings
/// Per Apple HIG and NN/G recommendations for iOS 26 Liquid Glass:
/// - reduceTransparency: Falls back to opaque background
/// - reduceMotion: Disables .interactive() animations
/// - accessibilityContrast: Uses higher contrast foreground styling
@available(iOS 26.0, macOS 26.0, *)
struct AccessibleGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.colorSchemeContrast) var contrast

    let glass: Glass
    let shape: AnyShape
    let isInteractive: Bool
    let tint: Color?

    init<S: Shape>(
        glass: Glass = .regular,
        in shape: S = Capsule(),
        isInteractive: Bool = false,
        tint: Color? = nil
    ) {
        self.glass = glass
        self.shape = AnyShape(shape)
        self.isInteractive = isInteractive
        self.tint = tint
    }

    func body(content: Content) -> some View {
        if reduceTransparency {
            // Fallback to opaque background for accessibility
            content
                .background(opaqueBackground)
                .clipShape(shape)
        } else {
            // Apply glass effect, respecting reduce motion
            let baseGlass = tint != nil ? glass.tint(tint!) : glass
            let effectiveGlass = isInteractive && !reduceMotion ? baseGlass.interactive() : baseGlass
            content.glassEffect(effectiveGlass, in: shape)
        }
    }

    /// Opaque background color for reduce transparency mode
    /// Uses higher contrast colors when accessibility contrast is increased
    @ViewBuilder
    private var opaqueBackground: some View {
        #if os(iOS)
        if contrast == .increased {
            Color(uiColor: .systemBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
                )
        } else {
            Color(uiColor: .secondarySystemBackground)
        }
        #else
        if contrast == .increased {
            Color(nsColor: .windowBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
                )
        } else {
            Color(nsColor: .controlBackgroundColor)
        }
        #endif
    }
}

@available(iOS 26.0, macOS 26.0, *)
extension View {
    /// Apply glass effect with full accessibility support
    /// Respects reduceTransparency, reduceMotion, and increased contrast
    func accessibleGlass<S: Shape>(
        _ glass: Glass = .regular,
        in shape: S = Capsule(),
        isInteractive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(AccessibleGlassModifier(glass: glass, in: shape, isInteractive: isInteractive, tint: tint))
    }
}

// MARK: - High Contrast Text Modifier

/// Modifier that adjusts text styling for high contrast mode
/// Use on text displayed over glass surfaces
struct HighContrastTextModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) var contrast

    let normalStyle: AnyShapeStyle
    let highContrastStyle: AnyShapeStyle

    init(normal: some ShapeStyle = Color.primary, highContrast: some ShapeStyle = Color.primary) {
        self.normalStyle = AnyShapeStyle(normal)
        self.highContrastStyle = AnyShapeStyle(highContrast)
    }

    func body(content: Content) -> some View {
        content
            .foregroundStyle(contrast == .increased ? highContrastStyle : normalStyle)
            .fontWeight(contrast == .increased ? .semibold : .regular)
    }
}

extension View {
    /// Apply high contrast-aware text styling for glass surfaces
    func glassTextStyle(
        normal: some ShapeStyle = Color.primary,
        highContrast: some ShapeStyle = Color.primary
    ) -> some View {
        modifier(HighContrastTextModifier(normal: normal, highContrast: highContrast))
    }
}

