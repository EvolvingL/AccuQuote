import Foundation

// MARK: - Section models

struct QuoteSectionDescriptor {
    let sectionKey: String
    let sectionLabel: String
    let tradeScope: String
}

struct QuoteSection: Identifiable {
    let id: String          // == sectionKey
    let label: String
    var labourDays: Double
    var labourRate: Double
    var items: [QuoteLineItem]
    var notes: String
    var status: SectionStatus

    var labourTotal: Double { labourDays * labourRate }
    var materialsTotal: Double { items.reduce(0) { $0 + $1.total } }
    var sectionSubtotal: Double { labourTotal + materialsTotal }
}

enum SectionStatus: Equatable {
    case pending
    case loading
    case complete
    case failed(String)
}

// MARK: - Generation state

enum GenerationState: Equatable {
    case idle
    case discoveringSections
    case generatingSections(total: Int, completed: Int)
    case complete
    case failed(String)
}

// MARK: - Service

@MainActor
final class QuoteGenerationService: ObservableObject {

    @Published var sections: [QuoteSection] = []
    @Published var state: GenerationState = .idle
    @Published var vatRate: Double = 20.0

    // Computed from completed sections
    var labourTotal: Double { sections.reduce(0) { $0 + $1.labourTotal } }
    var materialsTotal: Double { sections.reduce(0) { $0 + $1.materialsTotal } }
    var subtotal: Double { labourTotal + materialsTotal }
    var vatAmount: Double { subtotal * (vatRate / 100) }
    var grandTotal: Double { subtotal + vatAmount }
    var allItems: [QuoteLineItem] { sections.flatMap { $0.items } }
    var notes: String { sections.compactMap { $0.notes.isEmpty ? nil : $0.notes }.joined(separator: "\n") }
    var representativeLabourRate: Double { sections.first(where: { $0.labourDays > 0 })?.labourRate ?? 280 }
    var totalLabourDays: Double { sections.reduce(0) { $0 + $1.labourDays } }
    var completedCount: Int { sections.filter { if case .complete = $0.status { return true }; return false }.count }

    func generate(
        jobDescription: String,
        customerName: String,
        roomDimensions: RoomDimensions,
        claudeContext: String,
        preferredSupplier: String,
        usualItems: String
    ) async {
        sections = []
        state = .discoveringSections
        vatRate = 20.0

        // ── Phase 1: Discover sections via proxy → Haiku ─────────────────────
        let descriptors: [QuoteSectionDescriptor]
        do {
            descriptors = try await discoverSections(
                jobDescription: jobDescription,
                claudeContext: claudeContext
            )
        } catch {
            state = .failed("Could not plan quote sections: \(error.localizedDescription)")
            return
        }

        guard !descriptors.isEmpty else {
            state = .failed("No trade sections identified for this job.")
            return
        }

        sections = descriptors.map {
            QuoteSection(id: $0.sectionKey, label: $0.sectionLabel,
                         labourDays: 0, labourRate: 280, items: [], notes: "",
                         status: .pending)
        }
        state = .generatingSections(total: descriptors.count, completed: 0)

        // ── Phase 2: Fan out one Sonnet call per section in parallel ──────────
        await withTaskGroup(of: (Int, QuoteSection).self) { group in
            for (idx, descriptor) in descriptors.enumerated() {
                sections[idx].status = .loading
                group.addTask {
                    let section = await self.generateSection(
                        descriptor: descriptor,
                        jobDescription: jobDescription,
                        roomDimensions: roomDimensions,
                        claudeContext: claudeContext,
                        preferredSupplier: preferredSupplier,
                        usualItems: usualItems
                    )
                    return (idx, section)
                }
            }

            for await (idx, section) in group {
                sections[idx] = section
                let done = completedCount
                state = .generatingSections(total: descriptors.count, completed: done)
            }
        }

        state = .complete
        persistToHistory(
            jobDescription: jobDescription,
            customerName: customerName,
            roomDimensions: roomDimensions
        )
    }

