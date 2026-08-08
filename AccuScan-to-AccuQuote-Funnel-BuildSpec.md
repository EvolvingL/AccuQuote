# AccuScan → AccuQuote Conversion Funnel — Build Specification

> **TO CLAUDE CODE:** Implements the free-to-paid Trojan-horse funnel across two apps. Reference files: AccuScan (`ScanCoordinator.swift`, `NotificationService.swift`, `ContentView.swift`, `Views.swift`, `DesignSystem.swift`); AccuQuote (`AuthManager.swift`, `EntitlementManager.swift`, `QuoteGenerationService.swift`, `QuoteHistory.swift`). Mirror existing conventions: `enum AQ`/`enum AS` tokens, `@MainActor` state, file-backed JSON with atomic writes + backwards-compatible decoders, existing `NotificationService` scheduling. **Do not degrade AccuScan's standalone value — it must remain a complete, excellent free tool. Every prompt is dismissible; nothing nags.**

---

## 1. USER SEGMENTATION (AccuScan)

### 1.1 Persona tag — one tap, after first value

Store in a new `aq_user_profile.json` (`UserProfileStore`, same persistence pattern as history):

```swift
struct ASUserProfile: Codable {
    var persona: Persona = .unknown         // set once, editable in Settings
    var personaAskedAt: Date?
    var scanCount: Int = 0
    var distinctAddressCount: Int = 0        // proxy: distinct scan-session location clusters
    var exportCount: Int = 0
    var weekdayWorkHourScans: Int = 0        // scans Mon–Fri 07:00–17:00
    var firstScanAt: Date?
    var lastPromptShownAt: Date?
    var promptDismissCount: Int = 0
    var convertedToAccuQuote: Bool = false
}
enum Persona: String, Codable { case unknown, quoting, renovating, measuring, property }
```

Trigger: **after the first scan completes and dimensions render** (never on launch). Present a single sheet — "What do you use AccuScan for?" — four tappable cards (Quoting jobs / Planning a renovation / Just measuring / Work in property), styled on existing card component. Store result, set `personaAskedAt`. `.quoting` and `.property` = AccuQuote prospects. Skippable ("Ask me later" → re-ask after 3rd scan, max twice).

### 1.2 Behavioural scoring

Compute `prospectScore: Int` (0–100) on each scan completion, off-main:

```
+40  persona == .quoting
+20  persona == .property
+15  distinctAddressCount >= 3          (scans multiple properties = works for clients)
+10  scanCount >= 5
+10  weekdayWorkHourScans >= 3
+15  exportCount >= 2                    (using dimensions for real work)
```
`isHotProspect = prospectScore >= 50`. Recompute and persist each scan. This gates every in-app prompt so consumers never see trade-targeted messaging.

---

## 2. IN-APP CONVERSION MOMENTS (AccuScan)

One reusable component, `UpsellCard` (styled as a native next-step card, not a modal, not a banner ad). Content + trigger differ by moment. Central `UpsellCoordinator` decides which (if any) to show, enforcing frequency caps.

```swift
@MainActor final class UpsellCoordinator: ObservableObject {
    @Published var activeCard: UpsellMoment?
    // Rules: never show if !isHotProspect; never within 48h of last dismissal;
    // never more than once per session; stop after 6 total dismissals (respect the "no").
}
enum UpsellMoment { case postScan, frequency5, exportShare, featureLocked }
```

- **postScan** — after any scan, hot prospect: card under the dimensions. Copy: "You've measured this room. AccuQuote prices the job — materials, labour, a branded PDF — in about 90 seconds. First 3 quotes free." CTA → handoff (§4).
- **frequency5** — on 5th scan: "That's 5 rooms this week. Tradesmen use AccuQuote to turn each into a professional quote in minutes. Your first 3 are free."
- **exportShare** — fires when user exports/shares dimensions: "Pricing this up later? AccuQuote quotes the whole job while you're still on site."
- **featureLocked** — Full Works / advanced modes locked in AccuScan → benefit-first upsell (existing pattern).

All cards: primary CTA (handoff), secondary "Not now" (dismiss, increments `promptDismissCount`, sets `lastPromptShownAt`). Log impression + outcome to analytics.

---

## 3. NOTIFICATION SEQUENCE (AccuScan → AccuQuote)

Extend existing `NotificationService`. Schedule the 90-day sequence **only for hot prospects**, only after notification permission (requested after first scan, not launch). All local notifications (no server needed).

| Day | Trigger id | Body |
|---|---|---|
| 3 | `aq_upsell_d3` | "Quoting a job soon? AccuQuote turns your AccuScan measurements into a priced, branded quote." |
| 7 | `aq_upsell_d7` | "A professional-looking quote wins noticeably more jobs than a handwritten one. AccuQuote makes yours look the part." |
| 14 | `aq_upsell_d14` | "Price a full bathroom in minutes — materials and labour done for you. First 3 quotes free." |
| 30 | `aq_upsell_d30` | "Still measuring with AccuScan? Add pricing. 3 free quotes, no card." |
| 60 | `aq_upsell_d60` | "New in AccuQuote: {dynamic feature}. Turn your scans into quotes." |
| 90 | `aq_upsell_d90` | "Your measurements are half a quote already. Let AccuQuote finish the job." |

