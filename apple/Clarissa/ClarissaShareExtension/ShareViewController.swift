import Combine
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Observable state shared between the view controller and the SwiftUI view
class ShareProcessingState: ObservableObject {
    @Published var isProcessing = true
}

/// Share Extension view controller
/// Processes shared text, URLs, and images using Foundation Models
/// Results are stored in App Group for the main app to pick up

#if os(iOS)
@available(iOS 16.0, *)
class ShareViewController: UIViewController {
    private let state = ShareProcessingState()

    override func viewDidLoad() {
        super.viewDidLoad()

        // Show a simple processing UI
        let hostingView = UIHostingController(rootView: ShareExtensionView(state: state))
        addChild(hostingView)
        view.addSubview(hostingView.view)
        hostingView.view.frame = view.bounds
        hostingView.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingView.didMove(toParent: self)

        // Process shared items with timeout, then auto-dismiss
        Task { @MainActor in
            await withTimeoutProcessing()
            state.isProcessing = false
            try? await Task.sleep(for: .seconds(1.5))
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func withTimeoutProcessing() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await self.processExtensionItems()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(15))
            }
            // Return as soon as either finishes (processing done or timeout)
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func processExtensionItems() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }
        let processor = ShareProcessor()
        for item in items {
            guard let attachments = item.attachments else { continue }
            for attachment in attachments {
                await processAttachment(attachment, processor: processor)
            }
        }
    }
}

#elseif os(macOS)
@available(macOS 13.0, *)
class ShareViewController: NSViewController {
    private let state = ShareProcessingState()

    override func loadView() {
        let hostingView = NSHostingController(rootView: ShareExtensionView(state: state))
        addChild(hostingView)
        self.view = hostingView.view

        // Process shared items with timeout, then auto-dismiss
        Task { @MainActor in
            await withTimeoutProcessing()
            state.isProcessing = false
            try? await Task.sleep(for: .seconds(1.5))
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func withTimeoutProcessing() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await self.processExtensionItems()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(15))
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func processExtensionItems() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }
        let processor = ShareProcessor()
        for item in items {
            guard let attachments = item.attachments else { continue }
            for attachment in attachments {
                await processAttachment(attachment, processor: processor)
            }
        }
    }
}
#endif

/// Maximum size limits for shared content
private let maxTextLength = 50_000    // 50K characters
private let maxImageSize = 10_000_000 // 10 MB

/// Shared attachment processing logic for both platforms
private func processAttachment(_ attachment: NSItemProvider, processor: ShareProcessor) async {
    if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
        if let url = try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
           url.scheme == "http" || url.scheme == "https" {
            let result = await processor.processURL(url)
            SharedResultStore.save(result)
        }
    } else if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
        if let text = try? await attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
           text.count <= maxTextLength {
            let result = await processor.processText(text)
            SharedResultStore.save(result)
        }
    } else if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
        if let data = try? await attachment.loadItem(forTypeIdentifier: UTType.image.identifier) as? Data,
           data.count <= maxImageSize {
            let result = await processor.processImage(data)
            SharedResultStore.save(result)
        }
    }
}

/// Simple SwiftUI view shown during share extension processing
struct ShareExtensionView: View {
    @ObservedObject var state: ShareProcessingState

    var body: some View {
        VStack(spacing: 16) {
            if state.isProcessing {
                ProgressView()
                    .controlSize(.large)
                Text("Analyzing with Clarissa...")
                    .font(.headline)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("Saved to Clarissa")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
