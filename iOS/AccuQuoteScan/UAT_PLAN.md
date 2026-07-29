# AccuQuoteScan — UAT Plan

Covers everything actually built across Phases 0–7 of the Tri-Mode Scanning
build. Two device profiles needed — see device notes on each section.

- **Device A**: iPhone with LiDAR, iOS 17+ (e.g. iPhone 12 Pro or later) — the only config that can run all three modes end to end.
- **Device B**: iPhone without LiDAR (any iOS) — exercises fallback paths.

Test in this order — later sections assume earlier ones didn't leave the app
in a broken state (e.g. Phase 2 assumes you have at least one saved quote
from Phase 1 to look at in history).

---

## 0. First launch & auth (Device A or B)

- [ ] Fresh install (delete app first if reinstalling) — first launch doesn't crash or hang on a blank screen
- [ ] Sign-in flow completes (Google Sign-In and/or email, whichever you use)
- [ ] Camera permission prompt appears at the right time (first scan attempt, not at launch)
- [ ] App boots to the **mode picker** as the first real screen (not straight into a Room scan) — confirms Phase 7's `ModeLandingView` wiring
- [ ] "Just want to scan a room? Try it free →" guest link at the bottom still works and bypasses sign-in

---

## 1. Room mode — the core flow (Device A: LiDAR path, Device B: fallback path)

### 1a. Happy path (Device A, LiDAR)
- [ ] Tap **Room** card on mode picker → lands on the existing "Measure the room" screen
- [ ] "Start LiDAR Scan" begins a real RoomCaptureSession — walk a real room, confirm coverage ring fills as you cover walls/ceiling/floor
- [ ] Tap Done once coverage looks reasonable → either **Complete** (green checkmark) or **Needs Review** (see 1c)
- [ ] On Complete: dimensions look sane (compare to a tape measure — should be within a few cm)
- [ ] **"View in 3D"** row appears in the dimensions card and opens the shared 3D viewer — orbit works (drag), pinch-zoom clamps sensibly, double-tap recentres, bottom bar has Reset/Dimensions/Share/AR buttons
- [ ] Tap **AR** in the viewer — opens AR Quick Look, model appears anchored in your real space at real scale
- [ ] Tap **Share** — share sheet appears with a real `.usdz` file (send to yourself, confirm it opens in Files/Messages)
- [ ] **"Floor Plan"** row (new — sits directly under "View in 3D") opens a 2D top-down plan: walls, door swing arcs, window lines, dimension labels, room name/area label all present and legible
- [ ] Tap the share icon on the Floor Plan screen — share sheet appears with a real `.pdf` (send to yourself, confirm it opens and looks the same as on-screen)
- [ ] Proceed to "Describe the Job" → type or voice-record a job description → Generate Quote → real AI-generated sections appear with pricing
- [ ] After the quote saves, check history — the saved quote's `aq_scans/<id>/` folder should now contain both `model.usdz` and `plan.pdf` (only directly checkable via Files app "On My iPhone" if you've enabled file sharing for the app, otherwise just confirm nothing broke/hung during generation — the plan export happens silently in the background at this step)
- [ ] Quote saves — open History (profile menu → My Quotes) and confirm it's there with a **"Room"** mode chip and a 3D thumbnail image (not the placeholder cube icon)

