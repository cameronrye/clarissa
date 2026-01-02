import SwiftUI
import WatchKit

/// Main content view for the Watch app
struct WatchContentView: View {
    @EnvironmentObject private var appState: WatchAppState
    @State private var showingVoiceInput = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Status indicator
                statusView
                
                // Response display
                if let response = appState.lastResponse {
                    ScrollView {
                        Text(response)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    Spacer()
                    
                    Text("Tap to ask Clarissa")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                
                // Voice input button
                Button {
                    HapticManager.buttonTap()
                    showingVoiceInput = true
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(appState.isReachable ? Color.blue : Color.gray)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!appState.isReachable || isProcessing)
            }
            .padding(.horizontal)
            .navigationTitle("Clarissa")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingVoiceInput) {
                WatchVoiceInputView { text in
                    appState.sendQuery(text)
                }
            }
        }
    }
    
    @ViewBuilder
    private var statusView: some View {
        switch appState.status {
        case .idle:
            EmptyView()
            
        case .listening:
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                Text("Listening...")
            }
            .font(.caption)
            .foregroundStyle(.blue)
            
        case .sending:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Sending...")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
        case .waiting:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Waiting...")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
        case .processing(let message):
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text(message)
            }
            .font(.caption)
            .foregroundStyle(.orange)
            
        case .error(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message)
            }
            .font(.caption)
            .foregroundStyle(.red)
            .onTapGesture {
                appState.clearError()
            }
        }
    }
    
    private var isProcessing: Bool {
        switch appState.status {
        case .idle, .error:
            return false
        default:
            return true
        }
    }
}

#Preview {
    WatchContentView()
        .environmentObject(WatchAppState())
}

