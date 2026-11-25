import Foundation
import SwiftData
import XCTest
@testable import PillBox

enum TestSupport {
    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @MainActor
    static func inMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Medication.self, Bottle.self, Prescriber.self, DoseLog.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }
}

extension XCTestCase {
    /// Documents a review finding as an executable regression test while keeping the suite usable
    /// before the production fix lands. XCTest reports an unexpected pass once the defect is fixed.
    func knownIssue(_ reviewFinding: Int, _ explanation: String) {
        XCTExpectFailure("Review finding \(reviewFinding): \(explanation)")
    }
}
