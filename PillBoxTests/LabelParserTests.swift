import XCTest
@testable import PillBox

final class LabelParserTests: XCTestCase {
    func testSampleLabelParsesCoreMedicationFields() throws {
        let sample = try XCTUnwrap(SampleLabel.all.first { $0.asset == "label-lisinopril" })
        let parsed = LabelParser.parse(lines: sample.fullText, today: TestSupport.date(2026, 11, 23))

        XCTAssertEqual(parsed.name, "Lisinopril")
        XCTAssertEqual(parsed.strength, "10 mg")
        XCTAssertEqual(parsed.pillsPerDose, 1)
        XCTAssertEqual(parsed.form, "tablet")
        XCTAssertEqual(parsed.timesPerDay, 1)
        XCTAssertEqual(parsed.dayParts, [.morning])
        XCTAssertEqual(parsed.quantity, 30)
        XCTAssertEqual(parsed.refills, 2)
        XCTAssertEqual(parsed.prescriberName, "Dr. Sarah Chen")
        XCTAssertEqual(parsed.patientName, "Jordan Rivera")
        XCTAssertEqual(parsed.pillShape, "round")
        XCTAssertTrue(parsed.pillScored)
    }

    func testEveryHoursDirectionsSetIntervalAndMinimumGap() {
        let parsed = LabelParser.parse(lines: [
            "AMOXICILLIN 500 MG CAPSULE",
            "TAKE 1 CAPSULE BY MOUTH EVERY 8 HOURS",
            "EXP: 12/03/2027"
        ], today: TestSupport.date(2026, 11, 23))

        XCTAssertEqual(parsed.frequency, .everyHours)
        XCTAssertEqual(parsed.intervalHours, 8)
        XCTAssertEqual(parsed.minHoursApart, 8)
        XCTAssertEqual(parsed.timesPerDay, 3)
    }

    func testWeeklyDirectionsWithExplicitWeekdayPreserveThatWeekday() {
        let parsed = LabelParser.parse(lines: [
            "METHOTREXATE 10 MG TABLET",
            "TAKE ONE TABLET BY MOUTH ONCE WEEKLY ON MONDAY",
            "EXP: 12/03/2027"
        ], today: TestSupport.date(2026, 11, 23))

        XCTAssertEqual(parsed.weekdays, [2], "Calendar weekday 2 is Monday")
    }

    func testWeeklyDirectionsWithoutWeekdayDoNotInventTheScanDay() {
        knownIssue(7, "the parser currently substitutes the device's current weekday")

        let parsed = LabelParser.parse(lines: [
            "METHOTREXATE 10 MG TABLET",
            "TAKE ONE TABLET BY MOUTH ONCE WEEKLY",
            "EXP: 12/03/2027"
        ], today: TestSupport.date(2026, 11, 23))

        XCTAssertTrue(parsed.weekdays.isEmpty, "An unspecified weekday must remain unresolved for user confirmation")
    }

    func testInvalidCalendarExpirationDateIsRejected() {
        knownIssue(8, "Foundation currently normalizes invalid dates such as February 31")

        let parsed = LabelParser.parse(lines: [
            "LISINOPRIL 10 MG TABLET",
            "TAKE ONE TABLET BY MOUTH DAILY",
            "EXP: 02/31/2027"
        ], today: TestSupport.date(2026, 11, 23))

        XCTAssertNil(parsed.expiration)
        XCTAssertFalse(parsed.found.contains("expiration"))
    }

    func testMonthOnlyExpirationUsesLastDayOfMonth() throws {
        let parsed = LabelParser.parse(lines: [
            "METFORMIN 500 MG TABLET",
            "TAKE ONE TABLET BY MOUTH DAILY",
            "EXP: 02/2028"
        ], today: TestSupport.date(2026, 11, 23))
        let date = try XCTUnwrap(parsed.expiration)
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)

        XCTAssertEqual(components.year, 2028)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 29)
    }
}
