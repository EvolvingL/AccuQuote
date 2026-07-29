import { useState } from "react";

const BG  = "#07080A";
const S1  = "#0C0E13";
const S2  = "#111720";
const S3  = "#1A2232";
const S4  = "#222E40";
const T   = "#EEE9DF";
const M   = "#5A6A7E";
const Y   = "#FFD600";
const O   = "#FF6B00";
const GR  = "#22C55E";
const BL  = "#3B82F6";
const TE  = "#14B8A6";
const PU  = "#A855F7";
const RD  = "#EF4444";
const DIM = "#2A3548";
const LB  = "#7DD3FC"; // light blue — the scan highlight colour

const BLOCKS = [
  {
    id: "overview",
    num: "00",
    title: "Project Overview & Tech Stack",
    icon: "🏗️",
    color: Y,
    sections: [
      {
        title: "App Identity",
        code: false,
        body: `NAME: AccuScan
BUNDLE ID: com.slickdigital.accuscan
DEPLOYMENT TARGET: iOS 17.0+
SUPPORTED DEVICES: iPhone only (iPad optional v2)
ORIENTATION: Portrait only during scan, all orientations in review

LIDAR REQUIREMENT:
LiDAR Scanner present on: iPhone 12 Pro, 13 Pro, 14 Pro, 15 Pro, 16 Pro and all Pro Max variants.
Non-LiDAR fallback: ARKit ARWorldTrackingConfiguration with scene depth (A14+ chip required for decent results).
Graceful degradation: Manual dimension entry UI for very old devices.

The app must detect LiDAR availability at runtime:
  ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
If false → show fallback flow, never crash or show an error screen.`
      },
      {
        title: "Framework Stack",
        code: true,
        body: `// PRIMARY FRAMEWORKS
import RoomPlan          // Apple's room scanning API — handles LiDAR + room understanding
import ARKit             // Underlying AR session management
import RealityKit        // 3D rendering, AR overlays, wall highlight entities
import SceneKit          // Floor plan rendering, 2D projection
import CoreData          // Scan persistence
import PDFKit            // Floor plan + dimension sheet PDF export
import ModelIO           // USDZ / OBJ 3D model manipulation
import AVFoundation      // Camera session management
import CoreMotion        // Device orientation during scan
import CloudKit          // iCloud sync (Phase 2)

// UI FRAMEWORK
import SwiftUI           // All views — NO UIKit except bridging where required

// APPLE NATIVE (no third-party dependencies)
// The entire app ships with zero third-party packages.
// This keeps the binary small and removes supply chain risk.`
      },
      {
        title: "Project File Structure",
        code: true,
        body: `AccuScan.xcodeproj
│
├── App/
│   ├── AccuScanApp.swift           // @main — sets up CoreData stack + CloudKit
│   └── AppState.swift              // @StateObject root — navigation + global state
│
├── Models/
│   ├── ScanSession.swift           // CoreData entity — one scan session
│   ├── CapturedWall.swift          // Decoded from RoomPlan CapturedRoom.Wall
│   ├── CapturedRoom+Extensions.swift // Helpers on Apple's CapturedRoom type
│   ├── FloorPlan.swift             // Generated from walls array — 2D model
│   ├── DimensionSheet.swift        // Structured dimensions for export
│   └── ScanMetadata.swift          // Room type, name, date, device info
│
├── Scanning/
│   ├── ScanViewController.swift    // UIViewController hosting RoomCaptureView
│   ├── ScanViewControllerBridge.swift // UIViewControllerRepresentable
│   ├── ScanSessionManager.swift    // RoomCaptureSession delegate + state machine
│   ├── WallCoverageTracker.swift   // Tracks per-wall scan confidence + highlight state
│   ├── ScanFallbackController.swift // ARKit fallback for non-LiDAR devices
│   └── ManualEntryController.swift // Pure manual dimension entry (oldest devices)
│
├── AROverlays/
│   ├── WallHighlightEntity.swift   // RealityKit entity — light blue wall edge glow
│   ├── CornerAnchorEntity.swift    // Pulsing corner markers as walls complete
│   ├── DimensionLabelEntity.swift  // AR dimension labels floating on walls
│   ├── ScanProgressOverlay.swift   // SwiftUI overlay showing coverage %
│   └── CoachingOverlayView.swift   // "Scan this area" directional hints
│
├── Views/
│   ├── Home/
│   │   ├── HomeView.swift          // Scan history list
│   │   ├── ScanCardView.swift      // Individual scan card with thumbnail
│   │   └── EmptyStateView.swift
│   │
│   ├── ScanSetup/
│   │   ├── ScanSetupView.swift     // Room type + name entry before scanning
│   │   └── DeviceCapabilityView.swift // Explains LiDAR vs fallback to user
│   │
│   ├── ActiveScan/
│   │   ├── ActiveScanView.swift    // Main scanning screen
│   │   ├── ScanControlBar.swift    // Start / pause / stop controls
│   │   ├── WallCoverageHUD.swift   // Real-time coverage feedback UI
│   │   └── ScanProgressRing.swift  // Circular progress for overall coverage
│   │
│   ├── Review/
│   │   ├── ScanReviewView.swift    // Post-scan tabbed review
│   │   ├── ModelViewer3D.swift     // Interactive 3D model viewer
│   │   ├── FloorPlanView.swift     // 2D floor plan with dimensions
│   │   ├── DimensionTableView.swift // All measurements in table format
│   │   └── EditDimensionsView.swift // Manual override of any measurement
│   │
│   └── Export/
│       ├── ExportView.swift        // Choose format + share
│       ├── USDZExporter.swift      // 3D model USDZ export
│       ├── OBJExporter.swift       // 3D model OBJ export
│       ├── DXFExporter.swift       // Floor plan DXF for CAD software
│       ├── PDFExporter.swift       // Floor plan + dimensions PDF
│       └── CSVExporter.swift       // Raw dimensions CSV
│
├── Services/
│   ├── CoreDataStack.swift         // NSPersistentCloudKitContainer setup
│   ├── ThumbnailGenerator.swift    // Generates floor plan thumbnail for home list
│   └── HapticService.swift         // Haptic feedback throughout
│
├── Resources/
│   ├── Assets.xcassets
│   ├── AccuScan.entitlements       // iCloud, camera, microphone
│   └── Info.plist                  // All privacy strings
│
└── Preview Content/
    └── SampleScan.swift            // Mock data for SwiftUI previews`
      },
      {
        title: "Info.plist — Required Entries",
        code: true,
        body: `<!-- All required privacy strings — Apple rejects without these -->

<key>NSCameraUsageDescription</key>
<string>AccuScan uses your camera to scan and measure rooms using LiDAR and computer vision.</string>

<key>NSMicrophoneUsageDescription</key>
<string>AccuScan may capture ambient audio during scanning sessions for room acoustic analysis.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>AccuScan can save your floor plans and 3D models to your photo library.</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>AccuScan saves generated floor plans to your photo library.</string>

<!-- ARKit requirement — devices without ARKit cannot install -->
<key>UIRequiredDeviceCapabilities</key>
<array>
  <string>arkit</string>
</array>

<!-- iCloud for scan sync -->
<key>com.apple.developer.icloud-services</key>
<array>
  <string>CloudKit</string>
</array>`
      },
    ]
  },
  {
    id: "scanning",
    num: "01",
    title: "The Scanning Engine",
    icon: "📡",
    color: TE,
    sections: [
      {
        title: "ScanSessionManager — The Core State Machine",
        code: true,
        body: `// ScanSessionManager.swift
// Central coordinator between RoomPlan session, wall tracker, and UI
// All UI updates dispatched to MainActor

import RoomPlan
import ARKit
import Combine

@MainActor
class ScanSessionManager: NSObject, ObservableObject {

    // MARK: - Published State (drives all UI)
    @Published var scanState: ScanState = .idle
    @Published var capturedRoom: CapturedRoom?
    @Published var walls: [TrackedWall] = []
    @Published var overallCoverage: Float = 0.0      // 0.0 → 1.0
    @Published var instructionText: String = "Move slowly around the room"
    @Published var errorMessage: String?

    // MARK: - RoomPlan Objects
    private var captureSession: RoomCaptureSession!
    private(set) var captureView: RoomCaptureView!
    private let wallTracker = WallCoverageTracker()

    // MARK: - State Enum
    enum ScanState {
        case idle
        case preparing      // Camera starting
        case scanning       // Active scan in progress
        case processing     // RoomPlan post-processing
        case complete       // CapturedRoom ready
        case error(String)
    }

    // MARK: - Setup
    func setupCaptureView() -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.captureSession.delegate = self
        view.delegate = self
        self.captureView = view
        self.captureSession = view.captureSession
        return view
    }

    // MARK: - Controls
    func startScan() {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            scanState = .error("LiDAR not available on this device")
            return
        }
        scanState = .scanning
        let config = RoomCaptureSession.Configuration()
        captureSession.run(configuration: config)
    }

    func stopScan() {
        captureSession.stop()
        scanState = .processing
    }

    func pauseScan() {
        captureSession.stop()
    }

    func resumeScan() {
        let config = RoomCaptureSession.Configuration()
        captureSession.run(configuration: config)
    }
}

// MARK: - RoomCaptureSessionDelegate
extension ScanSessionManager: RoomCaptureSessionDelegate {

    // Called continuously as room is scanned — update coverage in real time
    func captureSession(_ session: RoomCaptureSession,
                        didUpdate room: CapturedRoom) {
        // Update tracked walls with new confidence data
        walls = wallTracker.update(from: room)

        // Calculate overall coverage (weighted by wall area)
        overallCoverage = wallTracker.calculateOverallCoverage()

        // Update coaching instruction based on what's missing
        instructionText = wallTracker.nextInstruction(for: room)
    }

    // Called on error
    func captureSession(_ session: RoomCaptureSession,
                        didProvide instruction: RoomCaptureSession.Instruction) {
        switch instruction {
        case .moveCloseToWall:    instructionText = "Move closer to the walls"
        case .moveAwayFromWall:   instructionText = "Step back a little"
        case .slowDown:           instructionText = "Slow down — keep it steady"
        case .turnOnLight:        instructionText = "More light needed"
        case .normal:             instructionText = "Keep scanning…"
        default:                  break
        }
    }
}

// MARK: - RoomCaptureViewDelegate
extension ScanSessionManager: RoomCaptureViewDelegate {

    // User tapped Done button — RoomPlan processes and returns final room
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                     error: Error?) -> Bool {
        return error == nil
    }

    func captureView(didPresent processedResult: CapturedRoom,
                     error: Error?) {
        if let error = error {
            scanState = .error(error.localizedDescription)
            return
        }
        capturedRoom = processedResult
        scanState = .complete
    }
}`
      },
      {
        title: "TrackedWall — Per-Wall Coverage Model",
        code: true,
        body: `// WallCoverageTracker.swift
// Tracks which walls have been scanned and to what confidence level.
// This data drives the light blue highlight overlay system.

import RoomPlan
import simd

// The state of a single detected wall
struct TrackedWall: Identifiable {
    let id: UUID
    let roomPlanWall: CapturedRoom.Wall  // Original RoomPlan wall
    var confidence: CapturedRoom.Confidence
    var highlightState: HighlightState
    var coveragePct: Float               // 0.0 → 1.0
    var worldPosition: simd_float3       // Centre of wall in world space
    var worldSize: simd_float3           // Width, height, depth
    var worldTransform: simd_float4x4    // Full transform for overlay placement

    // Corner positions in world space (for corner highlight entities)
    var topLeftCorner: simd_float3
    var topRightCorner: simd_float3
    var bottomLeftCorner: simd_float3
    var bottomRightCorner: simd_float3

    enum HighlightState {
        case none           // Not yet detected
        case partial        // Low confidence — dim blue
        case good           // Medium confidence — medium blue
        case complete       // High confidence — bright light blue pulse then settle
    }
}

class WallCoverageTracker {

    private var trackedWalls: [UUID: TrackedWall] = [:]

    // Called every time RoomPlan emits an updated CapturedRoom
    func update(from room: CapturedRoom) -> [TrackedWall] {
        for wall in room.walls {
            let wallID = UUID()  // RoomPlan walls don't have stable IDs — match by position
            let existingKey = findExisting(wall: wall) ?? wallID

            let state = highlightState(for: wall.confidence)
            let corners = extractCorners(wall: wall)

            trackedWalls[existingKey] = TrackedWall(
                id: existingKey,
                roomPlanWall: wall,
                confidence: wall.confidence,
                highlightState: state,
                coveragePct: coveragePercent(for: wall.confidence),
                worldPosition: simd_float3(wall.transform.columns.3.x,
                                           wall.transform.columns.3.y,
                                           wall.transform.columns.3.z),
                worldSize: simd_float3(wall.dimensions.x, wall.dimensions.y, 0.1),
                worldTransform: wall.transform,
                topLeftCorner: corners.topLeft,
                topRightCorner: corners.topRight,
                bottomLeftCorner: corners.bottomLeft,
                bottomRightCorner: corners.bottomRight
            )
        }
        return Array(trackedWalls.values)
    }

    func calculateOverallCoverage() -> Float {
        guard !trackedWalls.isEmpty else { return 0 }
        let totalArea = trackedWalls.values.reduce(0.0) { acc, w in
            acc + Double(w.worldSize.x * w.worldSize.y)
        }
        let coveredArea = trackedWalls.values.reduce(0.0) { acc, w in
            acc + Double(w.worldSize.x * w.worldSize.y) * Double(w.coveragePct)
        }
        return Float(coveredArea / max(totalArea, 1))
    }

    func nextInstruction(for room: CapturedRoom) -> String {
        let incompleteWalls = trackedWalls.values.filter { $0.confidence == .low }
        if incompleteWalls.isEmpty { return "Looking good — scan corners to finish" }
        if trackedWalls.count < 3 { return "Move slowly around the whole room" }
        return "Scan remaining walls until they glow blue"
    }

    // MARK: - Helpers
    private func highlightState(for confidence: CapturedRoom.Confidence) -> TrackedWall.HighlightState {
        switch confidence {
        case .low:    return .partial
        case .medium: return .good
        case .high:   return .complete
        @unknown default: return .none
        }
    }

    private func coveragePercent(for confidence: CapturedRoom.Confidence) -> Float {
        switch confidence {
        case .low:    return 0.25
        case .medium: return 0.65
        case .high:   return 1.0
        @unknown default: return 0.0
        }
    }

    private func extractCorners(wall: CapturedRoom.Wall) -> (topLeft: simd_float3, topRight: simd_float3, bottomLeft: simd_float3, bottomRight: simd_float3) {
        let w = wall.dimensions.x / 2
        let h = wall.dimensions.y / 2
        let transform = wall.transform

        func transformPoint(_ local: simd_float4) -> simd_float3 {
            let world = transform * local
            return simd_float3(world.x, world.y, world.z)
        }

        return (
            topLeft:     transformPoint(simd_float4(-w,  h, 0, 1)),
            topRight:    transformPoint(simd_float4( w,  h, 0, 1)),
            bottomLeft:  transformPoint(simd_float4(-w, -h, 0, 1)),
            bottomRight: transformPoint(simd_float4( w, -h, 0, 1))
        )
    }

    private func findExisting(wall: CapturedRoom.Wall) -> UUID? {
        // Match by proximity — walls within 15cm of known position are the same wall
        let pos = simd_float3(wall.transform.columns.3.x,
                              wall.transform.columns.3.y,
                              wall.transform.columns.3.z)
        return trackedWalls.first { _, tracked in
            simd_distance(tracked.worldPosition, pos) < 0.15
        }?.key
    }
}`
      },
    ]
  },
  {
    id: "highlights",
    num: "02",
    title: "Wall Highlight System",
    icon: "💡",
    color: LB,
    sections: [
      {
        title: "WallHighlightEntity — The Light Blue Glow",
        code: true,
        body: `// WallHighlightEntity.swift
// RealityKit entity placed on each detected wall.
// Shows light blue edge highlights at all four wall corners,
// plus a subtle face glow as confidence increases.
// This is the centrepiece visual feedback of the scanning experience.

import RealityKit
import ARKit
import simd

class WallHighlightEntity: Entity, HasModel, HasAnchoring {

    // MARK: - The four corner glow bars
    // Each wall shows highlights at: top-left edge, top-right edge,
    // bottom-left edge, bottom-right edge — all in light blue (#7DD3FC)
    // They animate from invisible → dim → bright as confidence increases

    private var topLeftBar:     ModelEntity!
    private var topRightBar:    ModelEntity!
    private var bottomLeftBar:  ModelEntity!
    private var bottomRightBar: ModelEntity!
    private var faceMesh:       ModelEntity!  // Full-wall subtle glow

    // Colours
    static let lightBlue    = UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 1.0) // #7DD3FC
    static let lightBlueDim = UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 0.25)
    static let lightBlueMid = UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 0.55)

    // MARK: - Init
    required init() { super.init() }

    static func make(for wall: TrackedWall) -> WallHighlightEntity {
        let entity = WallHighlightEntity()
        entity.configure(wall: wall)
        return entity
    }

    // MARK: - Configuration
    func configure(wall: TrackedWall) {
        let w = wall.worldSize.x   // wall width in metres
        let h = wall.worldSize.y   // wall height in metres
        let barThickness: Float = 0.025  // 2.5cm thick highlight bars
        let barLength: Float = min(0.35, w * 0.25)  // Length of corner bar (max 35cm)
        let barHeight: Float = min(0.35, h * 0.25)

        // Remove existing children
        children.forEach { $0.removeFromParent() }

        // Create the four corner L-shaped highlights
        // Each corner = one horizontal bar + one vertical bar

        // TOP-LEFT CORNER
        let tlH = makeBar(size: [barLength, barThickness, barThickness],
                          color: Self.lightBlueDim)
        let tlV = makeBar(size: [barThickness, barHeight, barThickness],
                          color: Self.lightBlueDim)
        tlH.position = [-w/2 + barLength/2, h/2, 0.01]
        tlV.position = [-w/2, h/2 - barHeight/2, 0.01]
        addChild(tlH); addChild(tlV)

        // TOP-RIGHT CORNER
        let trH = makeBar(size: [barLength, barThickness, barThickness],
                          color: Self.lightBlueDim)
        let trV = makeBar(size: [barThickness, barHeight, barThickness],
                          color: Self.lightBlueDim)
        trH.position = [w/2 - barLength/2, h/2, 0.01]
        trV.position = [w/2, h/2 - barHeight/2, 0.01]
        addChild(trH); addChild(trV)

        // BOTTOM-LEFT CORNER
        let blH = makeBar(size: [barLength, barThickness, barThickness],
                          color: Self.lightBlueDim)
        let blV = makeBar(size: [barThickness, barHeight, barThickness],
                          color: Self.lightBlueDim)
        blH.position = [-w/2 + barLength/2, -h/2, 0.01]
        blV.position = [-w/2, -h/2 + barHeight/2, 0.01]
        addChild(blH); addChild(blV)

        // BOTTOM-RIGHT CORNER
        let brH = makeBar(size: [barLength, barThickness, barThickness],
                          color: Self.lightBlueDim)
        let brV = makeBar(size: [barThickness, barHeight, barThickness],
                          color: Self.lightBlueDim)
        brH.position = [w/2 - barLength/2, -h/2, 0.01]
        brV.position = [w/2, -h/2 + barHeight/2, 0.01]
        addChild(brH); addChild(brV)

        // FACE GLOW — full wall semi-transparent blue overlay
        let faceMaterial = UnlitMaterial(color: UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 0.04))
        let faceMesh = ModelEntity(mesh: .generatePlane(width: w * 0.96, height: h * 0.96),
                                   materials: [faceMaterial])
        faceMesh.position = [0, 0, 0.005]
        addChild(faceMesh)
        self.faceMesh = faceMesh

        // Set world transform
        self.transform = Transform(matrix: wall.worldTransform)

        // Animate to current state
        update(to: wall.highlightState, animated: false)
    }

    // MARK: - State Updates (called every RoomPlan update)
    func update(to state: TrackedWall.HighlightState, animated: Bool = true) {
        let targetAlpha: Float
        let targetFaceAlpha: Float
        let shouldPulse: Bool

        switch state {
        case .none:
            targetAlpha = 0.0;     targetFaceAlpha = 0.0;    shouldPulse = false
        case .partial:
            targetAlpha = 0.35;    targetFaceAlpha = 0.03;   shouldPulse = false
        case .good:
            targetAlpha = 0.70;    targetFaceAlpha = 0.07;   shouldPulse = false
        case .complete:
            targetAlpha = 1.0;     targetFaceAlpha = 0.12;   shouldPulse = true
        }

        if animated {
            // Animate opacity change over 0.3s
            var transform = self.transform
            // RealityKit opacity animation via custom component
            animateOpacity(to: targetAlpha, duration: 0.3)
        }

        if shouldPulse {
            startPulseAnimation()
            HapticService.shared.lightImpact()  // Haptic when wall completes
        }
    }

    // MARK: - Pulse animation (plays once when wall reaches .complete)
    private func startPulseAnimation() {
        // Scale up slightly then back — confirms wall completion to user
        let scaleUp   = Transform(scale: .init(repeating: 1.04))
        let scaleDown = Transform(scale: .init(repeating: 1.0))
        move(to: scaleUp,   relativeTo: parent, duration: 0.15, timingFunction: .easeOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.move(to: scaleDown, relativeTo: self?.parent, duration: 0.15, timingFunction: .easeIn)
        }
    }

    // MARK: - Helpers
    private func makeBar(size: SIMD3<Float>, color: UIColor) -> ModelEntity {
        let material = UnlitMaterial(color: color)
        return ModelEntity(mesh: .generateBox(size: size, cornerRadius: 0.008),
                           materials: [material])
    }

    private func animateOpacity(to alpha: Float, duration: TimeInterval) {
        // Update all child materials — simplified; production uses custom AnimationComponent
        for child in children {
            if var model = child as? ModelEntity {
                // Update material opacity — implement via UnlitMaterial colour alpha
            }
        }
    }
}`
      },
      {
        title: "AR Overlay Coordinator — Placing Entities in the Scene",
        code: true,
        body: `// ActiveScanView.swift (key AR overlay management section)
// Manages the RealityKit scene and keeps highlight entities
// in sync with WallCoverageTracker updates

import SwiftUI
import RealityKit
import ARKit

struct ActiveScanView: View {
    @ObservedObject var sessionManager: ScanSessionManager
    @StateObject private var overlayCoordinator = AROverlayCoordinator()

    var body: some View {
        ZStack {
            // 1. RoomCaptureView — the live camera + RoomPlan wireframe
            ScanViewControllerBridge(sessionManager: sessionManager)
                .ignoresSafeArea()

            // 2. SwiftUI HUD overlays
            VStack {
                // Top HUD — coverage + instructions
                ScanTopHUD(
                    coverage: sessionManager.overallCoverage,
                    instruction: sessionManager.instructionText
                )
                Spacer()
                // Bottom HUD — wall-by-wall completion indicators
                WallCompletionStrip(walls: sessionManager.walls)
                // Control bar — pause / stop
                ScanControlBar(sessionManager: sessionManager)
            }
            .padding()
        }
        .onChange(of: sessionManager.walls) { newWalls in
            // Keep AR highlight entities in sync
            overlayCoordinator.sync(walls: newWalls)
        }
    }
}

// Manages WallHighlightEntity lifecycle in the RealityKit scene
class AROverlayCoordinator: ObservableObject {
    private var arView: ARView?
    private var highlightEntities: [UUID: WallHighlightEntity] = [:]
    private var anchorEntities:    [UUID: AnchorEntity] = [:]

    func setARView(_ view: ARView) {
        self.arView = view
    }

    func sync(walls: [TrackedWall]) {
        guard let arView = arView else { return }

        for wall in walls {
            if let existing = highlightEntities[wall.id] {
                // Update existing entity
                existing.update(to: wall.highlightState, animated: true)
                // Update transform if wall position refined
                existing.transform = Transform(matrix: wall.worldTransform)
            } else {
                // Create new entity for newly detected wall
                let anchor = AnchorEntity(world: wall.worldTransform)
                let highlight = WallHighlightEntity.make(for: wall)
                anchor.addChild(highlight)
                arView.scene.addAnchor(anchor)
                highlightEntities[wall.id] = highlight
                anchorEntities[wall.id] = anchor
            }
        }

        // Remove entities for walls no longer detected
        let activeIDs = Set(walls.map { $0.id })
        for id in highlightEntities.keys where !activeIDs.contains(id) {
            anchorEntities[id]?.removeFromParent()
            highlightEntities.removeValue(forKey: id)
            anchorEntities.removeValue(forKey: id)
        }
    }
}`
      },
      {
        title: "WallCompletionStrip — Bottom HUD",
        code: true,
        body: `// WallCompletionStrip.swift
// Row of wall indicators at the bottom of the scan screen.
// Each detected wall gets a small tile showing:
// - Wall number
// - Completion percentage (fills light blue as confidence grows)
// - A checkmark when .complete
// This gives the user a clear at-a-glance view of what's done.

import SwiftUI

struct WallCompletionStrip: View {
    let walls: [TrackedWall]

    var body: some View {
        if walls.isEmpty { EmptyView() }
        else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(walls.sorted(by: { $0.id.uuidString < $1.id.uuidString })) { wall in
                        WallTile(wall: wall)
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 56)
        }
    }
}

struct WallTile: View {
    let wall: TrackedWall

    private var fillColor: Color {
        switch wall.highlightState {
        case .none:     return Color.gray.opacity(0.2)
        case .partial:  return Color(hex: "#7DD3FC").opacity(0.4)
        case .good:     return Color(hex: "#7DD3FC").opacity(0.7)
        case .complete: return Color(hex: "#7DD3FC")
        }
    }

    private var label: String {
        switch wall.highlightState {
        case .complete: return "✓"
        default: return "\\(Int(wall.coveragePct * 100))%"
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.5))
                .frame(width: 44, height: 44)

            // Coverage fill — animates upward as confidence grows
            VStack(spacing: 0) {
                Spacer()
                RoundedRectangle(cornerRadius: 6)
                    .fill(fillColor)
                    .frame(width: 40, height: CGFloat(wall.coveragePct) * 40)
                    .animation(.easeInOut(duration: 0.4), value: wall.coveragePct)
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(fillColor, lineWidth: wall.highlightState == .complete ? 1.5 : 0)
        )
    }
}`
      },
    ]
  },
  {
    id: "model3d",
    num: "03",
    title: "3D Model Generation",
    icon: "🧊",
    color: PU,
    sections: [
      {
        title: "3D Model Strategy — Timing Decision",
        code: false,
        body: `DECISION: POST-SCAN GENERATION ✓ (not real-time)

Reasoning:
Real-time 3D mesh reconstruction IS possible with RealityKit's scene reconstruction
but it produces a raw unprocessed mesh that is computationally expensive,
visually noisy, and not useful as an exportable asset.

RoomPlan's post-scan processing produces a semantically understood, 
clean, parametric 3D model — walls, floors, ceilings, doors, windows,
and detected objects all as separate typed components.

DURING SCAN: RoomCaptureView natively shows a growing 3D wireframe
(the blue room outline building up in AR). This is Apple's own visualization.
We ADD our light blue highlights on top of this.
We do NOT need to build our own real-time 3D renderer.

POST-SCAN: RoomPlan generates a CapturedRoom which we convert to:
1. USDZ — native Apple 3D format, opens in Quick Look, AR Quick Look, Reality Composer
2. OBJ — universal 3D format, opens in any 3D software
3. A custom SwiftUI/SceneKit interactive viewer inside the app

THE 3D MODEL VIEWER inside the app is built with SceneKit (not RealityKit)
because SCNView gives us free orbit/pan/zoom gesture control.`
      },
      {
        title: "Post-Scan USDZ Export",
        code: true,
        body: `// USDZExporter.swift
// Converts RoomPlan's CapturedRoom to a USDZ file.
// RoomPlan has a built-in exporter — we wrap it with progress tracking.

import RoomPlan
import RealityKit

class USDZExporter {

    enum ExportError: Error {
        case exportFailed(String)
        case noRoomAvailable
    }

    // Export a complete CapturedRoom to USDZ
    // Returns URL of the exported file in the app's temp directory
    static func export(_ room: CapturedRoom,
                       named name: String) async throws -> URL {
        let outputURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("\\(name)_3d_\\(Date().timeIntervalSince1970).usdz")

        let exporter = CapturedRoom.Exporter()

        // exportOptions:
        // .mesh — full room mesh including walls, floor, ceiling
        // .parametric — clean geometric model (preferred for trades use)
        try exporter.export(
            room,
            to: outputURL,
            exportOptions: [.mesh, .parametric]
        )

        return outputURL
    }

    // Export with texture baking (slower, better visual quality)
    static func exportWithTextures(_ room: CapturedRoom,
                                   named name: String) async throws -> URL {
        let outputURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("\\(name)_textured.usdz")
        let exporter = CapturedRoom.Exporter()
        try exporter.export(room, to: outputURL, exportOptions: [.mesh])
        return outputURL
    }
}`
      },
      {
        title: "Interactive 3D Viewer (SceneKit)",
        code: true,
        body: `// ModelViewer3D.swift
// Interactive 3D viewer for the post-scan review screen.
// Uses SceneKit — gives free pinch/rotate/pan gesture handling.
// Renders the CapturedRoom as coloured geometry:
// Walls = semi-transparent white, Floor = light grey, Ceiling = off-white,
// Doors/windows = transparent apertures, Objects = coloured boxes.

import SwiftUI
import SceneKit
import RoomPlan

struct ModelViewer3D: View {
    let room: CapturedRoom
    @State private var showDimensions = true
    @State private var showObjects = true
    @State private var viewMode: ViewMode = .perspective

    enum ViewMode { case perspective, topDown, front }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Toggle("Dimensions", isOn: $showDimensions)
                    .toggleStyle(.button)
                Toggle("Objects", isOn: $showObjects)
                    .toggleStyle(.button)
                Spacer()
                Picker("View", selection: $viewMode) {
                    Text("3D").tag(ViewMode.perspective)
                    Text("Top").tag(ViewMode.topDown)
                    Text("Front").tag(ViewMode.front)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            .padding(10)
            .background(Color(uiColor: .systemBackground))

            // 3D Scene
            SceneKitView(room: room,
                         showDimensions: showDimensions,
                         showObjects: showObjects,
                         viewMode: viewMode)
        }
    }
}

// UIViewRepresentable wrapper for SCNView
struct SceneKitView: UIViewRepresentable {
    let room: CapturedRoom
    let showDimensions: Bool
    let showObjects: Bool
    let viewMode: ModelViewer3D.ViewMode

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = buildScene()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.1, alpha: 1)
        scnView.antialiasingMode = .multisampling4X
        setupLighting(in: scnView.scene!)
        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        scnView.scene = buildScene()
        setCamera(on: scnView, mode: viewMode)
    }

    private func buildScene() -> SCNScene {
        let scene = SCNScene()

        // WALLS
        for wall in room.walls {
            let node = wallNode(wall)
            scene.rootNode.addChildNode(node)
            if showDimensions {
                scene.rootNode.addChildNode(dimensionLabel(for: wall))
            }
        }

        // FLOORS
        for floor in room.floors {
            scene.rootNode.addChildNode(floorNode(floor))
        }

        // DOORS & WINDOWS (apertures)
        for door in room.doors {
            scene.rootNode.addChildNode(apertureNode(door, color: .systemOrange))
        }
        for window in room.windows {
            scene.rootNode.addChildNode(apertureNode(window, color: .systemBlue))
        }

        // FURNITURE & OBJECTS
        if showObjects {
            for obj in room.objects {
                scene.rootNode.addChildNode(objectNode(obj))
            }
        }

        // Grid floor plane
        scene.rootNode.addChildNode(gridPlane())

        return scene
    }

    private func wallNode(_ wall: CapturedRoom.Wall) -> SCNNode {
        let geo = SCNBox(
            width:  CGFloat(wall.dimensions.x),
            height: CGFloat(wall.dimensions.y),
            length: 0.08,
            chamferRadius: 0
        )
        geo.firstMaterial?.diffuse.contents  = UIColor.white.withAlphaComponent(0.85)
        geo.firstMaterial?.specular.contents = UIColor.white
        geo.firstMaterial?.lightingModel = .physicallyBased
        geo.firstMaterial?.roughness.contents = 0.8
        geo.firstMaterial?.isDoubleSided = true

        let node = SCNNode(geometry: geo)
        node.simdTransform = wall.transform
        return node
    }

    private func floorNode(_ floor: CapturedRoom.Floor) -> SCNNode {
        let geo = SCNPlane(
            width:  CGFloat(floor.dimensions.x),
            height: CGFloat(floor.dimensions.z)
        )
        geo.firstMaterial?.diffuse.contents = UIColor.systemGray5
        geo.firstMaterial?.isDoubleSided = true
        let node = SCNNode(geometry: geo)
        node.simdTransform = floor.transform
        node.eulerAngles.x = -.pi / 2
        return node
    }

    private func dimensionLabel(for wall: CapturedRoom.Wall) -> SCNNode {
        // Width label
        let wText = SCNText(string: String(format: "%.2fm", wall.dimensions.x), extrusionDepth: 0)
        wText.font = UIFont.monospacedSystemFont(ofSize: 0.12, weight: .bold)
        wText.firstMaterial?.diffuse.contents = UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 1)
        let labelNode = SCNNode(geometry: wText)
        labelNode.simdTransform = wall.transform
        labelNode.position.y += Float(wall.dimensions.y) / 2 + 0.15
        labelNode.position.x -= Float(wall.dimensions.x) / 4
        labelNode.constraints = [SCNBillboardConstraint()]  // Always face camera
        return labelNode
    }

    private func apertureNode(_ surface: any CapturedRoom.Surface,
                               color: UIColor) -> SCNNode {
        let geo = SCNBox(width: CGFloat(surface.dimensions.x),
                         height: CGFloat(surface.dimensions.y),
                         length: 0.05, chamferRadius: 0)
        geo.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.3)
        geo.firstMaterial?.isDoubleSided = true
        let node = SCNNode(geometry: geo)
        node.simdTransform = surface.transform
        return node
    }

    private func objectNode(_ object: CapturedRoom.Object) -> SCNNode {
        let geo = SCNBox(width:  CGFloat(object.dimensions.x),
                         height: CGFloat(object.dimensions.y),
                         length: CGFloat(object.dimensions.z),
                         chamferRadius: 0.02)
        geo.firstMaterial?.diffuse.contents = objectColor(for: object.category)
        geo.firstMaterial?.transparency = 0.6
        let node = SCNNode(geometry: geo)
        node.simdTransform = object.transform
        return node
    }

    private func objectColor(for category: CapturedRoom.Object.Category) -> UIColor {
        switch category {
        case .bathtub, .shower: return .systemBlue
        case .toilet, .sink:    return .systemGray
        case .bed:              return .systemIndigo
        case .sofa:             return .systemBrown
        case .refrigerator:     return .systemCyan
        default:                return .systemGray2
        }
    }

    private func gridPlane() -> SCNNode {
        let grid = SCNPlane(width: 20, height: 20)
        grid.firstMaterial?.diffuse.contents  = UIColor.white.withAlphaComponent(0.03)
        grid.firstMaterial?.isDoubleSided = true
        let node = SCNNode(geometry: grid)
        node.eulerAngles.x = -.pi / 2
        node.position.y = -0.01
        return node
    }

    private func setupLighting(in scene: SCNScene) {
        let ambient = SCNNode(); ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 400
        scene.rootNode.addChildNode(ambient)

        let directional = SCNNode(); directional.light = SCNLight()
        directional.light!.type = .directional
        directional.light!.intensity = 800
        directional.light!.castsShadow = true
        directional.position = SCNVector3(5, 10, 5)
        directional.look(at: .init(0,0,0))
        scene.rootNode.addChildNode(directional)
    }

    private func setCamera(on view: SCNView, mode: ModelViewer3D.ViewMode) {
        let camera = SCNCamera()
        camera.fieldOfView = 60
        let cameraNode = SCNNode(); cameraNode.camera = camera
        switch mode {
        case .perspective:
            cameraNode.position = SCNVector3(4, 4, 4)
            cameraNode.look(at: .init(0, 1, 0))
        case .topDown:
            cameraNode.position = SCNVector3(0, 8, 0.001)
            cameraNode.look(at: .init(0, 0, 0))
        case .front:
            cameraNode.position = SCNVector3(0, 1.5, 6)
            cameraNode.look(at: .init(0, 1.5, 0))
        }
        view.scene?.rootNode.addChildNode(cameraNode)
        view.pointOfView = cameraNode
    }
}`
      },
    ]
  },
  {
    id: "floorplan",
    num: "04",
    title: "Floor Plan Generation",
    icon: "📐",
    color: O,
    sections: [
      {
        title: "Floor Plan Renderer",
        code: true,
        body: `// FloorPlanView.swift
// Generates a clean 2D top-down floor plan from CapturedRoom data.
// Renders in SwiftUI Canvas — scales to fit, shows dimensions,
// marks doors and windows with standard architectural notation.
// Exportable as PDF or PNG.

import SwiftUI
import RoomPlan

struct FloorPlanView: View {
    let room: CapturedRoom
    @State private var showDimensions = true
    @State private var showNorth = false
    @State private var scale: FloorPlanScale = .auto

    enum FloorPlanScale: String, CaseIterable {
        case auto = "Auto"
        case oneToFifty  = "1:50"
        case oneToHundred = "1:100"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Toggle("Dimensions", isOn: $showDimensions)
                    .font(.caption).toggleStyle(.button)
                Spacer()
                Picker("Scale", selection: $scale) {
                    ForEach(FloorPlanScale.allCases, id: \\.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented).frame(width: 200)
            }
            .padding(10)

            // Floor plan canvas
            GeometryReader { geo in
                let plan = FloorPlanProjector.project(room: room, in: geo.size)
                Canvas { ctx, size in
                    drawFloorPlan(ctx: ctx, size: size,
                                  plan: plan, showDimensions: showDimensions)
                }
                .background(Color(hex: "#F5F0E8"))
            }
        }
    }

    private func drawFloorPlan(ctx: GraphicsContext, size: CGSize,
                                plan: ProjectedFloorPlan, showDimensions: Bool) {
        // 1. Draw room outline / filled polygon
        var outline = Path()
        if let first = plan.roomOutline.first {
            outline.move(to: first)
            plan.roomOutline.dropFirst().forEach { outline.addLine(to: $0) }
            outline.closeSubpath()
        }
        ctx.fill(outline, with: .color(Color.white))
        ctx.stroke(outline, with: .color(Color.black), lineWidth: 2.5)

        // 2. Draw internal walls
        for wall in plan.walls {
            var path = Path()
            path.move(to: wall.start)
            path.addLine(to: wall.end)
            ctx.stroke(path, with: .color(Color.black), lineWidth: 2.0)
        }

        // 3. Draw doors (arc notation)
        for door in plan.doors {
            drawDoor(ctx: ctx, door: door)
        }

        // 4. Draw windows (double line + hatching)
        for window in plan.windows {
            drawWindow(ctx: ctx, window: window)
        }

        // 5. Dimension lines (if enabled)
        if showDimensions {
            for dim in plan.dimensionLines {
                drawDimensionLine(ctx: ctx, dim: dim)
            }
        }

        // 6. North indicator + scale bar
        drawScaleBar(ctx: ctx, in: size, pixelsPerMetre: plan.pixelsPerMetre)
    }

    private func drawDoor(ctx: GraphicsContext, door: ProjectedDoor) {
        // Standard architectural door notation: line + quarter-circle arc
        var linePath = Path()
        linePath.move(to: door.hingePoint)
        linePath.addLine(to: door.swingStart)
        ctx.stroke(linePath, with: .color(.black), lineWidth: 1.5)

        var arcPath = Path()
        arcPath.addArc(center: door.hingePoint,
                       radius: door.width,
                       startAngle: door.startAngle,
                       endAngle: door.endAngle,
                       clockwise: false)
        ctx.stroke(arcPath, with: .color(.black), style: StrokeStyle(lineWidth: 1.0, dash: [3,2]))
    }

    private func drawWindow(ctx: GraphicsContext, window: ProjectedWindow) {
        // Standard window notation: three parallel lines across opening
        let offsets: [CGFloat] = [0, window.depth/2, window.depth]
        for offset in offsets {
            var path = Path()
            let perp = CGPoint(x: -window.direction.y, y: window.direction.x)
            let start = CGPoint(x: window.start.x + perp.x * offset,
                                y: window.start.y + perp.y * offset)
            let end   = CGPoint(x: window.end.x   + perp.x * offset,
                                y: window.end.y   + perp.y * offset)
            path.move(to: start); path.addLine(to: end)
            ctx.stroke(path, with: .color(.black), lineWidth: offset == 0 ? 1.5 : 0.8)
        }
    }

    private func drawDimensionLine(ctx: GraphicsContext, dim: DimensionLine) {
        // Dimension line with tick marks and measurement text
        var line = Path()
        line.move(to: dim.start); line.addLine(to: dim.end)
        ctx.stroke(line, with: .color(Color(hex: "#3B82F6")),
                   style: StrokeStyle(lineWidth: 0.8, dash: []))

        // Tick marks at ends
        for point in [dim.start, dim.end] {
            var tick = Path()
            tick.move(to: CGPoint(x: point.x - dim.perpendicular.x * 5,
                                  y: point.y - dim.perpendicular.y * 5))
            tick.addLine(to: CGPoint(x: point.x + dim.perpendicular.x * 5,
                                     y: point.y + dim.perpendicular.y * 5))
            ctx.stroke(tick, with: .color(Color(hex: "#3B82F6")), lineWidth: 0.8)
        }

        // Dimension text
        ctx.draw(
            Text(dim.label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: "#3B82F6")),
            at: dim.midpoint
        )
    }

    private func drawScaleBar(ctx: GraphicsContext, in size: CGSize, pixelsPerMetre: CGFloat) {
        let barLength = pixelsPerMetre  // = 1 metre
        let origin = CGPoint(x: size.width - barLength - 20, y: size.height - 30)

        var bar = Path()
        bar.move(to: origin)
        bar.addLine(to: CGPoint(x: origin.x + barLength, y: origin.y))
        ctx.stroke(bar, with: .color(.black), lineWidth: 2)

        ctx.draw(
            Text("1m").font(.system(size: 9, weight: .bold)),
            at: CGPoint(x: origin.x + barLength/2, y: origin.y - 10)
        )
    }
}

// MARK: - Floor Plan Projector
// Converts 3D RoomPlan world coordinates to 2D screen coordinates
struct FloorPlanProjector {

    static func project(room: CapturedRoom, in size: CGSize) -> ProjectedFloorPlan {
        // Extract all wall endpoints in XZ plane (top-down view, Y=0)
        let wallSegments: [(start: CGPoint, end: CGPoint, original: CapturedRoom.Wall)] = room.walls.map { wall in
            let w = wall.dimensions.x / 2
            let t = wall.transform
            let s = CGPoint(
                x: CGFloat(t.columns.3.x + t.columns.0.x * (-w)),
                y: CGFloat(t.columns.3.z + t.columns.0.z * (-w))
            )
            let e = CGPoint(
                x: CGFloat(t.columns.3.x + t.columns.0.x * w),
                y: CGFloat(t.columns.3.z + t.columns.0.z * w)
            )
            return (start: s, end: e, original: wall)
        }

        // Find bounding box of all points
        let allPoints = wallSegments.flatMap { [$0.start, $0.end] }
        let minX = allPoints.map { $0.x }.min() ?? 0
        let maxX = allPoints.map { $0.x }.max() ?? 1
        let minY = allPoints.map { $0.y }.min() ?? 0
        let maxY = allPoints.map { $0.y }.max() ?? 1

        let roomWidth  = maxX - minX
        let roomHeight = maxY - minY
        let padding: CGFloat = 60

        // Scale to fit canvas with padding
        let scaleX = (size.width  - padding*2) / max(roomWidth,  0.1)
        let scaleY = (size.height - padding*2) / max(roomHeight, 0.1)
        let scale  = min(scaleX, scaleY)

        // Transform function: 3D world XZ → 2D canvas XY
        func transform(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: (p.x - minX) * scale + padding,
                y: (p.y - minY) * scale + padding
            )
        }

        // Project walls
        let projectedWalls = wallSegments.map { seg in
            ProjectedWall(start: transform(seg.start), end: transform(seg.end))
        }

        // Room outline (convex hull of all endpoints)
        let outline = convexHull(points: allPoints.map(transform))

        // Dimension lines (for each wall, offset outward)
        let dimensionLines: [DimensionLine] = wallSegments.map { seg in
            let mid  = transform(CGPoint(x: (seg.start.x+seg.end.x)/2, y: (seg.start.y+seg.end.y)/2))
            let tStart = transform(seg.start); let tEnd = transform(seg.end)
            let dx = tEnd.x - tStart.x; let dy = tEnd.y - tStart.y
            let perp = CGPoint(x: -dy / max(hypot(dx,dy),0.001),
                               y:  dx / max(hypot(dx,dy),0.001))
            let offset: CGFloat = 22
            return DimensionLine(
                start: CGPoint(x: tStart.x + perp.x*offset, y: tStart.y + perp.y*offset),
                end:   CGPoint(x: tEnd.x   + perp.x*offset, y: tEnd.y   + perp.y*offset),
                midpoint: CGPoint(x: mid.x + perp.x*(offset+10), y: mid.y + perp.y*(offset+10)),
                perpendicular: perp,
                label: String(format: "%.2fm", seg.original.dimensions.x)
            )
        }

        return ProjectedFloorPlan(
            walls: projectedWalls,
            roomOutline: outline,
            doors: [],   // Add door projection
            windows: [], // Add window projection
            dimensionLines: dimensionLines,
            pixelsPerMetre: scale
        )
    }

    // Graham scan convex hull
    static func convexHull(points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        // Simplified — use the wall endpoints in order as the room polygon
        return points
    }
}

// Supporting types
struct ProjectedFloorPlan {
    var walls: [ProjectedWall]
    var roomOutline: [CGPoint]
    var doors: [ProjectedDoor]
    var windows: [ProjectedWindow]
    var dimensionLines: [DimensionLine]
    var pixelsPerMetre: CGFloat
}
struct ProjectedWall   { var start, end: CGPoint }
struct ProjectedDoor   { var hingePoint, swingStart: CGPoint; var width: CGFloat; var startAngle, endAngle: Angle; var direction: CGPoint }
struct ProjectedWindow { var start, end: CGPoint; var depth: CGFloat; var direction: CGPoint }
struct DimensionLine   { var start, end, midpoint: CGPoint; var perpendicular: CGPoint; var label: String }`
      },
    ]
  },
  {
    id: "export",
    num: "05",
    title: "Export System",
    icon: "📤",
    color: GR,
    sections: [
      {
        title: "Export Formats & Implementation",
        code: true,
        body: `// ExportView.swift — format picker + share sheet

// SUPPORTED EXPORT FORMATS:

// FORMAT 1: USDZ (3D Model — native Apple)
// Opens in: Quick Look, Reality Composer, Xcode, iPhone/iPad natively
// Use: Sharing with clients, AR preview, professional review
// Implementation: RoomPlan.CapturedRoom.Exporter (built into Apple SDK)

// FORMAT 2: OBJ + MTL (3D Model — universal)
// Opens in: Blender, SketchUp, AutoCAD, any 3D software
// Use: Architects, interior designers, professional CAD users
// Implementation: Convert RoomPlan mesh using ModelIO

// FORMAT 3: PDF Floor Plan (A4 / A3 / Letter)
// Opens in: Files, Mail, Print
// Use: Trades, planning applications, client presentations
// Implementation: PDFKit rendering of FloorPlanView canvas

// FORMAT 4: DXF (2D CAD format)
// Opens in: AutoCAD, SketchUp, QCAD, FreeCAD
// Use: Architects, surveyors, planning professionals
// Implementation: Custom DXF string writer (DXF is plain text)

// FORMAT 5: CSV (Raw dimensions)
// Opens in: Excel, Numbers, Google Sheets
// Use: Data processing, quantity takeoffs, spreadsheet integration
// Implementation: Simple CSV string from dimension model

// FORMAT 6: PNG (Floor plan image)
// Opens in: Everything
// Use: WhatsApp, email, adding to reports
// Implementation: ImageRenderer from SwiftUI view

import SwiftUI
import PDFKit
import ModelIO

struct ExportView: View {
    let room: CapturedRoom
    let session: ScanSession        // CoreData entity with metadata
    @State private var isExporting = false
    @State private var shareURL: URL?
    @State private var showShareSheet = false

    let formats: [(name: String, icon: String, desc: String, format: ExportFormat)] = [
        ("USDZ",       "cube.fill",       "3D model — opens in Quick Look",       .usdz),
        ("OBJ",        "cube",            "3D model — opens in any 3D software",  .obj),
        ("PDF",        "doc.fill",        "Floor plan — print ready",             .pdf),
        ("DXF",        "pencil.and.ruler","CAD format — AutoCAD / SketchUp",      .dxf),
        ("CSV",        "tablecells",      "Raw dimensions — Excel / Numbers",     .csv),
        ("PNG",        "photo",           "Floor plan image — share anywhere",    .png),
    ]

    enum ExportFormat { case usdz, obj, pdf, dxf, csv, png }

    var body: some View {
        NavigationView {
            List {
                Section("3D Model") {
                    ForEach(formats.filter { [.usdz,.obj].contains($0.format) }, id: \\.name) { fmt in
                        exportRow(fmt)
                    }
                }
                Section("Floor Plan") {
                    ForEach(formats.filter { [.pdf,.dxf,.png].contains($0.format) }, id: \\.name) { fmt in
                        exportRow(fmt)
                    }
                }
                Section("Data") {
                    ForEach(formats.filter { $0.format == .csv }, id: \\.name) { fmt in
                        exportRow(fmt)
                    }
                }
                Section("Dimensions Summary") {
                    DimensionTableView(room: room)
                }
            }
            .navigationTitle("Export")
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private func exportRow(_ fmt: (name: String, icon: String, desc: String, format: ExportFormat)) -> some View {
        Button {
            Task { await export(as: fmt.format) }
        } label: {
            HStack {
                Image(systemName: fmt.icon)
                    .frame(width: 32)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fmt.name).fontWeight(.semibold)
                    Text(fmt.desc).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if isExporting {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.secondary)
                }
            }
        }
        .disabled(isExporting)
    }

    private func export(as format: ExportFormat) async {
        isExporting = true
        defer { isExporting = false }
        do {
            let url: URL
            let name = session.name ?? "scan"
            switch format {
            case .usdz: url = try await USDZExporter.export(room, named: name)
            case .obj:  url = try await OBJExporter.export(room, named: name)
            case .pdf:  url = try await PDFExporter.export(room, named: name)
            case .dxf:  url = try await DXFExporter.export(room, named: name)
            case .csv:  url = try await CSVExporter.export(room, named: name)
            case .png:  url = try await PNGExporter.export(room, named: name)
            }
            shareURL = url
            showShareSheet = true
        } catch {
            // Show error alert
        }
    }
}

// MARK: - DXF Exporter (plain text, no library needed)
class DXFExporter {
    static func export(_ room: CapturedRoom, named name: String) async throws -> URL {
        var dxf = ""
        dxf += "0\\nSECTION\\n2\\nENTITIES\\n"

        for wall in room.walls {
            let w = wall.dimensions.x / 2
            let t = wall.transform
            let x1 = t.columns.3.x + t.columns.0.x * (-w)
            let y1 = t.columns.3.z + t.columns.0.z * (-w)
            let x2 = t.columns.3.x + t.columns.0.x * w
            let y2 = t.columns.3.z + t.columns.0.z * w

            dxf += "0\\nLINE\\n"
            dxf += "8\\n0\\n"           // Layer 0
            dxf += "10\\n\\(x1)\\n"    // Start X
            dxf += "20\\n\\(y1)\\n"    // Start Y
            dxf += "30\\n0.0\\n"        // Start Z
            dxf += "11\\n\\(x2)\\n"    // End X
            dxf += "21\\n\\(y2)\\n"    // End Y
            dxf += "31\\n0.0\\n"        // End Z
        }

        dxf += "0\\nENDSEC\\n0\\nEOF\\n"

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\\(name)_floor_plan.dxf")
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - CSV Exporter
class CSVExporter {
    static func export(_ room: CapturedRoom, named name: String) async throws -> URL {
        var csv = "Element,Width(m),Height(m),Depth(m),Area(m2),Confidence\\n"

        for (i, wall) in room.walls.enumerated() {
            let area = wall.dimensions.x * wall.dimensions.y
            let conf = confidenceString(wall.confidence)
            csv += "Wall \\(i+1),\\(f(wall.dimensions.x)),\\(f(wall.dimensions.y)),0.20,\\(f(area)),\\(conf)\\n"
        }
        for (i, door) in room.doors.enumerated() {
            csv += "Door \\(i+1),\\(f(door.dimensions.x)),\\(f(door.dimensions.y)),0.10,,\\(confidenceString(door.confidence))\\n"
        }
        for (i, window) in room.windows.enumerated() {
            csv += "Window \\(i+1),\\(f(window.dimensions.x)),\\(f(window.dimensions.y)),0.10,,\\(confidenceString(window.confidence))\\n"
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\\(name)_dimensions.csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func f(_ v: Float) -> String { String(format: "%.3f", v) }
    private static func confidenceString(_ c: CapturedRoom.Confidence) -> String {
        switch c { case .low: return "Low"; case .medium: return "Medium"; case .high: return "High"; default: return "Unknown" }
    }
}`
      },
    ]
  },
  {
    id: "acceptance",
    num: "06",
    title: "Acceptance Criteria",
    icon: "✅",
    color: GR,
    sections: [
      {
        title: "Full Acceptance Criteria — Claude Code Must Pass All",
        code: false,
        body: `SCANNING

[ ] App launches on iPhone 12 Pro or later without crash
[ ] LiDAR availability detected at runtime — non-LiDAR shows manual entry UI
[ ] RoomCaptureView fills screen edge-to-edge during active scan
[ ] Scanning starts within 2 seconds of tapping "Start Scan"
[ ] Wall highlight entities appear within 0.5 seconds of wall detection
[ ] Light blue corner highlights appear at all 4 corners of each detected wall
[ ] Corner highlights animate from dim → bright as confidence increases (.low → .medium → .high)
[ ] Haptic feedback fires when a wall reaches .high confidence
[ ] Wall completion strip at bottom shows correct percentage for each wall
[ ] Overall coverage ring shows aggregate coverage 0–100%
[ ] Coaching instructions update in real-time from RoomPlan delegate
[ ] Pause and resume scan works without data loss
[ ] Stop scan triggers RoomPlan post-processing animation
[ ] Scan state machine never gets stuck — always navigates correctly

3D MODEL

[ ] Post-scan 3D viewer loads within 3 seconds of scan completion
[ ] All walls render as white semi-transparent boxes in correct positions
[ ] Floor renders as grey plane
[ ] Doors render as orange apertures
[ ] Windows render as blue apertures
[ ] Detected objects (bathtub, sink etc) render as coloured boxes
[ ] Pinch to zoom works
[ ] Two-finger pan works
[ ] One-finger rotate works
[ ] Top-down / front / perspective view toggles work correctly
[ ] Dimension labels render at correct wall positions and face camera (billboard)

FLOOR PLAN

[ ] Floor plan renders as clean 2D top-down view
[ ] All walls render as black lines in correct relative positions
[ ] Doors show standard arc notation
[ ] Windows show triple-line notation
[ ] Dimension lines show correct measurements in metres (2 decimal places)
[ ] Scale bar visible and accurate
[ ] Floor plan fits the canvas with consistent padding
[ ] Toggle dimensions on/off works

EXPORT

[ ] USDZ export produces valid file that opens in iOS Quick Look
[ ] OBJ export produces valid file
[ ] PDF export produces A4 document with floor plan and dimension table
[ ] DXF export produces valid DXF file that opens in FreeCAD/QCAD
[ ] CSV export produces correctly formatted spreadsheet
[ ] PNG export produces high-resolution image of floor plan
[ ] Share sheet opens correctly for all formats
[ ] Export file names include room name and timestamp

DATA PERSISTENCE

[ ] Completed scans save to CoreData on completion
[ ] Home screen shows saved scans in reverse chronological order
[ ] Each scan card shows: room name, room type, date, thumbnail, wall count
[ ] Tapping a saved scan opens the review view
[ ] Delete scan works (swipe to delete)
[ ] Scans persist across app restarts

GENERAL

[ ] App runs at 60fps during scanning on iPhone 12 Pro
[ ] No memory warnings during a full room scan session
[ ] All privacy permission strings appear correctly when permissions requested
[ ] App handles permission denial gracefully (shows settings prompt)
[ ] Dark mode: all screens look correct
[ ] Dynamic Type: text scales without breaking layouts
[ ] No third-party dependencies — builds clean with Xcode 16`
      },
    ]
  },
];

