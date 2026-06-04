import SwiftUI
import RoomPlan

// MARK: - ExportView
// Format picker + share sheet. Six export formats.

struct ExportView: View {
    @EnvironmentObject var appState: AppState
    let session: ScanSession

    @State private var isExporting = false
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var exportError: String?

    private let formats: [(name: String, icon: String, desc: String, fmt: ExportFormat)] = [
        ("USDZ",  "cube.fill",          "3D model · opens in Quick Look",        .usdz),
        ("OBJ",   "cube",               "3D model · Blender / SketchUp / CAD",   .obj),
        ("PDF",   "doc.fill",           "Floor plan · print ready",              .pdf),
        ("DXF",   "pencil.and.ruler",   "CAD format · AutoCAD / FreeCAD",        .dxf),
        ("CSV",   "tablecells",         "Raw dimensions · Excel / Numbers",      .csv),
        ("PNG",   "photo",              "Floor plan image · share anywhere",     .png),
    ]

    enum ExportFormat { case usdz, obj, pdf, dxf, csv, png }

    var body: some View {
        ZStack {
            AS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav
                HStack {
                    Button { appState.showReview(session) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AS.lightBlue)
                    }
                    Spacer()
                    Text("Export")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AS.text)
                    Spacer()
                    Color.clear.frame(width: 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)
                .padding(.bottom, 20)

                List {
                    Section {
                        ForEach([ExportFormat.usdz, .obj], id: \.hashValue) { fmt in
                            exportRow(for: fmt)
                        }
                    } header: {
                        Text("3D Model").foregroundColor(AS.muted).font(.system(size: 11, weight: .semibold)).tracking(1)
                    }

                    Section {
                        ForEach([ExportFormat.pdf, .dxf, .png], id: \.hashValue) { fmt in
                            exportRow(for: fmt)
                        }
                    } header: {
                        Text("Floor Plan").foregroundColor(AS.muted).font(.system(size: 11, weight: .semibold)).tracking(1)
                    }

                    Section {
                        exportRow(for: .csv)
                    } header: {
                        Text("Data").foregroundColor(AS.muted).font(.system(size: 11, weight: .semibold)).tracking(1)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Export row

    @ViewBuilder
    private func exportRow(for fmt: ExportFormat) -> some View {
        if let info = formats.first(where: { $0.fmt == fmt }) {
            Button {
                Task { await export(as: fmt) }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: info.icon)
                        .frame(width: 32)
                        .foregroundColor(AS.lightBlue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(info.name).font(.system(size: 15, weight: .semibold)).foregroundColor(AS.text)
                        Text(info.desc).font(.system(size: 12)).foregroundColor(AS.muted)
                    }
                    Spacer()
                    if isExporting {
                        ProgressView().tint(AS.lightBlue).scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(AS.muted.opacity(0.5))
                    }
                }
                .contentShape(Rectangle())
            }
            .disabled(isExporting)
            .listRowBackground(AS.surface1)
        }
    }

    // MARK: - Export action

    private func export(as fmt: ExportFormat) async {
        isExporting = true
        defer { isExporting = false }
        do {
            let name = session.name.isEmpty ? session.roomType.rawValue : session.name
            let url: URL
            switch fmt {
            case .usdz: url = try await USDZExporter.export(session.capturedRoom, named: name)
            case .obj:  url = try await OBJExporter.export(session.capturedRoom,  named: name)
            case .pdf:  url = try await PDFExporter.export(session.capturedRoom,  named: name)
            case .dxf:  url = try await DXFExporter.export(session.capturedRoom,  named: name)
            case .csv:  url = try await CSVExporter.export(session.capturedRoom,  named: name)
            case .png:  url = try await PNGExporter.export(session.capturedRoom,  named: name)
            }
            shareURL     = url
            showShareSheet = true
            HapticService.shared.success()
        } catch {
            exportError = error.localizedDescription
            HapticService.shared.error()
        }
    }
}

extension ExportView.ExportFormat: Hashable {}

// MARK: - Share sheet wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
