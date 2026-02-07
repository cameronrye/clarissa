import SwiftUI

/// Compact context indicator for the toolbar
struct ContextIndicatorView: View {
    let stats: ContextStats
    let onTap: () -> Void

    private var gaugeColor: Color {
        if stats.isCritical {
            return .red
        } else if stats.isNearLimit {
            return .orange
        } else {
            return ClarissaTheme.purple
        }
    }

    /// Glass tint based on context state
    private var glassTint: Color? {
        if stats.isCritical { return ClarissaTheme.errorTint }
        if stats.isNearLimit { return .orange }
        return nil
    }

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassIndicator
        } else {
            legacyIndicator
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var glassIndicator: some View {
        Button(action: onTap) {
            gaugeContent
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(glassTint).interactive(), in: .circle)
        .accessibilityIdentifier("ContextIndicator")
        .accessibilityLabel("Context usage: \(Int(stats.usagePercent * 100)) percent")
        .accessibilityHint("Tap for context details")
    }

    private var legacyIndicator: some View {
        Button(action: onTap) {
            gaugeContent
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ContextIndicator")
        .accessibilityLabel("Context usage: \(Int(stats.usagePercent * 100)) percent")
        .accessibilityHint("Tap for context details")
    }

    private var gaugeContent: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                .frame(width: 24, height: 24)

            // Progress ring
            Circle()
                .trim(from: 0, to: stats.usagePercent)
                .stroke(
                    gaugeColor,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 24, height: 24)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: stats.usagePercent)

            // Percentage text (only show when significant)
            if stats.usagePercent > 0.1 {
                Text("\(Int(stats.usagePercent * 100))")
                    .font(.caption2.weight(.bold))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(gaugeColor)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.3), value: stats.usagePercent)
            }
        }
    }
}

/// Detailed context breakdown sheet
struct ContextDetailSheet: View {
    let stats: ContextStats
    var onSummarize: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Main gauge
                    mainGauge

                    // Token breakdown
                    tokenBreakdown

