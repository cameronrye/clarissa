import SwiftUI

/// Clarissa brand colors and theme
enum ClarissaTheme {
    // MARK: - Brand Colors

    /// Pink: #EC4899
    static let pink = Color(red: 0.925, green: 0.286, blue: 0.600)

    /// Purple: #8B5CF6
    static let purple = Color(red: 0.545, green: 0.361, blue: 0.965)

    /// Cyan: #06B6D4
    static let cyan = Color(red: 0.024, green: 0.714, blue: 0.831)

    /// Dark background: #0a0a0f
    static let backgroundDark = Color(red: 0.039, green: 0.039, blue: 0.059)

    /// Secondary background: #12121a
    static let backgroundSecondary = Color(red: 0.071, green: 0.071, blue: 0.102)

    // MARK: - Gradient

    /// The signature Clarissa gradient (pink -> purple -> cyan)
    static let gradient = LinearGradient(
        colors: [pink, purple, cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Reversed gradient (cyan -> purple -> pink)
    static let gradientReversed = LinearGradient(
        colors: [cyan, purple, pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - UI Colors

    /// Assistant message bubble background
    static let assistantBubble = purple.opacity(0.15)

    /// User message bubble uses the gradient
    static let userBubbleGradient = LinearGradient(
        colors: [purple, pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Glass Tint Colors (for semantic meaning per Liquid Glass guide)

    /// Tint for listening/recording state
    static let listeningTint = Color.blue

    /// Tint for thinking/processing state
    static let thinkingTint = purple

    /// Tint for speaking state
    static let speakingTint = Color.green

    /// Tint for error/warning state
    static let errorTint = Color.red

    /// Tint for success/completed state
    static let successTint = cyan

    /// Primary action tint
    static let primaryActionTint = purple
}

/// Extension for gradient text effect
extension View {
    func gradientForeground() -> some View {
        self.overlay(ClarissaTheme.gradient)
            .mask(self)
    }
}

/// Clarissa logo view matching the doc site design
struct ClarissaLogo: View {
    var size: CGFloat = 32
    
    var body: some View {
        ZStack {
            // Prism triangle
            Triangle()
                .stroke(
                    ClarissaTheme.gradientReversed,
                    style: StrokeStyle(lineWidth: size * 0.025, lineJoin: .round)
                )
                .frame(width: size, height: size)
            
            // C lettermark
            CLettermark()
                .stroke(
                    ClarissaTheme.gradient,
                    style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round)
                )
                .frame(width: size * 0.5, height: size * 0.5)
                .offset(y: size * 0.08)
        }
    }
}

/// Triangle shape for the prism
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.maxY - rect.height * 0.15))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.maxY - rect.height * 0.15))
        path.closeSubpath()
        return path
    }
}

/// C lettermark shape
struct CLettermark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        
        // Draw arc for C shape (approximately 270 degrees, open on right side)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-50),
            endAngle: .degrees(50),
            clockwise: true
        )
        return path
    }
}

#Preview {
    VStack(spacing: 20) {
        ClarissaLogo(size: 64)
        ClarissaLogo(size: 32)
        
        Text("Clarissa")
            .font(.title.bold())
            .gradientForeground()
    }
    .padding()
    .background(ClarissaTheme.backgroundDark)
}

