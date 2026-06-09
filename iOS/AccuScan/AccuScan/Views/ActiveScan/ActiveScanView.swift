import SwiftUI
import RoomPlan
import RealityKit
import UIKit

// MARK: - ActiveScanView
// Mirrors AccuQuote's scan UX: Face-ID coverage ring, glass-card HUD,
// tutorial overlay on first use, pulsing status pill, instruction text.

struct ActiveScanView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var sessionManager = ScanSessionManager()

    @State private var showScanComplete = false
    @State private var completedRoom: CapturedRoom?

    // Tutorial overlay — shown once, dismissed on tap or after 3s
    @State private var showTutorial = !UserDefaults.standard.bool(forKey: "accuscan_tutorial_seen")

    var body: some View {
        ZStack {
            ScanViewControllerBridge(sessionManager: sessionManager)
                .ignoresSafeArea()

            // ── Main scan HUD ─────────────────────────────────────────────
            // Hidden while coaching overlay is active (Apple AR HIG compliance)
            if !sessionManager.isCoachingActive {
                VStack(spacing: 0) {
                    // Top: cancel button + status pill
                    ScanTopBar(
                        onCancel: {
                            sessionManager.stopCapture()
                            sessionManager.reset()
                            appState.goHome()
                        },
                        isInterrupted: sessionManager.isInterrupted
                    )

                    Spacer()

                    // Instruction text above ring
                    Text(sessionManager.instructionText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 16)
                        .onChange(of: sessionManager.instructionText) { _ in
                            // Pulse haptic on critical instructions (matches AccuQuote)
                            let txt = sessionManager.instructionText.lowercased()
                            if txt.contains("light") || txt.contains("closer") || txt.contains("slow") {
                                HapticService.shared.mediumImpact()
                            }
                        }

                    // Face-ID coverage ring — matches AccuQuote exactly
                    CoverageRingView(
                        sectors:    sessionManager.coverageTracker.sectors,
                        coverage:   sessionManager.coverageTracker.coverage,
                        isComplete: sessionManager.coverageTracker.isComplete
                    )
                    .padding(.bottom, 20)

                    // Glass-card HUD with wall strip + done button
                    ScanGlassHUD(sessionManager: sessionManager)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 48)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: sessionManager.isCoachingActive)
            }

            // ── Interruption banner ───────────────────────────────────────
            if sessionManager.isInterrupted {
                InterruptionBanner(onReset: {
                    sessionManager.reset()
                    sessionManager.startScan()
                })
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: sessionManager.isInterrupted)
            }

            // ── Error overlay ─────────────────────────────────────────────
            if case .error(let msg) = sessionManager.scanState {
                ScanErrorOverlay(message: msg) {
                    sessionManager.reset()
                    sessionManager.startScan()
                } onExit: {
                    sessionManager.reset()
                    appState.goHome()
                }
            }

            // ── Processing overlay ────────────────────────────────────────
            if sessionManager.scanState == .processing {
                AnimatedProcessingOverlay()
                    .transition(.opacity)
            }

            // ── Scan complete celebration ─────────────────────────────────
            if showScanComplete, let room = completedRoom {
                ScanCompleteOverlay(room: room) {
                    showScanComplete = false
                    let thumbnail = ThumbnailGenerator.generate(from: room,
                                                                size: CGSize(width: 112, height: 112))
                    // #20: preserve the room name + type the user entered in setup
                    let roomName = appState.pendingRoomName
                    let roomType = appState.pendingRoomType
                    let meta = ScanMetadata(
                        id: UUID(),
                        name: roomName,
                        roomType: roomType,
                        date: Date(),
                        scanMethod: .lidar,
                        wallCount:    room.walls.count,
                        doorCount:    room.doors.count,
                        windowCount:  room.windows.count,
                        floorArea:    room.floors.first.map {
                            Double($0.dimensions.x * $0.dimensions.z)
                        } ?? 0,
                        wallArea:     room.walls.reduce(0) {
                            $0 + Double($1.dimensions.x * $1.dimensions.y)
                        },
                        ceilingHeight: room.walls.first.map {
                            Double($0.dimensions.y)
                        } ?? 2.4,
                        deviceInfo:   UIDevice.current.model,
                        thumbnailData: thumbnail.pngData()
                    )
                    let session = ScanSession(name: roomName, roomType: roomType,
                                             capturedRoom: room, scanMethod: .lidar)
                    ScanStore.shared.save(meta)
                    appState.showReview(session)
                }
                .transition(.opacity)
            }

            // ── First-use tutorial overlay (mirrors AccuQuote) ────────────
            if showTutorial {
                ScanTutorialOverlay {
                    withAnimation(.easeOut(duration: 0.3)) { showTutorial = false }
                    UserDefaults.standard.set(true, forKey: "accuscan_tutorial_seen")
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: showTutorial)
            }
        }
        .ignoresSafeArea()
        .onChange(of: sessionManager.scanState) { state in
            if case .complete(let room) = state {
                completedRoom = room
                withAnimation(.easeInOut(duration: 0.5)) { showScanComplete = true }
            }
        }
    }
}

