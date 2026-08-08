# AccuQuote — App Store Connect Listing Content

Everything needed to fill in App Store Connect's "App Information," "Pricing and
Availability," "App Privacy," and version-release metadata screens. Copy/paste
ready. Character limits noted where Apple enforces them.

---

## 1. App Information

**Name** (30 char max)
```
AccuQuote
```

**Subtitle** (30 char max — appears under the name in search/listing)
```
Scan. Quote. Send. In Minutes.
```
(29 chars)

**Bundle ID**
```
com.accuquote1.scan
```

**SKU** — any unique string you haven't used before, e.g.:
```
accuquote-ios-2026
```

**Primary language**
```
English (U.K.)
```

**Category**
- Primary: **Business**
- Secondary: **Productivity** (both fit; Business first since the core buyer is a tradesperson running a business, not a general productivity user)

---

## 2. Pricing and Availability

- Price: **Free** (app itself; revenue is via subscription, so the app download price is £0)
- Availability: All territories, or restrict to **United Kingdom** only for launch — the product is UK-specific (UK supplier pricing, £ pricing, UK trades regulations/copy). Recommend UK-only at launch to avoid support/refund noise from territories the product isn't built for; expand later.

---

## 3. Description (4000 char max)

```
AccuQuote turns a room scan into a professional, priced quote — before you've left the driveway.

Built for UK tradespeople who are losing evenings and weekends to quoting instead of doing the work they're actually good at.

HOW IT WORKS

1. SCAN
Point your phone at the room. AccuQuote uses your iPhone's camera (with LiDAR on supported models) to measure the space in seconds — no tape measure, no guesswork.

2. DESCRIBE
Tell AccuQuote what the job is — type it or just speak it. Our AI scopes the work from your description and the room's real dimensions.

3. PRICE
Live UK supplier pricing populates the materials list automatically, so your margin is protected from day one — not eaten by prices that moved since you last checked.

4. SEND
A branded, itemised PDF quote is ready to send — WhatsApp, email, however your customers prefer it. No spreadsheet. No late-night quote-writing.

THREE WAYS TO SCAN

• Room — measure a full room in under a minute, with a live 3D model and floor plan
• Space — precision-measure a detail: an under-sink void, a window frame, an alcove, accurate to within a centimetre
• Full Works — map an entire property, floor by floor, with a full room-by-room dimension schedule

EVERY SCAN GIVES YOU
• Accurate dimensions (LiDAR-precision on supported iPhones)
• A 3D model you can view, rotate, and share as a USDZ file (view in AR on your customer's phone)
• A 2D architectural floor plan, exportable as PDF
• A dimension schedule for every room

BUILT FOR HOW TRADESPEOPLE ACTUALLY WORK
No sales calls. No demo bookings. No forcing you to learn new software on a job site. Sign in, scan, quote — same day you install it.

SUBSCRIPTIONS
AccuQuote offers free trial quotes, then a paid subscription for unlimited use. Solo, Team, and Crew tiers are available depending on how many people in your business need access — see in-app for current pricing. Subscriptions renew automatically; manage or cancel any time in your Apple ID account settings.

Questions, feedback, or just want to talk to a real person? Email us — see our support page for details.
```

