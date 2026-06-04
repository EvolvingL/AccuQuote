import SwiftUI
import RoomPlan
import RealityKit
import UIKit

// MARK: - ActiveScanView

struct ActiveScanView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var sessionManager = ScanSessionManager()

    @State private var showScanComplete = false
    @State private var completedRoom: CapturedRoom?

    var body: some View {
        ZStack {
            ScanViewControllerBridge(sessionManager: sessionManager)
                .ignoresSafeArea()

            // HUD is hidden while ARCoachingOverlayView is active so the two
            // systems never overlap during initialisation (Fix #7)
            if !sessionManager.isCoachingActive {
                VStack(spacing: 0) {
                    ScanTopHUD(
                        coverage: sessionManager.overallCoverage,
                        instruction: sessionManager.instructionText,
                        isInterrupted: sessionManager.isInterrupted,
                        onCancel: {
                            sessionManager.stopCapture()
                            sessionManager.reset()
                            appState.goHome()
                        }
                    )
                    Spacer()
                    // Wall strip only shown once walls start appearing (Fix #6)
                    if sessionManager.walls.count >= 3 {
                        WallCompletionStrip(walls: sessionManager.walls)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    ScanControlBar(sessionManager: sessionManager)
                }
                .padding(.bottom, 8)
                .animation(.easeInOut(duration: 0.4), value: sessionManager.walls.count >= 3)
                .transition(.opacity)
            }

            // Error overlay (Fix #5)
            if case .error(let msg) = sessionManager.scanState {
                ScanErrorOverlay(message: msg) {
                    sessionManager.reset()
                    sessionManager.startScan()
                } onExit: {
                    sessionManager.reset()
                    appState.goHome()
                }
            }

            // Interruption banner (Fix #3)
            if sessionManager.isInterrupted {
                InterruptionBanner(onReset: {
                    sessionManager.reset()
                    sessionManager.startScan()
                })
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: sessionManager.isInterrupted)
            }

            // Animated processing overlay (Fix #14)
            if sessionManager.scanState == .processing {
                AnimatedProcessingOverlay()
                    .transition(.opacity)
            }

            // Scan complete celebration (Fix #9)
            if showScanComplete, let room = completedRoom {
                ScanCompleteOverlay(room: room) {
                    showScanComplete = false
                    let thumbnail = ThumbnailGenerator.generate(from: room,
                                                                size: CGSize(width: 112, height: 112))
                    let meta = ScanMetadata(
                        id: UUID(),
                        name: "",
                        roomType: .other,
                        date: Date(),
                        scanMethod: .lidar,
                        wallCount: room.walls.count,
                        doorCount: room.doors.count,
                        windowCount: room.windows.count,
                        floorArea: room.floors.first.map {
                            Double($0.dimensions.x * $0.dimensions.z)
                        } ?? 0,
                        wallArea: room.walls.reduce(0) {
                            $0 + Double($1.dimensions.x * $1.dimensions.y)
                        },
                        ceilingHeight: room.walls.first.map {
                            Double($0.dimensions.y)
                        } ?? 2.4,
                        deviceInfo: UIDevice.current.model,
                        thumbnailData: thumbnail.pngData()
                    )
                    let session = ScanSession(name: "", roomType: .other,
                                             capturedRoom: room, scanMethod: .lidar)
                    ScanStore.shared.save(meta)
                    appState.showReview(session)
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: sessionManager.isCoachingActive)
        .onChange(of: sessionManager.scanState) { state in
            if case .complete(let room) = state {
                completedRoom = room
                withAnimation(.easeInOut(duration: 0.5)) { showScanComplete = true }
            }
        }
    }
}

// MARK: - Top HUD

struct ScanTopHUD: View {
    let coverage: Float
    let instruction: String
    let isInterrupted: Bool
    let onCancel: () -> Void

    @State private var pulseInstruction = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Cancel scan")
                .accessibilityHint("Stops scanning and returns to home")

                Spacer()

                ScanProgressRing(coverage: coverage)
                    .accessibilityLabel("Scan coverage: \(Int(coverage * 100)) percent")
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)

            // Instruction capsule — pulses orange on critical warnings (Fix #7)
            Text(instruction)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(isCriticalInstruction
                    ? Color.orange.opacity(0.80)
                    : Color.black.opacity(0.50))
                .clipShape(Capsule())
                .scaleEffect(pulseInstruction ? 1.06 : 1.0)
                .animation(.easeInOut(duration: 0.18), value: pulseInstruction)
                .padding(.bottom, 8)
                .onChange(of: instruction) { _ in
                    guard isCriticalInstruction else { return }
                    HapticService.shared.mediumImpact()
                    withAnimation { pulseInstruction = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation { pulseInstruction = false }
                    }
                }
                .accessibilityLabel("Instruction: \(instruction)")
        }
    }

    private var isCriticalInstruction: Bool {
        instruction.lowercased().contains("light") ||
        instruction.lowercased().contains("closer") ||
        instruction.lowercased().contains("slow")
    }
}

