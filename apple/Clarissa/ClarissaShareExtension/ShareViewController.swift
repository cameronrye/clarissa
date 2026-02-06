import SwiftUI
import UniformTypeIdentifiers

/// Share Extension view controller
/// Processes shared text, URLs, and images using Foundation Models
/// Results are stored in App Group for the main app to pick up
@available(iOS 16.0, *)
class ShareViewController: UIViewController {
    private let processor = ShareProcessor()

    override func viewDidLoad() {
        super.viewDidLoad()

        // Show a simple processing UI
        let hostingView = UIHostingController(rootView: ShareExtensionView(
            onComplete: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        ))
        addChild(hostingView)
        view.addSubview(hostingView.view)
        hostingView.view.frame = view.bounds
        hostingView.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingView.didMove(toParent: self)

        // Process shared items
        Task {
            await processSharedItems()
            // Auto-dismiss after brief delay
            try? await Task.sleep(for: .seconds(1.5))
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func processSharedItems() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }

        for item in items {
            guard let attachments = item.attachments else { continue }

            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                        let result = await processor.processURL(url)
                        SharedResultStore.save(result)
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                        let result = await processor.processText(text)
                        SharedResultStore.save(result)
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let data = try? await attachment.loadItem(forTypeIdentifier: UTType.image.identifier) as? Data {
                        let result = await processor.processImage(data)
                        SharedResultStore.save(result)
                    }
                }
            }
        }
    }
}

/// Simple SwiftUI view shown during share extension processing
struct ShareExtensionView: View {
    let onComplete: () -> Void
    @State private var isProcessing = true

    var body: some View {
        VStack(spacing: 16) {
            if isProcessing {
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