// MARK: - Top bar (cancel + pulsing status pill)

private struct ScanTopBar: View {
    let onCancel: () -> Void
    let isInterrupted: Bool

    @State private var pulsing = false
    // Matches AccuQuote's vivid scan blue
    private let scanBlue = Color(red: 0.20, green: 0.60, blue: 1.00)

    var body: some View {
        HStack {
            // Pulsing "Scanning" status pill — identical to AccuQuote
            HStack(spacing: 7) {
                Circle()
                    .fill(scanBlue)
                    .frame(width: 9, height: 9)
                    .shadow(color: scanBlue.opacity(pulsing ? 0.9 : 0.2), radius: pulsing ? 8 : 2)
                    .scaleEffect(pulsing ? 1.35 : 0.85)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                               value: pulsing)
                Text(isInterrupted ? "Paused" : "Scanning")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(pulsing ? 1.0 : 0.55)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                               value: pulsing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(scanBlue.opacity(pulsing ? 0.28 : 0.12))
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)
            .cornerRadius(22)
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(scanBlue.opacity(0.5), lineWidth: 1))
            .onAppear { pulsing = true }

            Spacer()

            // Cancel button
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Cancel scan")
            .accessibilityHint("Stops scanning and returns to home")
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }
}

// MARK: - Glass HUD card (wall strip + done button)
// Matches AccuQuote's ScanHUD card aesthetic with glass material background.

private struct ScanGlassHUD: View {
    @ObservedObject var sessionManager: ScanSessionManager
    @State private var localPaused = false

    var body: some View {
        VStack(spacing: 14) {
            // Wall completion strip — only shown once walls detected (Fix #6 / HIG)
            if sessionManager.walls.count >= 3 {
                WallCompletionStrip(walls: sessionManager.walls)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.4), value: sessionManager.walls.count)
            }

            // Controls row
            HStack(spacing: 14) {
                // Pause / resume
                Button {
                    localPaused.toggle()
                    if localPaused { sessionManager.pauseScan() } else { sessionManager.resumeScan() }
                    HapticService.shared.mediumImpact()
                } label: {
                    Image(systemName: localPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .accessibilityLabel(localPaused ? "Resume scan" : "Pause scan")
                .onChange(of: sessionManager.isInterrupted) { interrupted in
                    localPaused = interrupted
                }

                // Done — enabled immediately but fades in fully at 80%+ coverage (AccuQuote pattern)
                Button {
                    sessionManager.stopScan()
                    HapticService.shared.heavyImpact()
                } label: {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AS.bg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AS.lightBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .opacity(sessionManager.coverageTracker.coverage >= 0.80 ? 1.0 : 0.55)
                .accessibilityLabel("Finish scan")
                .accessibilityHint("Processes your scan and shows the 3D model")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.55))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        )
    }
}

// MARK: - Tutorial overlay (first-use, mirrors AccuQuote's ScanTutorialAnimation)

private struct ScanTutorialOverlay: View {
    let onDismiss: () -> Void