*(Adjust the "Solo, Team, and Crew tiers... see in-app for current pricing" line if you'd rather list exact prices — Apple allows either; in-app is safer since prices can change without needing an app update or listing edit.)*

**Promotional text** (170 char max — the only description field you can update without a new app version; use for time-sensitive offers)
```
Free trial quotes, no card required. Scan a room, get a priced quote in minutes. Built for UK tradespeople.
```

---

## 4. Keywords (100 char max, comma-separated, no spaces needed after commas, don't repeat words already in Name/Subtitle)

```
tradesman,quote,quoting,builder,plumber,electrician,estimate,scan room,measure,LiDAR,job pricing,UK trade
```
(Avoid repeating "AccuQuote", "Scan", "Quote", "Send" since those are already in Name/Subtitle and get free credit — swap in words like "estimate", "builder", "plumber" instead, which I've done above.)

---

## 5. Support & Marketing URLs

| Field | URL |
|---|---|
| Support URL (required) | `https://accuquote.uk` (or a dedicated `/support` page if you want one — the marketing site homepage is acceptable if it has contact info, which it does via the footer) |
| Marketing URL (optional) | `https://accuquote.uk` |
| Privacy Policy URL (required) | `https://accuquote.uk/privacy-policy.html` |

---

## 6. App Privacy (the "Privacy Nutrition Label" questionnaire)

Based on what's actually implemented (`Info.plist` permission strings + `privacy-policy.html` + the server's Firebase/Anthropic/Stripe integrations):

**Data types collected, and Apple's required categorization:**

| Data type | Collected? | Linked to identity? | Used for tracking? | Purpose |
|---|---|---|---|---|
| Email Address | Yes | Yes | No | App Functionality (account creation/sign-in) |
| User ID | Yes (Firebase UID / Apple/Google sign-in identifier) | Yes | No | App Functionality |
| Photos or Videos | Yes (quote PDFs saved to Photos, only if user opts in via share sheet) | No | No | App Functionality |
| Precise Location | No | — | — | — |
| Coarse Location | Yes (`NSLocationWhenInUseUsageDescription` — nearest supplier branch) | No | No | App Functionality |
| Audio Data | Yes (microphone for voice-described jobs — transcribed, not stored as audio per your privacy policy's description) | No | No | App Functionality |
| Other User Content | Yes (job descriptions, sent to Anthropic's Claude API server-side for quote generation) | No | No | App Functionality |
| Payment Info | Yes (via StoreKit for subscriptions; via Stripe for customer deposit links) | Yes | No | App Functionality |
| Product Interaction | Only if you've added analytics — currently none beyond the funnel-events queue, which is anonymised and not yet live server-side (see §5/§8 of the Funnel Build Spec) — answer "No" unless/until `/api/events` ships |

**"Data Used to Track You"**: **No** — nothing here meets Apple's tracking definition (no cross-app/cross-site correlation, no data broker sharing, no third-party ad networks).

**Data linked to the user**: Email, User ID, Payment Info.
**Data not linked to the user**: Coarse location (used transiently for a supplier lookup, not stored against the account per your policy's wording — confirm server-side that you don't persist it against the user record; if you do, move it to "linked").

Fill this in via **App Store Connect → App Privacy → Get Started**, answering per the table above. Apple double-checks this against actual app behaviour during review, so keep it accurate to what's actually sent server-side — worth a final grep of `server/index.js` for anything sent to Firebase/Anthropic/Stripe beyond what's listed above before you submit.

---

## 7. Age Rating

Complete Apple's questionnaire (App Store Connect → App Privacy is separate from Age Rating — don't confuse the two, Age Rating is its own section). Given this is a B2B trade tool with no user-generated public content, no violence/gambling/mature themes, expect: **4+**.

---

## 8. Subscription / In-App Purchase Setup

Products confirmed from `Products.storekit` + `server/index.js` env vars — **note the local StoreKit test config only has 4 of the 6 products your server expects** (Team Annual and Crew Annual exist as env var slots — `STRIPE_PRICE_TEAM_ANNUAL`, `STRIPE_PRICE_CREW_ANNUAL` — but aren't in the local `.storekit` test file). Create all 6 as In-App Purchases in App Store Connect regardless of what's in the local test config:

| Product ID | Reference Name | Price (as configured) | Duration |
|---|---|---|---|
| `com.accuquote1.scan.solo.monthly` | Solo Monthly | £99.00 | 1 month |
| `com.accuquote1.scan.solo.annual` | Solo Annual | £990.00 | 1 year |
| `com.accuquote1.scan.team.monthly` | Team Monthly | £199.00 | 1 month |
| `com.accuquote1.scan.team.annual` | Team Annual | — *(set to match your intended annual discount, e.g. £1990.00 for a 2-months-free equivalent — not yet defined anywhere in code, decide and confirm)* | 1 year |
| `com.accuquote1.scan.crew.monthly` | Crew Monthly | £349.00 | 1 month |
| `com.accuquote1.scan.crew.annual` | Crew Annual | — *(same gap — not yet defined, decide before submitting)* | 1 year |

All 6 belong to **one subscription group** (matches `Products.storekit`'s "AccuQuote Pro" group) so users can upgrade/downgrade between tiers with proration.

**Subscription display name/description per tier** (from `Products.storekit` localizations):
- **Solo**: "Unlimited quotes for one user"
- **Team**: "2–5 users, shared customer database"
- **Crew**: "6+ users, multi-branch"

**App Review Information for subscriptions** (required text box in ASC):
```
AccuQuote is a quoting tool for UK trade businesses. New accounts get 3 free trial quotes before a subscription is required. The demo account below is a real free-tier account (not pre-subscribed) so you can see the actual first-run experience:

1. Sign in with the demo account credentials below.
2. On the mode picker, choose "Room" and start a scan. On Simulator/devices without LiDAR, tap through to the manual entry fallback ("I have the measurements") and enter any plausible dimensions (e.g. 4m x 3m x 2.4m).
3. Type a short job description (e.g. "repaint walls and ceiling") and generate a quote — this is a real, free trial quote. Repeat this 2 more times (3 free quotes total) — all three should succeed.
4. On the 4th quote attempt, the paywall (LockedResultView) should appear prompting a subscription — this is expected, not a bug.
5. To test the unlocked/paid experience directly, sandbox StoreKit purchases can be completed with a Sandbox Apple ID against any of the subscription products listed above.

Demo account:
Email: [fill in once created, e.g. slickdigitaluk+accuquote-reviewer@gmail.com]
Password: [fill in]
```

**Demo account — action needed**: create a real email + password account (not Google/Apple sign-in, so the reviewer can type credentials directly) via the app's own sign-up flow. Leave it on the free tier — don't pre-grant a subscription — so the reviewer sees the real new-user path and the paywall as intended. Paste the final credentials into the template above before submitting.

---

## 9. Screenshots (required sizes — 6.9" and 6.5" iPhone minimum; iPad only if you support it)

Per `UISupportedInterfaceOrientations` (portrait only) and `UIRequiredDeviceCapabilities` (arm64 only, no `arkit` hard-gate) — no iPad-specific screenshots needed unless you've enabled iPad idiom.

Required sizes (upload the largest of each and Apple auto-scales down where permitted — check current ASC requirements, they change occasionally):
- **6.9" display** (iPhone 16 Pro Max / 15 Pro Max class) — mandatory
- **6.5" display** (iPhone 11 Pro Max / XS Max class) — mandatory unless 6.9" covers it (ASC will tell you at upload time if a size can be waived)

Suggested screenshot sequence (5–10 images), based on what's actually built:
1. Mode picker screen (Room / Space / Full Works cards) — first impression of the product's range
2. Live Room scan in progress (coverage ring UI)
3. Result screen — dimensions + "View in 3D" + "Floor Plan" rows visible
4. 3D model viewer (AR Quick Look or in-app viewer)
5. 2D floor plan export
6. Job description / voice input screen
7. Generated quote with pricing (the actual payoff moment — arguably your strongest screenshot)
8. Quote history / saved quotes list
9. Paywall / subscription tiers screen (Apple wants to see this clearly if you have IAP — don't hide it)

Add short text overlays per Apple's usual style ("Scan a room in 60 seconds," "AI prices the job," "Send a pro quote before you leave") — you have this exact three-step copy already in the landing page draft and website meta description, reuse it verbatim for consistency across App Store, website, and ads.

---

## 10. App Preview Video (optional but recommended given this is a spatial/AR product)

Not required, but a 15–30s screen recording of a real Room scan → quote generation flow would convert far better than screenshots alone for a product whose whole differentiator is "watch this actually work." Lower priority than the required text/screenshot fields — revisit after the core listing is submitted once, if time allows before the deadline.

---

## Open items you need to decide/provide before this is submission-complete

1. **Team Annual / Crew Annual pricing** — not defined anywhere in code or docs; decide the figures and add them as products in ASC (see §8).
2. **Demo/reviewer account** — create one and add its credentials to the App Review Information notes.
3. **Screenshots** — none exist yet; need to be captured from a real device/simulator run of the app.
4. **UK-only vs. worldwide availability** — confirm your choice (§2) — recommend UK-only for launch given the product's UK-specific pricing data.
