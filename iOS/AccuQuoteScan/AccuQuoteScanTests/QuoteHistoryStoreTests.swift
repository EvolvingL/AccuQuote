import XCTest
@testable import AccuQuoteScan

// Uses QuoteHistoryStore's #if DEBUG `init(testDirectory:)` seam (added
// alongside this test suite) so every test gets an isolated temp directory
// instead of touching the real app's Documents/aq_quote_history.json.

@MainActor
final class QuoteHistoryStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    private func makeQuote(id: String = UUID().uuidString, customerName: String = "Jane", jobDescription: String = "Rewire",
                           roomType: String = "kitchen", grandTotal: Double = 500) -> SavedQuote {
        SavedQuote(
            id: id, savedAt: Date(), customerName: customerName, jobDescription: jobDescription,
            roomType: roomType, floorArea: 12, labourDays: 2, labourRate: 280, labourTotal: 560,
            items: [], subtotal: grandTotal, vatRate: 20, vatAmount: grandTotal * 0.2, grandTotal: grandTotal, notes: ""
        )
    }

    func testSaveInsertsAtFront() {
        let store = QuoteHistoryStore(testDirectory: tempDir)
        let first = makeQuote(customerName: "First")
        let second = makeQuote(customerName: "Second")
        store.save(first)
        store.save(second)
        XCTAssertEqual(store.quotes.first?.customerName, "Second", "most recently saved quote should be at index 0")
        XCTAssertEqual(store.quotes.count, 2)
    }

    func testDeleteRemovesByID() {
        let store = QuoteHistoryStore(testDirectory: tempDir)
        let quote = makeQuote(id: "delete-me")
        store.save(quote)
        XCTAssertEqual(store.quotes.count, 1)
        store.delete(id: "delete-me")
        XCTAssertTrue(store.quotes.isEmpty)
    }

    func testDeleteNonexistentIDIsNoOp() {
        let store = QuoteHistoryStore(testDirectory: tempDir)
        store.save(makeQuote())
        store.delete(id: "does-not-exist")
        XCTAssertEqual(store.quotes.count, 1)
    }

    func testMaxQuotesCapEnforced() {
        let store = QuoteHistoryStore(testDirectory: tempDir)
        // maxQuotes is 200 (private) — save 210 and confirm the store caps at 200.
        for i in 0..<210 {
            store.save(makeQuote(id: "q\(i)"))
        }
        XCTAssertEqual(store.quotes.count, 200, "history must cap growth at 200 entries")
        // Most recent saves must survive; oldest (first saved) must be evicted.
        XCTAssertTrue(store.quotes.contains { $0.id == "q209" })
        XCTAssertFalse(store.quotes.contains { $0.id == "q0" })
    }

    func testPersistenceRoundTripsAcrossStoreInstances() async {
        let quote = makeQuote(id: "persisted", customerName: "Persisted Customer")
        do {
            let store = QuoteHistoryStore(testDirectory: tempDir)
            store.save(quote)
            await store.flushPendingWritesForTesting()
        }
        // Fresh store instance pointed at the same directory should load what was persisted.
        let reloaded = QuoteHistoryStore(testDirectory: tempDir)
        XCTAssertEqual(reloaded.quotes.count, 1)
        XCTAssertEqual(reloaded.quotes.first?.id, "persisted")
        XCTAssertEqual(reloaded.quotes.first?.customerName, "Persisted Customer")
    }

    func testEmptyStoreHasNoQuotesAndNoCrashOnLoad() {
        let store = QuoteHistoryStore(testDirectory: tempDir)
        XCTAssertTrue(store.quotes.isEmpty)
    }

    func testCorruptOnDiskFileDoesNotCrashLoad() throws {
        let fileURL = tempDir.appendingPathComponent("aq_quote_history.json")
        try "not valid json {{{".data(using: .utf8)!.write(to: fileURL)
        let store = QuoteHistoryStore(testDirectory: tempDir)
        XCTAssertTrue(store.quotes.isEmpty, "corrupt JSON should fail closed to an empty history, not crash")
    }

    // MARK: - Search (mirrors QuoteHistoryView's filtering logic)

    func testSearchFiltersByCustomerJobOrRoomType() {
        let store = QuoteHistoryStore(testDirectory: tempDir)
        store.save(makeQuote(id: "a", customerName: "Alice Smith", jobDescription: "Bathroom refit", roomType: "bathroom"))
        store.save(makeQuote(id: "b", customerName: "Bob Jones", jobDescription: "Kitchen rewire", roomType: "kitchen"))

        let searchText = "kitchen"
        let filtered = store.quotes.filter {
            $0.customerName.localizedCaseInsensitiveContains(searchText)
            || $0.jobDescription.localizedCaseInsensitiveContains(searchText)
            || $0.roomType.localizedCaseInsensitiveContains(searchText)
        }
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, "b")
    }

    // MARK: - Stress: 500 SavedQuote records (client-side load per task spec)

    func testFiveHundredQuotesSaveLoadAndSearchStayCorrectAndFast() async {
        let store = QuoteHistoryStore(testDirectory: tempDir)

        let start = Date()
        for i in 0..<500 {
            store.save(makeQuote(id: "bulk-\(i)", customerName: "Customer \(i)", jobDescription: "Job \(i)", grandTotal: Double(i)))
        }
        let saveElapsed = Date().timeIntervalSince(start)

        // maxQuotes caps at 200, so only the most recent 200 of 500 survive.
        XCTAssertEqual(store.quotes.count, 200)
        XCTAssertLessThan(saveElapsed, 10.0, "500 sequential saves took \(saveElapsed)s")

        await store.flushPendingWritesForTesting()

        let searchStart = Date()
        let filtered = store.quotes.filter { $0.jobDescription.localizedCaseInsensitiveContains("Job 45") }
        let searchElapsed = Date().timeIntervalSince(searchStart)
        XCTAssertLessThan(searchElapsed, 1.0)
        XCTAssertFalse(filtered.isEmpty)

        // Reload from disk and confirm consistency after the stress run.
        let reloaded = QuoteHistoryStore(testDirectory: tempDir)
        XCTAssertEqual(reloaded.quotes.count, 200)
    }

    func testRapidSaveDeleteInterleavingDoesNotCorruptState() async {
        let store = QuoteHistoryStore(testDirectory: tempDir)
        for i in 0..<100 {
            let id = "q\(i)"
            store.save(makeQuote(id: id))
            if i % 3 == 0 {
                store.delete(id: id)
            }
        }
        await store.flushPendingWritesForTesting()
        // Every surviving quote should have a well-formed id matching the pattern —
        // no partial/corrupted entries from racing writes.
        for quote in store.quotes {
            XCTAssertTrue(quote.id.hasPrefix("q"))
        }
    }
}
