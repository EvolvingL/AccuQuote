import XCTest
@testable import AccuQuoteScan

final class MoneyTests: XCTestCase {

    func testWholePoundsOmitsPence() {
        XCTAssertEqual(Money.gbp(1200), "£1,200")
    }

    func testPenceShownWhenPresent() {
        XCTAssertEqual(Money.gbp(1234.56), "£1234.56")
    }

    func testZero() {
        XCTAssertEqual(Money.gbp(0), "£0")
    }

    func testNaNGuardedToZero() {
        XCTAssertEqual(Money.gbp(.nan), "£0")
    }

    func testInfinityGuardedToZero() {
        XCTAssertEqual(Money.gbp(.infinity), "£0")
        XCTAssertEqual(Money.gbp(-.infinity), "£0")
    }

    func testAstronomicValueClampsToOneBillion() {
        let result = Money.gbp(1e20)
        XCTAssertFalse(result.contains("e"), "must not fall back to scientific notation")
        // Clamped to 1_000_000_000 exactly, which is a whole number -> no pence.
        XCTAssertEqual(result, "£1,000,000,000")
    }

    func testNegativeAstronomicValueClampsToNegativeOneBillion() {
        let result = Money.gbp(-1e20)
        XCTAssertEqual(result, "£-1,000,000,000")
    }

    func testNegativeValue() {
        XCTAssertEqual(Money.gbp(-50), "£-50")
    }
}