                    // Info section
                    infoSection
                }
                .padding()
            }
            .navigationTitle("Context Window")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    doneButton
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    doneButton
                }
            }
            #endif
        }
        .tint(ClarissaTheme.purple)
    }

    @ViewBuilder
    private var doneButton: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Button("Done") { dismiss() }
                .buttonStyle(.glassProminent)
                .tint(ClarissaTheme.purple)
        } else {
            Button("Done") { dismiss() }
                .foregroundStyle(ClarissaTheme.purple)
        }
    }
    
    private var mainGauge: some View {
        VStack(spacing: 12) {
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                    .frame(width: 140, height: 140)
                
                // Progress arc with gradient
                Circle()
                    .trim(from: 0, to: stats.usagePercent)
                    .stroke(
                        AngularGradient(
                            colors: [ClarissaTheme.cyan, ClarissaTheme.purple, ClarissaTheme.pink],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: stats.usagePercent)
                
                // Center content
                VStack(spacing: 2) {
                    Text("\(Int(stats.usagePercent * 100))%")
                        .font(.largeTitle.weight(.bold))
                        .minimumScaleFactor(0.5)
                        .gradientForeground()
                    Text("used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Token counts
            Text("\(stats.currentTokens.formatted()) / \(stats.maxTokens.formatted()) tokens")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    /// Accessibility description for the breakdown bar
    private var breakdownAccessibilityLabel: String {
        let userPercent = stats.currentTokens > 0 ? Int(Double(stats.userTokens) / Double(stats.currentTokens) * 100) : 0
        let assistantPercent = stats.currentTokens > 0 ? Int(Double(stats.assistantTokens) / Double(stats.currentTokens) * 100) : 0
        let toolPercent = stats.currentTokens > 0 ? Int(Double(stats.toolTokens) / Double(stats.currentTokens) * 100) : 0
        return "Token breakdown: You \(stats.userTokens) tokens (\(userPercent)%), Clarissa \(stats.assistantTokens) tokens (\(assistantPercent)%), Tools \(stats.toolTokens) tokens (\(toolPercent)%)"
    }

    private var tokenBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Breakdown")
                .font(.headline)

            // Stacked bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    breakdownBar(tokens: stats.userTokens, color: ClarissaTheme.pink, width: geo.size.width)
                    breakdownBar(tokens: stats.assistantTokens, color: ClarissaTheme.purple, width: geo.size.width)
                    breakdownBar(tokens: stats.toolTokens, color: ClarissaTheme.cyan, width: geo.size.width)
                }
            }
            .frame(height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(breakdownAccessibilityLabel)

            // Legend
            HStack(spacing: 16) {
                legendItem(color: ClarissaTheme.pink, label: "You", tokens: stats.userTokens)
                legendItem(color: ClarissaTheme.purple, label: "Clarissa", tokens: stats.assistantTokens)
                legendItem(color: ClarissaTheme.cyan, label: "Tools", tokens: stats.toolTokens)
            }
            .font(.caption)
            .accessibilityHidden(true) // Already covered by breakdown bar label
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func breakdownBar(tokens: Int, color: Color, width: CGFloat) -> some View {
        let total = max(1, stats.currentTokens)
        let proportion = CGFloat(tokens) / CGFloat(total)
        let barWidth = proportion * width * stats.usagePercent

        if tokens > 0 {
            Rectangle()
                .fill(color)
                .frame(width: max(4, barWidth))
        }
    }

    private func legendItem(color: Color, label: String, tokens: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
            Text("(\(tokens))")
                .foregroundStyle(.tertiary)
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About Context")
                .font(.headline)

            Text("The context window is the AI's working memory for this conversation. When it fills up, older messages are automatically removed to make room for new ones.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Critical warning (>95%)
            if stats.isCritical {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text("Context is full. Start a new session to continue effectively.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if stats.isNearLimit {
                // Near limit warning (>80%)
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Context is nearly full. Consider starting a new session for complex tasks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Trimmed messages notice
            if stats.trimmedCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "scissors")
                        .foregroundStyle(.secondary)
                    Text("\(stats.trimmedCount) older message\(stats.trimmedCount == 1 ? "" : "s") removed to free space.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Manual summarize button (show when enough messages to be useful)
            if let onSummarize, stats.messageCount > 4 {
                Button {
                    onSummarize()
                    dismiss()
                } label: {
                    Label("Summarize Conversation", systemImage: "arrow.trianglehead.2.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ClarissaTheme.purple)
                .padding(.top, 4)
            }

            // Stats summary (messageCount - 1 to exclude system message)
            HStack {
                statItem(value: "\(max(0, stats.messageCount - 1))", label: "Messages")
                Divider().frame(height: 30)
                statItem(value: "\(stats.maxTokens.formatted())", label: "Max Tokens")
                Divider().frame(height: 30)
                statItem(value: "\(stats.systemTokens)", label: "System")
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .gradientForeground()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Indicator") {
    HStack(spacing: 20) {
        ContextIndicatorView(stats: .empty, onTap: {})
        ContextIndicatorView(
            stats: ContextStats(
                currentTokens: 439,
                maxTokens: TokenBudget.maxHistoryTokens,
                usagePercent: 0.22,
                systemTokens: 300,
                userTokens: 150,
                assistantTokens: 239,
                toolTokens: 50,
                messageCount: 6,
                trimmedCount: 0
            ),
            onTap: {}
        )
        ContextIndicatorView(
            stats: ContextStats(
                currentTokens: 1657,
                maxTokens: TokenBudget.maxHistoryTokens,
                usagePercent: 0.83,
                systemTokens: 300,
                userTokens: 500,
                assistantTokens: 957,
                toolTokens: 200,
                messageCount: 12,
                trimmedCount: 2
            ),
            onTap: {}
        )
    }
    .padding()
}

#Preview("Detail Sheet") {
    ContextDetailSheet(
        stats: ContextStats(
            currentTokens: 1038,
            maxTokens: TokenBudget.maxHistoryTokens,
            usagePercent: 0.52,
            systemTokens: 300,
            userTokens: 350,
            assistantTokens: 538,
            toolTokens: 150,
            messageCount: 8,
            trimmedCount: 0
        )
    )
}

