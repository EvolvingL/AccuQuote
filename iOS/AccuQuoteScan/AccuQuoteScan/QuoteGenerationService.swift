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

        // ── Phase 1: Discover sections via Haiku (fast, ~3s) ────────────────
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

        // Seed pending sections immediately so UI shows the plan
        sections = descriptors.map {
            QuoteSection(id: $0.sectionKey, label: $0.sectionLabel,
                         labourDays: 0, labourRate: 280, items: [], notes: "",
                         status: .pending)
        }
        state = .generatingSections(total: descriptors.count, completed: 0)

        // ── Phase 2: Fan out one Sonnet call per section in parallel ─────────
        await withTaskGroup(of: (Int, QuoteSection).self) { group in
            for (idx, descriptor) in descriptors.enumerated() {
                // Mark loading
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

    // MARK: - Phase 1: Section discovery

    private func discoverSections(
        jobDescription: String,
        claudeContext: String
    ) async throws -> [QuoteSectionDescriptor] {

        let prompt = """
        \(claudeContext.isEmpty ? "" : claudeContext + "\n\n")
        JOB: \(jobDescription)

        List the distinct trade sections that need quoting for this job.
        Include only sections within this tradesperson's scope and trade.
        Return ONLY a JSON array, no markdown, no prose.
        Each element: {"sectionKey":"snake_case_id","sectionLabel":"Human Label","tradeScope":"brief scope of what this section covers"}
        Maximum 10 sections. Do not include project management or preliminaries.
        """

        guard let url = URL(string: ANTHROPIC_API_URL) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ANTHROPIC_API_KEY, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 800,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw NSError(domain: "QuoteGen", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected Haiku response format"])
        }

        // Find JSON array in response
        guard let arrStart = text.firstIndex(of: "["),
              let arrEnd = text.lastIndex(of: "]") else {
            throw NSError(domain: "QuoteGen", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "No section list in response"])
        }
        let arrSlice = String(text[arrStart...arrEnd])
        guard let arrData = arrSlice.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: arrData) as? [[String: Any]] else {
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

    // MARK: - Phase 2: Per-section Sonnet call (streaming)

    private func generateSection(
        descriptor: QuoteSectionDescriptor,
        jobDescription: String,
        roomDimensions: RoomDimensions,
        claudeContext: String,
        preferredSupplier: String,
        usualItems: String
    ) async -> QuoteSection {

        let prompt = """
        \(claudeContext.isEmpty ? "" : claudeContext + "\n\n")
        OVERALL JOB: \(jobDescription)
        SECTION TO PRICE: \(descriptor.sectionLabel)
        SCOPE: \(descriptor.tradeScope)

        ROOM: \(roomDimensions.roomType)
        DIMENSIONS: \(roomDimensions.lengthStr)m × \(roomDimensions.widthStr)m × \(roomDimensions.heightStr)m
        FLOOR AREA: \(String(format: "%.1f", roomDimensions.floorArea))m²
        WALL AREA: \(String(format: "%.1f", roomDimensions.wallArea))m²
        DOORS: \(roomDimensions.doorCount)  WINDOWS: \(roomDimensions.windowCount)

        PREFERRED SUPPLIER: \(preferredSupplier)
        \(usualItems.isEmpty ? "" : "PRODUCTS THEY REGULARLY ORDER: \(usualItems)")

        Price ONLY the '\(descriptor.sectionLabel)' scope. Be exhaustive — include every line item.
        Match all materials to REAL products at \(preferredSupplier). Include exact SKU codes.

        OUTPUT: Return ONLY a single raw JSON object — no markdown, no prose.
        Schema: {"labourDays":2.0,"labourRate":280.0,"items":[{"description":"...","qty":1.0,"unit":"each","unitPrice":12.50,"sku":"123456","supplier":"..."}],"vatRate":20,"notes":"..."}
        No item cap — include everything needed. Keep descriptions concise (under 70 chars).
        """

        guard let url = URL(string: ANTHROPIC_API_URL) else {
            return failedSection(descriptor: descriptor, reason: "Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ANTHROPIC_API_KEY, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 4096,
            "stream": true,
            "messages": [["role": "user", "content": prompt]]
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

            return parseSection(descriptor: descriptor, text: fullText)

        } catch {
            return failedSection(descriptor: descriptor, reason: error.localizedDescription)
        }
    }

    // MARK: - Parse section JSON

    private func parseSection(descriptor: QuoteSectionDescriptor, text: String) -> QuoteSection {
        var cleaned = text
        // Strip markdown fences
        if let fs = cleaned.range(of: "```"),
           let fe = cleaned.range(of: "```", options: .backwards),
           fs.lowerBound != fe.lowerBound {
            let inner = cleaned[fs.upperBound..<fe.lowerBound]
            cleaned = String(inner.drop(while: { $0 != "\n" }).dropFirst())
            if cleaned.isEmpty { cleaned = String(inner) }
        }

        guard let jsonStart = cleaned.firstIndex(of: "{"),
              let jsonEnd = cleaned.lastIndex(of: "}"),
              let sliceData = String(cleaned[jsonStart...jsonEnd]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: sliceData) as? [String: Any] else {
            return failedSection(descriptor: descriptor, reason: "Could not parse section JSON")
        }

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
            id: descriptor.sectionKey,
            label: descriptor.sectionLabel,
            labourDays: labourDays,
            labourRate: labourRate,
            items: items,
            notes: notes,
            status: .complete
        )
    }

    private func failedSection(descriptor: QuoteSectionDescriptor, reason: String) -> QuoteSection {
        QuoteSection(
            id: descriptor.sectionKey,
            label: descriptor.sectionLabel,
            labourDays: 0, labourRate: 280, items: [], notes: "",
            status: .failed(reason)
        )
    }
}