### 1b. Fallback path (Device B, no LiDAR)
- [ ] Room mode shows "Sweep Room" instead of "Start LiDAR Scan", with poseFusion camera-sweep UI
- [ ] Sweeping produces a plausible dimension result (won't be as accurate — that's expected, just confirm it doesn't crash or produce nonsense like 0m or negative numbers)
- [ ] Manual entry path ("I have the measurements") still works as an alternative
- [ ] Confirm **no** "View in 3D" row appears (poseFusion has no CapturedRoom to show) — this is expected, not a bug
- [ ] History row for this quote shows scan method "Camera Sweep" or "Manual Entry" accuracy label correctly

### 1c. Quality gate / guided re-scan (Device A)
- [ ] Deliberately do a bad scan (stop very early, or scan a room with a mirror/glass wall) — should land on **Needs Review**, not silently complete or crash
- [ ] Needs Review screen shows the partial 3D model, lists the flagged issue(s) in plain English
- [ ] "Fix these areas" re-enters scanning — walk back and cover the flagged area, confirm it re-evaluates
- [ ] If only warnings (no blocking issues), "Use anyway" is available and completes the scan
- [ ] If a blocking issue is present, confirm "Use anyway" is **not** shown (quality gate should hard-block, per spec)

---

## 2. Space mode (Device A only — requires LiDAR; Device B should show the fallback, not crash)

### 2a. Void/recess capture (Device A)
- [ ] From mode picker, tap **Space** → capture screen opens with dark AR view
- [ ] Aim at a real gap (under a sink, a cupboard, an alcove) and tap on a detected surface to place the capture volume — a `#7DD3FC`-tinted box should appear anchored in AR
- [ ] Move around the detail — coverage ring fills, instruction text updates ("Move closer", "check the edges", etc.)
- [ ] Either let it auto-complete (~92% coverage held for 2s) or tap Done manually
- [ ] Result screen shows width/height/depth in mm — sanity-check against a tape measure (spec target ±1cm)
- [ ] Tap-to-measure: tap two points on the shown mesh, confirm a distance reading in mm appears and matches a rough manual check
- [ ] **Attach to quote**: type an item label, tap Attach — confirm it doesn't silently no-op
- [ ] **Save 3D model to Files (OBJ + USDZ)** — confirm both files export via the share sheet
- [ ] Confirm the attached measurement note actually appears in the job description text when you proceed to quote generation (this is the feature that makes it worth having — verify it isn't lost)

### 2b. Window/door frame capture (Device A)
- [ ] Same flow, but select **"Window / door frame"** target before placing the volume, aimed at a real window or door frame
- [ ] Result screen shows width/height/depth **and** a square-check ("Square" or "Out of square" with a diagonal delta in mm)
- [ ] Deliberately test on a frame you know is slightly uneven (older properties often have one) — confirm it flags "Out of square" rather than always saying "Square"

### 2c. Non-LiDAR fallback (Device B)
- [ ] Space mode on a non-LiDAR device shows the manual-entry screen with clear "this device doesn't have LiDAR" copy, not a crash or blank screen
- [ ] Manual width/height/depth entry (mm) works and produces a sane result

---

## 3. Full Works mode (Device A only — requires LiDAR + iOS 17+)

- [ ] From mode picker, tap **Full Works** → setup screen (property name + first floor picker)
- [ ] Start scanning → first room uses the exact same Room-mode scanning UI/quality gate as section 1
- [ ] After a room completes, lands on **between-rooms** screen showing a running floor summary (rooms captured, m² total)
- [ ] "Scan Next Room" repeats the capture for a second real room
- [ ] "Add another floor" prompts for a floor name and switches context correctly
- [ ] "Finish floor" on the last floor triggers the merge (StructureBuilder) — progress/processing screen shown, not a freeze
- [ ] Completion screen shows the "Scanned an N-room property in X minutes" stat card
- [ ] Per-floor **USDZ** share works for each floor
- [ ] Per-room **2D plan PDF** share works — open the PDF and visually check: walls, door swing arcs, window lines, dimension labels, room name/area label all present and legible
- [ ] **Dimension schedule CSV** share works — open in Numbers/Excel, confirm one row per room with correct L/W/H/area/counts
- [ ] Confirm the "combined whole-house USDZ isn't available" message is shown (this is a known, disclosed limitation — not a bug) rather than a broken/empty combined file being offered
- [ ] Confirm **no paywall or lock screen** appears anywhere in this flow (Full Works should be free in all tiers per spec)

---

## 4. Quote history & storage (Device A or B, after doing at least one of each mode above)

- [ ] Open quote history — each entry shows the correct mode chip (Room/Space/Full Works) and either a real 3D thumbnail or the fallback cube icon (never broken image)
- [ ] Search/filter in history still works with the new fields present
- [ ] Delete a quote — confirmation dialog appears, deletion works
- [ ] Profile menu → Account → **"3D scan storage"** row shows a non-zero, plausible size after the above testing
- [ ] Tap it → confirm the "Remove 3D models older than 90 days" dialog explains that dimensions/quotes are kept forever — trigger it and confirm quote history entries still exist afterward (only the mesh files should be affected, not the data)

---

## 5. Regression / cross-cutting checks

- [ ] Backgrounding the app mid-scan (any mode) and returning — session should resume or fail gracefully, never a hard crash
- [ ] Free-tier paywall still gates Room-mode quote generation correctly (LockedResultView) if you're testing on a non-paid account
- [ ] StoreKit purchase flow still works (if testing purchases, use a sandbox account)
- [ ] Rotate device / multitask (Slide Over, Split View if on iPad-compatible build) doesn't corrupt any in-progress scan
- [ ] Low storage / low battery — app should still function, no special crash under these conditions if you can simulate them

---

## 6. What to explicitly NOT expect (known, disclosed gaps — not bugs if you hit them)

- Combined whole-house USDZ with floor offsets — not implemented (RoomPlan API limitation, message shown instead)
- Space mode mesh export is untextured "clean CAD" only — no camera-texture baking yet
- 2D floor plan is view/export-only — no in-app "tap a wall to edit" correction yet
- No relocalization overlay if ARKit tracking drops between rooms in Full Works — it will just restart tracking silently; if a scan looks visibly wrong after an interruption, that's expected right now, flag it but don't treat it as a new bug
- AccuScan (the separate free sibling app) has not been updated with any of Phases 3–7 yet — this plan is AccuQuoteScan-only

---

## Reporting bugs found

For anything that fails, capture: device model + iOS version, which mode/step, what you expected vs. what happened, and if possible a screen recording (especially for AR/3D viewer issues — these are hard to describe in text). Send them back and I'll triage against the two categories above (real bug vs. known gap) before fixing.
