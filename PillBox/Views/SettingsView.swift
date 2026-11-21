import AlarmKit
import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("patientName") private var patientName = ""
    @State private var times: [DayPart: Date] = [:]
    @State private var alarmState = AlarmManager.shared.authorizationState
    @State private var notificationsOn = false
    @State private var testScheduled = false
    @State private var confirmWipe = false

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Your name", text: $patientName)
                }

                Section {
                    ForEach(DayPart.allCases) { part in
                        DatePicker(selection: binding(for: part), displayedComponents: .hourAndMinute) {
                            Label(part.title, systemImage: part.symbol).foregroundStyle(part.color)
                        }
                    }
                } header: {
                    Text("Reminder times")
                } footer: {
                    Text("Meds set to a part of the day remind you at these times. You can also set exact times on any medication.")
                }

                Section {
                    statusRow("Lock Screen alarms", on: alarmState == .authorized, detail: "Full-screen, rings on Silent, shows on Apple Watch")
                    statusRow("Notifications", on: notificationsOn, detail: "Backup reminders until you confirm")
                    if alarmState != .authorized || !notificationsOn {
                        Button("Turn on reminders") {
                            Task {
                                await ReminderService.shared.requestPermissions()
                                await refresh()
                                if alarmState == .denied || !notificationsOn, let url = URL(string: UIApplication.openSettingsURLString) {
                                    await UIApplication.shared.open(url)
                                }
                            }
                        }
                    }
                    Button {
                        Task {
                            await ReminderService.shared.scheduleTest(context: context, inSeconds: 60)
                            testScheduled = true
                        }
                    } label: {
                        Label(testScheduled ? "Test reminder set for 1 minute from now" : "Send a test reminder in 1 minute", systemImage: "alarm")
                    }
                } header: {
                    Text("Reminders")
                }

                Section {
                    Label("Labels are read on this iPhone. Photos and health details are never uploaded.", systemImage: "lock.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Demo") {
                    Button("Load demo medications") {
                        DemoData.seed(into: context)
                        dismiss()
                    }
                    Button("Delete all data", role: .destructive) { confirmWipe = true }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await refresh() }
            .confirmationDialog("Delete all medications and history?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    DemoData.wipe(context)
                    dismiss()
                }
            }
            .onDisappear { Task { await ReminderService.shared.rescheduleAll(context: context) } }
        }
    }

    private func binding(for part: DayPart) -> Binding<Date> {
        Binding(
            get: { times[part] ?? ClockText.date(Date(), minutes: DayPartTimes.minutes(for: part)) },
            set: { newValue in
                times[part] = newValue
                DayPartTimes.set(ClockText.minutes(of: newValue), for: part)
            }
        )
    }

    private func statusRow(_ title: String, on: Bool, detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: on ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(on ? .green : .red)
        }
    }

    private func refresh() async {
        alarmState = AlarmManager.shared.authorizationState
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsOn = settings.authorizationStatus == .authorized
    }
}
