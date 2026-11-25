import SwiftData
import XCTest
@testable import PillBox

final class ExpiryTests: XCTestCase {
    func testExpiryThresholdsMatchSpecification() {
        let now = TestSupport.date(2026, 11, 23, hour: 12)

        XCTAssertEqual(ExpiryLevel.level(for: TestSupport.date(2026, 12, 24), now: now), .ok)
        XCTAssertEqual(ExpiryLevel.level(for: TestSupport.date(2026, 12, 23), now: now), .month)
        XCTAssertEqual(ExpiryLevel.level(for: TestSupport.date(2026, 12, 8), now: now), .month)
        XCTAssertEqual(ExpiryLevel.level(for: TestSupport.date(2026, 12, 7), now: now), .twoWeeks)
        XCTAssertEqual(ExpiryLevel.level(for: TestSupport.date(2026, 11, 30), now: now), .week)
        XCTAssertEqual(ExpiryLevel.level(for: TestSupport.date(2026, 11, 23), now: now), .today)
        XCTAssertEqual(ExpiryLevel.level(for: TestSupport.date(2026, 11, 22), now: now), .expired)
    }
}

@MainActor
final class PersistenceTests: XCTestCase {
    func testSeparateBottlesKeepIndependentExpirationDates() throws {
        let container = try TestSupport.inMemoryContainer()
        let context = container.mainContext
        let medication = Medication(name: "Metformin", strength: "500 mg")
        let first = Bottle()
        first.expirationDate = TestSupport.date(2027, 1, 1)
        first.quantity = 30
        first.pillsRemaining = 30
        first.medication = medication
        let second = Bottle()
        second.expirationDate = TestSupport.date(2027, 6, 1)
        second.quantity = 60
        second.pillsRemaining = 60
        second.medication = medication
        context.insert(medication)
        context.insert(first)
        context.insert(second)
        try context.save()

        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<Medication>()).first)
        XCTAssertEqual(saved.bottles.count, 2)
        XCTAssertEqual(saved.activeBottles.map(\.expirationDate), [first.expirationDate, second.expirationDate])
        XCTAssertEqual(saved.pillsRemaining, 90)
    }

    func testMarkTakenIsIdempotentAndUsesEarliestExpiringBottleFirst() throws {
        let container = try TestSupport.inMemoryContainer()
        let context = container.mainContext
        let day = Calendar.current.startOfDay(for: Date())
        let medication = Medication(name: "Metformin", strength: "500 mg")
        medication.customTimes = [8 * 60]
        medication.pillsPerDose = 2
        let first = Bottle()
        first.expirationDate = Calendar.current.date(byAdding: .day, value: 10, to: day)
        first.quantity = 10
        first.pillsRemaining = 10
        first.medication = medication
        let second = Bottle()
        second.expirationDate = Calendar.current.date(byAdding: .day, value: 40, to: day)
        second.quantity = 10
        second.pillsRemaining = 10
        second.medication = medication
        context.insert(medication)
        context.insert(first)
        context.insert(second)
        try context.save()
        let key = Scheduler.key(day: day, minutes: 8 * 60)

        DoseActions.markTaken(slotKey: key, context: context)
        DoseActions.markTaken(slotKey: key, context: context)

        XCTAssertEqual(first.pillsRemaining, 8)
        XCTAssertEqual(second.pillsRemaining, 10)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DoseLog>()).count, 1)
    }
}
