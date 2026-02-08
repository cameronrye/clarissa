import SwiftUI

/// View for creating and editing custom tool chains
struct ToolChainEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var description: String
    @State private var icon: String
    @State private var steps: [ToolChainStep]
    @State private var showIconPicker: Bool = false

    let existingChain: ToolChain?
    let onSave: (ToolChain) -> Void

    init(chain: ToolChain? = nil, onSave: @escaping (ToolChain) -> Void) {
        self.existingChain = chain
        self.onSave = onSave
        _name = State(initialValue: chain?.name ?? "")
        _description = State(initialValue: chain?.description ?? "")
        _icon = State(initialValue: chain?.icon ?? "link")
        _steps = State(initialValue: chain?.steps ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    HStack {
                        Button {
                            showIconPicker = true
                        } label: {
                            Image(systemName: icon)
                                .font(.title2)
                                .foregroundStyle(ClarissaTheme.gradient)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        VStack(spacing: 8) {
                            TextField("Chain Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                            TextField("Description", text: $description)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                        }
                    }
                }

                Section("Steps") {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        StepEditorRow(
                            index: index,
                            step: binding(for: step.id),
                            onDelete: { steps.removeAll { $0.id == step.id } }
                        )
                    }
                    .onMove { from, to in
                        steps.move(fromOffsets: from, toOffset: to)
                    }

                    Button {
                        steps.append(ToolChainStep(
                            toolName: "weather",
                            label: "New step"
                        ))
                    } label: {
                        Label("Add Step", systemImage: "plus.circle")
                    }
                }

                if !steps.isEmpty {
                    Section("Preview") {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            HStack(spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(ClarissaTheme.purple)
                                    .frame(width: 20)
                                VStack(alignment: .leading) {
                                    Text(step.label)
                                        .font(.caption)
                                    Text(ToolDisplayNames.format(step.toolName))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if step.isOptional {
                                    Text("Optional")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(existingChain != nil ? "Edit Chain" : "New Chain")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChain() }
                        .disabled(name.isEmpty || steps.isEmpty)
                }
            }
            .sheet(isPresented: $showIconPicker) {
                ChainIconPicker(selectedIcon: $icon)
            }
        }
    }

    private func binding(for stepId: UUID) -> Binding<ToolChainStep> {
        Binding(
            get: { steps.first(where: { $0.id == stepId }) ?? ToolChainStep(toolName: "", label: "") },
            set: { newValue in
                if let index = steps.firstIndex(where: { $0.id == stepId }) {
                    steps[index] = newValue
                }
            }
        )
    }

    private func saveChain() {
        let chain = ToolChain(
            id: existingChain?.id ?? UUID().uuidString,
            name: name,
            description: description,
            icon: icon,
            steps: steps,
            createdAt: existingChain?.createdAt ?? Date()
        )
        onSave(chain)
        dismiss()
    }
}

// MARK: - Step Editor Row

private struct StepEditorRow: View {
    let index: Int
    @Binding var step: ToolChainStep
    let onDelete: () -> Void

    private let availableTools = [
        "weather", "calendar", "contacts", "reminders",
        "calculator", "web_fetch", "location", "remember", "image_analysis"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Step \(index + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(ClarissaTheme.purple)
                Spacer()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            TextField("Step label", text: $step.label)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)

            Picker("Tool", selection: $step.toolName) {
                ForEach(availableTools, id: \.self) { tool in
                    Text(ToolDisplayNames.format(tool)).tag(tool)
                }
            }

            TextField("Arguments (JSON)", text: $step.argumentTemplate)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())

            Toggle("Optional", isOn: $step.isOptional)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Icon Picker

private struct ChainIconPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIcon: String

    private let icons = [
        "link", "airplane", "newspaper", "person.3",
        "doc.text.magnifyingglass", "house", "car",
        "heart.text.square", "bolt", "star",
        "globe", "map", "clock", "bell",
        "folder", "envelope", "phone", "camera",
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        NavigationStack {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(icons, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                        dismiss()
                    } label: {
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundStyle(icon == selectedIcon ? ClarissaTheme.purple : .secondary)
                            .frame(width: 52, height: 52)
                            .background(
                                icon == selectedIcon
                                    ? ClarissaTheme.purple.opacity(0.15)
                                    : Color.secondary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .navigationTitle("Choose Icon")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