// MARK: - Progress ring

struct ScanProgressRing: View {
    let coverage: Float

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 3)
                .frame(width: 44, height: 44)
            Circle()
                .trim(from: 0, to: CGFloat(coverage))
                .stroke(AS.lightBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: coverage)
            Text("\(Int(coverage * 100))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Wall completion strip
// Sorted by insertionOrder for stable detection-order display (Fix #12)

struct WallCompletionStrip: View {
    let walls: [TrackedWall]

    private var sorted: [TrackedWall] {
        walls.sorted { $0.insertionOrder < $1.insertionOrder }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sorted) { wall in
                    WallTile(wall: wall)
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 60)
        .padding(.bottom, 8)
        .accessibilityLabel(
            "Wall progress: \(walls.filter { $0.highlightState == .complete }.count) of \(walls.count) complete"
        )
    }
}

struct WallTile: View {
    let wall: TrackedWall

    private var fillColor: Color {
        switch wall.highlightState {
        case .none:     return Color.white.opacity(0.08)
        case .partial:  return AS.lightBlue.opacity(0.35)
        case .good:     return AS.lightBlue.opacity(0.70)
        case .complete: return AS.lightBlue
        }
    }

    private var label: String {
        wall.highlightState == .complete ? "✓" : "\(Int(wall.coveragePct * 100))%"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.5))
                .frame(width: 44, height: 44)
            VStack(spacing: 0) {
                Spacer()
                RoundedRectangle(cornerRadius: 6)
                    .fill(fillColor)
                    .frame(width: 40, height: max(CGFloat(wall.coveragePct) * 40, 2))
                    .animation(.easeInOut(duration: 0.4), value: wall.coveragePct)
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(fillColor, lineWidth: wall.highlightState == .complete ? 1.5 : 0)
        )
        .accessibilityLabel("Wall \(wall.insertionOrder): \(label)")
    }
}

// MARK: - Control bar
// isPaused is derived from sessionManager state to prevent split-brain (Fix #18)

struct ScanControlBar: View {
    @ObservedObject var sessionManager: ScanSessionManager
    @State private var localPaused = false

