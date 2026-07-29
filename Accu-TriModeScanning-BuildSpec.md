# Accu Tri-Mode Scanning — Build Specification
### Room · Space · Full Works — for AccuQuote and AccuScan

> **TO CLAUDE CODE:** This spec extends the existing AccuQuote/AccuScan codebase (reference files: `Views.swift`, `ScanCoordinator.swift`, `ContentView.swift`, `QuoteHistory.swift`). Mirror the existing `enum AQ` design tokens, `ScanState` machine, `SessionBridge` pattern, `@MainActor` concurrency conventions, and file-backed persistence exactly. This document specifies THREE scanning modes, a shared 3D viewer, a unified output pipeline (2D plan + 3D model + dimension data from one source of truth), and a quality gate that guarantees a usable scan or guides a targeted re-scan. Build order: Mode Picker → Room (refactor of existing) → `ScanResult` canonical model + 2D/3D/CSV renderers → **Quality Gate + Guided Re-scan (§5.4)** → 3D Viewer → Space → Full Works. Build the quality gate early — every mode depends on it, and it is the feature that makes the output trustworthy enough to build a business on.

---

## 0. THE THREE MODES

| | **Room** | **Space** | **Full Works** |
|---|---|---|---|
| What it scans | One room | A detail: under-sink void, window frame, alcove, cupboard, boiler enclosure | An entire property, room-by-room, all floors |
| Core Apple API | RoomPlan (`RoomCaptureSession`) | ARKit scene reconstruction (`ARMeshAnchor` + `sceneDepth`) | RoomPlan multi-room (`StructureBuilder` merging `CapturedRoom`s, iOS 17+) |
| Typical duration | 30–60 s | 15–30 s | 10–25 min |
| Output | Dimensions + 2D plan + 3D model | Precision dimensions + 3D mesh of the detail | Whole-house 3D model + per-floor plans + full dimension schedule |
| Accuracy target | ±2 cm | ±1 cm at close range | ±2 cm per room, ±5 cm cumulative across house |
| Availability | Both apps | Both apps | AccuScan: locked teaser → AccuQuote upsell. AccuQuote: included in Solo+ |

Positioning: Room is the daily driver, Space is the "no other app does this" wow feature, Full Works is the premium showpiece that justifies £99/mo on its own.

---

## 1. MODE PICKER UI

Replace the current single "Start Scan" CTA with a three-card mode picker, styled exactly on the existing design system:

- White background, cards with `AQ.fill` background, 14pt corner radius, 24pt horizontal padding.
- Each card: SF Symbol glyph in `AQ.blue` (Room: `cube.transparent`; Space: `viewfinder.rectangular`; Full Works: `building.2`), title in `AQ.display(20)`, one-line subtitle in `AQ.body(14)` / `AQ.secondary`, and a chevron.
- Selected card animates with `.spring(response: 0.38, dampingFraction: 0.82)` scale to 1.02 with an `AQ.blue` 2pt border.
- Under each card a tiny caption row: estimated time (`clock` symbol) + accuracy chip reusing the existing `accuracyLabel`/`accuracyHex` pattern from `ScanMethod`.
- In AccuScan, the Full Works card renders with a `lock.fill` badge and opens the AccuQuote upsell sheet (existing Trojan-horse convention: benefit-first copy, one CTA, easy dismiss).

Copy:
- Room — "Scan a full room in under a minute"
- Space — "Measure a detail — under a sink, a window, an alcove"
- Full Works — "Map an entire property, floor by floor"

---

## 2. ROOM MODE (refactor, not rebuild)

The existing `ScanCoordinator` already implements this: LiDAR via RoomPlan, poseFusion fallback, manual entry, the iOS 26 workaround, interruption recovery. Changes:

1. Extract the current flow behind a `ScanMode.room` case so all three modes share one coordinator interface:
```swift
enum ScanMode: String, Codable { case room, space, fullWorks }
```
2. On completion, in addition to `RoomDimensions`, retain the `CapturedRoom` (LiDAR path) or the accumulated point cloud (poseFusion path) so the 3D viewer has real geometry to display, not just numbers.
3. Persist a lightweight `scanArtifactURL` alongside each `SavedQuote`/`SavedScan`: export the `CapturedRoom` to USDZ in the documents directory (`aq_scans/<uuid>.usdz`) using `CapturedRoom.export(to:)`. Backwards-compatible Codable decode (`(try? …) ?? nil`) so old records still open.

