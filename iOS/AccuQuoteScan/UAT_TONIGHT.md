# Tonight's changes — UAT checklist

Everything requested and built this session, in the order it was requested.
Fresh install recommended before starting section 1 (sign-up flow changed
significantly and is easiest to test clean).

---

## 1. Sign-up & business verification (new — hard gate)

New accounts must now verify a real, active UK company/LLP against Companies
House **before** they can use the app at all. No one should hold working
login credentials without a verified business attached.

- [ ] From a signed-out state, tap **Sign Up** — the form now shows Email,
      Password, Confirm password, **and Business or trading name** all on
      one screen (previously business name wasn't collected at sign-up)
- [ ] Submit with a real, active UK company/LLP name (e.g. your own
      registered trading name) — account is created and you land straight
      in the app, no separate verification screen in between
- [ ] Submit with a made-up/nonsense business name — account creation still
      happens, but verification fails with a clear error message, and you
      are **not** left signed into a dead-end screen; check that the
      account was actually deleted (try signing up again with the same
      email — it should be available, not "already exists")
- [ ] Submit a real company name with a typo (e.g. missing "Ltd") — confirm
      a **"Did you mean:"** list of close Companies House matches appears;
      tapping one completes verification and signs you in without
      re-creating the account or erroring
- [ ] Try **Sign in with Apple** as a brand-new user — confirm you land on
      a **"Verify your business"** screen (separate from the sign-up form,
      since Apple sign-in has no business-name field) before reaching the
      app
- [ ] On that screen, enter a valid business name — verifies and continues
      into the app normally
- [ ] On that screen, tap **"Cancel and delete account"** (only shown for
      brand-new sign-ups) — confirm you're returned to the login screen and
      that Apple ID no longer has a live AccuQuote account behind it
- [ ] Sign out of an **already-verified**, existing account and sign back
      in — confirm you go straight to the app with no verification prompt
      (server-side status is cached, shouldn't re-ask every time)

---

## 2. Persistent profile button (top-right, every screen)

Previously the profile/account button only existed on the Room-scan "ready"
screen — if you were anywhere else (History, a result, an error screen) there
was no way back to Settings or Sign out without first tapping into a scan.

- [ ] From the main Room-scan screen, confirm the profile icon (top-right)
      still opens the profile menu as before — and there is only **one**
      button there now, not two stacked/overlapping icons
- [ ] Navigate to a quote result screen — profile icon is visible top-right
      and opens the same menu
- [ ] Navigate to History (My Quotes) — profile icon still visible
- [ ] Trigger an error state (e.g. force a bad scan or kill network mid-quote)
      — profile icon still visible on the error screen
- [ ] Start an actual LiDAR/AR scan — confirm the profile icon **disappears**
      while the camera view is active (it would otherwise sit on top of and
      obstruct the AR capture UI) and reappears once you leave scanning
- [ ] From the profile menu opened via the new global button, confirm Sign
      out / Settings / My Quotes all still work exactly as before

---

## 3. Onboarding question text (quick setup)

- [ ] Trigger the "Quick setup" 3-question prompt (new account, thin profile)
      — confirm the question about what's included in a quote now reads
      **"What do you normally include in a quote?"** in full, not cut off
      mid-sentence
- [ ] Confirm the grey placeholder text inside the answer box now shows the
      "labour only / labour and materials" examples that used to be jammed
      into the question itself

---

## 4. My Quotes — tap to view details (previously did nothing)

- [ ] Open History (My Quotes) — confirm each row's descriptive info line
      no longer starts with a literal **"Room"** label (for Space or Full
      Works scans, that chip should still show "Space"/"Full Works" as
      before — only the redundant "Room" text is gone)
- [ ] Confirm the **section count** ("N sections") is no longer shown on
      any row
- [ ] **Tap** (not long-press) on any saved quote — confirms it now opens a
      full detail screen (previously tapping did nothing at all)
- [ ] On the detail screen, confirm you see: customer name, job description,
      date, room type/area, the full labour/materials/VAT breakdown by
      section, and the total
- [ ] If the quote has a saved 3D scan, confirm a **"View 3D model"** button
      appears and actually opens the model (AR Quick Look / USDZ viewer)
- [ ] If the quote is an older record with no saved 3D artifact, confirm the
      "View 3D model" button is simply absent (not shown broken/greyed out)
- [ ] Long-press a quote row still brings up the delete confirmation as
      before — deleting still works

---

## 5. Final quote page — button layout

- [ ] Generate a quote through to the final result screen
- [ ] Confirm **"New Quote"** is now in the **top-right of the navigation
      bar**, not in the footer
- [ ] Confirm **"Send to customer"** is now a single, full-width button
      centered in the footer (no longer squeezed next to "New Quote")
- [ ] Tap "New Quote" from the nav bar — confirms it still resets/starts a
      fresh quote exactly as the old footer button did
- [ ] Tap "Send to customer" — confirms the share sheet / PDF flow still
      works unchanged
- [ ] Confirm the row below (Full BOM / Request deposit via Stripe) is
      untouched and still both work

---

## Notes for whoever's testing

- Section 1 needs a **Companies House API key** configured server-side
  (`COMPANIES_HOUSE_API_KEY`) — if that's not set yet, every verification
  attempt will fail with a "Verification service not configured" error
  that's expected in that case, not a bug to file.
- Everything above was verified to compile clean (`xcodebuild` succeeded
  after every change) but has **not** been run in the simulator/device yet
  this session — this list is the first real functional pass.
