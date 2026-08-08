import SwiftUI
import RoomPlan

// MARK: - Quote View

struct QuoteView: View {
    let result: RoomDimensions
    let jobDescription: String
    let customerName: String
    @ObservedObject var coordinator: ScanCoordinator
    @EnvironmentObject var questionEngine: QuestionEngine
    @Environment(\.dismiss) var dismiss

    @StateObject private var service = QuoteGenerationService()

    private var preferredSupplier: String {
        let ans = questionEngine.profile.answers.first(where: { $0.id == "supplier" })?.answer ?? ""
        return ans.isEmpty ? "Screwfix or Toolstation" : ans
    }

    var body: some View {
        NavigationStack {
            Group {
                switch service.state {
                case .idle, .discoveringSections:
                    QuoteLoadingView(
                        step: 0,
                        steps: ["Planning your quote…", "Identifying trade sections…"]
                    )
                case .generatingSections(let total, let completed):
                    SectionedQuoteLoadingView(service: service, total: total, completed: completed)
                case .complete:
                    let quote = GeneratedQuote(
                        sections: service.sections,
                        vatRate: service.vatRate,
                        customerName: customerName,
                        jobDescription: jobDescription
                    )
                    QuoteResultView(quote: quote, result: result) {
                        dismiss(); coordinator.reset()
                    }
                case .failed(let message):
                    QuoteErrorView(message: message) {
                        startGeneration()
                    }
                }
            }
            .navigationTitle("Quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if case .complete = service.state {
                        Button("Back") { dismiss() }.foregroundColor(AQ.secondary)
                    }
                }
            }
        }
        .onAppear { startGeneration() }
    }

    private func startGeneration() {
        let ctx = questionEngine.claudeContext()
        let supplier = preferredSupplier
        let usualItems = questionEngine.profile.answers
            .first(where: { $0.id == "usual_items" })?.answer ?? ""
        let dims = result
        let job  = jobDescription
        let cust = customerName
        // §2 step 3 / §7: persist a USDZ alongside the saved quote so history
        // can show a 3D thumbnail and re-open the model later. Only Room's
        // LiDAR path has a CapturedRoom to export — poseFusion/manual scans
        // have no mesh, matching the same gap ScanViewer3D's own "View in
        // 3D" entry point in ResultView already has.
        let room = coordinator.lastCapturedRoom
        let roomName = result.roomType.capitalized
        Task.detached(priority: .userInitiated) {
            let artifactURL = room.flatMap { Self.exportRoomUSDZ($0) }
            // §7: thumbnail rendered once at save time, cached as JPEG next
            // to the USDZ — history rows read the cached file, never
            // re-render on every scroll.
            if let artifactURL {
                _ = HistoryThumbnailRenderer.renderThumbnail(usdzURL: artifactURL)
            }
            // §5.2/§5.5 — persist the same floor plan RoomFloorPlanScreen
            // would render, alongside the USDZ, so a plan.pdf exists in
            // aq_scans/<id>/ even if the user never opened the Floor Plan
            // row before generating the quote. Best-effort: a failed plan
            // render must never block quote generation.
            if let room, let artifactURL {
                let plan = FloorPlan2DBuilder.build(from: room, roomName: roomName)
                await MainActor.run {
                    let planURL = artifactURL.deletingLastPathComponent().appendingPathComponent("plan.pdf")
                    let tempPDF = FloorPlan2DExport.exportPDF(plan: plan, title: roomName)
                    try? FileManager.default.removeItem(at: planURL)
                    try? FileManager.default.copyItem(at: tempPDF, to: planURL)
                }
            }
            await service.generate(
                jobDescription: job,
                customerName: cust,
                roomDimensions: dims,
                claudeContext: ctx,
                preferredSupplier: supplier,
                usualItems: usualItems,
                scanMode: .room,
                scanArtifactURL: artifactURL
            )
        }
    }

    /// Exports to Documents/aq_scans/<uuid>.usdz per §2 step 3 / §5.5's
    /// persistence convention (same folder SpaceMeshExport/FloorPlan2DExport
    /// already write into).
    private static func exportRoomUSDZ(_ room: CapturedRoom) -> URL? {
        let folder = SpaceMeshExport.scanFolder(id: UUID().uuidString)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return nil }
        let url = folder.appendingPathComponent("model.usdz")
        do {
            try room.export(to: url, exportOptions: [.mesh, .parametric])
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Quote Loading View

struct QuoteLoadingView: View {
    let step: Int
    let steps: [String]
    @State private var pulse = false
    @State private var orbRotate = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Orb
            ZStack {
                Circle().fill(AQ.blue.opacity(0.06)).frame(width: 110, height: 110)
                    .scaleEffect(pulse ? 1.18 : 1.0)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)
                Circle().fill(AQ.blue.opacity(0.11)).frame(width: 78, height: 78)
                // Spinning arc
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(AQ.blue.opacity(0.45), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(orbRotate ? 360 : 0))
                    .animation(.linear(duration: 1.8).repeatForever(autoreverses: false), value: orbRotate)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(AQ.blue)
            }
            .onAppear { pulse = true; orbRotate = true }
            .padding(.bottom, 32)

            Text("Building your quote")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(AQ.ink)
                .padding(.bottom, 6)

            Text("Pricing live from your supplier catalogue")
                .font(.system(size: 13))
                .foregroundColor(AQ.secondary)
                .padding(.bottom, 36)

            // Step checklist
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, label in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(i < step ? AQ.green : (i == step ? AQ.blue.opacity(0.12) : AQ.fill))
                                .frame(width: 22, height: 22)
                            if i < step {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            } else if i == step {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .tint(AQ.blue)
                                    .frame(width: 22, height: 22)
                            } else {
                                Circle()
                                    .fill(AQ.secondary.opacity(0.2))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        Text(label)
                            .font(.system(size: 14, weight: i <= step ? .medium : .regular))
                            .foregroundColor(i < step ? AQ.green : (i == step ? AQ.ink : AQ.secondary.opacity(0.5)))
                            .animation(.easeInOut(duration: 0.25), value: step)
                    }
                }
            }
            .padding(.horizontal, 48)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