---

## 3. SPACE MODE (the differentiator)

RoomPlan cannot do this — it's built for room-scale parametric capture. Space mode uses raw ARKit scene reconstruction, which is exactly what Apple built for close-range geometry.

### 3.1 Capture pipeline
- `ARWorldTrackingConfiguration` with `sceneReconstruction = .meshWithClassification` (LiDAR devices) and `frameSemantics = [.sceneDepth, .smoothedSceneDepth]`.
- The user aims at the detail; a **capture volume** (adjustable virtual box, default 0.8 m³) is placed with a tap on the first detected plane. Only mesh inside the box is kept — this is what keeps under-sink scans clean instead of capturing the whole kitchen.
- Guidance overlay mirrors the existing dark scan screen: `#7DD3FC` highlight tint on accumulated mesh, instruction text driven by coverage ("Move closer", "Capture the left side", "Hold steady") using the existing `instructionText` published-property pattern.
- Coverage tracked by voxelising the capture volume (4 cm voxels) and marking voxels hit by `ARMeshAnchor` faces; progress ring = filled voxels / expected-surface voxels. Reuse the existing `CoverageRingView`.
- Completion: either auto (coverage > 92% and stable for 2 s) or manual Done.

### 3.2 Measurement extraction
- Merge `ARMeshAnchor` geometries inside the volume into one mesh (world space).
- Compute: oriented bounding box (PCA on vertices → width/height/depth of the void or frame), plus **tap-to-measure**: after capture, the user taps any two points on the frozen 3D mesh and gets a point-to-point distance at ±1 cm — this is the feature that makes a plumber measuring an under-sink void gasp.
- For window/door frames specifically: detect the dominant plane, project the mesh boundary onto it, fit a rectangle → report reveal width/height/depth and diagonals (diagonal check is how real tradesmen verify square).
- Non-LiDAR fallback: Space mode requires LiDAR; on non-LiDAR devices show the manual-entry fallback with the same graceful copy the existing coordinator uses for `.manual`.

### 3.3 Output
- `SpaceDimensions` struct mirroring `RoomDimensions` conventions (strings via the existing `rounded(to:)` helpers).
- Textured mesh export: bake camera frames onto the mesh (project highest-confidence frame per face) → OBJ + USDZ into `aq_scans/`.
- In AccuQuote, a Space scan attaches to a quote section (e.g. "Replace kitchen sink unit — void measured 562 × 448 × 585 mm") and flows into the Claude generation context.

---

## 4. FULL WORKS MODE

### 4.1 Capture flow
- iOS 17+ only (requires `StructureBuilder`). On iOS 16, hide the card.
- Session model wraps the existing single-room engine — do not fork it:
```swift
@MainActor final class FullWorksSession: ObservableObject {
    @Published var floors: [Floor] = []            // Floor = label + [CapturedRoomRecord]
    @Published var phase: Phase = .setup           // setup, scanningRoom, betweenRooms, merging, complete, error
    var structure: CapturedStructure?              // merged result
}
```
- Flow: user names the property → picks floor ("Ground", "First", custom) → scans room 1 with the standard Room engine → **between-rooms screen** shows a live floor summary (rooms captured, running m², next-room prompt: "Walk to the next room, keep the phone up, then tap Scan") → repeat → "Finish floor" → next floor or Finish.
- Critical UX rule from Apple's multi-room guidance: instruct the user NOT to close doors between rooms mid-floor and to keep ARKit tracking alive between rooms (session pause, not stop). If tracking is lost between rooms, show the relocalisation overlay ("Point at the doorway you just came through") before allowing the next scan.
- Merge: `StructureBuilder(configuration: .init()).capturedStructure(from: capturedRooms)` per floor, run inside the existing `Task.detached` pattern with a `merging` phase and progress UI (reuse `ProcessingView` styling). Whole-house = array of per-floor structures stacked with floor-height offsets.

