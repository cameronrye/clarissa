import Foundation
import SwiftUI

// MARK: - Shared Result Types (main app copy)
// These types mirror the Share Extension's SharedResult.swift
// Both targets need their own copies since they can't share a module

/// A result from the Share Extension processing
struct SharedResult: Codable, Identifiable, Sendable {
    let id: UUID
    let type: SharedResultType
    let originalContent: String
    let analysis: String
    let createdAt: Date
    /// Optional tool chain ID to trigger when this result is processed
    let chainId: String?
}

/// The type of content that was shared
enum SharedResultType: String, Codable, Sendable {
    case text
    case url
    case image
}

/// Reads and writes SharedResults to the App Group UserDefaults
enum SharedResultStore {
    /// Load all pending shared results
    static func load() -> [SharedResult] {
        guard let defaults = ClarissaAppGroup.sharedDefaults,
              let data = defaults.data(forKey: ClarissaConstants.sharedResultsKey),
              let results = try? JSONDecoder().decode([SharedResult].self, from: data)
        else { return [] }
        return results
    }

    /// Clear all shared results (called after main app picks them up)
    static func clear() {
        ClarissaAppGroup.sharedDefaults?.removeObject(forKey: ClarissaConstants.sharedResultsKey)
    }
}

// MARK: - Shared Result Banner

/// Banner shown when shared content is available from the Share Extension
struct SharedResultBanner: View {
    let result: SharedResult
    let onInsert: () -> Void
    let onRunChain: ((String) -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(ClarissaTheme.purple)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.chainId != nil ? "Shared → Chain" : "Shared Content")
                    .font(.subheadline.weight(.medium))
                Text(result.analysis.prefix(60) + (result.analysis.count > 60 ? "..." : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let chainId = result.chainId, let onRunChain {
                Button("Run") { onRunChain(chainId) }
                    .buttonStyle(.borderedProminent)
                    .tint(ClarissaTheme.purple)
                    .controlSize(.small)
            }

            Button("Add") { onInsert() }
                .buttonStyle(.borderedProminent)
                .tint(result.chainId != nil ? .secondary : ClarissaTheme.purple)
                .controlSize(.small)

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var iconName: String {
        switch result.type {
        case .text: return "doc.text"
        case .url: return "link"
        case .image: return "photo"
        }
    }
}