// MARK: - Sectioned Quote Loading View

struct SectionedQuoteLoadingView: View {
    @ObservedObject var service: QuoteGenerationService
    let total: Int
    let completed: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.85)
                        Text("\(completed) of \(total) sections")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AQ.secondary)
                        Spacer()
                        if service.grandTotal > 0 {
                            Text(Money.gbp(service.grandTotal))
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(AQ.ink)
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.3), value: service.grandTotal)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(AQ.rule).frame(height: 3)
                            Rectangle()
                                .fill(AQ.blue)
                                .frame(width: geo.size.width * CGFloat(completed) / CGFloat(max(total, 1)), height: 3)
                                .animation(.easeInOut(duration: 0.4), value: completed)
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }

                // Section cards
                LazyVStack(spacing: 0) {
                    ForEach(service.sections) { section in
                        SectionStatusCard(section: section)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: service.sections.count)
            }
        }
        .background(Color.white)
    }
}

private struct SectionStatusCard: View {
    let section: QuoteSection

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Status icon
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.1))
                        .frame(width: 32, height: 32)
                    statusIcon
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(statusColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AQ.ink)
                    if case .complete = section.status {
                        Text("\(section.items.count) items · \(Money.gbp(section.sectionSubtotal))")
                            .font(.system(size: 12))
                            .foregroundColor(AQ.secondary)
                    } else if case .loading = section.status {
                        Text("Pricing items…")
                            .font(.system(size: 12))
                            .foregroundColor(AQ.secondary)
                    } else if case .failed(let reason) = section.status {
                        Text(reason)
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.7))
                            .lineLimit(1)
                    } else {
                        Text("Waiting…")
                            .font(.system(size: 12))
                            .foregroundColor(AQ.secondary)
                    }
                }
                Spacer()
                if case .complete = section.status {
                    Text(Money.gbp(section.sectionSubtotal))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(AQ.ink)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            Divider().background(AQ.rule).padding(.leading, 24)
        }
    }

    private var statusColor: Color {
        switch section.status {
        case .complete:      return AQ.green
        case .loading:       return AQ.blue
        case .failed:        return .red
        case .pending:       return AQ.secondary
        }
    }

    private var statusIcon: Image {
        switch section.status {
        case .complete:      return Image(systemName: "checkmark")
        case .loading:       return Image(systemName: "arrow.triangle.2.circlepath")
        case .failed:        return Image(systemName: "exclamationmark")
        case .pending:       return Image(systemName: "clock")
        }
    }
}

// MARK: - Quote Error View

struct QuoteErrorView: View {
    let message: String
    let onRetry: () -> Void
    @Environment(\.dismiss) private var dismiss