### 4.2 Output
- Whole-house USDZ (per floor + combined), per-floor 2D plans rendered by the existing floor-plan renderer, and a **dimension schedule**: table of every room (name, L × W × H, floor area, wall area, door/window counts) exportable as CSV and included in the quote/brochure PDF.
- Headline stat card on completion: total floor area, room count, scan duration — screenshot-bait by design ("Scanned a 4-bed in 14 minutes").

### 4.3 Gating
- AccuScan: card visible, locked. Tapping opens the upsell sheet: "Full Works maps entire properties. It's part of AccuQuote." One CTA → App Store / deep link. This is the strongest Trojan-horse asset in the whole funnel.
- AccuQuote: included in all tiers (do not paywall inside the paid app — the £99 already signals premium; gating features inside a premium subscription breeds resentment).

---

## 5. OUTPUT PIPELINE — 2D PLANS, 3D MODELS, DIMENSION DATA (the trajectory-changer)

This is the section that decides whether the apps feel like a toy or a tool a surveyor would pay for. Three deliverable artefacts per scan — a **2D floor plan**, a **3D model**, and a **structured dimension dataset** — all derived from one canonical geometry object so they can never disagree with each other. The golden rule: **one source of truth, many renderers.** Numbers on the 2D plan, labels on the 3D model, and rows in the CSV must all read from the same `ScanResult`, never from independent calculations.

### 5.1 The canonical geometry model

Every mode, on completion, produces one `ScanResult` — the single object all outputs derive from. Define it explicitly:

```swift
struct ScanResult: Codable, Identifiable {
    let id: String
    let mode: ScanMode
    let capturedAt: Date

    // Canonical geometry (world space, metres, +Y up, right-handed)
    var surfaces: [Surface]        // walls, floors, ceilings, openings
    var objects: [DetectedObject]  // RoomPlan objects: sink, toilet, window, door, cabinet…
    var meshURL: URL?              // high-res triangle mesh (USDZ) for 3D + export
    var pointCloudURL: URL?        // raw points (Space mode / QA only)

    // Derived + cached at save time (never recomputed at display time)
    var dimensionSchedule: [RoomDimensionRecord]
    var confidence: ScanConfidence // see 5.4
    var floorPlan2D: FloorPlan2D    // vector plan model, see 5.2
    var thumbnailURL: URL?          // pre-rendered 3D snapshot JPEG

    // Backwards-compatible decode — every field added later defaults via (try? …) ?? default
}

struct Surface: Codable {
    let category: SurfaceCategory  // wall, floor, ceiling, opening(door|window)
    var polygon: [SIMD3<Float>]    // ordered boundary loop, world space
    var confidence: Float          // 0…1 per surface, from RoomPlan/ARKit confidence
    var edges: [Edge]              // adjacency for gap detection (see 5.4)
}
```

All three outputs (2D, 3D, data) are pure functions of `ScanResult`. This is what guarantees a window measured at 1,204 mm shows as 1,204 mm on the plan, on the model, and in the CSV.

### 5.2 2D FLOOR PLAN — architectural-grade vector output

Not a screenshot of the 3D view flattened. A true vector plan built with SwiftUI `Canvas` + Core Graphics, exported as **PDF (vector)**, **SVG**, and **PNG (raster, 300 dpi)**.

**Rendering rules (mirror architectural drawing conventions so it looks professional to a builder/estate agent):**
- Walls: 2.5 pt near-black (`AQ.ink`) double-line stroke showing wall thickness (RoomPlan gives wall thickness; if absent, default 100 mm and flag as estimated with a hairline dashed inner line).
- Doors: opening gap in the wall + quarter-circle swing arc (0.75 pt, `AQ.secondary`).
- Windows: triple parallel line across the opening.
- Dimension strings: outside the wall line, extension + dimension lines with ticks, value in `AQ.mono(9)` `AQ.blue`. Every wall auto-dimensioned; overall bounding dimensions on two sides.
- Room labels: name + floor area centred in each enclosed region (`AQ.title(13)` + `AQ.caption(11)` grey).
- Fixtures: sink, toilet, bath, cabinet drawn as standardised architectural symbols (build a small symbol library keyed to RoomPlan object categories; fall back to a labelled rectangle for unknown categories).
- North arrow (from `CMMotionManager` heading captured at scan start) + graphic scale bar + "Not to scale — indicative" disclaimer toggle for legal safety.
- Multi-floor (Full Works): one plan page per floor, plus a stacked isometric key page.

