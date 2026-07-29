import XCTest
@testable import AccuQuoteScan

final class ScanStorageManagerTests: XCTestCase {

    func testRecentFolderNotEligibleForCleanup() {
        let now = Date()
        let recentDate = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        XCTAssertFalse(ScanStorageManager.isEligibleForCleanup(modificationDate: recentDate, now: now, retentionDays: 90))
    }

    func testOldFolderEligibleForCleanup() {
        let now = Date()
        let oldDate = Calendar.current.date(byAdding: .day, value: -120, to: now)!
        XCTAssertTrue(ScanStorageManager.isEligibleForCleanup(modificationDate: oldDate, now: now, retentionDays: 90))
    }

    func testBorderlineJustOverRetentionIsEligible() {
        let now = Date()
        let borderlineDate = Calendar.current.date(byAdding: .day, value: -91, to: now)!
        XCTAssertTrue(ScanStorageManager.isEligibleForCleanup(modificationDate: borderlineDate, now: now, retentionDays: 90))
    }

    func testExactlyAtRetentionBoundaryIsNotEligible() {
        // cutoff = now - 90 days; modificationDate == cutoff should NOT be
        // eligible since the predicate is strictly `<` cutoff.
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: now)!
        XCTAssertFalse(ScanStorageManager.isEligibleForCleanup(modificationDate: cutoff, now: now, retentionDays: 90))
    }

    func testFutureModificationDateNeverEligible() {
        // Defensive case: a clock-skewed or future modification date should
        // never be treated as "old."
        let now = Date()
        let future = Calendar.current.date(byAdding: .day, value: 10, to: now)!
        XCTAssertFalse(ScanStorageManager.isEligibleForCleanup(modificationDate: future, now: now, retentionDays: 90))
    }

    func testFormattedSizeProducesHumanReadableString() {
        let str = ScanStorageManager.formattedSize(1_500_000)
        XCTAssertFalse(str.isEmpty)
        // Don't assert exact locale-formatted text (varies by device locale) —
        // just confirm it's not zero-length and doesn't crash.
    }

    func testFormattedSizeZeroBytes() {
        let str = ScanStorageManager.formattedSize(0)
        XCTAssertFalse(str.isEmpty)
    }
}