    // Fix #34: detect non-retryable errors (subscription required, auth) so we can
    // show an exit path instead of trapping the user in an infinite retry loop.
    // Fix #11: classification now lives in ScanErrorClassifier (ScanCoordinator.swift)
    // so ErrorView/SpaceErrorView/FullWorksErrorView can share the same logic
    // instead of each screen inventing its own (or, as before, not having any).
    private var isRetryable: Bool { ScanErrorClassifier.isRetryable(message) }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: isRetryable ? "exclamationmark.circle" : "lock.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(isRetryable ? AQ.secondary : AQ.blue)
            Text(isRetryable ? "Quote Failed" : "Subscription Required")
                .font(.system(size: 22, weight: .semibold)).foregroundColor(AQ.ink)
            Text(isRetryable ? message : "Quote generation requires an active AccuQuote Pro subscription.")
                .font(AQ.body(15)).foregroundColor(AQ.secondary)
                .multilineTextAlignment(.center).lineSpacing(4).padding(.horizontal, 40)
            Spacer()
            VStack(spacing: 12) {
                Divider().background(AQ.rule).padding(.bottom, 8)
                if isRetryable {
                    Button(action: onRetry) {
                        Text("Try Again")
                            .font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 17)
                            .background(AQ.blue).cornerRadius(14)
                    }
                    .padding(.horizontal, 24)
                }
                // Always provide a way out — Fix #34
                Button(action: { dismiss() }) {
                    Text(isRetryable ? "Go Back" : "Close")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AQ.secondary)
                }
                .padding(.bottom, 36)
            }
        }
        .background(Color.white)
    }
}

// MARK: - Quote Result View

struct QuoteResultView: View {
    let quote: GeneratedQuote
    let result: RoomDimensions
    let onStartOver: () -> Void
    @EnvironmentObject var questionEngine: QuestionEngine
    @State private var pdfURL: URL?
    @State private var showBreakdown = false
    @State private var editingLabourTotal = false
    @State private var labourTotalOverride: Double? = nil
    @State private var showProfileNudge = true
    @State private var showOnboarding = false
    @State private var showDepositSheet = false

    var effectiveLabourTotal: Double { labourTotalOverride ?? quote.labourTotal }
    var effectiveSubtotal: Double { effectiveLabourTotal + quote.items.reduce(0) { $0 + $1.total } }
    var effectiveVatAmount: Double { effectiveSubtotal * (quote.vatRate / 100) }
    var effectiveGrandTotal: Double { effectiveSubtotal + effectiveVatAmount }

