# AccuQuote — Paid Ad Strategy (£5/day Start)

**Objective:** Drive qualified UK tradie traffic to AccuQuote landing page
**Starting budget:** £5/day (~£150/month)
**Scale trigger:** Double daily budget every time CPA holds for 14 consecutive days
**Platforms:** Meta (primary, Weeks 1–4) → Meta + Google (Weeks 5+)

---

## 1. The Strategic Frame

Before any tactics, this is what every ad must do:

### Lead with the wound, not the product

Tradies aren't looking for "AI quoting software." They're looking to **stop bleeding margin on materials** and **stop losing weekends to paperwork**. The product is the answer to a problem they already feel. Don't sell AI. Sell relief.

### Inoculate against the cold-call fatigue

Every other ad in their feed right now is some bloke in a headset trying to book a Calendly call about AI. Your ads must signal **the opposite**: discover-it-yourself, no call, no salesperson, just try it.

Tactical implications:
- **No "Book a Demo" CTAs.** Use "Try Free" or "See It In Action."
- **No phone numbers in ads.**
- **Add the line** "No call required" or "Just download and try it" to creative.
- **No corporate slick.** Real faces, real vans, real quotes.

### Community is the proof, not a feature

The story isn't "Luke built an AI tool." It's "200+ UK tradies designed this with us." Show that. Faces, names, towns, vans, sites. Make the user research visible.

### Materials inflation is the wedge

Materials prices in the UK have moved hard since 2020 — and tradies feel it on every job. That's the universal pain. Lead creative angles with it:
- "Materials up 38% since 2020 — your quote template is from 2022"
- "AccuQuote scans live UK supplier prices every time you quote"
- "Stop discovering your quote was wrong when the supplier bill lands"

### Referrals are in the ad, not just the app

Every landing page banner reads: **"Bring 3 mates → 3 months free."** Every ad mentions community/peers. The cascade starts before signup, not after.

---

## 2. Why Meta First, Google Second

At £5/day you can only learn from one platform at a time. Splitting gives you noise on both.

**Meta wins Round 1 because:**
- Tradies live there (Facebook groups, Reels) — far more daily time than Google
- The community + materials story needs visuals — text-only Google can't carry it
- £5/day on Meta = 200–400 impressions/day (enough to test creative)
- £5/day on Google high-intent keywords = 2–5 clicks/day (too thin to learn)
- Meta creative compounds into organic content too (cross-post the winners)