    private func persistToHistory(
        jobDescription: String, customerName: String, roomDimensions: RoomDimensions
    ) {
        let savedSections = sections.map { sec in
            SavedQuoteSection(
                id: sec.id, label: sec.label,
                labourDays: sec.labourDays, labourRate: sec.labourRate,
                notes: sec.notes,
                items: sec.items.map {
                    SavedQuoteItem(
                        id: $0.id.uuidString, description: $0.description,
                        qty: $0.qty, unit: $0.unit, unitPrice: $0.unitPrice,
                        sku: $0.sku, supplier: $0.supplier, sectionKey: $0.sectionKey
                    )
                }
            )
        }
        let allItems = savedSections.flatMap { $0.items }
        let saved = SavedQuote(
            id: UUID().uuidString, savedAt: Date(),
            customerName: customerName, jobDescription: jobDescription,
            roomType: roomDimensions.roomType, floorArea: roomDimensions.floorArea,
            labourDays: totalLabourDays, labourRate: representativeLabourRate,
            labourTotal: labourTotal, items: allItems,
            subtotal: subtotal, vatRate: vatRate, vatAmount: vatAmount, grandTotal: grandTotal,
            notes: notes, sections: savedSections
        )
        QuoteHistoryStore.shared.save(saved)
    }

    func reset() {
        sections = []
        state = .idle
        vatRate = 20.0
    }

    // MARK: - Phase 1: Section discovery via /api/quote/discover