**Data model** `FloorPlan2D` holds resolved vector primitives (walls, arcs, dimension strings, labels, symbols) so the plan is reproducible and diff-able, not pixels.

**Interaction (in-app):** pinch-zoom/pan the plan; tap any dimension to toggle mm/cm/m; tap a wall to edit its length manually (writes back to `ScanResult`, re-derives everything — this is the "trust but let me correct" escape hatch tradesmen need).

### 5.3 3D MODEL OUTPUT
- Display + interaction handled by `ScanViewer3D` (section 6).
- Export formats: **USDZ** (AR Quick Look, iMessage, native), **OBJ + MTL** (CAD/SketchUp), **glTF/GLB** (web/CRM embeds), **STL** (optional, for the Space-mode detail scans some users will 3D-print). Generate USDZ always; others on demand to save time/space.
- Texturing: bake highest-confidence camera frame per face (Space + Full Works). Provide an untextured "clean CAD" white-model variant toggle — estate agents want textured, builders often want clean.

### 5.4 THE QUALITY GATE — "perfect every time, or tell them exactly what to fix"

This is the heart of the request and the hardest engineering. RoomPlan/ARKit output is **never guaranteed complete** — missed corners, holes where glass/mirrors confused the LiDAR, low-confidence walls where the user moved too fast. The app must detect this deterministically and guide a targeted re-scan. Never present a broken model as finished.

**Step 1 — Compute a `ScanConfidence` report at capture end (before showing "Complete"):**

```swift
struct ScanConfidence: Codable {
    var overallScore: Float               // 0…1, weighted composite
    var issues: [ScanIssue]               // ordered worst-first
    var isPassing: Bool { overallScore >= 0.85 && !issues.contains { $0.severity == .blocking } }
}

struct ScanIssue: Codable, Identifiable {
    let id: String
    let kind: IssueKind        // openLoop, lowConfidenceSurface, holeInMesh, unmeasuredOpening,
                               // suspiciousDimension, driftDetected, insufficientCoverage
    let severity: Severity     // blocking, warning, info
    var worldAnchor: SIMD3<Float>   // where it is in 3D
    var affectedSurfaceIDs: [String]
    var hint: String           // human copy: "This corner didn't close — walk back and scan it"
}
```

