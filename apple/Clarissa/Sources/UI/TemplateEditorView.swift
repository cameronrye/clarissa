import SwiftUI

/// List view for managing custom templates (used from Settings)
struct CustomTemplateListView: View {
    @State private var customTemplates: [ConversationTemplate] = []
    @State private var showEditor = false
    @State private var editingTemplate: ConversationTemplate?

    var body: some View {
        List {
            if customTemplates.isEmpty {
                ContentUnavailableView {
                    Label("No Custom Templates", systemImage: "rectangle.stack")
                } description: {
                    Text("Create templates with specialized prompts and tools for common tasks.")
                }
            } else {
                ForEach(customTemplates) { template in
                    Button {
                        editingTemplate = template
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: template.icon)
                                .foregroundStyle(ClarissaTheme.purple)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(template.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let template = customTemplates[index]
                        Task {
                            try? await TemplateStore.shared.delete(id: template.id)
                            customTemplates = await TemplateStore.shared.load()
                        }
                    }
                }
            }
        }
        .navigationTitle("Custom Templates")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingTemplate = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            TemplateEditorView { newTemplate in
                Task {
                    try? await TemplateStore.shared.add(newTemplate)
                    customTemplates = await TemplateStore.shared.load()
                }
            }
        }
        .sheet(item: $editingTemplate) { template in
            TemplateEditorView(existingTemplate: template) { updated in
                Task {
                    try? await TemplateStore.shared.update(updated)
                    customTemplates = await TemplateStore.shared.load()
                }
            }
        }
        .task {
            customTemplates = await TemplateStore.shared.load()
        }
    }
}

/// Form for creating or editing a custom conversation template
struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss

    /// If editing an existing template, pass it here; nil for new template
    var existingTemplate: ConversationTemplate?
    var onSave: (ConversationTemplate) -> Void

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var selectedIcon: String = "bubble.left.and.text.bubble.right"
    @State private var systemPromptFocus: String = ""
    @State private var selectedTools: Set<String> = []
    @State private var responseLength: ResponseLength = .medium
    @State private var initialPrompt: String = ""

    private let iconOptions = [
        "bubble.left.and.text.bubble.right", "brain.head.profile", "lightbulb",
        "book", "pencil.and.outline", "doc.text", "list.bullet",
        "chart.bar", "globe", "gear", "star", "bolt"
    ]

    enum ResponseLength: String, CaseIterable, Identifiable {
        case short = "Short"
        case medium = "Medium"
        case long = "Long"

        var id: String { rawValue }

        var tokens: Int {
            switch self {
            case .short: return 200
            case .medium: return 400
            case .long: return 800
            }
        }

        init(tokens: Int?) {
            switch tokens {
            case .some(let t) where t <= 250: self = .short
            case .some(let t) where t >= 600: self = .long
            default: self = .medium
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $description)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                                    .background(selectedIcon == icon ? ClarissaTheme.purple.opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(icon)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    TextEditor(text: $systemPromptFocus)
                        .frame(minHeight: 80)
                } header: {
                    Text("System Prompt Focus")
                } footer: {
                    Text("Instructions appended to Clarissa's base prompt for this template.")
                }

                Section {
                    let tools = ToolSettings.shared.allTools
                    ForEach(tools) { tool in
                        Toggle(tool.name, isOn: Binding(
                            get: { selectedTools.contains(tool.id) },
                            set: { enabled in
                                if enabled {
                                    selectedTools.insert(tool.id)
                                } else {
                                    selectedTools.remove(tool.id)
                                }
                            }
                        ))
                    }
                } header: {
                    Text("Tools")
                } footer: {
                    Text("Leave all off to use current tool settings.")
                }

                Section("Response Length") {
                    Picker("Length", selection: $responseLength) {
                        ForEach(ResponseLength.allCases) { length in
                            Text(length.rawValue).tag(length)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("Optional initial message", text: $initialPrompt)
                } header: {
                    Text("Initial Prompt")
                } footer: {
                    Text("Sent automatically when the template is selected. Leave empty to just configure tools and prompt.")
                }
            }
            .navigationTitle(existingTemplate != nil ? "Edit Template" : "New Template")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let template = ConversationTemplate(
                            id: existingTemplate?.id ?? "custom_\(UUID().uuidString.prefix(8))",
                            name: name,
                            description: description,
                            icon: selectedIcon,
                            systemPromptFocus: systemPromptFocus.isEmpty ? nil : systemPromptFocus,
                            toolNames: selectedTools.isEmpty ? nil : Array(selectedTools),
                            maxResponseTokens: responseLength.tokens,
                            initialPrompt: initialPrompt.isEmpty ? nil : initialPrompt
                        )
                        onSave(template)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .tint(ClarissaTheme.purple)
        .onAppear {
            if let t = existingTemplate {
                name = t.name
                description = t.description
                selectedIcon = t.icon
                systemPromptFocus = t.systemPromptFocus ?? ""
                selectedTools = Set(t.toolNames ?? [])
                responseLength = ResponseLength(tokens: t.maxResponseTokens)
                initialPrompt = t.initialPrompt ?? ""
            }
        }
    }
}