    private var profileNudgeQuestion: OnboardingQuestion? {
        guard questionEngine.answeredCount < 6 else { return nil }
        let priority = ["day_rate", "trade", "region", "material_markup", "vat"]
        return priority.compactMap { id in
            questionEngine.questions.first(where: { $0.id == id && !$0.isAnswered })
        }.first
    }

    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
            // #14 LazyVStack — defers rendering of off-screen quote sections/items
            LazyVStack(spacing: 0) {

                // Grand total hero
                VStack(spacing: 6) {
                    Text("Total")
                        .font(.caption.weight(.semibold))   // #1
                        .foregroundColor(AQ.secondary)
                        .kerning(0.8)
                        .textCase(.uppercase)
                    Text(Money.gbp(effectiveGrandTotal))   // #24 keeps pence
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundColor(AQ.ink)
                        .minimumScaleFactor(0.6)   // #7 large totals shrink to fit
                        .lineLimit(1)
                    Text("inc. VAT")
                        .font(AQ.body(13))
                        .foregroundColor(AQ.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(AQ.fill)

                Divider().background(AQ.rule)

                // Profile nudge banner
                if showProfileNudge, let q = profileNudgeQuestion {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Make this quote more accurate")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AQ.ink)
                            Text(q.text)
                                .font(.system(size: 12))
                                .foregroundColor(AQ.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Answer") {
                            showProfileNudge = false
                            showOnboarding = true
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(AQ.blue).cornerRadius(8)
                        Button { showProfileNudge = false } label: {
                            Image(systemName: "xmark").font(.system(size: 10)).foregroundColor(AQ.secondary)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(AQ.blue.opacity(0.06))
                    .overlay(Rectangle().frame(height: 1).foregroundColor(AQ.blue.opacity(0.12)), alignment: .bottom)
                }

                // Summary rows always visible
                QuoteSectionHeader(title: "Summary")
                Button {
                    labourTotalOverride = labourTotalOverride ?? quote.labourTotal
                    editingLabourTotal = true
                } label: {
                    // Fix #17 — previously identical to the read-only
                    // Materials/VAT/Total rows below it apart from the "✎"
                    // glyph tucked into the label text, easy to miss. Now
                    // matches the same tappable-row affordance already used
                    // for "View in 3D"/"Floor Plan" elsewhere: a trailing
                    // chevron plus AQ.blue tint on the label.
                    HStack(alignment: .center) {
                        Text("Labour")
                            .font(AQ.body(15))
                            .foregroundColor(AQ.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Money.gbp(effectiveLabourTotal))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AQ.blue)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AQ.blue)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                }
                Divider().background(AQ.rule).padding(.leading, 24)
                if !quote.items.isEmpty {
                    QuoteRow(label: "Materials", value: Money.gbp(quote.items.reduce(0) { $0 + $1.total }), bold: false)
                    Divider().background(AQ.rule).padding(.leading, 24)
                }
                QuoteRow(label: "VAT (\(Int(quote.vatRate))%)", value: Money.gbp(effectiveVatAmount), bold: false)
                Divider().background(AQ.rule).padding(.leading, 24)
                QuoteRow(label: "Total", value: Money.gbp(effectiveGrandTotal), bold: true)
                Divider().background(AQ.rule)

                // Breakdown toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { showBreakdown.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(showBreakdown ? "Hide breakdown" : "View breakdown")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AQ.blue)
                        Image(systemName: showBreakdown ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AQ.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }

                if showBreakdown {
                    Divider().background(AQ.rule)

                    if quote.sections.count > 1 {
                        // ── Multi-section breakdown ──────────────────────────
                        ForEach(quote.sections) { section in
                            QuoteSectionHeader(title: section.label)
                            // Labour row for this section
                            if section.labourDays > 0 {
                                QuoteRow(
                                    label: "\(String(format: "%.1f", section.labourDays))d labour @ \(Money.gbp(section.labourRate))/day",
                                    value: Money.gbp(section.labourTotal),
                                    bold: false
                                )
                                Divider().background(AQ.rule).padding(.leading, 24)
                            }
                            ForEach(section.items) { item in
                                QuoteLineItemRow(item: item, formatQty: formatQty)
                            }
                            if !section.notes.isEmpty {
                                Text(section.notes)
                                    .font(AQ.body(13)).foregroundColor(AQ.secondary)
                                    .lineSpacing(4)
                                    .padding(.horizontal, 24).padding(.vertical, 10)
                                Divider().background(AQ.rule).padding(.leading, 24)
                            }
                            QuoteRow(
                                label: "Section subtotal",
                                value: Money.gbp(section.sectionSubtotal),
                                bold: true
                            )
                            Divider().background(AQ.rule)
                        }
                    } else {
                        // ── Single-section (legacy) breakdown ────────────────
                        QuoteSectionHeader(title: "Labour")
                        QuoteRow(
                            label: "\(String(format: "%.1f", quote.labourDays)) day\(quote.labourDays == 1 ? "" : "s") @ \(Money.gbp(quote.labourRate))/day",
                            value: Money.gbp(effectiveLabourTotal),
                            bold: false
                        )
                        Divider().background(AQ.rule).padding(.leading, 24)
                        if !quote.items.isEmpty {
                            QuoteSectionHeader(title: "Materials & Items")
                            ForEach(quote.items) { item in
                                QuoteLineItemRow(item: item, formatQty: formatQty)
                            }
                        }
                        if !quote.notes.isEmpty {
                            QuoteSectionHeader(title: "Notes & Inclusions")
                            Text(quote.notes)
                                .font(AQ.body(14)).foregroundColor(AQ.secondary)
                                .lineSpacing(5)
                                .padding(.horizontal, 24).padding(.vertical, 16)
                            Divider().background(AQ.rule)
                        }
                    }
                }

                Color.clear.frame(height: 20)
            }
        }
        .background(Color.white)

        // Sticky footer
        VStack(spacing: 0) {
            Divider().background(AQ.rule)

            // Row 1: New Quote + Send to customer
            HStack(spacing: 10) {
                Button(action: onStartOver) {
                    Text("New Quote")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AQ.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(AQ.fill)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AQ.rule, lineWidth: 1))
                }
                .frame(width: 110)

                Button {
                    pdfURL = buildPDF(summarised: true)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Send to customer")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AQ.blue)
                    .cornerRadius(14)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            // Row 2: Full BOM + Request deposit
            HStack(spacing: 10) {
                Button {
                    pdfURL = buildPDF(summarised: false)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Full BOM")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(AQ.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AQ.fill)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AQ.rule, lineWidth: 1))
                }

                Button {
                    showDepositSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Request deposit via Stripe")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(AQ.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AQ.green.opacity(0.09))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AQ.green.opacity(0.25), lineWidth: 1))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color.white)
        } // end outer VStack
        .background(Color.white)
        .sheet(item: $pdfURL) { url in
            ShareSheet(url: url)
        }
        .sheet(isPresented: $editingLabourTotal) {
            LabourEditSheet(
                current: effectiveLabourTotal,
                onSave: { newVal in
                    labourTotalOverride = newVal
                    editingLabourTotal = false
                },
                onCancel: { editingLabourTotal = false }
            )
            .presentationDetents([.height(260)])
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingSheet().environmentObject(questionEngine)
        }
        .sheet(isPresented: $showDepositSheet) {
            let traderName = questionEngine.profile.answers
                .first(where: { $0.id == "business_name" })?.answer ?? "AccuQuote"
            DepositRequestView(
                quote: quote,
                effectiveGrandTotal: effectiveGrandTotal,
                traderName: traderName,
                onDismiss: { showDepositSheet = false }
            )
        }
    }

    private func formatQty(_ qty: Double) -> String {
        qty == qty.rounded() ? "\(Int(qty))" : String(format: "%.1f", qty)
    }

    // MARK: - PDF Generation

    private func buildPDF(summarised: Bool = true, depositURL: String? = nil) -> URL {
        let profile = questionEngine.profile
        let businessName    = profile.answers.first(where: { $0.id == "business_name" })?.answer ?? "AccuQuote"
        let businessContact = profile.answers.first(where: { $0.id == "business_contact" })?.answer ?? ""
        let traderName      = profile.answers.first(where: { $0.id == "trade" })?.answer ?? ""
        let region          = profile.answers.first(where: { $0.id == "region" })?.answer ?? ""

        let pageW: CGFloat = 595   // A4 points
        let pageH: CGFloat = 842
        let margin: CGFloat = 48
        let col2: CGFloat = pageW - margin   // right edge

        let fmt = UIGraphicsPDFRendererFormat()
        fmt.documentInfo = [
            kCGPDFContextTitle as String:  "Quote — \(businessName)",
            kCGPDFContextAuthor as String: businessName,
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH), format: fmt)

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccuQuote-\(UUID().uuidString.prefix(8)).pdf")

        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)

        try? renderer.writePDF(to: tmpURL) { ctx in
            ctx.beginPage()
            var y: CGFloat = margin

            // ── Header bar ──────────────────────────────────────────────────
            let headerRect = CGRect(x: 0, y: 0, width: pageW, height: 80)
            UIColor(AQ.ink).setFill(); UIRectFill(headerRect)

            let bizAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.white.withAlphaComponent(0.65),
            ]
            businessName.draw(at: CGPoint(x: margin, y: 20), withAttributes: bizAttrs)
            let subLine = [traderName, region].filter { !$0.isEmpty }.joined(separator: " · ")
            if !subLine.isEmpty {
                subLine.draw(at: CGPoint(x: margin, y: 43), withAttributes: subAttrs)
            }
            if !businessContact.isEmpty {
                businessContact.draw(at: CGPoint(x: margin, y: 57), withAttributes: subAttrs)
            }
            // Date right-aligned
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.white.withAlphaComponent(0.65),
            ]
            let dateSize = dateStr.size(withAttributes: dateAttrs)
            dateStr.draw(at: CGPoint(x: col2 - dateSize.width, y: 57), withAttributes: dateAttrs)

            y = 100

            // ── QUOTE title + total ──────────────────────────────────────────
            let quoteLabel = "QUOTE"
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: UIColor(AQ.secondary),
                .kern: 2.0,
            ]
            quoteLabel.draw(at: CGPoint(x: margin, y: y), withAttributes: labelAttrs)
            y += 18