**Detection heuristics (deterministic, run on-device in the `merging`/`processing` phase):**
1. **Open-loop / non-manifold walls** — walk the wall adjacency graph; any wall edge not shared by two surfaces at a corner = open loop → `openLoop`, severity blocking. This is the classic "room that doesn't close."
2. **Holes in mesh** — boundary-edge detection on the triangle mesh; boundary loops that aren't at expected openings (doors/windows) = `holeInMesh`. Area-threshold: holes > 0.05 m² are blocking, smaller are warnings.
3. **Low-confidence surfaces** — RoomPlan/ARKit per-surface confidence < 0.5, or surfaces built from < N depth samples → `lowConfidenceSurface`, warning (blocking if it's a load-bearing dimension surface).
4. **Unmeasured openings** — a detected door/window whose full extent was never in frame (tracked via coverage voxels overlapping the opening) → `unmeasuredOpening`.
5. **Suspicious dimensions** — sanity bounds: ceiling height ∉ [1.9 m, 4.5 m], wall length < 0.2 m, floor area implausible vs perimeter (isoperimetric check) → `suspiciousDimension`.
6. **Drift** — for Full Works, if a room's re-entry doorway position disagrees with its previously captured position by > 8 cm, flag `driftDetected` on the join.
7. **Insufficient coverage** — Space mode: filled voxels / expected < 92%.

Run these before ever emitting `.complete`. If `isPassing == false`, the coordinator enters a new state **`.needsReview(ScanResult)`** rather than `.complete`.

**Step 2 — The Review & Guided Re-scan screen (`.needsReview`):**

Design mirrors the existing result screen but with a guidance layer. This is a first-class state, not an error dialog.

- Show the **partial 3D model** in `ScanViewer3D`, already built so far — the user sees their real progress, which reduces frustration.
- Overlay each `ScanIssue` as a pulsing marker pinned to its `worldAnchor` (billboarded, colour by severity: blocking `AQ.amber`→red, warning `AQ.amber`, info `AQ.blue`). Markers stay locked to the geometry as the model orbits (they're child nodes of the model rig, so they inherit the centred-orbit behaviour from 6.2).
- A bottom sheet lists issues worst-first, each row: icon, plain-English hint ("The far-left corner didn't close"), and a **"Show me"** button that animates the camera to frame that marker (`SCNTransaction`, 0.5 s) and pulses it.
- Primary CTA: **"Fix these areas"** → re-enters live scanning in **patch mode**: the previously captured geometry is shown as a translucent `#7DD3FC` ghost in the AR view, with the flagged regions glowing. The user only needs to re-cover the glowing zones; coverage voxels for good areas are pre-filled so the ring only demands the missing bits. On return, merge the new capture into the existing `ScanResult` (don't discard the good data) and re-run the quality gate. Loop until `isPassing`.
- Secondary CTA: **"Use anyway"** (only if no `blocking` issues) — lets an experienced user accept a warning-level scan, with a persisted note on the record that it was accepted with warnings.
- Never allow export/quote generation from a scan with unresolved **blocking** issues — the "perfect every time" guarantee. Warnings may pass at user discretion.

**Step 3 — Patch-mode merge (technical):**
- Keep the accumulated `ARSession`/`CapturedRoom` alive where possible so re-scan is same-coordinate-space (no relocalisation needed). If the session was torn down (app backgrounded), require relocalisation against the saved world map (`ARWorldMap` persisted with the scan) before patch capture — show "Point at [nearest recognisable feature]" overlay.
- New geometry is fused into existing surfaces by nearest-surface association + weighted average (favour higher-confidence samples), not naive replacement — this monotonically improves the model and can't make a good wall worse.
- After each patch, recompute `ScanConfidence` and update markers live.

### 5.5 Output persistence & regeneration
- Persist `ScanResult` (JSON) + artefacts in `Documents/aq_scans/<id>/` (`result.json`, `model.usdz`, `plan.pdf`, `plan.svg`, `thumb.jpg`, optional `worldmap.arworldmap`).
- 2D/3D/CSV are regenerated from `result.json` on demand, so a future app version with a better plan renderer can re-emit prettier plans from old scans — do **not** treat the rendered PDF as the source of truth.
- All exports flow through the existing share-sheet pattern; Full Works bundles per-floor plans + whole-house USDZ + dimension CSV into a single zipped deliverable.

---

## 6. THE 3D VIEWER (shared, all modes)

The viewer is where the delight lands. One component, `ScanViewer3D`, used by all three modes and the history screens.

### 6.1 Engine
- SceneKit (`SCNView`) wrapped in `UIViewRepresentable`. SceneKit over RealityKit here because we need precise custom camera control; RealityKit's camera API is less mature for orbit constraints.
- Load the USDZ artifact via `SCNScene(url:)` off the main actor; show a skeleton shimmer (existing convention) while loading.

### 6.2 Camera — the "object stays centred" requirement
- **Orbit-around-pivot camera**: compute the model's bounding-box centre once at load; the camera is attached to an `SCNNode` rig whose pivot is that centre. Pan gestures rotate the rig (yaw unlimited, pitch clamped to −10°…+85° so the user can't go underground); the model therefore always stays dead-centre.
- Pinch zoom moves the camera along its local z toward the pivot, clamped between 0.4× and 6× the bounding-sphere radius — the model can never be lost off-screen or zoomed through.
- Two-finger pan is deliberately **disabled** (no free translation) — this is what guarantees the centred feel; it's also exactly what Apple's own RoomPlan preview does.
- Double-tap: animated reset to the default ¾ aerial view (`SCNTransaction` 0.45 s ease-in-out).
- Inertia on orbit (decaying velocity) for the premium hand-feel.

### 6.3 Presentation
- Light viewer background — `AQ.fill` → white vertical gradient — with a soft contact shadow under the model (SceneKit floor with shadow-only material). Matches the app's light theme; the dark treatment stays exclusive to live scanning.
- Walls rendered semi-opaque (85%) so interiors read from outside; doors/windows tinted `AQ.blue` at 30%; Space-mode meshes show the real baked texture with a "Show mesh" toggle (wireframe overlay in `#7DD3FC`).
- Dimension labels as billboarded `SCNText` that fade in over 300 ms only when camera distance < 2.5× bounding radius (avoids label soup at far zoom).
- Bottom control bar (capsule, `.ultraThinMaterial`): Reset · Dimensions on/off · Share (existing export sheet) · AR button — the AR button opens `ARQuickLookPreviewController` with the same USDZ so users can walk around the model at real scale in their actual space. This is a free, one-line feature that reliably produces the "no way" reaction.

### 6.4 Performance budget
- 60 fps orbit on iPhone 12 Pro. Full Works models: decimate merged meshes over 250k triangles (quadric simplification via ModelIO `MDLMesh` before display; keep the full-res mesh for export only). Texture atlas ≤ 4096². Viewer cold-open < 1.2 s for Room/Space, < 3 s for Full Works.

---

## 7. PERSISTENCE & HISTORY

- Extend `SavedQuote`/`SavedScan` with `scanMode: String` and `scanArtifactURL: String?` using the established backwards-compatible decoder pattern.
- History rows gain a mode chip (Room/Space/Full Works in `AQ.caption(11)`) and a 3D thumbnail: render once with `SCNRenderer.snapshot` at save time, cache as JPEG next to the USDZ.
- Artifacts live in `Documents/aq_scans/`; add a settings row showing total storage with "Remove 3D models older than 90 days" (keeps dimensions forever, deletes only meshes).

---

## 8. ACCEPTANCE CRITERIA

- [ ] Mode picker matches design tokens; Full Works locked in AccuScan with upsell sheet.
- [ ] Room mode unchanged functionally; now also persists USDZ and opens in the 3D viewer.
- [ ] Space mode: capture-volume placement, coverage ring, auto-complete, OBB dimensions, tap-to-measure at ±1 cm, rectangle fit for frames, textured USDZ export.
- [ ] Full Works: multi-room per floor, tracking kept alive between rooms, relocalisation recovery, StructureBuilder merge with progress phase, per-floor plans + dimension schedule + whole-house USDZ.
- [ ] Viewer: orbit locked to model centre, pitch clamp, zoom clamp, no free pan, double-tap reset, inertia, AR Quick Look, 60 fps on iPhone 12 Pro.
- [ ] **All three outputs (2D plan, 3D model, dimension CSV) derive from one `ScanResult`; a value changed on one appears identically on all three.**
- [ ] **2D plan is true vector (PDF/SVG), architectural conventions (wall thickness, door swings, window triple-line, auto-dimensioning, north arrow, scale bar); tap-to-edit a wall re-derives all outputs.**
- [ ] **Quality gate runs before `.complete` is ever emitted; open loops, mesh holes > 0.05 m², low-confidence surfaces, unmeasured openings, out-of-bounds dimensions, and drift are all detected deterministically.**
- [ ] **A failing scan enters `.needsReview`, shows the partial model with pulsing markers pinned to each issue's world anchor, worst-first issue list, and a "Show me" camera fly-to.**
- [ ] **"Fix these areas" re-enters patch mode: prior geometry shown as ghost, only flagged zones glow, coverage pre-filled for good areas, new capture fused (not replaced) into the existing `ScanResult`, gate re-runs, loops until passing.**
- [ ] **Export/quote generation is hard-blocked while any `blocking` issue is unresolved; warnings may be accepted with a persisted note.**
- [ ] **Patch mode reuses the live session when available; otherwise relocalises against a persisted `ARWorldMap` before capture.**
- [ ] `ScanResult` persists as JSON + artefacts under `Documents/aq_scans/<id>/`; plans/models regenerate from JSON so a future renderer can re-emit old scans.
- [ ] All state mutations `@MainActor`; heavy work in `Task.detached`; no regressions to existing quote flow.
- [ ] iOS 16 devices: Full Works hidden, Space requires LiDAR with graceful manual fallback, Room untouched.
