import SwiftUI
import RoomPlan

// MARK: - FullWorksFlowView (Tri-Mode Scanning build spec §4.1)
//
// Top-level switch over FullWorksSession.phase, mirroring SpaceScanFlowView's
// role for Space mode — kept as its own flow view rather than folded into
// ContentView because the mode picker (§1, not yet built) is what will
// actually decide which flow to present; until then this is reachable
// standalone from Dev Tools for on-device testing.
//
// Wraps a fresh ScanCoordinator per room (§4.1: "do not fork it" — reuses
// the existing Room engine unmodified, just drives a new instance per room
// rather than the app-wide singleton ContentView owns, since Full Works
// needs to capture N rooms in sequence and ScanCoordinator is built around
// capturing exactly one).
//
// Gating (§4.3): deliberately NO paywall/entitlement check anywhere in this
// file or FullWorksSession/FullWorksOutput/FullWorksCompleteView —
// AccuQuoteScan includes Full Works in all tiers ("do not paywall inside the
// paid app — the £99 already signals premium; gating features inside a
// premium subscription breeds resentment"). The locked-with-upsell-sheet
// variant is AccuScan-only (§4.3's "AccuScan: card visible, locked... opens
// the upsell sheet") and belongs in AccuScan's own codebase, ported there
// after this AccuQuoteScan implementation is verified, per this project's
// established build sequencing.

struct FullWorksFlowView: View {
    @StateObject private var session = FullWorksSession()
    @StateObject private var roomCoordinator = ScanCoordinator()
    var onDone: () -> Void = {}

    var body: some View {
        Group {
            if !FullWorksSession.isSupported {
                FullWorksUnsupportedView(onCancel: onDone)
            } else {
                switch session.phase {
                case .setup:
                    FullWorksSetupView(session: session)
                case .scanningRoom:
                    FullWorksScanningView(session: session, roomCoordinator: roomCoordinator)
                case .betweenRooms:
                    FullWorksBetweenRoomsView(session: session)
                case .merging:
                    ProcessingView()
                case .complete:
                    FullWorksCompleteView(session: session, onDone: onDone)
                case .error(let message):
                    FullWorksErrorView(message: message, onRetry: { session.finishWholeHouse() }, onCancel: onDone)
                }
            }
        }
        .onDisappear { session.reset() }
    }
}

// MARK: - Unsupported (iOS 16 — §4.1 "On iOS 16, hide the card")

struct FullWorksUnsupportedView: View {
    var onCancel: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "building.2")
                .font(.system(size: 40))
                .foregroundColor(AQ.secondary)
            Text("Full Works needs iOS 17 or later")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AQ.ink)
            Text("Update iOS to scan and merge multiple rooms into one whole-property model.")
                .font(AQ.body(14))
                .foregroundColor(AQ.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            Button("Close", action: onCancel)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AQ.blue)
                .padding(.bottom, 24)
        }
        .background(Color.white)
    }
}

// MARK: - Setup — property name + first floor label

struct FullWorksSetupView: View {
    @ObservedObject var session: FullWorksSession
    @State private var propertyName = ""
    @State private var floorLabel = "Ground floor"

    private let floorPresets = ["Ground floor", "First floor", "Second floor", "Basement"]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("New Full Works Scan")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(AQ.ink)
                Text("Name the property, then scan it room by room.")
                    .font(AQ.body(14))
                    .foregroundColor(AQ.secondary)
            }
            .padding(.top, 48)
            .padding(.bottom, 32)

            VStack(alignment: .leading, spacing: 8) {
                Text("Property name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AQ.secondary)
                TextField("e.g. 14 Oak Street", text: $propertyName)
                    .font(.system(size: 16))
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(AQ.fill).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AQ.rule, lineWidth: 1))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 8) {
                Text("First floor")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AQ.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(floorPresets, id: \.self) { preset in
                            Button {
                                floorLabel = preset
                            } label: {
                                Text(preset)
                                    .font(.system(size: 13, weight: floorLabel == preset ? .semibold : .medium))
                                    .foregroundColor(floorLabel == preset ? .white : AQ.ink)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(floorLabel == preset ? AQ.blue : AQ.fill)
                                    .cornerRadius(20)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                session.start(propertyName: propertyName.isEmpty ? "Untitled property" : propertyName, firstFloorLabel: floorLabel)
                session.beginScanningNextRoom()
            } label: {
                Text("Start Scanning")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AQ.blue)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.white)
    }
}

// MARK: - Scanning a room — reuses the standard Room engine

struct FullWorksScanningView: View {
    @ObservedObject var session: FullWorksSession
    @ObservedObject var roomCoordinator: ScanCoordinator

