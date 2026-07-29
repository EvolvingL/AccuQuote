import XCTest
@testable import AccuQuoteScan

// MARK: - MockURLProtocol
//
// Minimal URLProtocol stub registered on a test-only URLSessionConfiguration,
// injected into QuoteGenerationService via its `urlSession:` initializer
// parameter (added alongside this test suite). Lets these tests exercise the
// service's HTTP status-code handling paths without a real network call.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeMockedSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

@MainActor
final class QuoteGenerationServiceTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
    }

    // MARK: - Pure JSON extraction (internal, exposed for direct testing)

    func testExtractJSONObjectWithBalancedBraces() {
        let service = QuoteGenerationService()
        let text = "prefix noise { \"a\": 1, \"b\": { \"c\": 2 } } trailing }garbage"
        let obj = service.extractJSONObject(from: text)
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?["a"] as? Int, 1)
    }

    func testExtractJSONObjectIgnoresBracesInsideStrings() {
        let service = QuoteGenerationService()
        let text = "{ \"description\": \"a { b } c\", \"qty\": 1 }"
        let obj = service.extractJSONObject(from: text)
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?["description"] as? String, "a { b } c")
    }

    func testExtractJSONObjectReturnsNilWhenNoObjectPresent() {
        let service = QuoteGenerationService()
        XCTAssertNil(service.extractJSONObject(from: "no json here"))
    }

    func testExtractJSONObjectHandlesEscapedQuotesInString() {
        let service = QuoteGenerationService()
        let text = "{ \"note\": \"a \\\"quoted\\\" word\" }"
        let obj = service.extractJSONObject(from: text)
        XCTAssertEqual(obj?["note"] as? String, "a \"quoted\" word")
    }

    func testExtractJSONArrayWithTrailingGarbage() {
        let service = QuoteGenerationService()
        let text = "here's your list: [{\"sectionKey\":\"plumbing\",\"sectionLabel\":\"Plumbing\",\"tradeScope\":\"pipes\"}] ] extra"
        let arr = service.extractJSONArray(from: text)
        XCTAssertEqual(arr?.count, 1)
        XCTAssertEqual(arr?.first?["sectionKey"] as? String, "plumbing")
    }

    func testExtractJSONArrayReturnsNilForNoArray() {
        let service = QuoteGenerationService()
        XCTAssertNil(service.extractJSONArray(from: "nothing to see"))
    }

    // MARK: - parseSection sanitisation (numeric clamping against a hostile AI response)

    func testParseSectionSanitisesNonFiniteAndOutOfRangeValues() {
        let service = QuoteGenerationService()
        let descriptor = QuoteSectionDescriptor(sectionKey: "electrical", sectionLabel: "Electrical", tradeScope: "wiring")
        let json = """
        {"labourDays": "NaN-ish-but-actually-missing", "labourRate": 999999999, "notes": "test",
         "items": [{"description": "Cable", "qty": -5, "unit": "m", "unitPrice": 1e20, "sku": "C1", "supplier": "Screwfix"}]}
        """
        let section = service.parseSection(descriptor: descriptor, text: json)
        XCTAssertNotNil(section)
        guard let section else { return }
        XCTAssertEqual(section.labourDays, 0, "missing/non-numeric labourDays should default to 0")
        XCTAssertLessThanOrEqual(section.labourRate, 100_000, "labourRate must clamp to the sane max")
        XCTAssertEqual(section.items.count, 1)
        XCTAssertGreaterThanOrEqual(section.items[0].qty, 0, "negative qty must clamp to >= 0")
        XCTAssertLessThanOrEqual(section.items[0].unitPrice, 1_000_000, "runaway unitPrice must clamp")
    }

    func testParseSectionDefaultsMissingFieldsSafely() {
        let service = QuoteGenerationService()
        let descriptor = QuoteSectionDescriptor(sectionKey: "plumbing", sectionLabel: "Plumbing", tradeScope: "pipes")
        let section = service.parseSection(descriptor: descriptor, text: "{}")
        XCTAssertNotNil(section)
        XCTAssertEqual(section?.labourDays, 0)
        XCTAssertEqual(section?.labourRate, 280)
        XCTAssertEqual(section?.items.count, 0)
    }

    func testParseSectionReturnsNilForUnparsableText() {
        let service = QuoteGenerationService()
        let descriptor = QuoteSectionDescriptor(sectionKey: "x", sectionLabel: "X", tradeScope: "x")
        XCTAssertNil(service.parseSection(descriptor: descriptor, text: "not json at all"))
    }

    func testParseSectionCarriesVATRateFromResponse() {
        let service = QuoteGenerationService()
        let descriptor = QuoteSectionDescriptor(sectionKey: "x", sectionLabel: "X", tradeScope: "x")
        let section = service.parseSection(descriptor: descriptor, text: "{\"vatRate\": 5}")
        XCTAssertEqual(section?.vatRate, 5)
    }

    // MARK: - Computed totals

    func testComputedTotalsAggregateAcrossSections() {
        let service = QuoteGenerationService()
        service.sections = [
            QuoteSection(id: "a", label: "A", labourDays: 1, labourRate: 200,
                         items: [QuoteLineItem(description: "Item", qty: 2, unit: "each", unitPrice: 10, sku: "", supplier: "")],
                         notes: "note-a", status: .complete),
            QuoteSection(id: "b", label: "B", labourDays: 2, labourRate: 300, items: [], notes: "", status: .complete),
        ]
        service.vatRate = 20
        XCTAssertEqual(service.labourTotal, 1 * 200 + 2 * 300, accuracy: 0.001)
        XCTAssertEqual(service.materialsTotal, 20, accuracy: 0.001)
        XCTAssertEqual(service.subtotal, service.labourTotal + service.materialsTotal, accuracy: 0.001)
        XCTAssertEqual(service.vatAmount, service.subtotal * 0.2, accuracy: 0.001)
        XCTAssertEqual(service.notes, "note-a")
    }

    func testCompletedCountOnlyCountsCompleteStatus() {
        let service = QuoteGenerationService()
        service.sections = [
            QuoteSection(id: "a", label: "A", labourDays: 0, labourRate: 280, items: [], notes: "", status: .complete),
            QuoteSection(id: "b", label: "B", labourDays: 0, labourRate: 280, items: [], notes: "", status: .loading),
            QuoteSection(id: "c", label: "C", labourDays: 0, labourRate: 280, items: [], notes: "", status: .failed("err")),
        ]
        XCTAssertEqual(service.completedCount, 1)
    }

    // MARK: - Re-entrancy guard (R5)

    func testGenerateIgnoresReentrantCallWhileDiscovering() async {
        let service = QuoteGenerationService(urlSession: makeMockedSession())
        service.state = .discoveringSections
        // Since state is already .discoveringSections, generate() should return
        // immediately without resetting `sections` or touching the network.
        service.sections = [QuoteSection(id: "existing", label: "Existing", labourDays: 0, labourRate: 280, items: [], notes: "", status: .complete)]
        await service.generate(
            jobDescription: "test", customerName: "test",
            roomDimensions: ScanCoordinator.stubbedResult(method: .manual),
            claudeContext: "", preferredSupplier: "", usualItems: ""
        )
        XCTAssertEqual(service.sections.count, 1, "re-entrant call must not clobber the in-progress sections array")
    }

    // MARK: - reset()

    func testResetClearsStateAndSections() {
        let service = QuoteGenerationService()
        service.sections = [QuoteSection(id: "a", label: "A", labourDays: 1, labourRate: 280, items: [], notes: "", status: .complete)]
        service.state = .complete
        service.vatRate = 5
        service.reset()
        XCTAssertTrue(service.sections.isEmpty)
        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.vatRate, 20.0)
    }

    // MARK: - Network-mocked: discoverSections HTTP status handling
    //
    // These exercise `generate()`'s failure path when the mocked backend
    // returns a non-200 status. Since AuthManager.shared has no stored
    // session in a test process, `attachAuthToken()`/`currentIdToken()`
    // returns nil and generate() fails at the auth step before ever reaching
    // the network — so these confirm the *unauthenticated* failure path,
    // which is itself the realistic behaviour for a signed-out user hitting
    // "Generate Quote." Full 200-OK success-path coverage would additionally
    // require faking AuthManager's Firebase session, which is out of scope
    // for this pass (see report).

    func testGenerateFailsGracefullyWhenUnauthenticated() async {
        let service = QuoteGenerationService(urlSession: makeMockedSession())
        MockURLProtocol.requestHandler = { request in
            XCTFail("network should never be reached before auth in a signed-out test process")
            throw URLError(.badServerResponse)
        }
        await service.generate(
            jobDescription: "Rewire kitchen", customerName: "Jane",
            roomDimensions: ScanCoordinator.stubbedResult(method: .manual),
            claudeContext: "", preferredSupplier: "", usualItems: ""
        )
        guard case .failed = service.state else {
            return XCTFail("expected .failed state when unauthenticated, got \(service.state)")
        }
    }
}