            // Customer
            if !quote.customerName.isEmpty {
                let custAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                    .foregroundColor: UIColor(AQ.ink),
                ]
                quote.customerName.draw(at: CGPoint(x: margin, y: y), withAttributes: custAttrs)
                y += 22
            }

            // Grand total right block
            let totalStr = Money.gbp(quote.grandTotal)
            let totalAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 36, weight: .bold),
                .foregroundColor: UIColor(AQ.ink),
            ]
            let totalSize = totalStr.size(withAttributes: totalAttrs)
            totalStr.draw(at: CGPoint(x: col2 - totalSize.width, y: y - 10), withAttributes: totalAttrs)
            let incVATAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor(AQ.secondary),
            ]
            "inc. VAT".draw(at: CGPoint(x: col2 - 42, y: y + 30), withAttributes: incVATAttrs)

            y += 52

            // ── Divider ──────────────────────────────────────────────────────
            func drawRule(_ yPos: CGFloat) {
                UIColor(AQ.rule).setStroke()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: yPos))
                path.addLine(to: CGPoint(x: col2, y: yPos))
                path.lineWidth = 0.5; path.stroke()
            }
            drawRule(y); y += 16

            // ── Section header helper ────────────────────────────────────────
            func sectionHeader(_ title: String) {
                let a: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
                    .foregroundColor: UIColor(AQ.secondary),
                    .kern: 1.2,
                ]
                title.uppercased().draw(at: CGPoint(x: margin, y: y), withAttributes: a)
                y += 16
            }

            // ── Row helper ───────────────────────────────────────────────────
            func row(left: String, right: String, bold: Bool = false, secondary: String = "") {
                let lAttrs: [NSAttributedString.Key: Any] = [
                    .font: bold ? UIFont.systemFont(ofSize: 13, weight: .semibold)
                                : UIFont.systemFont(ofSize: 13),
                    .foregroundColor: UIColor(AQ.ink),
                ]
                let rAttrs: [NSAttributedString.Key: Any] = [
                    .font: bold ? UIFont.systemFont(ofSize: 13, weight: .semibold)
                                : UIFont.systemFont(ofSize: 13),
                    .foregroundColor: UIColor(bold ? AQ.ink : AQ.ink),
                ]
                left.draw(at: CGPoint(x: margin, y: y), withAttributes: lAttrs)
                let rSize = right.size(withAttributes: rAttrs)
                right.draw(at: CGPoint(x: col2 - rSize.width, y: y), withAttributes: rAttrs)
                y += 18
                if !secondary.isEmpty {
                    let sAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 10),
                        .foregroundColor: UIColor(AQ.secondary),
                    ]
                    secondary.draw(at: CGPoint(x: margin, y: y), withAttributes: sAttrs)
                    y += 14
                }
                y += 4
                drawRule(y); y += 10
            }

            // ── Labour ───────────────────────────────────────────────────────
            sectionHeader("Labour")
            let labourLabel = "\(String(format: "%.1f", quote.labourDays)) day\(quote.labourDays == 1 ? "" : "s") @ £\(Int(quote.labourRate))/day"
            row(left: labourLabel, right: Money.gbp(quote.labourTotal))

            // ── Materials ────────────────────────────────────────────────────
            if !quote.items.isEmpty {
                y += 6
                if summarised {
                    // Customer quote: single materials total, no SKUs or supplier names
                    sectionHeader("Materials")
                    let matTotal = quote.items.reduce(0) { $0 + $1.total }
                    row(left: "Materials & supplies", right: Money.gbp(matTotal))
                } else {
                    // Full BOM: every line item with SKU and supplier
                    sectionHeader("Materials & Items")
                    for item in quote.items {
                        var meta = "\(formatQty(item.qty)) \(item.unit) × £\(String(format: "%.2f", item.unitPrice))"
                        if !item.sku.isEmpty {
                            let sup = item.supplier.isEmpty ? "" : "\(item.supplier) "
                            meta += "   \(sup)SKU \(item.sku)"
                        }
                        let maxDescWidth = pageW - margin * 2 - 80
                        let descAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13)]
                        let descWidth = item.description.size(withAttributes: descAttrs).width
                        if descWidth > maxDescWidth {
                            row(left: String(item.description.prefix(55)) + "…",
                                right: "£\(String(format: "%.2f", item.total))",
                                secondary: meta)
                        } else {
                            row(left: item.description,
                                right: "£\(String(format: "%.2f", item.total))",
                                secondary: meta)
                        }
                    }
                }
            }

            // ── Summary ──────────────────────────────────────────────────────
            y += 6
            sectionHeader("Summary")
            row(left: "Subtotal",               right: Money.gbp(quote.subtotal))
            row(left: "VAT (\(Int(quote.vatRate))%)", right: Money.gbp(quote.vatAmount))
            row(left: "Total",                  right: Money.gbp(quote.grandTotal), bold: true)

            // ── Notes ────────────────────────────────────────────────────────
            if !quote.notes.isEmpty {
                y += 10
                sectionHeader("Notes & Inclusions")
                let notesAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor(AQ.secondary),
                ]
                let maxW = pageW - margin * 2
                let notesRect = CGRect(x: margin, y: y, width: maxW, height: 200)
                quote.notes.draw(in: notesRect, withAttributes: notesAttrs)
                let estimatedLines = max(1, Int(ceil(Double(quote.notes.count) / 90)))
                y += CGFloat(estimatedLines) * 16 + 16
            }

            // ── Job description ──────────────────────────────────────────────
            y += 6
            sectionHeader("Job Description")
            let jobAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor(AQ.secondary),
            ]
            let jobRect = CGRect(x: margin, y: y, width: pageW - margin * 2, height: 150)
            quote.jobDescription.draw(in: jobRect, withAttributes: jobAttrs)

            // ── Footer ───────────────────────────────────────────────────────
            let footerY: CGFloat = pageH - 36
            drawRule(footerY - 8)
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor(AQ.secondary),
            ]
            "Generated by AccuQuote".draw(at: CGPoint(x: margin, y: footerY), withAttributes: footerAttrs)
            let footerDate = "Quote date: \(dateStr)"
            let fdSize = footerDate.size(withAttributes: footerAttrs)
            footerDate.draw(at: CGPoint(x: col2 - fdSize.width, y: footerY), withAttributes: footerAttrs)
        }

        return tmpURL
    }
}


