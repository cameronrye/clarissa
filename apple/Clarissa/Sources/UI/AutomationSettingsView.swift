import SwiftUI

/// Settings view for managing tool chains, scheduled check-ins, and automation triggers.
struct AutomationSettingsView: View {
    @StateObject private var automationManager = AutomationManager.shared
    @StateObject private var calendarMonitor = CalendarMonitor.shared

    @State private var chains: [ToolChain] = []
    @State private var checkIns: [ScheduledCheckIn] = []
    @State private var showChainEditor: Bool = false
    @State private var showCheckInEditor: Bool = false
    @State private var editingChain: ToolChain?
    @State private var notificationAuthorized: Bool = false
    @AppStorage(MemoryReminderScanner.settingsKey) private var memoryRemindersEnabled: Bool = false

    var body: some View {
        Form {
            // MARK: - Tool Chains
            Section {
                ForEach(chains) { chain in
                    HStack(spacing: 12) {
                        Image(systemName: chain.icon)
                            .font(.title3)
                            .foregroundStyle(ClarissaTheme.gradient)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(chain.name)
                                .font(.subheadline.bold())
                            Text("\(chain.steps.count) steps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if chain.isBuiltIn {
                            Text("Built-in")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if !chain.isBuiltIn {
                            Button(role: .destructive) {
                                deleteChain(chain)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                editingChain = chain
                                showChainEditor = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }

                Button {
                    editingChain = nil
                    showChainEditor = true
                } label: {
                    Label("Create Custom Chain", systemImage: "plus.circle")
                }
            } header: {
                Text("Tool Chains")
            } footer: {
                Text("Multi-step workflows that chain tool outputs together. Built-in chains can't be deleted.")
            }

            // MARK: - Scheduled Check-Ins
            #if os(iOS)
            Section {
                ForEach(checkIns) { checkIn in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(checkIn.name)
                                .font(.subheadline)
                            Text(formatSchedule(checkIn.schedule))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: binding(for: checkIn))
                            .labelsHidden()
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteCheckIn(checkIn)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Button {
                    showCheckInEditor = true
                } label: {
                    Label("Add Scheduled Check-In", systemImage: "plus.circle")
                }
            } header: {
                Text("Scheduled Check-Ins")
            } footer: {
                Text("Run a chain or template at scheduled times and receive the results as a notification.")
            }
            #endif

            // MARK: - Calendar Alerting
            Section {
                Toggle("Meeting Prep Alerts", isOn: $calendarMonitor.isEnabled)

                if calendarMonitor.isEnabled {
                    Stepper("Alert \(calendarMonitor.alertMinutesBefore) min before",
                            value: $calendarMonitor.alertMinutesBefore,
                            in: 10...60,
                            step: 5)

                    Stepper("Min \(calendarMonitor.minAttendeesForAlert) attendees",
                            value: $calendarMonitor.minAttendeesForAlert,
                            in: 2...10)
                }
            } header: {
                Text("Calendar Alerts")
            } footer: {
                Text("Get notified before meetings with multiple attendees you haven't met.")
            }

            // MARK: - Memory Reminders
            Section {
                Toggle("Memory Reminders", isOn: $memoryRemindersEnabled)
            } header: {
                Text("Memory Reminders")
            } footer: {
                Text("Surface time-sensitive memories as notifications (e.g., \"Follow up with Alex this week\").")
            }

            // MARK: - Notification Status
            Section {
                HStack {
                    Text("Notifications")
                    Spacer()
                    if notificationAuthorized {
                        Label("Authorized", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Button("Enable") {
                            Task {
                                notificationAuthorized = await NotificationManager.shared.requestAuthorization()
                            }
                        }
                        .font(.caption)
                    }
                }
            } footer: {
                Text("Notifications are required for scheduled check-ins, calendar alerts, and memory reminders.")
            }
        }
        .task {
            chains = await ToolChain.allChains()
            checkIns = await ScheduledCheckInStore.shared.load()
            await NotificationManager.shared.checkAuthorization()
            notificationAuthorized = NotificationManager.shared.isAuthorized
        }
        .sheet(isPresented: $showChainEditor) {
            ToolChainEditorView(chain: editingChain) { chain in
                Task {
                    if editingChain != nil {
                        try? await ToolChainStore.shared.update(chain)
                    } else {
                        try? await ToolChainStore.shared.add(chain)
                    }
                    chains = await ToolChain.allChains()
                }
            }
        }
        .sheet(isPresented: $showCheckInEditor) {
            CheckInEditorView { checkIn in
                Task {
                    try? await ScheduledCheckInStore.shared.add(checkIn)
                    checkIns = await ScheduledCheckInStore.shared.load()
                    #if os(iOS)
                    await CheckInScheduler.shared.scheduleNextRun()
                    #endif
                }
            }
        }
    }

    // MARK: - Helpers

    private func binding(for checkIn: ScheduledCheckIn) -> Binding<Bool> {
        Binding(
            get: { checkIn.isEnabled },
            set: { newValue in
                Task {
                    var updated = checkIn
                    updated.isEnabled = newValue
                    try? await ScheduledCheckInStore.shared.update(updated)
                    checkIns = await ScheduledCheckInStore.shared.load()
                    #if os(iOS)
                    await CheckInScheduler.shared.scheduleNextRun()
                    #endif
                }
            }
        )
    }

    private func deleteChain(_ chain: ToolChain) {
        Task {
            try? await ToolChainStore.shared.delete(id: chain.id)
            chains = await ToolChain.allChains()
        }
    }

    private func deleteCheckIn(_ checkIn: ScheduledCheckIn) {
        Task {
            try? await ScheduledCheckInStore.shared.delete(id: checkIn.id)
            checkIns = await ScheduledCheckInStore.shared.load()
            NotificationManager.shared.cancelCheckInNotifications(checkInId: checkIn.id)
        }
    }

    private func formatSchedule(_ schedule: ScheduledCheckIn.Schedule) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        var components = DateComponents()
        components.hour = schedule.hour
        components.minute = schedule.minute
        let timeString = Calendar.current.date(from: components).map { timeFormatter.string(from: $0) } ?? "\(schedule.hour):\(String(format: "%02d", schedule.minute))"

        let days = schedule.days.sorted(by: { $0.rawValue < $1.rawValue }).map(\.shortName).joined(separator: ", ")
        return "\(timeString) on \(days)"
    }
}

// MARK: - Check-In Editor

struct CheckInEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var hour: Int = 7
    @State private var minute: Int = 30
    @State private var selectedDays: Set<ScheduledCheckIn.Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    @State private var triggerType: TriggerChoice = .template
    @State private var selectedTemplateId: String = "morning_briefing"
    @State private var selectedChainId: String = "daily_digest"

    let onSave: (ScheduledCheckIn) -> Void

    enum TriggerChoice: String, CaseIterable {
        case template = "Template"
        case chain = "Tool Chain"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Check-in name", text: $name)
                }

                Section("Schedule") {
                    HStack {
                        Picker("Hour", selection: $hour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(formatHour(h)).tag(h)
                            }
                        }
                        #if os(iOS)
                        .pickerStyle(.wheel)
                        #endif
                        .frame(width: 100)

                        Text(":")
                            .font(.title2)

                        Picker("Minute", selection: $minute) {
                            ForEach(stride(from: 0, to: 60, by: 5).map { $0 }, id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        #if os(iOS)
                        .pickerStyle(.wheel)
                        #endif
                        .frame(width: 80)
                    }

                    // Day selector
                    HStack(spacing: 4) {
                        ForEach(ScheduledCheckIn.Weekday.allCases, id: \.self) { day in
                            Button {
                                if selectedDays.contains(day) {
                                    selectedDays.remove(day)
                                } else {
                                    selectedDays.insert(day)
                                }
                            } label: {
                                Text(String(day.shortName.prefix(1)))
                                    .font(.caption.bold())
                                    .frame(width: 32, height: 32)
                                    .background(
                                        selectedDays.contains(day)
                                            ? ClarissaTheme.purple.opacity(0.2)
                                            : Color.secondary.opacity(0.1),
                                        in: Circle()
                                    )
                                    .foregroundStyle(selectedDays.contains(day) ? ClarissaTheme.purple : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Action") {
                    Picker("Type", selection: $triggerType) {
                        ForEach(TriggerChoice.allCases, id: \.self) { choice in
                            Text(choice.rawValue).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)

                    if triggerType == .template {
                        Picker("Template", selection: $selectedTemplateId) {
                            ForEach(ConversationTemplate.bundled) { template in
                                Text(template.name).tag(template.id)
                            }
                        }
                    } else {
                        Picker("Chain", selection: $selectedChainId) {
                            ForEach(ToolChain.builtIn) { chain in
                                Text(chain.name).tag(chain.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Check-In")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty || selectedDays.isEmpty)
                }
            }
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour) \(period)"
    }

    private func save() {
        let trigger: ScheduledCheckIn.TriggerType = triggerType == .template
            ? .template(templateId: selectedTemplateId)
            : .toolChain(chainId: selectedChainId)

        let checkIn = ScheduledCheckIn(
            id: UUID().uuidString,
            name: name,
            isEnabled: true,
            triggerType: trigger,
            schedule: .init(hour: hour, minute: minute, days: selectedDays)
        )
        onSave(checkIn)
        dismiss()
    }
}