**Google joins Round 2 (Week 5+) because:**
- High-intent capture (someone searching "quoting software for builders" is already a buyer)
- Different funnel position (bottom vs Meta's middle)
- By Week 5 you'll have MRR funding £10/day total

**Override rule:** If Meta CPL is over £8 after 14 days at £5/day, flip to Google immediately. Some products just don't convert on Meta.

---

## 3. Meta Ads — Full Setup

### 3.1 Campaign architecture

```
Campaign: AccuQuote_UK_Traffic_v1
├── Objective: Traffic (Weeks 1–2) → Conversions (Weeks 3+, once pixel has 50 events)
├── Budget: £5/day, CBO off (use Adset Budget for control at low spend)
├── Optimisation: Landing page views (Weeks 1–2) → Trial Signup (Weeks 3+)
└── Ad Sets:
    ├── AS1: Broad UK Tradies (primary)
    └── AS2: Retargeting (launches Week 2 once pixel has data)
```

### 3.2 Audience setup

**Ad Set 1 — Broad UK Tradies (£4/day initially)**

- **Geo:** United Kingdom, exclude Northern Ireland in Week 1 (keep targeting tight)
- **Age:** 28–60 (broad — let the algorithm find within it)
- **Gender:** All (don't exclude female tradies — small but real segment)
- **Detailed targeting (start narrow, broaden in Week 3 if needed):**

Use **OR** logic across these interests:
- Plumbing, Electrician, Construction worker, Carpentry, Roofer, Bricklayer
- Self-employment, Small business
- Screwfix, Toolstation, Wickes (page interests)
- Trade-specific magazines (Professional Builder, PHAM News if available)

- **Behaviours (layer ON TOP if reach is too wide):** Small business owners
- **Exclusions:** Anyone who has already visited the landing page (use Custom Audience once active)
- **Placements:** Advantage+ Placements ON (let Meta optimise — at £5/day you can't afford manual control)

**Ad Set 2 — Retargeting (Week 2+, £1/day to start)**

- Custom Audience: Website visitors last 30 days
- Custom Audience: 75% video views (from your founder videos and ads)
- Custom Audience: Facebook Page engagers last 90 days
- Exclude: Already-signed-up trial users
- Use a different creative — softer, social-proof heavy ("Sarah from Leeds quoted 6 jobs last Sunday")

### 3.3 Creative — 3 angles, 3 ads each (9 total to start)

You need a creative *library*, not single ads. Test multiple hooks, kill losers fast.

#### Angle A — Materials Inflation Pain

**Hook:** "Materials are up 38% since 2020 — your margin's the casualty."

**Ad A1 — UGC talking head (15–25 sec Reel)**
A real plumber, Welsh or Northern accent, on-site, in branded gear:
> "Quoted a bathroom three weeks ago. Materials came in £487 over what I quoted. That's my Sunday gone, for nothing. AccuQuote scans live supplier prices — actually shows you what stuff costs *today*. Game-changer."
CTA: **Try Free → accuquote.app/start**

**Ad A2 — Founder talking head (Luke, 30 sec)**
> "I'm Luke. I built AccuQuote because every tradie I know is losing £200–500 a job to materials inflation they didn't see coming. We scan live UK supplier prices every time you quote. No call required — try it free, see what your last job *should* have cost."

**Ad A3 — Static carousel**
- Slide 1: "Your 2023 quote template in 2026..."
- Slide 2: Photo of receipt showing £847 in materials (vs £589 quoted) — circled in red
- Slide 3: "AccuQuote: live supplier prices every quote"
- Slide 4: "200+ UK tradies use it. No salesperson will call you."

#### Angle B — The Sunday Quote (Workflow compression)

**Hook:** "Site visit → measure → scope → quote — all before you leave the driveway."

**Ad B1 — Screen recording (vertical, 30 sec)**
Phone screen recording showing: open AccuQuote in van → scan room with camera → AI populates materials list → tap → quote PDF generated. Caption overlay: "From site visit to sent quote. 4 minutes."

**Ad B2 — Tradie reaction (UGC, 20 sec)**
Builder in van, dashboard visible:
> "Used to take me 2 hours per quote. Did three today between jobs. Quote sent before I got home. Game over, mate."

**Ad B3 — Static comparison**
Two columns side by side:
- LEFT: "The old way" — list with 7 painful steps, ends with "quote rejected"
- RIGHT: "AccuQuote" — 3 steps, ends with "quote accepted same day"

#### Angle C — Community / Anti-Cold-Call

**Hook:** "Built *with* 200 UK tradies — not pitched at them."

**Ad C1 — User research montage (45 sec)**
Quick cuts: Luke in a van with a plumber discussing his quoting setup. Luke on a building site watching a sparky scope a job. Whiteboard notes from user interviews. Closing card: "Built with the people who use it. No sales calls. Just try it."

**Ad C2 — Faces and names static**
6 real user portraits (with permission) — name, trade, town under each. Headline: "These 6 helped design AccuQuote. Another 194 did too. None of them got cold-called. They found it. So can you."

**Ad C3 — The "no call" hook**
Plain bold text on a tradie van background:
> "Tired of AI sales calls? Same. We built this WITH 200 tradies — not for them. Try it, decide for yourself. No one will phone you."

### 3.4 Creative production reality

You won't shoot all 9 in week 1. Start with:
- **Week 1:** Ads A2 (founder talking head), B3 (static comparison), C3 (no-call hook) — all can be done by you on a phone with Sophia's help on Canva
- **Week 2:** Add B1 (screen recording demo) and C2 (faces static)
- **Week 3–4:** Recruit 3 beta users to film UGC (A1, B2)
- **Week 5–6:** Production-level shoot for A3, C1 if winners emerge

### 3.5 Budget pacing

| Week | Daily | Strategy |
|---|---|---|
| 1 | £5 | 3 creatives in 1 broad ad set, learn |
| 2 | £5 | Add retargeting ad set (£1), broad gets £4 |
| 3 | £5 | Kill losers, add 2 new creatives |
| 4 | £10 if CPA <£10 | Scale winning creative |
| 5+ | £15–25 if performing | Funded by MRR, mirror to Google starts |

### 3.6 Kill / scale criteria

After **48 hours** at minimum 1,000 impressions per creative:
- **CTR <1%** → kill the creative
- **CTR >2%** → put more behind it
- **Landing page view → trial signup rate <8%** → not the ad's fault, fix the LP

After **14 days**:
- **CPL <£5** → scale the winner, double the budget
- **CPL £5–£10** → hold, iterate
- **CPL >£10** → reassess the angle entirely (or flip to Google)

---

## 4. Google Ads — Full Setup (Week 5+)

Adding Google when MRR allows £5/day on top of the Meta £5/day.

### 4.1 Campaign architecture

```
Campaign: AccuQuote_UK_Search_v1
├── Type: Search Network only (no Display partners — kills budget)
├── Budget: £5/day
├── Bid strategy: Maximize Clicks (Weeks 5–8), then Maximize Conversions
├── Locations: UK, exclude Channel Islands & remote regions for now
├── Ad Schedule: Mon–Sat 6am–9pm (when tradies are searching)
└── Ad Groups:
    ├── AG1: Quoting Software (commercial intent)
    ├── AG2: Trade Quoting Help (informational intent)
    └── AG3: Materials & Pricing (problem-aware)
```

### 4.2 Keywords (start tight, expand based on data)

**Ad Group 1 — Quoting Software (highest intent)**

Phrase and exact match only at this budget. Examples:
- "quoting software for tradesmen"
- "quoting app for builders"
- "quoting app plumbers"
- "estimating software UK trades"
- "best quote software for tradesmen"
- "electrician quoting software UK"
- "builder quoting app"

**Ad Group 2 — Trade Quoting Help (mid intent)**

- "how to quote a building job"
- "how to quote a plumbing job"
- "builder quote template UK"
- "tradesman quote template"
- "how to write a quote for tradesmen"

**Ad Group 3 — Materials & Pricing (problem-aware)**

- "UK materials price increase"
- "building materials price tracker"
- "how to calculate material costs for a job"

**Negative keywords (apply campaign-wide):**
- free, freebie, free download (you have a free trial but free-seekers don't convert)
- job, jobs, career, vacancy, hiring
- salary, course, training, qualification
- diy, homeowner, customer (you want trade buyers, not their end clients)
- examples, sample (informational only, won't convert)
- youtube, reddit, forum (your organic is there, don't pay for it)

### 4.3 Responsive Search Ads (RSA) — 3 per ad group

**Ad Group 1 — Quoting Software**

**Headlines (15, Google picks 3 to show):**
1. AI Quoting App for UK Trades
2. Quote a Job in 5 Minutes
3. Live UK Supplier Prices
4. Built With 200+ UK Tradies
5. Stop Quoting on Sundays
6. No Sales Calls, Just Try It
7. Quote, Win, Get Paid Faster
8. From Van to Sent Quote in Minutes
9. Materials Prices Calculated Live
10. Try Free — Card Not Required
11. AccuQuote — The Trades Quoting App
12. Replace 2-Hour Quotes With 5-Minute Ones
13. Designed Around Real UK Tradies
14. Win More Jobs by Quoting Faster
15. UK Trade Quoting, Reinvented

**Descriptions (4):**
1. AccuQuote scans live UK supplier prices every quote. No more material-cost surprises eating your margin. Try free.
2. Built with 200+ plumbers, sparkies and builders. Quote a full job in 5 minutes — site visit to PDF.
3. No sales calls. No demo bookings. Just download and quote your next job in minutes. Free trial.
4. Bring 3 mates and get 3 months free. The fastest-growing quoting tool for UK trades.

**Final URL:** accuquote.app/start?src=g_quoting (UTM-tagged)

**Ad Group 2 — Trade Quoting Help**

Reframe headlines around the educational angle:
1. How to Quote Like a Pro in 2026
2. UK Tradesman Quote Template + App
3. Stop Guessing — Quote Accurately
4. Real Quote Templates for Trades
5. Free Quoting Tool for UK Trades
6. Win Quotes With Live Pricing
... [etc, 15 headlines]

**Ad Group 3 — Materials & Pricing**

Headlines around the materials inflation angle:
1. Materials Up 38% — Quote Accordingly
2. Live UK Supplier Price Tracking
3. Stop Bleeding Margin on Materials
... [etc]

### 4.4 Sitelink extensions (free, use all of them)

- "Free Quote Calculator" → /free-tool
- "How AccuQuote Works" → /how-it-works
- "Real User Stories" → /case-studies
- "Pricing" → /pricing

### 4.5 Callout extensions

- "No Sales Calls"
- "Built With UK Tradies"
- "Live Supplier Prices"
- "Quote in 5 Minutes"
- "Free Trial — No Card"

### 4.6 Audience targeting (observation, not exclusion)

Add as "Observation" audiences so you can see how they perform without restricting reach:
- In-market: Business Services
- In-market: Construction & Industrial Equipment
- Custom intent: people who've searched competing terms

### 4.7 Conversion tracking — set up before going live

- **Primary:** Trial Signup (the buy signal)
- **Secondary:** Landing Page View, Free Tool Use, Email Capture
- **Microconversions:** Video play >50%, Pricing page view

Without these, you're guessing. £5/day means every conversion event matters double.

---

## 5. Landing Page Requirements (Critical)

You'll burn the £5/day if the landing page can't convert. Non-negotiables based on the ad angles:

### Above the fold (what they see in 3 seconds)

- **Headline:** "Quote a job in 5 minutes. With live UK supplier prices."
- **Sub:** "Built with 200+ UK tradies. No sales calls. Just try it."
- **CTA button:** "Try Free — No Card" (large, contrasting colour)
- **Hero visual:** 30-sec autoplay muted video showing the van-to-quote flow
- **Trust strip:** 5 real user portraits with name + town + trade under each

### Below the fold

1. **The "we sat in vans" section** — show the user research process. Photos, names, towns. This is the differentiator.
2. **Materials inflation hook** — chart showing UK materials price rises 2020–2026, then "AccuQuote scans live prices every quote"
3. **3-step "how it works"** — site visit → AI scopes → quote sent
4. **Real user case study** — one detailed story with photos, ideally video
5. **Referral banner** — "Bring 3 mates, get 3 months free" (this should be visible *before* signup, not just after)
6. **FAQ** — top 5 objections (price, my trade isn't supported, do I need to be technical, what about my CRM, do you cold call me)
7. **No-call promise** — explicit section: "We will never cold call you. Ever. We hate it too."

### What NOT to put on the landing page

- Phone number (anti-cold-call signal)
- "Book a demo" / Calendly embed
- Live chat asking for your email upfront
- Corporate stock photography
- Logos of fake "as seen in" press until you actually have them
- Long forms (just email → trial → onboard inside the product)

---

## 6. Tracking & Attribution

### Pixels and tags to fire (before launch)

- Meta Pixel + Conversions API (Conversions API is critical with iOS 14+ attribution loss)
- Google Ads conversion tag + GA4
- UTM parameters on every ad:
  - utm_source = meta / google
  - utm_medium = paid
  - utm_campaign = [campaign name]
  - utm_content = [creative ID] / [ad group + keyword]

### Dashboard you need to check daily (5 min)

| Metric | Meta target | Google target |
|---|---|---|
| CTR | >1.5% | >5% (search) |
| CPC | <£0.80 | <£1.50 |
| Landing page view rate | >85% | >90% |
| Trial signup rate (from LP) | 8–15% | 8–15% |
| Cost per trial | <£8 | <£10 |
| Trial → paid rate | 25%+ | 25%+ |
| **Blended CPA (paid user)** | **<£35** | **<£40** |

If CPA <£35 and LTV is ~£780 (at £39/mo, 5% churn): payback in ~1.5 months. Strong unit economics.

---

## 7. The 90-Day Test Plan

### Days 1–14: Meta Foundation
- 1 ad set, 3 creatives (A2, B3, C3)
- Goal: identify which angle (materials, workflow, community) wins
- Decision Day 14: kill 2 losers, double down on winner

### Days 15–30: Meta Expansion
- Winning angle gets 2 new variants
- Retargeting ad set launches
- Goal: trial signups under £8
- Decision Day 30: scale or pivot

### Days 31–60: Google Joins
- £5/day on Google Search (MRR-funded)
- 3 ad groups live
- Continue Meta optimisation
- Goal: 2 channels with sub-£10 CPL

### Days 61–90: Scale Winners
- Total daily spend: £15–25 (MRR-funded)
- 2 new Meta angles tested
- Add Meta Lookalike audience (1% LAL of trial signup list, requires 1,000+ signups)
- Google Performance Max test (small budget)
- Goal: 200+ paid users cumulative

---

## 8. The "Don'ts" — Save Yourself Money

- **Don't run Display ads on Google.** £5/day vanishes in 2 hours of meaningless impressions on mobile games and parked domains.
- **Don't broad-target Meta with "Small business owner."** You'll get café owners, market traders, accountants.
- **Don't test more than 3 creatives at £5/day.** Each needs 1,000+ impressions to judge. £5/day = ~400 impressions. Math doesn't work.
- **Don't optimise for Engagement.** Vanity metric. Optimise for Landing Page Views (Weeks 1–2) then Trial Signups (Weeks 3+).
- **Don't use Boost Post inside Facebook.** Always create ads in Ads Manager. Boost Post is for amateurs and burns budget.
- **Don't use lookalike audiences before 1,000 trial signups in the source.** Meta needs critical mass to make a useful LAL.
- **Don't use a generic homepage as your landing page.** Build a dedicated /start or /try page that matches the ad copy.
- **Don't ignore the negative keyword list on Google.** "Builders Arms quotes" will eat your budget if you let it.

---

## 9. Scaling Rules — When to Add Budget

Every increase must be earned by data, not enthusiasm.

**Trigger to go from £5 → £10/day on Meta:**
- 14 consecutive days at CPL under £8
- CTR above 1.5% on at least 1 creative
- Trial → paid rate above 20%

**Trigger to add Google at £5/day:**
- Meta is profitable (CPA < LTV/3)
- MRR is > £1,500 (so paid spend is < 20% of MRR)

**Trigger to add a third channel (YouTube ads, TikTok ads):**
- Both Meta + Google are profitable
- MRR > £5,000
- You have 5+ pieces of high-performing creative to repurpose

**Hard ceiling at this stage:** Don't spend more than 30% of MRR on paid ads while you're still bootstrapped. Above 30% and one bad month wipes you out.

---

## 10. First-Week Setup Checklist

**Before any ad goes live:**

- [ ] Landing page live with all 7 above-fold requirements
- [ ] Meta Pixel + Conversions API installed and firing test events
- [ ] Google Tag Manager + GA4 + Ads conversion tag installed
- [ ] UTM strategy documented (use a UTM builder spreadsheet)
- [ ] Privacy policy + cookie banner GDPR-compliant
- [ ] /start, /how-it-works, /case-studies, /pricing pages built
- [ ] 5 real user portraits + quotes collected (with written permission)
- [ ] 3 ad creatives ready (A2, B3, C3 from the matrix)
- [ ] Trial signup flow tested end-to-end on mobile
- [ ] Referral banner live ("3 mates → 3 months free")
- [ ] Meta and Google account billing set up, daily caps in place
- [ ] Negative keyword list compiled
- [ ] Daily 5-min dashboard review scheduled (set a calendar reminder)

---

## 11. Sample Ad Copy — Ready to Paste

### Meta — Materials Inflation (A3 static)

**Primary text:**
> Your 2023 quoting template in 2026 is bleeding money.
>
> Materials are up 38% on average. Skirting up 51%. Copper pipe up 67%. Plasterboard up 44%.
>
> AccuQuote scans live UK supplier prices every time you quote. So when you say £4,800 — you actually make £4,800.
>
> Built with 200+ UK tradies. No one will cold call you. Just try it.

**Headline:** "Quote Like It's 2026 — Not 2022"
**Description:** "Live UK supplier prices on every quote. Try free, no card."
**CTA:** Learn More

### Meta — Anti-Cold-Call (C3)

**Primary text:**
> Got another AI sales call this week? Same.
>
> We built AccuQuote with 200+ UK tradies — sat in their vans, watched them quote, fixed what was broken.
>
> No salesperson will phone you. No demo to book. Just download, try it, decide for yourself.
>
> Quote a job in 5 minutes. Free for 14 days. Card not required.

**Headline:** "We Hate Cold Calls Too"
**Description:** "Try AccuQuote free. No salesperson, no pressure, just the tool."
**CTA:** Sign Up

### Google — Quoting Software (commercial intent)

**RSA — Sample assembled ad:**
- **H:** AI Quoting App for UK Trades
- **H:** Quote a Job in 5 Minutes
- **H:** Live UK Supplier Prices
- **D:** Built with 200+ plumbers, sparkies and builders. No sales calls. Just try it free — no card.
- **Path:** /try-free
- **Sitelinks:** Free Quote Calculator | How It Works | Real User Stories | Pricing

---

## 12. The One-Page Summary

If you only remember 10 things:

1. Meta first, Google Week 5+, never split £5/day across both
2. Lead with materials inflation, not AI
3. "No sales calls" in every ad — invert the cold-call experience
4. Real tradies, named, with towns — community is the moat
5. Referral mechanic visible before signup, not after
6. 3 creatives only at £5/day — testing more is statistical noise
7. £35 blended CPA target = 1.5-month payback at £39 MRR
8. Daily 5-min dashboard check, weekly creative review
9. Scale the budget only after 14 days of held performance
10. Never exceed 30% of MRR on paid spend while bootstrapped

---

*Document version 1.0 — review after Day 14, Day 30, Day 60, Day 90.*