// MARK: - Deposit Request View

struct DepositRequestView: View {
    let quote: GeneratedQuote
    let effectiveGrandTotal: Double
    let traderName: String
    let onDismiss: () -> Void

    @State private var selectedPreset: Int? = 25       // % preset button selected
    @State private var customInput: String = ""
    @State private var useCustom = false
    @State private var isLoading = false
    @State private var paymentLink: DepositPaymentLink? = nil
    @State private var errorMessage: String? = nil
    @State private var showShareSheet = false
    @State private var shareURL: URL? = nil

    private let presets = [10, 25, 50]
    private let stripeMinimum: Double = 0.50   // Stripe minimum charge

    private var depositAmount: Double {
        if useCustom {
            // Fix #28/#29: parse robustly — take only the first valid numeric segment
            let cleaned = customInput.filter { $0.isNumber || $0 == "." }
            // If multiple dots, only parse up to the second one (e.g. "1.2.3" → "1.2")
            let parts = cleaned.components(separatedBy: ".")
            let normalised = parts.count > 2 ? parts[0] + "." + parts[1] : cleaned
            return Double(normalised) ?? 0
        }
        let pct = Double(selectedPreset ?? 25) / 100.0
        return (effectiveGrandTotal * pct * 100).rounded() / 100
    }