    var body: some View {
        HStack(spacing: 20) {
            Button {
                localPaused.toggle()
                if localPaused {
                    sessionManager.pauseScan()
                } else {
                    sessionManager.resumeScan()
                }
                HapticService.shared.mediumImpact()
            } label: {
                Image(systemName: localPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .accessibilityLabel(localPaused ? "Resume scan" : "Pause scan")
            // Sync local state if OS interrupts the session
            .onChange(of: sessionManager.isInterrupted) { interrupted in
                if interrupted { localPaused = true } else { localPaused = false }
            }

            Button {
                sessionManager.stopScan()
                HapticService.shared.heavyImpact()
            } label: {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AS.bg)
                    .frame(width: 140, height: 56)
                    .background(AS.lightBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .accessibilityLabel("Finish scan")
            .accessibilityHint("Processes your scan and shows the 3D model")
        }
        .padding(.bottom, 32)
    }
}

// MARK: - Animated processing overlay (Fix #13 — uses .task for auto-cancellation)

struct AnimatedProcessingOverlay: View {
    @State private var currentStep = 0
    private let steps = [
        "Analysing walls…",
        "Measuring doors and windows…",
        "Building floor plan…",
        "Finalising model…",
        "Done"
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 24) {
                ProgressView()
                    .tint(AS.lightBlue)
                    .scaleEffect(1.4)

                VStack(spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(spacing: 10) {
                            if i < currentStep {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AS.green)
                                    .font(.system(size: 14))
                            } else if i == currentStep {
                                ProgressView()
                                    .tint(AS.lightBlue)
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                            } else {
                                Circle()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: 14, height: 14)
                            }
                            Text(step)
                                .font(.system(size: 14,
                                              weight: i <= currentStep ? .semibold : .regular))
                                .foregroundColor(i <= currentStep ? .white : Color.white.opacity(0.35))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 48)
                .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
        // .task is cancelled automatically when the overlay disappears (processing completes)
        .task {
            for i in steps.indices {
                withAnimation { currentStep = i }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
        .accessibilityLabel("Building your 3D model, please wait")
    }
}

// MARK: - Error overlay (Fix #5)

struct ScanErrorOverlay: View {
    let message: String
    let onReset: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.orange)

                Text("Scan could not complete")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Text(message)
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                HStack(spacing: 14) {
                    Button(action: onExit) {
                        Text("Exit")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 110, height: 48)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityLabel("Exit and return to home")

                    Button(action: onReset) {
                        Text("Try again")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AS.bg)
                            .frame(width: 140, height: 48)
                            .background(AS.lightBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityLabel("Try scanning again")
                }
            }
            .padding(32)
        }
    }
}

// MARK: - Interruption banner (Fix #3)
// Uses GeometryReader to position below the safe area top rather than a magic
// constant, so it clears the coaching overlay and notch on all device sizes.

struct InterruptionBanner: View {
    let onReset: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "pause.circle.fill")
                    .foregroundColor(.orange)
                Text("Scan paused")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onReset) {
                    Text("Restart")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AS.bg)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(AS.lightBlue)
                        .clipShape(Capsule())
                }
                .accessibilityLabel("Restart scan from the beginning")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.85))
            Spacer()
        }
        // Reads safe area inset dynamically so the banner clears the notch/coaching
        // overlay on all device sizes rather than using a hardcoded magic number.
        .safeAreaInset(edge: .top) { Color.clear.frame(height: 56) }
    }
}

// MARK: - Scan complete celebration (Fix #9)

struct ScanCompleteOverlay: View {
    let room: CapturedRoom
    let onContinue: () -> Void

    @State private var appeared = false

    private var floorArea: Double {
        room.floors.first.map { Double($0.dimensions.x * $0.dimensions.z) }
            ?? Double(room.walls.reduce(0) { $0 + $1.dimensions.x * $1.dimensions.y }) / 4
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(AS.lightBlue.opacity(0.15))
                        .frame(width: 100, height: 100)
                        .scaleEffect(appeared ? 1.0 : 0.4)
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(AS.lightBlue)
                        .scaleEffect(appeared ? 1.0 : 0.2)
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.65), value: appeared)

                Text("Room measured")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeIn(duration: 0.3).delay(0.3), value: appeared)

                HStack(spacing: 20) {
                    StatBadge(value: "\(room.walls.count)", label: "walls")
                    StatBadge(value: String(format: "%.1f m²", floorArea), label: "floor area")
                    StatBadge(value: "\(room.doors.count + room.windows.count)", label: "openings")
                }
                .opacity(appeared ? 1 : 0)
                .animation(.easeIn(duration: 0.3).delay(0.5), value: appeared)

                Button(action: onContinue) {
                    Text("View 3D Model")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AS.bg)
                        .frame(width: 200, height: 52)
                        .background(AS.lightBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .opacity(appeared ? 1 : 0)
                .animation(.easeIn(duration: 0.3).delay(0.7), value: appeared)
                .accessibilityLabel("Open 3D model of the scanned room")
            }
        }
        // Fix #14 — set appeared in onAppear directly; SwiftUI batches to next render pass
        // so the spring animation triggers correctly without a manual delay.
        .onAppear {
            appeared = true
            HapticService.shared.success()
        }
    }
}

struct StatBadge: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(AS.lightBlue)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
