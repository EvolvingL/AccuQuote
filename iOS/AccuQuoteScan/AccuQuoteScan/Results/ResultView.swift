import SwiftUI
import RoomPlan

// MARK: - Result View

struct ResultView: View {
    let result: RoomDimensions
    @ObservedObject var coordinator: ScanCoordinator
    @State private var showJobDescription = false
    @State private var roomTypeOverride = ""
    @State private var show3DViewer = false
    @State private var showFloorPlan = false

    private func isSelected(_ type: String) -> Bool {
        if roomTypeOverride.isEmpty {
            return result.roomType.lowercased() == type.lowercased()
        }
        return roomTypeOverride.lowercased() == type.lowercased()
    }

    var effectiveRoomType: String { roomTypeOverride.isEmpty ? result.roomType : roomTypeOverride }

    var body: some View {
        VStack(spacing: 0) {

            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    AQLogoView()
                    Text("Room measured")
                        .font(.system(size: 12))
                        .foregroundColor(AQ.green)
                }
                Spacer()
                ZStack {
                    Circle().fill(AQ.green.opacity(0.1)).frame(width: 36, height: 36)
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AQ.green)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 20)

            Divider().background(AQ.rule).padding(.horizontal, 24).padding(.bottom, 16)

            // Room type picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["Kitchen", "Bathroom", "Living room", "Bedroom", "Other"], id: \.self) { type in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { roomTypeOverride = type }
                        } label: {
                            Text(type)
                                .font(.system(size: 13, weight: isSelected(type) ? .semibold : .medium))
                                .foregroundColor(isSelected(type) ? .white : AQ.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isSelected(type) ? AQ.blue : AQ.fill)
                                .cornerRadius(20)
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(isSelected(type) ? AQ.blue : AQ.rule, lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 16)

            // Dimensions card
            VStack(spacing: 0) {
                HStack {
                    Text("Room Dimensions")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AQ.secondary)
                        .kerning(0.8)
                        .textCase(.uppercase)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(result.roomType.capitalized)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AQ.secondary)
                        Text("·")
                            .foregroundColor(AQ.rule)
                        Text(result.scanMethod.accuracyLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: result.scanMethod.accuracyHex))
                    }
                }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 20)

                Divider().background(AQ.rule).padding(.horizontal, 20)

                HStack(spacing: 0) {
                    DimensionCell(label: "Length", value: result.lengthStr, unit: "m")
                    Divider().frame(height: 60).background(AQ.rule)
                    DimensionCell(label: "Width",  value: result.widthStr,  unit: "m")
                    Divider().frame(height: 60).background(AQ.rule)
                    DimensionCell(label: "Height", value: result.heightStr, unit: "m")
                }
                .padding(.vertical, 4)

                Divider().background(AQ.rule).padding(.horizontal, 20)

                HStack(spacing: 0) {
                    StatCell(label: "Floor area", value: "\(result.floorAreaStr) m²")
                    Divider().frame(height: 44).background(AQ.rule)
                    StatCell(label: "Doors",    value: "\(result.doorCount)")
                    Divider().frame(height: 44).background(AQ.rule)
                    StatCell(label: "Windows",  value: "\(result.windowCount)")
                }
                .padding(.vertical, 4).padding(.bottom, 8)

                // §6 — 3D preview entry point. Only available when the scan
                // actually produced a CapturedRoom (LiDAR path); poseFusion/
                // manual/custom-shape completions have no mesh to show, same
                // as AR Quick Look never worked for those methods either.
                if coordinator.lastCapturedRoom != nil {
                    Divider().background(AQ.rule).padding(.horizontal, 20)
                    Button { show3DViewer = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "cube.transparent")
                                .font(.system(size: 13, weight: .medium))
                            Text("View in 3D")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(AQ.blue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                    }

                    // §5.2 — 2D floor plan entry point. Same CapturedRoom
                    // availability gate as "View in 3D": poseFusion/manual/
                    // custom-shape completions have no CapturedRoom to
                    // project a plan from (FloorPlan2DBuilder.build(from:)
                    // needs real wall/door/window/object geometry, not just
                    // the extracted RoomDimensions numbers).
                    Divider().background(AQ.rule).padding(.horizontal, 20)
                    Button { showFloorPlan = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.plaintext")
                                .font(.system(size: 13, weight: .medium))
                            Text("Floor Plan")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(AQ.blue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                    }
                }
            }
            .background(Color.white)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AQ.rule, lineWidth: 1))
            .padding(.horizontal, 24)

            Spacer()

            // CTAs
            VStack(spacing: 0) {
                Divider().background(AQ.rule).padding(.bottom, 20)

                Button { showJobDescription = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Describe the Job")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(AQ.blue)
                    .cornerRadius(14)
                }
                .padding(.horizontal, 24)

                Button { coordinator.reset() } label: {
                    Text("Rescan")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AQ.secondary)
                }
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
        .background(AQ.fill)
        .fullScreenCover(isPresented: $showJobDescription) {
            JobDescriptionView(result: result, coordinator: coordinator, roomTypeOverride: effectiveRoomType)
        }
        .fullScreenCover(isPresented: $show3DViewer) {
            if let room = coordinator.lastCapturedRoom {
                NavigationStack {
                    ScanViewer3D(content: .room(room))
                        .navigationTitle("3D Model")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { show3DViewer = false }
                            }
                        }
                }
            }
        }
        .fullScreenCover(isPresented: $showFloorPlan) {
            if let room = coordinator.lastCapturedRoom {
                RoomFloorPlanScreen(room: room, roomName: effectiveRoomType.capitalized, onDone: { showFloorPlan = false })
            }
        }
    }
}

// MARK: - Room mode floor plan screen (§5.2)
//
// Single-room equivalent of what FullWorksOutput already does per-room for
// Full Works — same FloorPlan2DBuilder.build(from:roomName:) projection and
// FloorPlan2DExport.exportPDF/exportPNG renderers, just reached from
// ResultView's own "Floor Plan" row instead of the Full Works completion
// screen. One source of truth (§5.1): both call sites project from the same
// CapturedRoom through the same builder/renderer, so a single-room plan and
// a Full Works per-floor plan can never disagree in style or content.
struct RoomFloorPlanScreen: View {
    let room: CapturedRoom
    let roomName: String
    var onDone: () -> Void = {}

    @State private var plan: FloorPlan2D?
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if let plan {
                    FloorPlan2DView(plan: plan)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Floor Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done", action: onDone)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        guard let plan else { return }
                        shareURL = FloorPlan2DExport.exportPDF(plan: plan, title: roomName)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(plan == nil)
                }
            }
        }
        .onAppear {
            guard plan == nil else { return }
            plan = FloorPlan2DBuilder.build(from: room, roomName: roomName)
        }
        .sheet(item: $shareURL) { url in
            ShareSheet(url: url)
        }
    }
}