    @State private var sweepOffset: CGFloat = -40
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 28) {
                // Animated phone sweep — identical to AccuQuote
                ZStack {
                    ForEach(0..<3) { i in
                        Capsule()
                            .fill(Color.white.opacity(0.15 - Double(i) * 0.04))
                            .frame(width: 3, height: 40 + CGFloat(i) * 16)
                            .offset(x: sweepOffset + CGFloat(i) * 6)
                            .animation(
                                .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.08),
                                value: sweepOffset
                            )
                    }
                    Image(systemName: "iphone")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(90))
                        .offset(x: sweepOffset)
                        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                                   value: sweepOffset)
                }
                .frame(width: 160, height: 100)

                VStack(spacing: 8) {
                    Text("Move around the room")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                        Text("Cover every wall, ceiling and floor")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Text("Tap anywhere to start")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
            .opacity(opacity)
            .padding(.bottom, 140)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.4)) { opacity = 1 }
            sweepOffset = 40
            // Auto-dismiss after 3s
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { onDismiss() }
        }
        .onTapGesture { onDismiss() }
    }
}

// MARK: - Wall completion strip (unchanged — only shown ≥3 walls)

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
            .padding(.horizontal, 4)
        }
        .frame(height: 52)
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

// MARK: - Error overlay

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

// MARK: - Interruption banner

struct InterruptionBanner: View {
    let onReset: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "pause.circle.fill").foregroundColor(.orange)
                Text("Scan paused")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onReset) {
                    Text("Restart")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AS.bg)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(AS.lightBlue)
                        .clipShape(Capsule())
                }
                .accessibilityLabel("Restart scan from the beginning")
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Color.black.opacity(0.85))
            Spacer()
        }
        .safeAreaInset(edge: .top) { Color.clear.frame(height: 56) }
    }
}

// MARK: - Animated processing overlay (step checklist — AccuScan's is better than AccuQuote's here)

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
                ProgressView().tint(AS.lightBlue).scaleEffect(1.4)
                VStack(spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(spacing: 10) {
                            if i < currentStep {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AS.green).font(.system(size: 14))
                            } else if i == currentStep {
                                ProgressView().tint(AS.lightBlue).scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                            } else {
                                Circle().fill(Color.white.opacity(0.15))
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
        .task {
            for i in steps.indices {
                withAnimation { currentStep = i }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
        .accessibilityLabel("Building your 3D model, please wait")
    }
}

// MARK: - Scan complete celebration

struct ScanCompleteOverlay: View {
    let room: CapturedRoom
    let onContinue: () -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion   // #11

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
                        .accessibilityHidden(true)
                }
                // #11 respect Reduce Motion — no spring bounce when enabled
                .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.65), value: appeared)

                Text("Room measured")
                    .font(.title2.weight(.bold))   // #1
                    .foregroundColor(.white)
                    .opacity(appeared ? 1 : 0)
                    .animation(reduceMotion ? .none : .easeIn(duration: 0.3).delay(0.3), value: appeared)

                HStack(spacing: 20) {
                    StatBadge(value: "\(room.walls.count)",  label: "walls")
                    StatBadge(value: String(format: "%.1f m²", floorArea), label: "floor area")
                    StatBadge(value: "\(room.doors.count + room.windows.count)", label: "openings")
                }
                .opacity(appeared ? 1 : 0)
                .animation(reduceMotion ? .none : .easeIn(duration: 0.3).delay(0.5), value: appeared)

                Button(action: onContinue) {
                    Text("View 3D Model")
                        .font(.headline)   // #1
                        .foregroundColor(AS.bg)
                        .frame(width: 200, height: 52)
                        .background(AS.lightBlue)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))   // #17
                }
                .buttonStyle(ScaleButtonStyle())   // #15
                .opacity(appeared ? 1 : 0)
                .animation(reduceMotion ? .none : .easeIn(duration: 0.3).delay(0.7), value: appeared)
                .accessibilityLabel("Open 3D model of the scanned room")
            }
        }
        // #18 success haptic via sensoryFeedback (declarative, respects user settings)
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            appeared = true
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
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
