import SwiftUI
import WatchKit

/// Voice input view for the Watch app
/// Uses SwiftUI TextField with built-in dictation support
struct WatchVoiceInputView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @FocusState private var isTextFieldFocused: Bool

    let onSubmit: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Text input with dictation support
            TextField("Ask Clarissa...", text: $inputText, axis: .vertical)
                .lineLimit(3...6)
                .focused($isTextFieldFocused)
                .submitLabel(.send)
                .onSubmit {
                    submitQuery()
                }

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                // Cancel button
                Button {
                    HapticManager.buttonTap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.gray)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Send button
                Button {
                    HapticManager.buttonTap()
                    submitQuery()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(inputText.isEmpty ? Color.gray : Color.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty)
            }
        }
        .padding()
        .navigationTitle("Ask")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Auto-focus to trigger keyboard/dictation
            isTextFieldFocused = true
        }
    }

    private func submitQuery() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        dismiss()
    }
}

#Preview {
    WatchVoiceInputView { text in
        print("Submitted: \(text)")
    }
}