    private func discoverSections(
        jobDescription: String,
        claudeContext: String
    ) async throws -> [QuoteSectionDescriptor] {

        guard let url = URL(string: "\(AQBackend.baseURL)/api/quote/discover") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await request.attachAuthToken()
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "jobDescription": jobDescription,
            "claudeContext": claudeContext,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 403 {
            throw NSError(domain: "QuoteGen", code: 403,
                          userInfo: [NSLocalizedDescriptionKey: "subscription_required"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw NSError(domain: "QuoteGen", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected server response"])
        }

        guard let arr = extractJSONArray(from: text) else {
            throw NSError(domain: "QuoteGen", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Could not parse section list"])
        }

        return arr.compactMap { dict -> QuoteSectionDescriptor? in
            guard let key   = dict["sectionKey"]   as? String,
                  let label = dict["sectionLabel"]  as? String,
                  let scope = dict["tradeScope"]    as? String else { return nil }
            return QuoteSectionDescriptor(sectionKey: key, sectionLabel: label, tradeScope: scope)
        }
    }

    // MARK: - Phase 2: Per-section Sonnet call via /api/quote/section (streaming)

    private func generateSection(
        descriptor: QuoteSectionDescriptor,
        jobDescription: String,
        roomDimensions: RoomDimensions,
        claudeContext: String,
        preferredSupplier: String,
        usualItems: String,
        isRetry: Bool = false
    ) async -> QuoteSection {

        guard let url = URL(string: "\(AQBackend.baseURL)/api/quote/section") else {
            return failedSection(descriptor: descriptor, reason: "Invalid server URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120

        guard let token = await AuthManager.shared.currentIdToken() else {
            return failedSection(descriptor: descriptor, reason: "Not authenticated")
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let rdMap: [String: Any] = [
            "roomType":   roomDimensions.roomType,
            "lengthStr":  roomDimensions.lengthStr,
            "widthStr":   roomDimensions.widthStr,
            "heightStr":  roomDimensions.heightStr,
            "floorArea":  roomDimensions.floorArea,
            "wallArea":   roomDimensions.wallArea,
            "doorCount":  roomDimensions.doorCount,
            "windowCount": roomDimensions.windowCount,
        ]

        let body: [String: Any] = [
            "sectionLabel":      descriptor.sectionLabel,
            "tradeScope":        descriptor.tradeScope,
            "jobDescription":    jobDescription,
            "claudeContext":     claudeContext,
            "roomDimensions":    rdMap,
            "preferredSupplier": preferredSupplier,
            "usualItems":        usualItems,
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return failedSection(descriptor: descriptor, reason: "Request encoding failed")
        }
        request.httpBody = bodyData

        do {
            let (byteStream, response) = try await URLSession.shared.bytes(for: request)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard httpStatus == 200 else {
                return failedSection(descriptor: descriptor, reason: "HTTP \(httpStatus)")
            }

            var fullText = ""
            for try await line in byteStream.lines {
                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))
                guard payload != "[DONE]" else { break }
                if let d = payload.data(using: .utf8),
                   let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let delta = j["delta"] as? [String: Any],
                   let t = delta["text"] as? String {
                    fullText += t
                }
            }

            if let section = parseSection(descriptor: descriptor, text: fullText) {
                return section
            }
            if !isRetry {
                return await retrySection(descriptor: descriptor, jobDescription: jobDescription,
                                          roomDimensions: roomDimensions, claudeContext: claudeContext,
                                          preferredSupplier: preferredSupplier, usualItems: usualItems)
            }
            return failedSection(descriptor: descriptor, reason: "Could not parse section response")
        } catch {
            if !isRetry {
                return await retrySection(descriptor: descriptor, jobDescription: jobDescription,
                                          roomDimensions: roomDimensions, claudeContext: claudeContext,
                                          preferredSupplier: preferredSupplier, usualItems: usualItems)
            }
            return failedSection(descriptor: descriptor, reason: error.localizedDescription)
        }
    }

    private func retrySection(
        descriptor: QuoteSectionDescriptor,
        jobDescription: String,
        roomDimensions: RoomDimensions,
        claudeContext: String,
        preferredSupplier: String,
        usualItems: String
    ) async -> QuoteSection {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return await generateSection(
            descriptor: descriptor, jobDescription: jobDescription,
            roomDimensions: roomDimensions, claudeContext: claudeContext,
            preferredSupplier: preferredSupplier, usualItems: usualItems, isRetry: true
        )
    }

    // MARK: - Parse section JSON

    private func parseSection(descriptor: QuoteSectionDescriptor, text: String) -> QuoteSection? {
        var cleaned = text
        if let fs = cleaned.range(of: "```"),
           let fe = cleaned.range(of: "```", options: .backwards),
           fs.lowerBound != fe.lowerBound {
            let inner = cleaned[fs.upperBound..<fe.lowerBound]
            cleaned = String(inner.drop(while: { $0 != "\n" }).dropFirst())
            if cleaned.isEmpty { cleaned = String(inner) }
        }

        guard let json = extractJSONObject(from: cleaned) else { return nil }

        let labourDays = (json["labourDays"] as? Double) ?? 0.0
        let labourRate = (json["labourRate"] as? Double) ?? 280.0
        let notes      = (json["notes"] as? String) ?? ""
        if let vr = json["vatRate"] as? Double {
            Task { @MainActor in self.vatRate = vr }
        }

        var items: [QuoteLineItem] = []
        if let rawItems = json["items"] as? [[String: Any]] {
            for raw in rawItems {
                let desc     = (raw["description"] as? String) ?? "Item"
                let qty      = (raw["qty"]         as? Double) ?? 1.0
                let unit     = (raw["unit"]         as? String) ?? "each"
                let price    = (raw["unitPrice"]    as? Double) ?? 0.0
                let sku      = (raw["sku"]          as? String) ?? ""
                let supplier = (raw["supplier"]     as? String) ?? ""
                items.append(QuoteLineItem(
                    description: desc, qty: qty, unit: unit,
                    unitPrice: price, sku: sku, supplier: supplier,
                    sectionKey: descriptor.sectionKey
                ))
            }
        }

        return QuoteSection(
            id: descriptor.sectionKey, label: descriptor.sectionLabel,
            labourDays: labourDays, labourRate: labourRate,
            items: items, notes: notes, status: .complete
        )
    }

    // MARK: - JSON extraction helpers

    private func extractJSONObject(from text: String) -> [String: Any]? {
        var searchFrom = text.startIndex
        while searchFrom < text.endIndex {
            guard let start = text[searchFrom...].firstIndex(of: "{") else { break }
            if let end = text.lastIndex(of: "}"), end >= start,
               let data = String(text[start...end]).data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
            searchFrom = text.index(after: start)
        }
        return nil
    }

    private func extractJSONArray(from text: String) -> [[String: Any]]? {
        var searchFrom = text.startIndex
        while searchFrom < text.endIndex {
            guard let start = text[searchFrom...].firstIndex(of: "[") else { break }
            if let end = text.lastIndex(of: "]"), end >= start,
               let data = String(text[start...end]).data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return arr
            }
            searchFrom = text.index(after: start)
        }
        return nil
    }

    private func failedSection(descriptor: QuoteSectionDescriptor, reason: String) -> QuoteSection {
        QuoteSection(
            id: descriptor.sectionKey, label: descriptor.sectionLabel,
            labourDays: 0, labourRate: 280, items: [], notes: "",
            status: .failed(reason)
        )
    }
}

// MARK: - URLRequest auth helper

private extension URLRequest {
    mutating func attachAuthToken() async throws {
        guard let token = await AuthManager.shared.currentIdToken() else {
            throw NSError(domain: "Auth", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
}
