import Foundation
import XCTest
@testable import PillBox

@MainActor
final class ReminderPolicyTests: XCTestCase {
    func testReminderHorizonCoversAtLeastOneWeekWithoutReopeningTheApp() {
        knownIssue(12, "the production horizon currently covers only today and tomorrow")

        XCTAssertGreaterThanOrEqual(ReminderService.scheduledDayOffsets.count, 7)
    }

    func testCommonDosePlanFitsNotificationBudgetIncludingExpiryReserve() {
        knownIssue(14, "dose follow-ups and expiration warnings currently have separate budgets")

        let distinctDoseTimesPerDay = 4
        let expiryReserve = 16
        let doseRequests = distinctDoseTimesPerDay
            * ReminderService.scheduledDayOffsets.count
            * ReminderService.followUps.count

        XCTAssertLessThanOrEqual(doseRequests + expiryReserve, 64)
    }
}

final class ArchitectureContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func contents(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func section(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return String(source[start..<end])
    }

    func testScannerSurfacesPhotoImportOCRAndCameraErrors() throws {
        knownIssue(5, "photo loading, OCR, and live scanner start errors are currently discarded")
        let source = try contents("PillBox/Views/AddMedFlow.swift")

        XCTAssertFalse(source.contains("try? await item.loadTransferable"))
        XCTAssertFalse(source.contains("try? await LabelReader.readLines"))
        XCTAssertFalse(source.contains("try? scanner.startScanning()"))
    }

    func testCriticalNotificationSoundHasRequiredAuthorizationAndEntitlement() throws {
        knownIssue(15, "critical sound is configured without critical-alert authorization or entitlement")
        let reminders = try contents("PillBox/Services/ReminderService.swift")
        let project = try contents("PillBox.xcodeproj/project.pbxproj")

        XCTAssertTrue(reminders.contains(".criticalAlert"), "Authorization must request the critical-alert option")
        XCTAssertTrue(project.contains("com.apple.developer.usernotifications.critical-alerts"))
    }

    func testProjectContainsWatchApplicationTarget() throws {
        knownIssue(2, "the project currently contains only an iPhone application target")
        let project = try contents("PillBox.xcodeproj/project.pbxproj")

        XCTAssertTrue(
            project.contains("com.apple.product-type.application.watchapp") || project.contains("watchOS"),
            "Smartwatch integration requires a watchOS target, not only mirrored AlarmKit presentation"
        )
    }

    func testInfoMedicationDeletionUsesSharedPastMedicationWorkflow() throws {
        knownIssue(31, "MedicationDetailView bypasses HealthProfile.recordStopped")
        let source = try contents("PillBox/Views/MedicationDetailView.swift")

        XCTAssertTrue(source.contains("HealthProfile.recordStopped(med)"))
    }

    func testDoseConfirmationDoesNotClearRemindersAfterAnIgnoredSaveFailure() throws {
        knownIssue(17, "dose confirmation currently ignores fetch/save errors before clearing reminders")
        let appModel = try contents("PillBox/Services/AppModel.swift")
        let action = try section(
            in: appModel,
            from: "static func markTaken",
            to: "static func snooze"
        )

        XCTAssertFalse(action.contains("try?"), "Dose confirmation must propagate persistence errors")
        let save = try XCTUnwrap(action.range(of: "context.save"))
        let cancel = try XCTUnwrap(action.range(of: "cancelReminders"))
        XCTAssertLessThan(save.lowerBound, cancel.lowerBound, "Reminders may be cleared only after a durable save")
    }

    func testEveryScannedLabelImageCanBeRetainedWithItsBottle() throws {
        knownIssue(21, "live scans retain no still and multi-photo scans persist only one image")
        let models = try contents("PillBox/Models/Models.swift")
        let addFlow = try contents("PillBox/Views/AddMedFlow.swift")

        XCTAssertTrue(models.contains("labelImages: [Data]"), "A bottle needs storage for every captured label image")
        XCTAssertTrue(
            addFlow.contains("static func save(_ draft: MedDraft, images:"),
            "The save boundary must receive the complete image collection"
        )
    }

    func testPrescriberNotificationPreferencesControlAlertOffers() throws {
        knownIssue(22, "the prescriber notification toggles are currently never read by alert logic")
        let alerts = try contents("PillBox/Views/AlertsView.swift")
        let reminders = try contents("PillBox/Services/ReminderService.swift")
        let consumers = alerts + reminders

        XCTAssertTrue(consumers.contains("notifyWhenExpiring"))
        XCTAssertTrue(consumers.contains("notifyWhenLow"))
    }

    func testProductionPersistenceDoesNotIgnoreContextSaveErrors() throws {
        knownIssue(28, "multiple production paths still use try? context.save()")
        let enumerator = FileManager.default.enumerator(
            at: repositoryRoot.appendingPathComponent("PillBox"),
            includingPropertiesForKeys: nil
        )
        let swiftFiles = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        let offenders = try swiftFiles.compactMap { file -> String? in
            let source = try String(contentsOf: file, encoding: .utf8)
            return source.contains("try? context.save()") ? file.lastPathComponent : nil
        }

        XCTAssertTrue(offenders.isEmpty, "Ignored save errors in: \(offenders.sorted().joined(separator: ", "))")
    }

    func testDatabaseInitializationHasARecoverableFailurePath() throws {
        knownIssue(29, "SwiftData initialization currently terminates the application with fatalError")
        let appModel = try contents("PillBox/Services/AppModel.swift")

        XCTAssertFalse(appModel.contains("fatalError("))
    }

    func testHealthDataAndLockScreenContentHavePrivacyControls() throws {
        knownIssue(30, "health profile fields use UserDefaults and notification bodies always reveal medication names")
        let info = try contents("PillBox/Views/InfoView.swift")
        let settings = try contents("PillBox/Views/SettingsView.swift")
        let reminders = try contents("PillBox/Services/ReminderService.swift")

        XCTAssertFalse(info.contains("UserDefaults.standard"), "Sensitive profile fields need an explicitly protected store")
        let privacyKeyCandidates = ["hideMedicationNames", "showMedicationNames", "redactMedicationNames"]
        XCTAssertTrue(
            privacyKeyCandidates.contains { settings.contains($0) && reminders.contains($0) },
            "A Settings privacy preference must control medication names in notification bodies"
        )
    }

    func testMedicationSavingHasOneProductionImplementation() throws {
        knownIssue(32, "MedicationFormView.save and MedSaver.save duplicate bottle persistence")
        let legacyForm = try contents("PillBox/Views/MedicationFormView.swift")
        let addFlow = try contents("PillBox/Views/AddMedFlow.swift")
        let saveImplementations = [legacyForm, addFlow].filter { $0.contains("context.insert(bottle)") }

        XCTAssertLessThanOrEqual(saveImplementations.count, 1)
    }

    func testBrandNameIsConsistentInBundleAndCameraPermissionCopy() throws {
        knownIssue(33, "the bundle and permissions still use PillBox while the UI uses MEDI")
        let project = try contents("PillBox.xcodeproj/project.pbxproj")

        XCTAssertTrue(project.contains("INFOPLIST_KEY_CFBundleDisplayName = MEDI;"))
        XCTAssertFalse(project.contains("PillBox uses the camera"))
    }

    func testProjectIncludesAnAutomatedUnitTestTarget() throws {
        let project = try contents("PillBox.xcodeproj/project.pbxproj")

        XCTAssertTrue(project.contains("com.apple.product-type.bundle.unit-test"))
        XCTAssertTrue(project.contains("PillBoxTests.xctest"))
    }
}
