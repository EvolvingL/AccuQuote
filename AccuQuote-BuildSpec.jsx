import { useState } from "react";

const BLOCKS = [
  {
    id: 1,
    title: "App Shell + Global State",
    icon: "🏗️",
    estimated: "1 session",
    claudeCall: false,
    status: "foundation",
    goal: "Create the persistent React app container with routing, global state, and the sidebar navigation. Every subsequent block slots into this shell without modification.",
    techStack: [
      "React 18 with useState / useContext for global state",
      "React Router v6 — hash-based routing (no server needed)",
      "Tailwind CSS via CDN for utility classes",
      "Lucide React for icons",
      "No build step — single JSX artifact that runs in Claude sandbox"
    ],
    globalStateShape: `{
  // Set during Block 2 — Onboarding
  profile: {
    id: string,
    name: string,                    // e.g. "Dave Harris"
    businessName: string,            // e.g. "Harris Electrical Ltd"
    trade: string,                   // e.g. "electrician"
    specialisms: string[],           // e.g. ["consumer units","EV chargers","rewires"]
    avoidJobs: string[],             // e.g. ["flat roofs","asbestos work"]
    homePostcode: string,            // e.g. "WD23 1AA"
    travelRadiusMiles: number,       // e.g. 25
    dayRatePerPerson: number,        // e.g. 350
    typicalOperatives: number,       // e.g. 1
    targetMarginPct: number,         // e.g. 30
    minimumJobValue: number,         // e.g. 500
    workingHoursEnd: string,         // e.g. "17:30"
    paymentTerms: string,            // e.g. "50% deposit, balance on completion"
    vatRegistered: boolean,
    vatNumber: string,
    preferredSuppliers: {            // ordered by preference per category
      electrical: string[],          // e.g. ["screwfix","cef","tlc"]
      general: string[],             // e.g. ["screwfix","toolstation"]
    },
    brandColour: string,             // hex e.g. "#FFD600"
    logoUrl: string,                 // base64 or URL
    toneOfVoice: string,             // e.g. "friendly but professional"
    standardTCs: string,             // full T&C text block
    guaranteeText: string,           // e.g. "All work guaranteed for 2 years"
    workingStyleNarrative: string,   // raw free-text from onboarding Q
    parsedProfileJson: object,       // Claude-parsed structured version
  },

  // Set during Block 4 — Job Capture
  currentJob: {
    id: string,
    createdAt: string,
    status: "capturing"|"calculated"|"proposed"|"accepted"|"ordered"|"complete",
    customer: {
      name: string,
      email: string,
      phone: string,
      address: string,
      postcode: string,
    },
    scan: {
      roomType: string,              // e.g. "bathroom"
      dimensions: {                  // metres
        length: number,
        width: number,
        height: number,
      },
      surfaces: {
        floorArea: number,           // m²
        wallArea: number,            // m²
        ceilingArea: number,         // m²
      },
      features: {
        windowCount: number,
        doorCount: number,
        existingSocketCount: number,
        existingLightCount: number,
      },
      anomalies: string[],           // e.g. ["damp patch NE wall","no earth bonding"]
      rawDimensionInputs: object,    // exactly what user typed
    },
    jobDescription: string,          // raw free-text voice/typed description
    outOfScope: string,              // explicit exclusions user stated
    customerSuppliedMaterials: string[],
    subContractorsNeeded: string[],
    proposedStartDate: string,
    estimatedDurationDays: number,
  },

  // Set during Block 5 — Materials Agent
  billOfMaterials: [
    {
      id: string,
      material: string,              // e.g. "2.5mm² twin & earth cable"
      quantity: number,              // e.g. 50
      unit: string,                  // e.g. "m"
      category: string,              // e.g. "cable"
      wasteFactor: number,           // e.g. 0.1 = 10% added
      quantityWithWaste: number,
      supplierPreference: string,    // e.g. "screwfix"
      catalogueLookup: {
        sku: string,
        productName: string,
        supplierName: string,
        packSize: number,
        packUnit: string,
        pricePerPack: number,
        packsNeeded: number,
        lineTotal: number,
        inStock: boolean,
        url: string,
      },
      customerSupplied: boolean,
      notes: string,
      agentConfidence: "high"|"medium"|"low",
    }
  ],

  // Set during Block 6 — Quote Builder
  quote: {
    materialsTotal: number,
    labourLines: [
      { description: string, days: number, operatives: number, dayRate: number, total: number }
    ],
    labourTotal: number,
    expenses: {
      travel: number,
      parking: number,
      skipHire: number,
      subContractors: number,
      other: number,
    },
    expensesTotal: number,
    costBase: number,               // materials + labour + expenses
    tiers: {
      standard: { margin: number, total: number, vatAmount: number, grandTotal: number, label: string },
      premium:  { margin: number, total: number, vatAmount: number, grandTotal: number, label: string },
      priority: { margin: number, total: number, vatAmount: number, grandTotal: number, label: string },
    },
    selectedTier: "standard"|"premium"|"priority",
    depositAmount: number,
    depositPct: number,
  },

  // Set during Block 7 — Proposal
  proposal: {
    id: string,
    generatedAt: string,
    scopeBullets: string[],          // Claude-cleaned scope bullets
    coverLetterText: string,         // Claude-written in tradesperson tone
    sentAt: string,
    sentVia: "email"|"sms"|"whatsapp",
    viewedAt: string,
    status: "draft"|"sent"|"viewed"|"accepted"|"declined",
  },

  // Set during Block 8 — Customer Acceptance
  acceptance: {
    acceptedAt: string,
    depositPaid: number,
    stripePaymentIntentId: string,   // mocked in demo
    confirmationSentAt: string,
  },

  // Set during Block 9 — Pre-Orders
  supplierOrders: [
    {
      supplierId: string,
      supplierName: string,
      lines: [ { sku: string, productName: string, qty: number, unitPrice: number, lineTotal: number } ],
      orderTotal: number,
      deliveryAddress: "site"|"yard",
      requestedDeliveryDate: string,
      status: "draft"|"committed"|"confirmed",
      poReference: string,
    }
  ],

  // Set during Block 10 — Dashboard
  jobs: [],  // array of completed/historical currentJob snapshots
}`,
    screens: [
      {
        name: "AppShell",
        description: "Persistent wrapper. Renders sidebar + <Outlet /> for current screen. Sidebar shows: AccuQuote logo, nav links (Dashboard, New Job, Active Job, Settings), current job progress indicator (steps 1–7 with completion ticks), and at the bottom: tradesperson name + trade badge."
      },
      {
        name: "Sidebar progress tracker",
        description: "Shows 7 steps: Scan → Describe → Materials → Quote → Proposal → Accepted → Ordered. Each step shows: pending (grey dot), active (orange pulse dot), complete (green tick). Clicking a completed step navigates back to it."
      }
    ],
    designSystem: "AccuQuote brand throughout: background #0D0D0D, surface #111418, accent #FFD600 (hi-vis yellow), secondary #FF6B00 (orange), text #F5F0E8. Font: Barlow Condensed (headings, bold labels) + Barlow (body). All buttons: uppercase, letter-spacing 2px, no rounded corners (border-radius: 3px max). Industrial, no-nonsense aesthetic.",
    acceptanceCriteria: [
      "App loads with sidebar visible and Dashboard screen rendered",
      "Navigating between screens via sidebar works",
      "Global state context is accessible from any screen",
      "Profile stub is pre-loaded with a fictional electrician (Dave Harris, Watford) so all other blocks can be built without completing onboarding first",
      "Active job stub is pre-loaded with a test bathroom rewire job",
      "Console logs state shape on load so it's inspectable during development"
    ]
  },
  {
    id: 2,
    title: "Onboarding — Guided Q&A + Claude Profile Parse",
    icon: "⚙️",
    estimated: "2 sessions",
    claudeCall: true,
    status: "core",
    goal: "Capture the tradesperson's full working profile through a conversational step-by-step flow. The final screen sends their free-text description to Claude API which returns a structured profile JSON merged into global state. Once complete, the tradesperson never has to configure again — every quote inherits their settings.",
    screens: [
      {
        name: "OnboardingWelcome",
        description: "Full-screen dark landing. Logo, headline: 'Let's set you up. Takes 4 minutes.' Subline: 'We'll ask you a few questions. No forms to fill — just tell us how you work.' Single CTA button. Skip link in corner (loads stub profile for demo)."
      },
      {
        name: "OnboardingSteps (multi-step, 8 steps)",
        description: `Each step is a full-screen card with: step counter (3/8), question in large Barlow Condensed, input below, Next button. Progress bar at top. Steps:

STEP 1 — What's your name and business name? (two text inputs)
STEP 2 — What trade are you? (large tap-to-select grid: Electrician, Plumber, Gas Engineer, Builder, Tiler, Plasterer, Roofer, Painter & Decorator, Carpenter, Landscaper, Other). Multi-select allowed.
STEP 3 — What are your specialisms? (free text + suggested chips based on trade selected e.g. for electrician: 'Consumer units', 'EV chargers', 'Rewires', 'CCTV', 'Solar', 'Commercial')
STEP 4 — Where are you based and how far will you travel? (postcode input + radius slider: 5/10/15/25/40/50 miles)
STEP 5 — What's your day rate and how many operatives do you usually work with? (number input for day rate, stepper for operatives 1–5)
STEP 6 — What's your target margin? (slider 10%–50%, default 30%. Show live example: 'On a £1,000 cost job your quote would be £X')
STEP 7 — Which suppliers do you use? (tap-to-select multi: Screwfix, Toolstation, Jewson, Travis Perkins, CEF, TLC Electrical, Plumb Center, City Plumbing, other). Reorder by drag to set preference.
STEP 8 — Describe how you work. (large textarea + mic button for voice. Prompt text: 'In your own words: what kinds of jobs do you go for, what do you avoid, how do you like to work, what are your standards? Speak as if briefing a new employee on your entire way of working. The more detail, the better every quote will be.')`
      },
      {
        name: "OnboardingProcessing",
        description: "Full screen animation while Claude API call runs. Show: 'Building your profile...' with animated steps ticking off: 'Understanding your trade ✓', 'Mapping your job preferences ✓', 'Setting up your pricing rules ✓', 'Configuring supplier preferences ✓'. Minimum 3 second display even if API returns faster."
      },
      {
        name: "OnboardingComplete",
        description: "Profile summary card. Shows parsed profile back to user: trade badge, day rate, margin, suppliers, radius. Editable inline. 'Looks good — start quoting' CTA navigates to Dashboard."
      }
    ],
    claudeCallSpec: {
      model: "claude-sonnet-4-20250514",
      systemPrompt: `You are a profile parser for AccuQuote, a quoting app for UK tradespeople. Extract structured data from the tradesperson's self-description and the structured answers they provided. Return ONLY valid JSON, no preamble, no markdown fences.`,
      userPromptTemplate: `Tradesperson answers:
Trade: {{trade}}
Specialisms: {{specialisms}}
Location: {{postcode}}, radius {{radius}} miles
Day rate: £{{dayRate}}, Operatives: {{operatives}}
Target margin: {{margin}}%
Preferred suppliers: {{suppliers}}

Their own description of how they work:
"{{workingStyleNarrative}}"

Return this exact JSON structure (fill all fields, infer sensibly from context):
{
  "jobTypesExcellentAt": ["..."],
  "jobTypesToAvoid": ["..."],
  "typicalJobSizeRange": { "min": number, "max": number },
  "workingStyle": "...",
  "qualityStandards": "...",
  "customerCommunicationStyle": "...",
  "commonMaterialsUsed": ["..."],
  "sundryItemsAlwaysNeeded": ["..."],
  "wasteFactorByMaterialType": { "cable": 0.05, "conduit": 0.1, "... ": 0.0 },
  "toneOfVoice": "...",
  "redFlags": ["job types or situations to flag in quotes"],
  "suggestedGuaranteeText": "..."
}`,
      maxTokens: 1000,
      parseInstructions: "JSON.parse response directly. Merge into profile object in global state."
    },
    stubProfile: {
      name: "Dave Harris",
      businessName: "Harris Electrical Ltd",
      trade: "electrician",
      specialisms: ["consumer units", "EV chargers", "full rewires", "fuse board upgrades", "outdoor lighting"],
      avoidJobs: ["industrial three-phase", "anything requiring asbestos survey", "jobs under £300"],
      homePostcode: "WD23 1AA",
      travelRadiusMiles: 20,
      dayRatePerPerson: 350,
      typicalOperatives: 1,
      targetMarginPct: 30,
      minimumJobValue: 500,
      workingHoursEnd: "17:30",
      paymentTerms: "50% deposit on acceptance, balance on completion",
      vatRegistered: true,
      vatNumber: "GB 123 4567 89",
      preferredSuppliers: { electrical: ["screwfix", "cef", "tlc"], general: ["screwfix", "toolstation"] },
      brandColour: "#FFD600",
      toneOfVoice: "friendly, direct, no waffle",
      standardTCs: "All work carried out to BS 7671:2018. Payment terms as quoted. Variations charged at day rate. Guarantee: 2 years labour, manufacturer warranty on parts.",
      guaranteeText: "All electrical work guaranteed for 2 years. All parts carry full manufacturer warranty."
    },
    acceptanceCriteria: [
      "All 8 steps render and validate correctly",
      "Voice input (Web Speech API) works on step 8",
      "Claude API call fires on step 8 submit with correct prompt",
      "Parsed JSON is logged and merged into global profile state",
      "OnboardingProcessing shows animated steps",
      "Skip/demo mode loads stub profile and bypasses all steps",
      "Profile persists in localStorage so refresh doesn't lose it"
    ]
  },
  {
    id: 3,
    title: "Supplier Catalogue — Stub Data Layer",
    icon: "🏪",
    estimated: "1 session",
    claudeCall: false,
    status: "data",
    goal: "Build a realistic UK trade supplier catalogue as a structured JS data module. This is the data source the Materials Agent (Block 5) queries. Every product has real-ish SKUs, pack sizes, units, and prices based on 2024/25 UK trade counter pricing. The lookup function interface is designed so it can later be swapped for live scraping without any other code changes.",
    catalogueStructure: `// supplierCatalogue.js
export const CATALOGUE = [
  {
    id: "SF-001",
    name: "2.5mm² Twin & Earth Cable (100m drum)",
    category: "cable",
    subcategory: "twin-earth",
    searchTerms: ["2.5mm cable", "twin earth", "t&e", "lighting circuit cable"],
    unit: "m",
    packSize: 100,
    packUnit: "drum",
    suppliers: {
      screwfix: { sku: "3672T", price: 68.99, inStock: true, url: "https://www.screwfix.com/p/3672T" },
      cef:      { sku: "CEF-2502", price: 64.50, inStock: true, url: "https://www.cef.co.uk" },
      tlc:      { sku: "TLC-25T100", price: 66.00, inStock: true, url: "https://www.tlc-direct.co.uk" }
    },
    defaultWasteFactor: 0.10,
    tradeNotes: "Always round up to nearest full drum"
  },
  // ... 200 more products
]`,
    categories: [
      {
        name: "Electrical",
        subcategories: ["cable", "conduit", "trunking", "consumer-units", "sockets-switches", "light-fittings", "accessories", "fixings", "testing-equipment"],
        productCount: 60,
        sampleProducts: [
          "1mm² T&E cable (50m drum) — Screwfix £32.99",
          "1.5mm² T&E cable (100m drum) — Screwfix £52.99",
          "2.5mm² T&E cable (100m drum) — Screwfix £68.99",
          "6mm² T&E cable (25m drum) — Screwfix £45.99",
          "25mm white oval conduit (3m) — Screwfix £1.49",
          "20mm metal conduit (3m) — Screwfix £4.99",
          "Hager 10-way consumer unit — CEF £89.00",
          "Legrand 13A double socket — Screwfix £4.49",
          "Crabtree 16A outdoor socket — Screwfix £22.99",
          "LED downlight 6W (10-pack) — Screwfix £24.99",
          "5x5 white mini trunking (3m) — Screwfix £1.79",
          "Junction box 30A round — Screwfix £2.49",
          "Back box 35mm single — Screwfix £0.89",
          "Back box 47mm double — Screwfix £1.29",
          "Gland kit PG7 (10-pack) — Screwfix £3.49"
        ]
      },
      {
        name: "Plumbing",
        subcategories: ["copper-pipe", "fittings", "valves", "radiators", "boiler-parts", "waste", "tools"],
        productCount: 50,
        sampleProducts: [
          "22mm copper pipe (3m) — Screwfix £9.49",
          "15mm copper pipe (3m) — Screwfix £5.99",
          "22mm straight coupler (5-pack) — Screwfix £7.49",
          "15mm 90° elbow (10-pack) — Screwfix £8.99",
          "22mm gate valve — Screwfix £8.99",
          "15mm isolating valve — Screwfix £3.99",
          "Single panel radiator 600×600 — Screwfix £44.99",
          "PTFE tape (12m) — Screwfix £0.79",
          "Fernox F1 inhibitor (500ml) — Screwfix £12.99",
          "40mm waste pipe (3m) — Screwfix £4.99"
        ]
      },
      {
        name: "Building / General",
        subcategories: ["plasterboard", "timber", "insulation", "fixings", "adhesives", "tools", "waste"],
        productCount: 50,
        sampleProducts: [
          "12.5mm plasterboard 2400×1200 — Jewson £7.20",
          "4x2 CLS timber 3.0m — Jewson £4.50",
          "50mm Rockwool insulation (5.76m² pack) — Jewson £22.50",
          "M4 woodscrew 40mm (200-pack) — Screwfix £4.99",
          "25mm plasterboard screws (500-pack) — Screwfix £5.49",
          "No More Nails 432ml — Screwfix £5.49",
          "Grip Fill 350ml — Screwfix £3.99",
          "6-yard skip hire (local, 1 week) — Local £220.00",
          "Dust sheet cotton 12x9ft — Screwfix £14.99",
          "Protective floor covering roll 25m — Screwfix £24.99"
        ]
      },
      {
        name: "Tiling",
        subcategories: ["adhesive", "grout", "tile-trim", "tools", "backer-board"],
        productCount: 20,
        sampleProducts: [
          "Mapei Ultrabond Eco 990 tile adhesive 15kg — Screwfix £19.99",
          "Mapei Ultracolor Plus grout 5kg — Screwfix £14.99",
          "Chrome tile trim 2.5m — Screwfix £5.49",
          "12mm Hardie backer board 1200×800 — Screwfix £22.99",
          "Notched trowel — Screwfix £7.99"
        ]
      },
      {
        name: "Painting & Decorating",
        subcategories: ["paint", "primer", "filler", "tape", "tools"],
        productCount: 20,
        sampleProducts: [
          "Dulux Trade Vinyl Matt 10L white — Screwfix £44.99",
          "Dulux Trade Gloss 5L white — Screwfix £34.99",
          "Dulux Trade primer 5L — Screwfix £26.99",
          "Polyfilla professional 1kg — Screwfix £5.99",
          "Frog Tape 36mm×41m — Screwfix £8.49",
          "9in roller sleeve medium pile (5-pack) — Screwfix £8.99"
        ]
      }
    ],
    lookupFunction: `// The interface that Block 5 calls — DO NOT CHANGE THIS SIGNATURE
// when swapping stub for live scraping later
export function lookupMaterial(materialName, quantity, unit, preferredSuppliers, tradeType) {
  // 1. Fuzzy match materialName against CATALOGUE[].searchTerms
  // 2. Filter by category relevance to tradeType
  // 3. For each match, find best supplier from preferredSuppliers array (in order)
  // 4. Calculate packsNeeded = Math.ceil(quantity / packSize)
  // 5. Return best match with full pricing breakdown
  return {
    matched: boolean,
    confidence: "exact"|"close"|"inferred"|"not-found",
    catalogueId: string,
    productName: string,
    supplierName: string,
    sku: string,
    unitPrice: number,          // price per single unit (not per pack)
    packSize: number,
    packUnit: string,
    pricePerPack: number,
    packsNeeded: number,
    lineTotal: number,
    inStock: boolean,
    url: string,
    alternativeSuppliers: []    // other matched suppliers with prices
  }
}`,
    acceptanceCriteria: [
      "Catalogue has minimum 150 products across all 5 categories",
      "Every product has: id, name, searchTerms array, unit, packSize, at least one supplier with SKU + price + URL",
      "lookupMaterial() function returns correct structure for at least 20 test material names",
      "Fuzzy matching correctly handles: '2.5mm cable', '2.5 twin earth', 'T&E 2.5', '2.5mm² T&E'",
      "Pack size rounding works: asking for 85m of 100m-drum cable returns 1 drum, not 0.85",
      "Fallback: if no supplier match from preferred list, falls back to any available supplier",
      "Console utility: lookupMaterial('test', 1, 'unit', ['screwfix'], 'electrician') returns valid object"
    ]
  },
  {
    id: 4,
    title: "Job Capture — Scan Simulation + Job Description",
    icon: "📐",
    estimated: "1 session",
    claudeCall: false,
    status: "core",
    goal: "The tradesperson's entry point for a new job. Two-step screen: first they 'scan' the space (simulated with dimension inputs — in production this would be ARKit/ARCore), then describe the job in natural language via voice or text. The output feeds directly into the Materials Agent. UX must feel instant and intuitive — no instructions needed.",
    screens: [
      {
        name: "NewJobScreen",
        description: "Full screen. Two steps shown as large cards the user swipes/taps through. Header: 'New Job' + customer name input at top (name, phone, email, address — can be filled in later). Step indicator: ● ○"
      },
      {
        name: "Step 1 — Scan the Space",
        description: `Large camera-frame UI element (orange corner brackets, dark interior, pulse animation). 
        
CENTER TEXT (large, uppercase): 'POINT AND SWEEP' 
Subtext: 'Move your phone slowly around the room'

DEMO MODE (since we can't do real ARKit): After 3 seconds of 'scanning animation' (camera graphic sweeps, progress fills), reveal a dimension input form:

Room type selector (large chips): Bathroom / Kitchen / Living Room / Bedroom / Loft / Extension / Whole Property / Other

Then input fields:
- Length (m) — number input with stepper
- Width (m) — number input  
- Height (m) — number input, default 2.4
- Number of windows — stepper
- Number of doors — stepper

Auto-calculates and displays live:
- Floor area: X.Xm²
- Wall area: X.Xm²  
- Ceiling area: X.Xm²

Anomaly tagger at bottom: 'Anything to flag?' — free text chips. User types e.g. 'damp wall' and it appears as an orange chip. Pre-suggestions based on trade: for electrician show 'No earth bonding', 'Old wiring', 'No consumer unit space', 'Active asbestos risk'.

'Space mapped ✓ — Describe the job' CTA button.`
      },
      {
        name: "Step 2 — Describe the Job",
        description: `Full screen. Large mic button dominant in centre. 

ABOVE MIC (large): 'Tell me about the job'
BELOW MIC (small muted): 'Speak naturally. What needs doing, what doesn't, what you spotted.'

MIC BUTTON behaviour:
- Tap to start: button pulses orange, Web Speech API starts recording
- Live transcription appears in text area below mic as they speak
- Tap again to stop
- Keyboard icon toggle switches to type-only mode

PROMPT CHIPS (tappable, adds phrase to transcript):
'Not in scope:', 'Customer supplying:', 'Sub-contractor needed:', 'Potential issue:', 'Existing [item] to be removed:'

OUT OF SCOPE field: separate smaller textarea below main description. Pre-prompted: 'Anything explicitly NOT included in this quote?'

CUSTOMER SUPPLIED toggle list: items user marks as customer-supplied (removed from BOM)

ESTIMATED START DATE: date picker

Below the form, collapsible CHECKLIST: 'Have you covered...'
✓ What's being installed/replaced
✓ What's being removed/stripped
✓ Any making good required
✓ Access restrictions or site conditions
✓ Any existing work that needs testing/certifying

'Calculate Materials →' CTA button (disabled until description > 50 chars)`
      }
    ],
    testJobData: {
      customer: { name: "Mr & Mrs Thompson", email: "j.thompson@gmail.com", phone: "07891 234567", address: "42 Maple Avenue, Bushey, WD23 2BT" },
      scan: {
        roomType: "bathroom",
        dimensions: { length: 3.2, width: 2.1, height: 2.4 },
        features: { windowCount: 1, doorCount: 1, existingSocketCount: 1, existingLightCount: 1 },
        anomalies: ["no existing earth bonding to pipework", "old round-pin sockets present"]
      },
      jobDescription: "Full bathroom electrical refurb. Strip out the old round-pin sockets — there's one by the sink which isn't even to regs. Install a new shaver socket above the mirror, IP65 rated. Two new LED downlights in the ceiling replacing the old pendant, need to be IP65 as well, probably 6 watt warm white. Run new earth bonding to the copper pipework under the sink and to the bath — both need bonding. New dedicated extractor fan circuit from the consumer unit, the bathroom doesn't have mechanical ventilation at the moment. All circuits to be tested and certified, I'll provide an Electrical Installation Certificate. Making good to be done by the customer's plasterer.",
      outOfScope: "No general plumbing work. Making good after cable runs is by others. No tiling.",
      customerSupplied: [],
      proposedStartDate: "2025-05-15",
      estimatedDurationDays: 2
    },
    acceptanceCriteria: [
      "Scan animation plays for minimum 2 seconds before showing dimension inputs",
      "All dimension inputs update the auto-calculated areas in real time",
      "Anomaly chips appear correctly and are removable",
      "Web Speech API mic button works and transcribes to textarea",
      "Minimum character check prevents empty job descriptions proceeding",
      "Checklist collapse/expand works",
      "All captured data is stored correctly in currentJob in global state",
      "Test job data can be loaded via 'Load test job' button for demo purposes",
      "CTA button correctly disabled until description threshold met"
    ]
  },
  {
    id: 5,
    title: "Materials Agent — Claude API + BOM Editor",
    icon: "🧮",
    estimated: "2 sessions",
    claudeCall: true,
    status: "core",
    goal: "The centrepiece of AccuQuote. Sends the full job context to Claude API which returns a structured bill of materials. Each line is immediately priced via the supplier catalogue lookup function. The resulting BOM is displayed in an editable table — the tradesperson reviews, tweaks quantities, swaps suppliers, marks customer-supplied items. Running total updates live. This is where AccuQuote proves its value.",
    screens: [
      {
        name: "MaterialsLoading",
        description: `Full screen loading state. Shows animated progress with real steps:
'Reading the job description...' (0.5s)
'Identifying materials needed...' (1s)  
'Calculating quantities from your scan...' (1s)
'Applying waste factors...' (0.5s)
'Checking supplier prices...' (1s — this is when catalogue lookup runs after API returns)
'Done — reviewing your materials list'

Show a pulsing BOM preview (blurred rows appearing) underneath to build anticipation. Do NOT show a spinner — show something that communicates intelligence is happening.`
      },
      {
        name: "BOMEditorScreen",
        description: `Two-panel layout on wide screens, stacked on mobile.

LEFT / MAIN PANEL — Bill of Materials table:

HEADER ROW: Material | Qty | Unit | Supplier | Unit Price | Total | [action]

Each ROW shows:
- Material name (editable inline on tap)
- Quantity (editable number input)
- Unit (e.g. 'm', 'pack', 'each')
- Supplier badge (e.g. 'Screwfix' in orange — tappable to swap supplier)
- Unit price
- Line total (recalculates on qty change)
- Confidence indicator: green dot (high), orange dot (medium), red dot (low) — low confidence items flagged for review
- [×] delete button
- Customer supplied toggle (checkbox — greys out line and zeros price)

CATEGORY GROUPING: Materials grouped by category with collapsible headers:
⚡ Cable & Containment   [total]
🔌 Accessories & Fittings  [total]
🔦 Light Fittings   [total]
🔧 Fixings & Sundries  [total]

BOTTOM OF TABLE: 
'+ Add material' row — opens search input that queries catalogue
'+ Add free-text item' — for items not in catalogue

MISSED ITEMS CHECKER (collapsible section at bottom):
'Have you included...' — trade-specific checklist of commonly forgotten items:
For electrician: [ ] EICR / EIC certificate (£) [ ] Test equipment consumables [ ] Wall plugs & screws [ ] Cable clips [ ] Warning labels [ ] Earth sleeving
Each item is one-tap to add to BOM.

RIGHT / SUMMARY PANEL:
Materials subtotal: £XXX.XX
Number of supplier orders: X
Estimated delivery: [date based on start date minus 3 days]
[Proceed to Quote Builder →] button (sticky at bottom)

SUPPLIER SWAP MODAL:
When user taps a supplier badge: show all suppliers that stock this item, with their prices. User taps to swap. Line total updates instantly.`
      }
    ],
    claudeCallSpec: {
      model: "claude-sonnet-4-20250514",
      systemPrompt: `You are a materials estimation expert for a UK electrical contractor. You receive a job description, scan dimensions, and tradesperson profile. Return ONLY valid JSON — an array of materials needed to complete the job. Be specific and complete. Include every material needed including sundries, fixings, and consumables. Do not include labour. Do not include items marked as customer-supplied. Use UK trade terminology. Quantities must be calculated from the dimensions provided.`,
      userPromptTemplate: `TRADESPERSON PROFILE:
Trade: {{trade}}
Specialisms: {{specialisms}}
Sundries always included: {{sundryItems}}
Waste factors: {{wasteFactors}}

SCAN DATA:
Room type: {{roomType}}
Dimensions: {{length}}m × {{width}}m × {{height}}m
Floor area: {{floorArea}}m²
Wall area: {{wallArea}}m²
Anomalies noted: {{anomalies}}

JOB DESCRIPTION:
{{jobDescription}}

OUT OF SCOPE:
{{outOfScope}}

CUSTOMER SUPPLYING:
{{customerSupplied}}

Return a JSON array of this exact structure:
[
  {
    "material": "2.5mm² twin & earth cable",
    "quantity": 25,
    "unit": "m",
    "category": "cable",
    "wasteFactor": 0.10,
    "quantityWithWaste": 28,
    "rationale": "Ring circuit for sockets, estimated 20m run plus 5m for drops",
    "confidence": "high",
    "tradeSearchTerm": "2.5mm twin earth cable"
  }
]

Include ALL of the following where relevant:
- All cables with lengths calculated from room dimensions and run estimates
- All back boxes, accessories, fittings
- All light fittings specified
- All conduit, trunking, containment
- All fixings (screws, wall plugs, cable clips)
- Sundry consumables (earth sleeving, warning labels, connector blocks)
- Testing/certification costs as a line item if required
- Any bonding or earthing materials
- Making good materials ONLY if in scope`,
      maxTokens: 2000,
      parseInstructions: `JSON.parse the response. For each item, immediately call lookupMaterial(item.tradeSearchTerm, item.quantityWithWaste, item.unit, profile.preferredSuppliers.electrical, profile.trade) and merge the catalogue lookup result onto the item. Items with confidence 'low' should be highlighted in the UI.`
    },
    testBOMExpected: [
      { material: "1.5mm² twin & earth cable", quantity: 10, unit: "m", category: "cable", supplier: "screwfix", approxCost: 5.99 },
      { material: "6mm earth cable", quantity: 3, unit: "m", category: "cable", supplier: "screwfix", approxCost: 3.49 },
      { material: "IP65 LED downlight 6W (warm white)", quantity: 2, unit: "each", category: "light-fittings", supplier: "screwfix", approxCost: 12.99 },
      { material: "IP65 shaver socket", quantity: 1, unit: "each", category: "accessories", supplier: "screwfix", approxCost: 22.99 },
      { material: "IP65 extractor fan with timer", quantity: 1, unit: "each", category: "accessories", supplier: "screwfix", approxCost: 44.99 },
      { material: "Round conduit 20mm (3m)", quantity: 2, unit: "length", category: "containment", supplier: "screwfix", approxCost: 2.49 },
      { material: "Earth bonding clamps 22mm", quantity: 4, unit: "each", category: "fixings", supplier: "screwfix", approxCost: 1.99 },
      { material: "Green/yellow earth sleeving (1m)", quantity: 5, unit: "each", category: "consumables", supplier: "screwfix", approxCost: 0.49 },
      { material: "Electrical Installation Certificate (EIC)", quantity: 1, unit: "each", category: "certification", supplier: "self", approxCost: 0 },
      { material: "Cable clips assorted (100-pack)", quantity: 1, unit: "pack", category: "fixings", supplier: "screwfix", approxCost: 3.49 }
    ],
    acceptanceCriteria: [
      "Loading screen shows animated steps, minimum 4 seconds display",
      "Claude API call fires with correctly assembled prompt including all job context",
      "API response is parsed and each item run through lookupMaterial()",
      "BOM table renders all items grouped by category",
      "Inline quantity editing updates line total and materials subtotal in real time",
      "Supplier swap modal shows alternative suppliers with prices",
      "Customer-supplied toggle greys line and zeros contribution to total",
      "Low-confidence items show orange dot and tooltip explaining why",
      "Missed items checklist is trade-appropriate (electrician gets electrical checklist)",
      "Add material search queries catalogue and appends correctly",
      "Test job produces a BOM with at least 8 line items and total between £80–£250",
      "'Proceed to Quote Builder' disabled until at least one line item exists"
    ]
  },
  {
    id: 6,
    title: "Labour + Quote Builder",
    icon: "💷",
    estimated: "1 session",
    claudeCall: false,
    status: "core",
    goal: "Takes the priced BOM and adds the labour layer. All fields are pre-filled from the tradesperson profile but fully editable. Calculates three pricing tiers. The tradesperson picks which tiers to include in the proposal. Clean, fast, no surprises.",
    screens: [
      {
        name: "QuoteBuilderScreen",
        description: `Three-section layout:

SECTION 1 — MATERIALS (read-only summary from BOM)
Materials total: £XXX.XX
Number of lines: XX
[View full BOM] link back to Block 5

SECTION 2 — LABOUR
Pre-filled from profile, all editable:

Days on site: [stepper, default 2]
Operatives: [stepper, default profile.typicalOperatives]  
Day rate per person: [£ input, default profile.dayRatePerPerson]
Labour subtotal: £XXX.XX (auto-calculated, bold)

ADDITIONAL COSTS (expandable rows, each toggleable):
☐ Travel & parking: £[input] (default £25/day × days)
☐ Skip hire: £[input] (default £220 if job type typically needs it)
☐ Sub-contractor: [description input] £[input]
☐ Other: [description input] £[input]

COST SUMMARY (running total):
Materials:      £XXX.XX
Labour:         £XXX.XX
Expenses:       £XXX.XX
────────────────
Cost base:      £XXX.XX

SECTION 3 — PRICING TIERS
Three cards side by side. Each shows:

[STANDARD]              [PREMIUM ★]             [PRIORITY ⚡]
Margin: 30%             Margin: 38%             Margin: 45%
Your price: £X,XXX      Your price: £X,XXX      Your price: £X,XXX
+VAT: £XXX              +VAT: £XXX              +VAT: £XXX
Total: £X,XXX           Total: £X,XXX           Total: £X,XXX

Includes:               Includes:               Includes:
• Standard work         • 2yr guarantee         • Start within 5 days
                        • Priority comms        • 2yr guarantee
                                               • Senior engineer

[Include ☐]             [Include ☐]             [Include ☐]

At least one must be included. Checkboxes toggle inclusion in proposal.
Margin sliders under each tier (10%–60% range) update totals live.

DEPOSIT SECTION:
Deposit: [%] of [selected tier minimum total]
Deposit amount: £XXX.XX (updates live)
Options: 25% / 50% / on completion / custom

'Build Proposal →' CTA`
      }
    ],
    calculations: `
// Margin applied to cost base, not materials alone
const tierTotal = (costBase, marginPct) => costBase / (1 - marginPct/100)
const vatAmount = (total) => profile.vatRegistered ? total * 0.20 : 0
const grandTotal = (total) => total + vatAmount(total)
const depositAmount = (grandTotal, depositPct) => grandTotal * (depositPct/100)

// Tier defaults
Standard: profile.targetMarginPct (default 30%)
Premium:  profile.targetMarginPct + 8% (default 38%)
Priority: profile.targetMarginPct + 15% (default 45%)`,
    acceptanceCriteria: [
      "All inputs pre-populated from profile — tradesperson can start with zero edits",
      "Labour subtotal recalculates on any input change",
      "All three tier totals update when cost base changes or margin sliders move",
      "VAT is added correctly if profile.vatRegistered = true",
      "At least one tier must remain selected (prevent deselecting all)",
      "Deposit amount updates correctly with any tier total change",
      "Test job produces: cost base ~£700, Standard total ~£1,000, Premium ~£1,100, Priority ~£1,275",
      "'Build Proposal' proceeds only with at least one tier selected"
    ]
  },
  {
    id: 7,
    title: "Proposal Builder + Preview",
    icon: "📄",
    estimated: "2 sessions",
    claudeCall: true,
    status: "core",
    goal: "Generates a professional, branded proposal document. Claude API cleans up the raw job description into professional scope bullets and writes a cover letter in the tradesperson's tone of voice. The tradesperson reviews a live preview before sending. One button sends it. The customer experience of receiving this should feel premium — better than anything they've seen from a tradesperson before.",
    screens: [
      {
        name: "ProposalBuilderScreen",
        description: `Split screen: left panel = editable fields, right panel = live proposal preview (updates as left panel changes).

LEFT PANEL — EDITABLE FIELDS:
Customer details (pre-filled from job capture, editable):
- Name, address, email, phone

Job reference: AQ-[YYYY]-[XXX] (auto-generated)
Proposal date: today
Valid until: today + 30 days
Proposed start: from job capture
Estimated duration: from job capture

Scope of work: (editable bullet list — Claude fills this, user can edit)
Payment schedule: (pre-filled from profile payment terms, editable)
Send via: Email / SMS / WhatsApp (toggle)

RIGHT PANEL — LIVE PROPOSAL PREVIEW:
Rendered as a document-style panel with:

[BRAND COLOUR HEADER BAR]
[LOGO]  HARRIS ELECTRICAL LTD
        Proposal for Electrical Works
        
Prepared for: Mr & Mrs Thompson
42 Maple Avenue, Bushey, WD23 2BT

Ref: AQ-2025-001 | Date: 14 May 2025 | Valid: 30 days

────────────────────────────────────
COVER LETTER (Claude-generated, editable textarea)
────────────────────────────────────
SCOPE OF WORK
• [bullet 1]
• [bullet 2]
...

INVESTMENT
[If one tier selected: single price table]
[If multiple tiers: comparison table]

Option 1 — Standard          £1,020 inc VAT
Option 2 — Premium           £1,128 inc VAT  
Option 3 — Priority          £1,275 inc VAT

Payment Schedule:
50% deposit on acceptance:   £XXX
Balance on completion:        £XXX

────────────────────────────────────
TERMS & CONDITIONS
[profile.standardTCs]

GUARANTEE
[profile.guaranteeText]

[ACCEPT THIS PROPOSAL] button (styled in brand colour)

────────────────────────────────────
[Footer: VAT reg, address, contact]

SEND PANEL (below preview):
'Send this proposal' — 
[Email preview] [SMS preview] [Copy link]
[SEND PROPOSAL →] large CTA button

On send: status transitions to 'sent', navigate to ProposalSentScreen`
      },
      {
        name: "ProposalSentScreen",
        description: "Confirmation screen. Large animated tick. 'Proposal sent to Mr & Mrs Thompson'. Shows: proposal summary card, customer contact details, 'View proposal' link. Two CTAs: 'Back to dashboard' and 'Follow up reminder' (sets a 48hr reminder to chase)."
      }
    ],
    claudeCallSpec: {
      model: "claude-sonnet-4-20250514",
      systemPrompt: `You are a professional proposal writer for a UK trades business. You write clear, professional but warm proposal content. Never use jargon the customer won't understand. Never mention technology or AI. Write as if the tradesperson wrote it themselves.`,
      userPromptTemplate: `TRADESPERSON:
Name: {{name}}, Business: {{businessName}}
Trade: {{trade}}
Tone of voice: {{toneOfVoice}}

CUSTOMER:
{{customerName}}, {{customerAddress}}

RAW JOB DESCRIPTION (tradesperson's words):
{{jobDescription}}

OUT OF SCOPE:
{{outOfScope}}

QUOTE:
Selected tier: {{selectedTier}}
Total: £{{grandTotal}} inc VAT
Deposit: £{{depositAmount}} ({{depositPct}}% on acceptance)
Start date: {{startDate}}
Duration: {{durationDays}} days

Write two things and return as JSON:
{
  "coverLetter": "3-4 paragraph professional letter. Open with thanks for the opportunity. Summarise the scope in plain English. Confirm price and payment terms. Close warmly. Sign off as {{name}}, {{businessName}}.",
  "scopeBullets": ["array", "of", "clear", "scope", "items", "written", "for", "the", "customer", "not", "the", "tradesperson"]
}

Scope bullets must: be written for a homeowner, not use trade codes, include what's excluded, be factual and clear.`,
      maxTokens: 1000,
      parseInstructions: "JSON.parse. Populate coverLetter textarea and scopeBullets list in left panel. User can edit both before sending."
    },
    proposalPDFNote: "For the demo, render the proposal as a styled HTML div that can be printed/saved as PDF via window.print(). In production this would use PDFShift or Puppeteer server-side.",
    acceptanceCriteria: [
      "Claude API call fires correctly on screen load (or on 'Generate' button)",
      "Cover letter populates in left panel textarea — editable",
      "Scope bullets populate as editable list — user can add/remove bullets",
      "Right panel preview updates live as left panel fields are edited",
      "Brand colour is applied to header bar from profile.brandColour",
      "If multiple tiers selected: comparison table renders correctly",
      "If one tier selected: single price table renders",
      "VAT breakdown shown correctly",
      "T&Cs from profile appear in preview",
      "'Send' button transitions status to sent and shows ProposalSentScreen",
      "Print/PDF button triggers window.print() with proposal-only content"
    ]
  },
  {
    id: 8,
    title: "Customer Acceptance + Mock Payment",
    icon: "✅",
    estimated: "2 sessions",
    claudeCall: false,
    status: "core",
    goal: "The customer-facing view and acceptance flow. For demo purposes this is a separate screen within the same app (in production it would be a public URL). Customer views the proposal, accepts it, pays the deposit via a mocked Stripe UI. On payment, both customer and tradesperson get confirmation. Job status advances to 'confirmed'.",
    screens: [
      {
        name: "CustomerProposalView",
        description: `Public-facing proposal view (navigated to via 'Preview as customer' button in proposal builder, or via simulated email link).

Clean, white, professional. Brand colour accent. Mobile-first layout.

Shows full proposal content: cover letter, scope, pricing, T&Cs.

If multiple tiers: large comparison cards. Customer taps to select their preferred option.

Bottom of page:
[ACCEPT & PAY DEPOSIT]  large branded button
[REQUEST A CHANGE]      secondary button (opens a textarea to send message)
[DECLINE]              small text link`
      },
      {
        name: "MockStripePaymentScreen",
        description: `Styled to look like Stripe Checkout. Shows:

Harris Electrical Ltd
Bathroom Electrical Works — Deposit

Amount: £510.00

Card number: [4242 4242 4242 4242] (pre-filled placeholder — Stripe test card)
Expiry: [12/28]
CVC: [123]
Name on card: [Mr J Thompson]

[PAY £510.00] button

On submit: 2 second loading animation, then success.
Mock payment intent ID generated: pi_test_XXXXX`
      },
      {
        name: "CustomerConfirmationScreen",
        description: `Large animated tick (brand colour). 'Booking confirmed!'

Your details:
Job: Bathroom Electrical Works
Start date: 15 May 2025
Contractor: Harris Electrical Ltd
Contact: 07700 900000

What happens next:
1. Dave will confirm materials and arrival time one week before
2. You'll get a reminder the day before
3. Remaining balance of £510 due on completion

[Add to calendar] button — generates .ics file
[Save confirmation PDF] — saves page as PDF`
      },
      {
        name: "TradesConfirmationScreen",
        description: `Back on tradesperson side. Full-screen celebration moment (on job status update to 'accepted').

'DEPOSIT RECEIVED'
£510.00 paid by Mr & Mrs Thompson

Job: AQ-2025-001
Start: 15 May 2025

Next: [Prepare supplier orders →]`
      }
    ],
    mockStripeDetails: "Do NOT use real Stripe.js in demo. Build a pixel-perfect replica of Stripe Checkout UI with identical styling. On 'Pay' button: simulate 2s processing, generate fake payment intent ID (pi_test_ + random 24 chars), set acceptance state in global state. Show success animation. In production note: replace with real Stripe.js integration and webhook for payment confirmation.",
    acceptanceCriteria: [
      "CustomerProposalView renders full proposal correctly from global state",
      "Tier selection works if multiple tiers were included in proposal",
      "Mock Stripe screen is visually convincing — looks like real Stripe Checkout",
      "Pay button shows 2s loading then success state",
      "Global state updates: acceptance.depositPaid, acceptance.acceptedAt, acceptance.stripePaymentIntentId",
      "Job status advances to 'accepted'",
      "CustomerConfirmationScreen shows correct job details",
      "Add to calendar generates valid .ics file that downloads",
      "TradesConfirmationScreen shows deposit received with correct amount",
      "'Prepare supplier orders' CTA navigates to Block 9"
    ]
  },
  {
    id: 9,
    title: "Supplier Pre-Order Screen",
    icon: "📦",
    estimated: "1 session",
    claudeCall: false,
    status: "core",
    goal: "Takes the confirmed BOM and groups items by supplier into draft purchase orders. The tradesperson can review each PO, adjust delivery details, and commit all orders in one tap. The screen should feel like having a prepared shopping list for every supplier — nothing to work out, just review and confirm.",
    screens: [
      {
        name: "SupplierOrdersScreen",
        description: `Header: 'Materials for AQ-2025-001' | Start date: 15 May | Order by: 12 May

SUMMARY BAR:
Total materials cost: £XXX.XX
Suppliers: 2
Lines: XX items
[COMMIT ALL ORDERS] — large CTA (disabled until user has reviewed)

SUPPLIER PO CARDS (one per supplier):

┌─────────────────────────────────────┐
│ 🟠 SCREWFIX                         │
│ 8 items · £127.45                   │
│                                     │
│ Item             Qty   Pack  Total  │
│ 2.5mm T&E 100m   1    drum  £68.99 │
│ IP65 downlight   2    each  £25.98 │
│ IP65 shaver skt  1    each  £22.99 │
│ ...                                 │
│                                     │
│ Delivery to: ○ Site  ● Yard         │
│ Deliver by: [12 May 2025]          │
│                                     │
│ [COMMIT THIS ORDER]                 │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ 🔵 CEF                              │  
│ 1 item · £44.50                     │
│ ...                                 │
│ [COMMIT THIS ORDER]                 │
└─────────────────────────────────────┘

Each order has status: DRAFT → COMMITTED → CONFIRMED (mock)

COMMIT ALL button: commits all DRAFT orders simultaneously, animates each to COMMITTED state, shows success screen.

NOTE displayed: 'In production, AccuQuote will place these orders directly through your trade accounts. For now, your orders are saved — use the details below to place them manually or call your local branch.'`
      },
      {
        name: "OrdersConfirmedScreen",
        description: `All suppliers show COMMITTED badge. 

Summary:
Screwfix: 8 items · £127.45 ✓
CEF: 1 item · £44.50 ✓

Total committed: £171.95

'Materials ordered. You're all set for 15 May.'

[Back to dashboard] [View job details]`
      }
    ],
    groupingLogic: `
// Group BOM items by supplier
const ordersBySupplier = billOfMaterials
  .filter(item => !item.customerSupplied)
  .reduce((acc, item) => {
    const supplier = item.catalogueLookup.supplierName
    if (!acc[supplier]) acc[supplier] = { lines: [], total: 0 }
    acc[supplier].lines.push(item)
    acc[supplier].total += item.catalogueLookup.lineTotal
    return acc
  }, {})

// Recommended order date = proposedStartDate minus 3 days
const orderByDate = new Date(currentJob.proposedStartDate)
orderByDate.setDate(orderByDate.getDate() - 3)`,
    acceptanceCriteria: [
      "BOM items correctly grouped by supplier with accurate totals",
      "Each PO card shows all line items with quantities and prices",
      "Delivery address toggle (site vs yard) works per supplier",
      "Delivery date defaults to start date minus 3 days",
      "Individual commit button marks that supplier as committed",
      "Commit All button commits all draft orders simultaneously with animation",
      "Committed orders show visual confirmation state",
      "Total across all suppliers matches materials total from BOM",
      "Global state supplierOrders array is populated correctly",
      "Back to dashboard reflects updated job status"
    ]
  },
  {
    id: 10,
    title: "Job Dashboard + Reminder System",
    icon: "📊",
    estimated: "1 session",
    claudeCall: false,
    status: "supporting",
    goal: "The home screen once onboarding is complete. Shows all jobs in a status pipeline, upcoming work this week, and reminder management. The reminder system simulates sending (in production would hit Twilio/SendGrid). The dashboard makes AccuQuote feel like a professional job management system, not just a quoting tool.",
    screens: [
      {
        name: "DashboardScreen",
        description: `HEADER: 'Good morning, Dave.' | Today's date | [+ New Job] button

STATS ROW (4 cards):
[Quotes this month: 8] [Won: 6 (75%)] [Avg job value: £1,140] [Revenue pipeline: £6,840]

PIPELINE VIEW:
Horizontal scroll of job status columns (Kanban style, simplified):

QUOTED → ACCEPTED → ORDERED → SCHEDULED → COMPLETE

Each job appears as a card in its current status column:
┌─────────────────┐
│ AQ-2025-001     │
│ Mr & Mrs Thompson│
│ Bathroom Rewire │
│ £1,020          │
│ Start: 15 May   │
│ [View] [→]      │
└─────────────────┘

THIS WEEK section:
Calendar-style view of the current week. Jobs shown on their start dates.

REMINDERS section:
List of pending/sent reminders:
AQ-2025-001 — 7-day reminder    [SEND NOW] [Sent ✓]
AQ-2025-001 — 24hr reminder     [SEND NOW] [Pending]

[SEND NOW] simulates sending: shows 'Sending...' then 'Sent ✓ — SMS delivered to 07891 234567'

RECENT ACTIVITY feed:
Timeline of events: quote sent, deposit received, materials ordered, reminders sent.`
      }
    ],
    reminderContent: {
      sevenDay: {
        customer: "Hi [Name], just a reminder that Dave from Harris Electrical is scheduled to start your bathroom electrical works on [date]. Please ensure the bathroom is cleared and access is available from [time]. Any questions, call Dave on [number].",
        tradesperson: "Reminder: [Customer name] bathroom rewire starts in 7 days ([date]). Materials committed: YES. Deposit received: YES. Check materials are on track for delivery."
      },
      twentyFourHour: {
        customer: "See you tomorrow! Dave from Harris Electrical will arrive at [address] at approximately [time] to begin your bathroom electrical works. Any last-minute questions: [number].",
        tradesperson: "Job tomorrow: [Customer] — [address]. Arriving [time]. Materials: Screwfix delivery confirmed. Balance due on completion: £[amount]."
      },
      postJob: {
        customer: "Hi [Name], thanks for having us — it was a pleasure working at your home. If you're happy with the work, a Google review would mean the world: [link]. Harris Electrical — recommended by your neighbours."
      }
    },
    acceptanceCriteria: [
      "Dashboard loads with stub job (AQ-2025-001) in correct pipeline stage",
      "Stats row calculates correctly from jobs in global state",
      "Pipeline columns render with cards in correct status column",
      "Clicking a job card navigates to that job's active screen",
      "This week view shows upcoming jobs on correct dates",
      "Reminders list shows correct reminders for each job",
      "Send now button shows sending animation then success state",
      "Recent activity feed shows chronological events",
      "New Job button navigates to Block 4 — Job Capture"
    ]
  },
  {
    id: 11,
    title: "Polish Pass — Production Ready",
    icon: "✨",
    estimated: "1 session",
    claudeCall: false,
    status: "polish",
    goal: "Cross-cutting improvements that make AccuQuote feel like a real product. Applied across all screens after blocks 1–10 are functional.",
    tasks: [
      {
        area: "Loading states",
        detail: "Every Claude API call must have: a meaningful loading animation (not a spinner — animated steps or pulsing skeleton UI), a minimum display time of 2 seconds, and an error state with retry button."
      },
      {
        area: "Error handling",
        detail: "Wrap all API calls in try/catch. If Claude API fails: show error card with exact error, retry button, and fallback option (manual entry). If catalogue lookup fails: flag item as 'price TBC' and continue. Never crash the whole screen."
      },
      {
        area: "Mobile responsiveness",
        detail: "All screens must work on a 375px wide screen (iPhone SE). Sidebar collapses to bottom tab bar on mobile. BOM table scrolls horizontally. Proposal preview switches to single-column."
      },
      {
        area: "LocalStorage persistence",
        detail: "Profile, current job, BOM, and quote all persist to localStorage. On reload, state is restored. Add a 'Clear all data' button in Settings for demo reset."
      },
      {
        area: "Demo mode",
        detail: "A floating 'Demo' button (bottom-right, small) that: resets all state to stub data, pre-fills the test bathroom rewire job, and navigates to any screen. Essential for demonstrations."
      },
      {
        area: "Transitions",
        detail: "Screen-to-screen transitions: fade + slight upward translate (200ms). Within-screen state changes: smooth height animations for expanding/collapsing sections."
      },
      {
        area: "Empty states",
        detail: "Dashboard with no jobs: 'No jobs yet. Tap + New Job to create your first quote.' BOM with no items after API call: 'No materials identified — add manually or refine your job description.' All empty states have actionable CTAs."
      },
      {
        area: "Settings screen",
        detail: "Edit profile, update day rate, change brand colour, update T&Cs, manage preferred suppliers. All changes propagate to new quotes immediately."
      },
      {
        area: "Branding consistency",
        detail: "AccuQuote logo (ACCUQUOTE in Barlow Condensed, weight 900, letter-spacing 4px) appears in: sidebar header, proposal document, customer confirmation, all email/SMS previews. Never just plain text."
      },
      {
        area: "Print / export",
        detail: "Proposal: window.print() with @media print CSS that hides sidebar and controls, leaves only proposal content. BOM: export as CSV. Quote summary: export as PDF via print."
      }
    ],
    acceptanceCriteria: [
      "Full demo flow works end-to-end: Dashboard → New Job → Scan → Describe → Materials → Quote → Proposal → Customer view → Pay → Supplier Orders → Dashboard",
      "All Claude API calls have loading states and error handling",
      "App works on mobile 375px width",
      "State persists across browser refresh",
      "Demo reset button reloads test job data in under 1 second",
      "No console errors in normal operation",
      "Print proposal produces clean PDF-ready output",
      "BOM CSV export works"
    ]
  }
];