    var body: some View {
        Group {
            switch roomCoordinator.state {
            case .ready:
                Color.black.ignoresSafeArea()
                    .onAppear { roomCoordinator.startScan() }
            case .scanning:
                ScanningView(coordinator: roomCoordinator)
            case .processing:
                ProcessingView()
            case .complete(let dims):
                Color.clear.onAppear {
                    if let room = roomCoordinator.lastCapturedRoom {
                        session.recordCompletedRoom(room, dimensions: dims)
                    } else {
                        // No CapturedRoom (shouldn't happen on the LiDAR path
                        // Full Works requires, but fail safe rather than
                        // silently dropping the room) — bounce back to the
                        // between-rooms screen without recording anything.
                        session.phase = .betweenRooms
                    }
                    roomCoordinator.reset()
                }
            case .needsReview(let room, let dims, let confidence):
                ScanNeedsReviewView(coordinator: roomCoordinator, room: room, result: dims, confidence: confidence)
            case .error(let message):
                FullWorksErrorView(message: message, onRetry: { roomCoordinator.reset(); roomCoordinator.startScan() },
                                    onCancel: { session.phase = .betweenRooms; roomCoordinator.reset() })
            }
        }
    }
}

// MARK: - Between rooms — live floor summary + next-room prompt

struct FullWorksBetweenRoomsView: View {
    @ObservedObject var session: FullWorksSession
    @State private var showAddFloor = false
    @State private var newFloorLabel = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    AQLogoView()
                    Text(session.propertyName)
                        .font(.system(size: 12))
                        .foregroundColor(AQ.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 20)

            Divider().background(AQ.rule).padding(.horizontal, 24).padding(.bottom, 16)

            if let floor = session.currentFloor {
                VStack(spacing: 0) {
                    HStack {
                        Text(floor.label.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AQ.secondary)
                            .kerning(0.8)
                        Spacer()
                        Text("\(floor.rooms.count) room\(floor.rooms.count == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AQ.blue)
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)

                    Divider().background(AQ.rule).padding(.horizontal, 20)

                    if floor.rooms.isEmpty {
                        Text("No rooms scanned on this floor yet")
                            .font(.system(size: 13))
                            .foregroundColor(AQ.secondary)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(floor.rooms) { record in
                            HStack {
                                Text(record.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AQ.ink)
                                Spacer()
                                Text("\(record.dimensions.lengthStr)×\(record.dimensions.widthStr)m · \(record.dimensions.floorAreaStr)m²")
                                    .font(.system(size: 12))
                                    .foregroundColor(AQ.secondary)
                            }
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            Divider().background(AQ.rule).padding(.horizontal, 20)
                        }
                    }

                    HStack {
                        Text("Running total")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AQ.ink)
                        Spacer()
                        Text("\(String(format: "%.1f", floor.rooms.reduce(0) { $0 + $1.dimensions.floorArea })) m²")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AQ.ink)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)
                }
                .background(Color.white)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AQ.rule, lineWidth: 1))
                .padding(.horizontal, 24)
            }

            Text("Walk to the next room, keep the phone up, then tap Scan")
                .font(.system(size: 13))
                .foregroundColor(AQ.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 16)

            Spacer()

            VStack(spacing: 12) {
                Button { session.beginScanningNextRoom() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "viewfinder")
                        Text("Scan Next Room")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AQ.blue)
                    .cornerRadius(14)
                }

                HStack(spacing: 12) {
                    Button("Add another floor") { showAddFloor = true }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AQ.secondary)
                    Text("·").foregroundColor(AQ.rule)
                    Button("Finish floor") { session.finishFloor() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AQ.blue)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(AQ.fill)
        .alert("Add floor", isPresented: $showAddFloor) {
            TextField("Floor name", text: $newFloorLabel)
            Button("Add") {
                guard !newFloorLabel.isEmpty else { return }
                session.addFloor(label: newFloorLabel)
                newFloorLabel = ""
            }
            Button("Cancel", role: .cancel) { newFloorLabel = "" }
        }
    }
}

// MARK: - Error

struct FullWorksErrorView: View {
    let message: String
    var onRetry: () -> Void
    var onCancel: () -> Void

    // Fix #11 — same shared classification as ErrorView/QuoteErrorView/
    // SpaceErrorView, so all four error screens agree on when "Try Again"
    // is actually meaningful to show.
    private var isRetryable: Bool { ScanErrorClassifier.isRetryable(message) }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: isRetryable ? "exclamationmark.triangle" : "lock.circle")
                .font(.system(size: 40))
                .foregroundColor(AQ.secondary)
            Text(message)
                .font(AQ.body(15))
                .foregroundColor(AQ.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                if isRetryable {
                    Button(action: onRetry) {
                        Text("Try Again")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AQ.blue)
                            .cornerRadius(14)
                    }
                }
                Button(isRetryable ? "Cancel" : "Close", action: onCancel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AQ.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.white)
    }
}