Cancel the whole sequence the moment `convertedToAccuQuote == true` (detected via §4 handoff or shared App Group flag). Each fire respects OS quiet hours; tapping deep-links to handoff.

---

## 4. THE HANDOFF (the core mechanic)

Carry the scan across so AccuQuote opens **with the room already loaded**. Two transport paths.

### 4.1 Shared App Group
Add both apps to App Group `group.com.slickdigital.accu`. AccuScan writes the most recent scan artifact (the `ScanResult`/USDZ + dimensions JSON from the tri-mode pipeline) to the shared container on every scan:
```
<AppGroup>/handoff/latest_scan.json   + latest_scan.usdz
```
Contains: dimensions, floor plan vector data, mode, capturedAt, a `handoffID` UUID.

### 4.2 Deep link
CTA calls `accuquote://import?handoffID={uuid}`:
- **AccuQuote installed:** opens directly, reads the App Group container, loads the scan, lands on "Here's the room you just scanned. Let's price it." → straight into quote generation pre-filled with dimensions. Sets shared flag `didConvert=true` (AccuScan reads it, cancels notifications, sets `convertedToAccuQuote`).
- **AccuQuote NOT installed:** universal link falls through to the App Store product page. On AccuQuote first launch, it checks the App Group container for a pending handoff and, if present, imports it so the **first-run screen is their room, never an empty state**.

### 4.3 AccuQuote import handler
`HandoffImporter` (AccuQuote): reads container, validates `handoffID` unused (dedupe), constructs a draft quote seeded with the scan's dimensions + floor plan, routes to `QuoteGenerationService` context so the AI already knows the room. Clears the handoff file after successful import.

**Acceptance:** a user tapping postScan in AccuScan lands in AccuQuote with their exact room loaded and can generate a quote without re-scanning or re-entering a single dimension.

---

## 5. ANALYTICS & FUNNEL INSTRUMENTATION

Emit events (existing analytics pipeline; if none, lightweight `aq_events.json` batched to `AQBackend`). Minimum event set per stage so each conversion ratio is measurable:

```
scan_completed            {mode, prospectScore}
persona_selected          {persona}
upsell_shown              {moment}
upsell_tapped             {moment}
upsell_dismissed          {moment, dismissCount}
handoff_initiated         {handoffID}
handoff_imported          (AccuQuote side)  {handoffID}
accuquote_first_quote     (AccuQuote side)
accuquote_subscribed      (AccuQuote side)  {tier}
```
Dashboards for: install → hot-prospect rate (target 30–40%), hot-prospect → upsell-tap (15–20%), tap → AccuQuote install (60%), install → first quote (70%), first quote → subscribe (25–35%). Blended target ≈ 3%.

**Privacy:** persona/behaviour data stays on device except anonymised funnel events. No personal quote/scan content ever transmitted. Enforce in one choke-point, unit-tested.

---

## 6. A/B TESTING HOOKS
Wrap upsell copy + notification bodies in a `RemoteConfig`-style keyed lookup (can be a bundled plist v1, remote later) so copy variants can be tested without a build. Assign a stable variant bucket per install (`hash(installID) % N`). Log variant on every `upsell_shown` so conversion can be attributed. Highest-priority tests: postScan copy, d7/d14 notification copy, persona-ask timing (after 1st vs 2nd scan).

---

## 7. BUILD ORDER
1. `UserProfileStore` + persona sheet + behavioural scoring (AccuScan). *Measurable segmentation, ships alone.*
2. App Group + handoff writer (AccuScan) + `HandoffImporter` (AccuQuote) + deep links. *The core mechanic — highest value.*
3. `UpsellCoordinator` + `UpsellCard` moments. *In-session conversion.*
4. Notification sequence extension (hot-prospect gated).
5. Analytics events + funnel dashboards.
6. A/B config layer.

Steps 1–2 alone create a working Trojan horse (scan in free app → one tap → priced in paid app). 3–6 optimise conversion rate on top.

---

## 8. QUALITY GATES
- [ ] AccuScan remains fully usable and pleasant for a user who never converts (no nagging; prompts stop after 6 dismissals; non-prospects never see trade upsells).
- [ ] Handoff loads the exact scan into AccuQuote with zero re-entry; dedupe prevents double-import.
- [ ] AccuQuote-not-installed path lands the scan on first launch (no empty state).
- [ ] Conversion detected → AccuScan cancels remaining notifications, sets `convertedToAccuQuote`.
- [ ] Persona/behaviour data never leaves device; only anonymised funnel events transmitted (choke-point test).
- [ ] Every prompt/notification respects frequency caps and OS quiet hours.
- [ ] All new stores decode old fixtures unchanged; no regression to scan flow performance (60 fps, scan-complete latency unchanged).