export default function BuildSpec() {
  const [activeBlock, setActiveBlock] = useState("overview");
  const [activeSection, setActiveSection] = useState(0);

  const block = BLOCKS.find(b => b.id === activeBlock);

  return (
    <div style={{ fontFamily: "'DM Sans', system-ui", background: BG, minHeight: "100vh", color: T }}>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Bebas+Neue&family=DM+Sans:wght@300;400;500;600&family=DM+Mono:wght@400;500&display=swap');
        * { box-sizing:border-box; margin:0; padding:0; }
        ::-webkit-scrollbar { width:4px; }
        ::-webkit-scrollbar-track { background:${S1}; }
        ::-webkit-scrollbar-thumb { background:${S3}; border-radius:2px; }
        .bb { cursor:pointer; transition:all .12s; }
        .bb:hover { background:${S2} !important; }
        .sb { cursor:pointer; transition:all .1s; border:none; }
        pre { white-space:pre-wrap; word-break:break-word; font-size: 11.5px; line-height: 1.75; }
        code { font-family: 'DM Mono', monospace; }
      `}</style>

      <header style={{ background: S1, borderBottom: `1px solid ${S3}`, padding: "14px 24px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <span style={{ fontFamily: "'Bebas Neue'", fontSize: 22, letterSpacing: 5, color: Y }}>ACCUSCAN</span>
          <span style={{ width: 1, height: 18, background: S3, display: "inline-block" }} />
          <span style={{ fontSize: 10, color: M, letterSpacing: 2 }}>iOS PRODUCTION BUILD SPEC — CLAUDE CODE READY</span>
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          {[
            { l: "Framework", v: "RoomPlan + ARKit", c: TE },
            { l: "3D Render", v: "SceneKit", c: PU },
            { l: "Highlights", v: "RealityKit", c: LB },
            { l: "Exports", v: "6 formats", c: GR },
          ].map(s => (
            <div key={s.l} style={{ background: S2, border: `1px solid ${S3}`, borderRadius: 4, padding: "5px 12px", textAlign: "center" }}>
              <div style={{ fontFamily: "'Bebas Neue'", fontSize: 15, color: s.c, lineHeight: 1 }}>{s.v}</div>
              <div style={{ fontSize: 9, color: M, letterSpacing: 1 }}>{s.l}</div>
            </div>
          ))}
        </div>
      </header>

      <div style={{ display: "flex", height: "calc(100vh - 51px)" }}>
        <div style={{ width: 210, background: S1, borderRight: `1px solid ${S3}`, overflowY: "auto", flexShrink: 0, padding: "12px 0" }}>
          <div style={{ padding: "0 14px 10px", fontSize: 9, color: DIM, letterSpacing: 2 }}>BUILD BLOCKS</div>
          {BLOCKS.map(b => (
            <div key={b.id} className="bb" onClick={() => { setActiveBlock(b.id); setActiveSection(0); }} style={{
              padding: "12px 14px",
              borderLeft: `3px solid ${activeBlock === b.id ? b.color : "transparent"}`,
              background: activeBlock === b.id ? `${b.color}0D` : "transparent",
            }}>
              <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                <span style={{ fontSize: 16 }}>{b.icon}</span>
                <div>
                  <div style={{ fontSize: 10, color: activeBlock === b.id ? b.color : M, fontWeight: 700 }}>{b.num} — {b.title.split(" ")[0]} {b.title.split(" ")[1] || ""}</div>
                  <div style={{ fontSize: 9, color: DIM, marginTop: 1 }}>{b.sections.length} section{b.sections.length > 1 ? "s" : ""}</div>
                </div>
              </div>
            </div>
          ))}
        </div>

        <div style={{ flex: 1, overflowY: "auto", padding: 28 }}>
          {block && (
            <div style={{ maxWidth: 900 }}>
              <div style={{ display: "flex", gap: 12, marginBottom: 20 }}>
                <span style={{ fontSize: 32 }}>{block.icon}</span>
                <div>
                  <div style={{ fontSize: 10, color: block.color, letterSpacing: 3, marginBottom: 4 }}>BLOCK {block.num}</div>
                  <div style={{ fontFamily: "'Bebas Neue'", fontSize: 32, color: T, letterSpacing: 2, lineHeight: 1 }}>{block.title}</div>
                </div>
              </div>

              <div style={{ display: "flex", gap: 8, marginBottom: 20, flexWrap: "wrap" }}>
                {block.sections.map((s, i) => (
                  <button key={i} className="sb" onClick={() => setActiveSection(i)} style={{
                    padding: "7px 14px", background: activeSection === i ? `${block.color}18` : S2,
                    border: `1px solid ${activeSection === i ? block.color : S3}`,
                    borderRadius: 4, color: activeSection === i ? block.color : M,
                    fontSize: 11, fontWeight: 600, cursor: "pointer",
                  }}>{s.title}</button>
                ))}
              </div>

              <div style={{ background: S2, border: `1px solid ${block.color}40`, borderRadius: 8, overflow: "hidden" }}>
                <div style={{ padding: "12px 20px", background: `${block.color}0C`, borderBottom: `1px solid ${S3}`, fontSize: 12, fontWeight: 700, color: block.color }}>
                  {block.sections[activeSection]?.title}
                </div>
                <div style={{ padding: 24 }}>
                  {block.sections[activeSection]?.code ? (
                    <pre style={{ fontFamily: "'DM Mono', monospace", color: "#8a95a0" }}>
                      {block.sections[activeSection]?.body}
                    </pre>
                  ) : (
                    <pre style={{ fontFamily: "'DM Mono', monospace", color: "#8a95a0" }}>
                      {block.sections[activeSection]?.body}
                    </pre>
                  )}
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
