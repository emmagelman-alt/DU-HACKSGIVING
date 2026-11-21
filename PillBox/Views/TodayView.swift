import SwiftData
import SwiftUI

/// Home (Figma "01 Home"): the chosen day's dose times, each with the medications to take then.
struct TodayView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \Medication.name) private var meds: [Medication]
    @Query private var logs: [DoseLog]
    @State private var day = Date()

    var body: some View {
        if meds.isEmpty {
            OnboardingHomeView()
        } else {
            schedule
        }
    }

    private var schedule: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                HomeHeader(topInset: geo.safeAreaInsets.top)
                DateBar(day: $day).padding(.top, 15)
                ScrollView {
                    let slots = Scheduler.slots(on: day, meds: meds)
                    LazyVStack(spacing: 14) {
                        if slots.isEmpty {
                            Text("No medications to take this day.")
                                .font(.karla(24))
                                .foregroundStyle(Medi.inkSecondary)
                                .padding(.top, 30)
                        }
                        ForEach(slots) { slot in card(slot) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 21)
                    .padding(.bottom, 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
        }
        .background(Medi.screen.ignoresSafeArea())
    }

    private func card(_ slot: DoseSlot) -> some View {
        let status = Scheduler.status(of: slot, logs: logs)
        let isToday = Calendar.current.isDateInToday(slot.day)
        let taken: Bool = if case .taken = status { true } else { false }
        return Button {
            router.openTakeScreen(slotKey: slot.key)
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(slot.timeText).font(.karla(36, .bold))
                    ForEach(slot.meds) { med in
                        Text(med.displayName).font(.karla(24, .semibold))
                    }
                }
                .foregroundStyle(Medi.ink)
                Spacer(minLength: 8)
                if taken {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color(hex: 0x5BA832))
                        .accessibilityLabel("Taken")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        // Only today's due or missed doses open the "Time for your meds" screen.
        .allowsHitTesting(isToday && status != .upcoming && !taken)
    }
}