    private var serviceFeeAmount: Double {
        (depositAmount * 0.01 * 100).rounded() / 100
    }

    // Fix #26: >= stripeMinimum not > stripeMinimum — exactly £0.50 is valid
    private var isValidAmount: Bool {
        depositAmount >= stripeMinimum && depositAmount <= effectiveGrandTotal
    }

    // Fix #27/#28: user-facing error for invalid custom amounts
    private var customAmountError: String? {
        guard useCustom && !customInput.isEmpty else { return nil }
        let amt = depositAmount
        if amt <= 0 { return "Please enter a valid amount." }
        if amt < stripeMinimum { return "Minimum deposit is £\(String(format: "%.2f", stripeMinimum))." }
        if amt > effectiveGrandTotal { return "Deposit cannot exceed the quote total." }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {

                    // ── Header ────────────────────────────────────────────
                    VStack(spacing: 4) {
                        Text("Request a Deposit")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(AQ.ink)
                        Text("Send a Stripe payment link with your quote")
                            .font(AQ.body(14))
                            .foregroundColor(AQ.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 24)

                    Divider().background(AQ.rule)

                    // ── Quote total context — #24 shared currency formatter ──────
                    HStack {
                        Text("Quote total")
                            .font(AQ.body(15))
                            .foregroundColor(AQ.secondary)
                        Spacer()
                        Text(Money.gbp(effectiveGrandTotal))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AQ.ink)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)

                    Divider().background(AQ.rule)

                    // ── Preset buttons ────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deposit amount")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AQ.secondary)
                            .textCase(.uppercase)
                            .kerning(0.6)
                            .padding(.horizontal, 24)

                        HStack(spacing: 10) {
                            ForEach(presets, id: \.self) { pct in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedPreset = pct
                                        useCustom = false
                                        customInput = ""
                                    }
                                } label: {
                                    VStack(spacing: 3) {
                                        Text("\(pct)%")
                                            .font(.system(size: 16, weight: .semibold))
                                        Text(Money.gbp((effectiveGrandTotal * Double(pct) / 100).rounded()))
                                            .font(.system(size: 12))
                                    }
                                    .foregroundColor((!useCustom && selectedPreset == pct) ? .white : AQ.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background((!useCustom && selectedPreset == pct) ? AQ.blue : AQ.fill)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke((!useCustom && selectedPreset == pct) ? AQ.blue : AQ.rule, lineWidth: 1)
                                    )
                                }
                            }

                            // Custom button
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    useCustom = true
                                    selectedPreset = nil
                                }
                            } label: {
                                Text(useCustom ? "Custom ✎" : "Custom")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(useCustom ? .white : AQ.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(useCustom ? AQ.blue : AQ.fill)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(useCustom ? AQ.blue : AQ.rule, lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.horizontal, 24)

                        if useCustom {
                            HStack {
                                Text("£")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(AQ.secondary)
                                TextField("e.g. 500", text: $customInput)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 17))
                                    .foregroundColor(AQ.ink)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(AQ.fill)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(customAmountError != nil ? Color.red : AQ.blue, lineWidth: 1.5))
                            .padding(.horizontal, 24)

                            // Fix #27/#28/#29: show why the amount is invalid
                            if let err = customAmountError {
                                Text(err)
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 24)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .padding(.vertical, 20)

                    Divider().background(AQ.rule)

                    // ── Fee breakdown ─────────────────────────────────────
                    VStack(spacing: 0) {
                        HStack {
                            Text("Customer pays")
                                .font(AQ.body(15))
                                .foregroundColor(AQ.secondary)
                            Spacer()
                            Text(isValidAmount ? "£\(String(format: "%.2f", depositAmount))" : "—")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AQ.ink)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)

                        Divider().background(AQ.rule).padding(.leading, 24)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AccuQuote service fee")
                                    .font(AQ.body(15))
                                    .foregroundColor(AQ.secondary)
                                Text("1% of deposit — deducted from payout")
                                    .font(AQ.body(12))
                                    .foregroundColor(AQ.secondary.opacity(0.7))
                            }
                            Spacer()
                            Text(isValidAmount ? "£\(String(format: "%.2f", serviceFeeAmount))" : "—")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AQ.secondary)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)

                        Divider().background(AQ.rule).padding(.leading, 24)

                        HStack {
                            Text("You receive")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AQ.ink)
                            Spacer()
                            Text(isValidAmount ? "£\(String(format: "%.2f", depositAmount - serviceFeeAmount))" : "—")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(AQ.green)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }

                    Divider().background(AQ.rule)

                    // ── Error message ─────────────────────────────────────
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(AQ.body(14))
                                .foregroundColor(.red)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.06))
                        .cornerRadius(10)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                    }

                    // ── Success — show link ───────────────────────────────
                    if let link = paymentLink {
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AQ.green)
                                    .font(.system(size: 18))
                                Text("Payment link created")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(AQ.green)
                            }

                            Text(link.url.absoluteString)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(AQ.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            Button {
                                shareURL = link.url
                                showShareSheet = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("Share payment link")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(AQ.green)
                                .cornerRadius(14)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                    }

                    Color.clear.frame(height: 100)
                }
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // Fix #33: show "Done" (not "Cancel") once link is created —
                    // "Cancel" implies the action was aborted, which is misleading.
                    Button(paymentLink != nil ? "Done" : "Cancel") { onDismiss() }
                        .foregroundColor(paymentLink != nil ? AQ.blue : AQ.secondary)
                        .fontWeight(paymentLink != nil ? .semibold : .regular)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if paymentLink == nil {
                    VStack(spacing: 0) {
                        Divider().background(AQ.rule)
                        Button {
                            Task { await generateLink() }
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    HStack(spacing: 8) {
                                        Image(systemName: "link")
                                            .font(.system(size: 15, weight: .semibold))
                                        Text("Create payment link")
                                            .font(.system(size: 17, weight: .semibold))
                                    }
                                }
                            }
                            .foregroundColor(isValidAmount ? .white : AQ.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isValidAmount ? AQ.blue : AQ.fill)
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(isValidAmount ? Color.clear : AQ.rule, lineWidth: 1)
                            )
                        }
                        .disabled(!isValidAmount || isLoading)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                    }
                    .background(Color.white)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(url: url)
            }
        }
    }

    @MainActor
    private func generateLink() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }   // Fix #32: always clears loading state even on early return
        do {
            let link = try await StripeService.createPaymentLink(
                depositAmount:  depositAmount,
                maxAmount:      effectiveGrandTotal,   // H4: deposit can't exceed the quote
                customerName:   quote.customerName,
                jobDescription: quote.jobDescription,
                traderName:     traderName
            )
            paymentLink = link
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
