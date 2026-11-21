import SwiftData
import SwiftUI

/// Full-screen "Time for your meds" screen. It can only be closed by confirming or snoozing.
struct TakeMedsView: View {
    let slot: DoseSlot
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @State private var showSnooze = false
    @State private var confirmed = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [slot.dayPart.color, slot.dayPart.color.opacity(0.65), Color(.systemBackground)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image(systemName: slot.dayPart.symbol)
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(.white.opacity(0.22), in: Circle())
                        .symbolEffect(.pulse, options: .repeating, isActive: !confirmed)
                    Text("Time for your").font(.title3.weight(.medium))
                    Text(slot.title).font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("\(slot.timeText) · \(slot.date.formatted(.dateTime.weekday(.wide).month().day()))")
                        .font(.headline)
                        .opacity(0.9)
                }
                .foregroundStyle(.white)
                .padding(.top, 24)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(slot.meds) { med in
                            HStack(spacing: 14) {
                                PillIcon(colorIndex: med.colorIndex, form: med.form, size: 52)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(med.displayName).font(.title3.weight(.semibold))
                                    Text(med.doseText).font(.body).foregroundStyle(.secondary)
                                    if !med.instructions.isEmpty {
                                        Label(med.instructions, systemImage: "info.circle")
                                            .font(.subheadline).foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }

                VStack(spacing: 12) {
                    Button(action: confirm) {
                        Label(slot.meds.count == 1 ? "I took it" : "I took all \(slot.meds.count)", systemImage: "checkmark.circle.fill")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .buttonBorderShape(.roundedRectangle(radius: 20))

                    Button { showSnooze = true } label: {
                        Label("Snooze", systemImage: "zzz")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 18))

                    Text("This reminder stays until you confirm you took your meds.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .interactiveDismissDisabled()
        .sensoryFeedback(.success, trigger: confirmed)
        .sheet(isPresented: $showSnooze) { SnoozeSheet(slot: slot) }
        .onAppear {
            if router.showSnoozeOnOpen { showSnooze = true; router.showSnoozeOnOpen = false }
        }
    }

    private func confirm() {
        confirmed = true
        DoseActions.markTaken(slotKey: slot.key, context: context)
    }
}

/// Snooze choices. The reminder can only move later within the same part of the day, on the same day.
struct SnoozeSheet: View {
    let slot: DoseSlot
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var custom = Date().addingTimeInterval(20 * 60)

    var body: some View {
        let now = Date()
        let options = SnoozeStore.options(for: slot, now: now)
        let earliest = options.base.addingTimeInterval(60)
        NavigationStack {
            List {
                if !options.presets.isEmpty {
                    Section(options.base > now ? "Remind me after \(slot.timeText)" : "Remind me again") {
                        ForEach(options.presets, id: \.self) { minutes in
                            let date = options.base.addingTimeInterval(Double(minutes) * 60)
                            Button { snooze(until: date) } label: {
                                HStack {
                                    Text(minutes == 60 ? "1 hour later" : "\(minutes) minutes later")
                                    Spacer()
                                    Text(date.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary)
                                }
                                .font(.body.weight(.medium))
                            }
                        }
                    }
                }
                if options.latest > earliest {
                    Section {
                        DatePicker("Pick a time", selection: $custom, in: earliest...options.latest, displayedComponents: .hourAndMinute)
                        Button("Snooze until \(custom.formatted(date: .omitted, time: .shortened))") { snooze(until: custom) }
                            .font(.body.weight(.semibold))
                    }
                }
                Section {
                    Label {
                        Text("\(slot.dayPart.title) meds can be snoozed until \(options.latest.formatted(date: .omitted, time: .shortened)) today at the latest. The reminder can't be turned off until you take them.")
                    } icon: {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Snooze reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } } }
            .onAppear { custom = min(max(custom, earliest), options.latest) }
        }
        .presentationDetents([.medium, .large])
    }

    private func snooze(until date: Date) {
        DoseActions.snooze(slotKey: slot.key, until: date, context: context)
        dismiss()
    }
}