const statusColors = {
  foundation: "#3B82F6",
  core: "#F97316",
  data: "#14B8A6",
  supporting: "#A855F7",
  polish: "#22C55E"
};

const statusLabels = {
  foundation: "Foundation",
  core: "Core Feature",
  data: "Data Layer",
  supporting: "Supporting",
  polish: "Polish"
};

export default function BuildSpec() {
  const [activeBlock, setActiveBlock] = useState(1);
  const [activeTab, setActiveTab] = useState("overview");

  const block = BLOCKS.find(b => b.id === activeBlock);

  const tabs = [
    { id: "overview", label: "Overview" },
    { id: "screens", label: "Screens" },
    { id: "claude", label: "Claude Call" },
    { id: "data", label: "Data / State" },
    { id: "acceptance", label: "Acceptance Criteria" },
  ];

  return (
    <div style={{
      fontFamily: "'DM Sans', system-ui, sans-serif",
      background: "#08090B",
      minHeight: "100vh",
      color: "#E8EDF2",
      display: "flex",
      flexDirection: "column"
    }}>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=DM+Mono:wght@400;500&family=Barlow+Condensed:wght@700;900&family=DM+Sans:wght@300;400;500;600&display=swap');
        * { box-sizing: border-box; margin: 0; padding: 0; }
        ::-webkit-scrollbar { width: 5px; height: 5px; }
        ::-webkit-scrollbar-track { background: #0D0E10; }
        ::-webkit-scrollbar-thumb { background: #2a2a2a; border-radius: 3px; }
        pre { white-space: pre-wrap; word-break: break-word; }
        .block-btn:hover { background: #1a1e24 !important; }
        .tab-btn:hover { color: #F97316 !important; }
      `}</style>

      {/* Top bar */}
      <div style={{
        padding: "14px 24px", background: "#0D0E10",
        borderBottom: "1px solid #1a1e24",
        display: "flex", alignItems: "center", justifyContent: "space-between"
      }}>
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <span style={{
            fontFamily: "'Barlow Condensed', sans-serif", fontWeight: 900,
            fontSize: 22, letterSpacing: 4, color: "#FFD600"
          }}>ACCUQUOTE</span>
          <span style={{ fontSize: 10, color: "#444", letterSpacing: 2 }}>CLAUDE CODE BUILD SPEC v1.0</span>
        </div>
        <div style={{ display: "flex", gap: 6 }}>
          {Object.entries(statusColors).map(([k, v]) => (
            <div key={k} style={{ display: "flex", alignItems: "center", gap: 5, marginLeft: 8 }}>
              <div style={{ width: 8, height: 8, borderRadius: 2, background: v }} />
              <span style={{ fontSize: 10, color: "#555" }}>{statusLabels[k]}</span>
            </div>
          ))}
        </div>
      </div>

      <div style={{ display: "flex", flex: 1, overflow: "hidden", height: "calc(100vh - 51px)" }}>

        {/* Block list */}
        <div style={{
          width: 220, background: "#0D0E10", borderRight: "1px solid #1a1e24",
          overflowY: "auto", flexShrink: 0, padding: "12px 0"
        }}>
          <div style={{ padding: "0 16px 10px", fontSize: 9, color: "#444", letterSpacing: 2 }}>
            BUILD BLOCKS
          </div>
          {BLOCKS.map(b => (
            <div
              key={b.id}
              className="block-btn"
              onClick={() => { setActiveBlock(b.id); setActiveTab("overview"); }}
              style={{
                padding: "11px 16px", cursor: "pointer",
                borderLeft: `3px solid ${activeBlock === b.id ? statusColors[b.status] : "transparent"}`,
                background: activeBlock === b.id ? "#131820" : "transparent",
              }}
            >
              <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <span style={{ fontSize: 14 }}>{b.icon}</span>
                <div>
                  <div style={{ fontSize: 11, fontWeight: 600, color: activeBlock === b.id ? "#E8EDF2" : "#888", lineHeight: 1.3 }}>
                    Block {b.id}
                  </div>
                  <div style={{ fontSize: 10, color: "#444", lineHeight: 1.3 }}>{b.title.split("—")[0]}</div>
                </div>
              </div>
              <div style={{ display: "flex", gap: 6, marginTop: 6, paddingLeft: 22 }}>
                <span style={{
                  fontSize: 9, padding: "2px 6px", borderRadius: 2,
                  background: `${statusColors[b.status]}20`, color: statusColors[b.status],
                  letterSpacing: 1
                }}>{statusLabels[b.status]}</span>
                {b.claudeCall && (
                  <span style={{
                    fontSize: 9, padding: "2px 6px", borderRadius: 2,
                    background: "#FFD60015", color: "#FFD600", letterSpacing: 1
                  }}>API</span>
                )}
              </div>
            </div>
          ))}
        </div>

        {/* Content */}
        <div style={{ flex: 1, overflowY: "auto" }}>
          {block && (
            <div>
              {/* Block header */}
              <div style={{
                padding: "24px 32px", borderBottom: "1px solid #1a1e24",
                background: "#0D0E10",
                display: "flex", alignItems: "flex-start", justifyContent: "space-between"
              }}>
                <div>
                  <div style={{ display: "flex", align: "center", gap: 10, marginBottom: 8 }}>
                    <span style={{ fontSize: 28 }}>{block.icon}</span>
                    <div>
                      <div style={{ fontSize: 11, color: statusColors[block.status], letterSpacing: 2, marginBottom: 3 }}>
                        BLOCK {block.id} — {statusLabels[block.status].toUpperCase()}
                      </div>
                      <div style={{
                        fontFamily: "'Barlow Condensed', sans-serif", fontWeight: 900,
                        fontSize: 28, letterSpacing: 1, color: "#F5F0E8", lineHeight: 1
                      }}>{block.title}</div>
                    </div>
                  </div>
                  <p style={{ fontSize: 13, color: "#6B7A8D", maxWidth: 700, lineHeight: 1.6, marginTop: 8 }}>
                    {block.goal}
                  </p>
                </div>
                <div style={{ textAlign: "right", flexShrink: 0, marginLeft: 24 }}>
                  <div style={{ fontSize: 10, color: "#444", marginBottom: 4 }}>EST. BUILD TIME</div>
                  <div style={{ fontSize: 15, color: "#F97316", fontWeight: 600 }}>{block.estimated}</div>
                  {block.claudeCall && (
                    <div style={{
                      marginTop: 8, fontSize: 10, padding: "4px 10px",
                      background: "#FFD60015", color: "#FFD600", borderRadius: 3, letterSpacing: 1
                    }}>CLAUDE API CALL</div>
                  )}
                </div>
              </div>

              {/* Tabs */}
              <div style={{ display: "flex", borderBottom: "1px solid #1a1e24", background: "#0D0E10" }}>
                {tabs.map(t => (
                  <button key={t.id} className="tab-btn" onClick={() => setActiveTab(t.id)} style={{
                    padding: "11px 20px", fontSize: 11, fontWeight: 500,
                    background: "transparent", border: "none", cursor: "pointer",
                    color: activeTab === t.id ? "#F97316" : "#555",
                    borderBottom: activeTab === t.id ? "2px solid #F97316" : "2px solid transparent",
                    letterSpacing: 1, textTransform: "uppercase"
                  }}>{t.label}</button>
                ))}
              </div>

              {/* Tab content */}
              <div style={{ padding: 32 }}>

                {activeTab === "overview" && (
                  <div>
                    {block.techStack && (
                      <Section title="Tech Stack">
                        {block.techStack.map((t, i) => (
                          <Pill key={i}>{t}</Pill>
                        ))}
                      </Section>
                    )}
                    {block.designSystem && (
                      <Section title="Design System">
                        <CodeBlock>{block.designSystem}</CodeBlock>
                      </Section>
                    )}
                    {block.catalogueStructure && (
                      <Section title="Catalogue Structure">
                        <CodeBlock>{block.catalogueStructure}</CodeBlock>
                      </Section>
                    )}
                    {block.lookupFunction && (
                      <Section title="Lookup Function Signature">
                        <CodeBlock>{block.lookupFunction}</CodeBlock>
                      </Section>
                    )}
                    {block.calculations && (
                      <Section title="Pricing Calculations">
                        <CodeBlock>{block.calculations}</CodeBlock>
                      </Section>
                    )}
                    {block.groupingLogic && (
                      <Section title="Grouping Logic">
                        <CodeBlock>{block.groupingLogic}</CodeBlock>
                      </Section>
                    )}
                    {block.mockStripeDetails && (
                      <Section title="Mock Stripe Note">
                        <Note>{block.mockStripeDetails}</Note>
                      </Section>
                    )}
                    {block.proposalPDFNote && (
                      <Section title="PDF Note">
                        <Note>{block.proposalPDFNote}</Note>
                      </Section>
                    )}
                    {block.tasks && (
                      <Section title="Polish Tasks">
                        {block.tasks.map((t, i) => (
                          <div key={i} style={{
                            background: "#111418", border: "1px solid #1a1e24",
                            borderRadius: 6, padding: "16px 20px", marginBottom: 10
                          }}>
                            <div style={{ fontSize: 12, fontWeight: 600, color: "#F97316", marginBottom: 6, letterSpacing: 1 }}>
                              {t.area.toUpperCase()}
                            </div>
                            <div style={{ fontSize: 13, color: "#8a95a0", lineHeight: 1.6 }}>{t.detail}</div>
                          </div>
                        ))}
                      </Section>
                    )}
                    {block.reminderContent && (
                      <Section title="Reminder Message Templates">
                        {Object.entries(block.reminderContent).map(([k, v]) => (
                          <div key={k} style={{ marginBottom: 16 }}>
                            <div style={{ fontSize: 11, color: "#FFD600", letterSpacing: 2, marginBottom: 8 }}>
                              {k.toUpperCase().replace(/([A-Z])/g, ' $1').trim()}
                            </div>
                            {Object.entries(v).map(([who, msg]) => (
                              <div key={who} style={{
                                background: "#111418", padding: "12px 16px",
                                borderLeft: `3px solid ${who === "customer" ? "#3B82F6" : "#F97316"}`,
                                marginBottom: 8, borderRadius: "0 4px 4px 0"
                              }}>
                                <div style={{ fontSize: 10, color: "#555", marginBottom: 4, letterSpacing: 1 }}>
                                  → {who.toUpperCase()}
                                </div>
                                <div style={{ fontSize: 12, color: "#8a95a0", lineHeight: 1.6 }}>{msg}</div>
                              </div>
                            ))}
                          </div>
                        ))}
                      </Section>
                    )}
                  </div>
                )}

                {activeTab === "screens" && (
                  <div>
                    {block.screens?.map((s, i) => (
                      <div key={i} style={{
                        background: "#111418", border: "1px solid #1a1e24",
                        borderRadius: 8, overflow: "hidden", marginBottom: 16
                      }}>
                        <div style={{
                          padding: "12px 20px", background: "#131820",
                          borderBottom: "1px solid #1a1e24",
                          fontFamily: "'DM Mono', monospace", fontSize: 13, color: "#F97316"
                        }}>{s.name}</div>
                        <div style={{
                          padding: 20, fontSize: 13, color: "#8a95a0",
                          lineHeight: 1.8, whiteSpace: "pre-wrap"
                        }}>{s.description}</div>
                      </div>
                    ))}
                    {block.testJobData && (
                      <Section title="Test Job Data (pre-fill for demo)">
                        <CodeBlock>{JSON.stringify(block.testJobData, null, 2)}</CodeBlock>
                      </Section>
                    )}
                    {block.testBOMExpected && (
                      <Section title="Expected BOM Items (test job)">
                        {block.testBOMExpected.map((item, i) => (
                          <div key={i} style={{
                            display: "flex", gap: 16, padding: "10px 16px",
                            background: "#111418", borderBottom: "1px solid #0D0E10",
                            fontSize: 12, color: "#8a95a0"
                          }}>
                            <span style={{ color: "#22C55E", fontWeight: 600, minWidth: 20 }}>✓</span>
                            <span style={{ flex: 1 }}>{item.material}</span>
                            <span style={{ color: "#555" }}>{item.quantity} {item.unit}</span>
                            <span style={{ color: "#F97316" }}>{item.supplier}</span>
                            <span style={{ color: "#FFD600", fontFamily: "'DM Mono', monospace" }}>~£{item.approxCost}</span>
                          </div>
                        ))}
                      </Section>
                    )}
                    {block.categories && (
                      <Section title="Catalogue Categories">
                        {block.categories.map((cat, i) => (
                          <div key={i} style={{
                            background: "#111418", border: "1px solid #1a1e24",
                            borderRadius: 6, padding: 20, marginBottom: 12
                          }}>
                            <div style={{ fontSize: 14, fontWeight: 600, color: "#E8EDF2", marginBottom: 8 }}>
                              {cat.name} <span style={{ fontSize: 11, color: "#555" }}>({cat.productCount} products)</span>
                            </div>
                            <div style={{ fontSize: 11, color: "#555", marginBottom: 10 }}>
                              Subcategories: {cat.subcategories.join(", ")}
                            </div>
                            <div style={{ fontSize: 11, color: "#6B7A8D", lineHeight: 1.8 }}>
                              <strong style={{ color: "#555" }}>Sample products:</strong><br />
                              {cat.sampleProducts.map((p, pi) => (
                                <span key={pi} style={{ display: "block" }}>• {p}</span>
                              ))}
                            </div>
                          </div>
                        ))}
                      </Section>
                    )}
                  </div>
                )}

                {activeTab === "claude" && (
                  <div>
                    {block.claudeCall ? (
                      <div>
                        <div style={{
                          padding: "14px 20px", background: "#FFD60010",
                          border: "1px solid #FFD60030", borderRadius: 6, marginBottom: 24,
                          fontSize: 12, color: "#FFD600"
                        }}>
                          ⚡ This block makes a real Claude API call via the Anthropic API
                        </div>
                        <Section title="Model">
                          <CodeBlock>{block.claudeCallSpec?.model}</CodeBlock>
                        </Section>
                        <Section title="System Prompt">
                          <CodeBlock>{block.claudeCallSpec?.systemPrompt}</CodeBlock>
                        </Section>
                        <Section title="User Prompt Template">
                          <CodeBlock>{block.claudeCallSpec?.userPromptTemplate}</CodeBlock>
                        </Section>
                        <Section title="Max Tokens">
                          <CodeBlock>{String(block.claudeCallSpec?.maxTokens)}</CodeBlock>
                        </Section>
                        <Section title="Parse Instructions">
                          <Note>{block.claudeCallSpec?.parseInstructions}</Note>
                        </Section>
                      </div>
                    ) : (
                      <div style={{
                        padding: 40, textAlign: "center", color: "#444",
                        border: "1px dashed #1a1e24", borderRadius: 8, fontSize: 13
                      }}>
                        No Claude API call in this block — pure UI and data manipulation.
                      </div>
                    )}
                  </div>
                )}

                {activeTab === "data" && (
                  <div>
                    {block.globalStateShape && (
                      <Section title="Global State Shape (full spec)">
                        <CodeBlock>{block.globalStateShape}</CodeBlock>
                      </Section>
                    )}
                    {block.stubProfile && (
                      <Section title="Stub Profile (Dave Harris — pre-loaded for dev)">
                        <CodeBlock>{JSON.stringify(block.stubProfile, null, 2)}</CodeBlock>
                      </Section>
                    )}
                    {!block.globalStateShape && !block.stubProfile && (
                      <div style={{ fontSize: 13, color: "#555", padding: 20 }}>
                        See the Overview tab for data structures specific to this block.
                      </div>
                    )}
                  </div>
                )}

                {activeTab === "acceptance" && (
                  <div>
                    <div style={{
                      fontSize: 12, color: "#6B7A8D", marginBottom: 20, lineHeight: 1.6,
                      padding: "12px 16px", background: "#111418", borderLeft: "3px solid #F97316",
                      borderRadius: "0 4px 4px 0"
                    }}>
                      All criteria below must pass before moving to the next block. The final criterion in Block 11 is the end-to-end demo flow — this is the acceptance test for the entire build.
                    </div>
                    {block.acceptanceCriteria.map((c, i) => (
                      <div key={i} style={{
                        display: "flex", gap: 14, padding: "13px 16px",
                        background: "#111418", borderBottom: "1px solid #0D0E10",
                        borderRadius: i === 0 ? "6px 6px 0 0" : i === block.acceptanceCriteria.length - 1 ? "0 0 6px 6px" : 0
                      }}>
                        <div style={{
                          width: 22, height: 22, borderRadius: 3,
                          border: "1.5px solid #2a2a2a", flexShrink: 0, marginTop: 1
                        }} />
                        <span style={{ fontSize: 13, color: "#8a95a0", lineHeight: 1.5 }}>{c}</span>
                      </div>
                    ))}
                  </div>
                )}

              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function Section({ title, children }) {
  return (
    <div style={{ marginBottom: 28 }}>
      <div style={{
        fontSize: 10, color: "#555", letterSpacing: 2, textTransform: "uppercase",
        marginBottom: 12, fontWeight: 600
      }}>{title}</div>
      {children}
    </div>
  );
}

function CodeBlock({ children }) {
  return (
    <pre style={{
      background: "#0D0E10", border: "1px solid #1a1e24", borderRadius: 6,
      padding: 16, fontFamily: "'DM Mono', monospace", fontSize: 12,
      color: "#8a95a0", lineHeight: 1.7, overflowX: "auto"
    }}>{children}</pre>
  );
}

function Note({ children }) {
  return (
    <div style={{
      background: "#F9731610", border: "1px solid #F9731630",
      borderRadius: 6, padding: "14px 18px", fontSize: 13,
      color: "#8a95a0", lineHeight: 1.7
    }}>{children}</div>
  );
}

function Pill({ children }) {
  return (
    <span style={{
      display: "inline-block", background: "#1a1e24", border: "1px solid #252b34",
      borderRadius: 4, padding: "5px 12px", fontSize: 12, color: "#6B7A8D",
      marginRight: 8, marginBottom: 8
    }}>{children}</span>
  );
}
