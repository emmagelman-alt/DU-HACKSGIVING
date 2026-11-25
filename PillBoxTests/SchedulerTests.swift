import XCTest
@testable import PillBox

final class SchedulerTests: XCTestCase {
    func testSlotsGroupMedicationsDueAtTheSameTime() {
        let first = Medication(name: "Metformin", strength: "500 mg")
        first.customTimes = [8 * 60]
        let second = Medication(name: "Lisinopril", strength: "10 mg")
        second.customTimes = [8 * 60]

        let slots = Scheduler.slots(on: TestSupport.date(2026, 11, 23), meds: [first, second])

        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots[0].minutes, 8 * 60)
        XCTAssertEqual(slots[0].meds.map(\.name), ["Lisinopril", "Metformin"])
    }

    func testWeekdayFilterOnlySchedulesSelectedDays() {
        let medication = Medication(name: "Methotrexate", strength: "10 mg")
        medication.customTimes = [8 * 60]
        medication.weekdays = [2] // Monday

        XCTAssertEqual(Scheduler.slots(on: TestSupport.date(2026, 11, 23), meds: [medication]).count, 1)
        XCTAssertTrue(Scheduler.slots(on: TestSupport.date(2026, 11, 24), meds: [medication]).isEmpty)
    }

    func testCustomTimesAreSortedAndDeduplicated() {
        let medication = Medication(name: "Example", strength: "10 mg")
        medication.customTimes = [18 * 60, 8 * 60, 8 * 60]

        XCTAssertEqual(Scheduler.times(for: medication), [8 * 60, 18 * 60])
    }

    func testEveryHoursScheduleMaintainsRequestedGap() {
        let times = Scheduler.intervalTimes(hours: 8)

        XCTAssertEqual(times.count, 3)
        XCTAssertEqual(zip(times, times.dropFirst()).map { $1 - $0 }, [8 * 60, 8 * 60])
        XCTAssertLessThanOrEqual(try XCTUnwrap(times.last), 23 * 60 + 30)
    }

    func testMinimumGapEnforcementDoesNotSilentlyDropDoses() {
        knownIssue(26, "enforceGap currently omits doses that would be pushed past 23:59")

        let requested = [8 * 60, 13 * 60, 18 * 60, 21 * 60 + 30]
        let adjusted = Scheduler.enforceGap(requested, hours: 8)

        XCTAssertEqual(adjusted.count, requested.count, "An unsatisfiable schedule must be reported, not truncated")
    }

    func testSnoozeBeforePeriodEndRemainsWithinThePeriod() {
        let day = TestSupport.date(2026, 11, 23)
        let slot = DoseSlot(day: day, minutes: 8 * 60, meds: [])
        let now = TestSupport.date(2026, 11, 23, hour: 9)
        let options = SnoozeStore.options(for: slot, now: now)
        let endOfMorning = ClockText.date(day, minutes: DayPart.morning.endMinutes)

        XCTAssertLessThanOrEqual(options.latest, endOfMorning)
        XCTAssertTrue(options.presets.allSatisfy { options.base.addingTimeInterval(Double($0) * 60) <= endOfMorning })
    }

    func testOverdueSnoozeDoesNotCrossIntoAnotherDayPeriod() {
        knownIssue(24, "an overdue morning dose currently gets a 15-minute afternoon snooze")

        let day = TestSupport.date(2026, 11, 23)
        let slot = DoseSlot(day: day, minutes: 8 * 60, meds: [])
        let now = TestSupport.date(2026, 11, 23, hour: 12, minute: 30)
        let options = SnoozeStore.options(for: slot, now: now)
        let endOfMorning = ClockText.date(day, minutes: DayPart.morning.endMinutes)

        XCTAssertLessThanOrEqual(options.latest, endOfMorning)
    }

    func testClockDatePreservesRequestedMorningAcrossDSTBoundary() {
        XCTExpectFailure("Additional scheduler regression: adding elapsed minutes from midnight shifts wall-clock doses after the spring DST transition")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let dstStart = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let result = ClockText.date(dstStart, minutes: 8 * 60, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 8)
        XCTAssertEqual(components.hour, 8)
        XCTAssertEqual(components.minute, 0)
    }
}
