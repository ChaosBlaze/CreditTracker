# CreditTracker — Dashboard Redesign Development Plan

## Context

The user iterated on low-fi wireframes in Claude Design, landed on a "Dashboard v2" layout, and exported a polished HTML handoff spec. The handoff covers the **Dashboard tab only** — a complete redesign of `DashboardView.swift` and its child components. All other tabs (History, Cards, Bonus, Settings) and all services, models, and utilities remain unchanged unless noted.

The app is already mature (35+ Swift files, iOS 26 / Swift 6 / SwiftData). This is a targeted visual-layer update, not a rewrite.

---

## System Overview

**CreditTracker** is an iOS 26 app that tracks credit card statement credits (e.g., monthly dining credits, airline fees) across multiple cards. Users log how much of each credit they've used; the app tracks per-period progress, fires local notifications before credits expire, and shows net ROI (value claimed minus annual fees).

The handoff redesigns the **Dashboard** as a two-state view:
- **Collapsed (default):** A hero "Unclaimed this month" card → "Expires Soon" urgency section → compact card list with colored status pips
- **Expanded:** Same hero + expires section pinned at top → full per-card credit blocks with progress rings, tap-to-log

The design uses a **Claude-warm palette** (cream #FAF7F2 / terracotta #D97757) with a Fraunces/iOS-serif hero numeral — warmer and cozier than pure Liquid Glass, while retaining iOS 26 glass for the tab bar, nav bar, toolbar buttons, and modal sheets.

---

## Component Architecture

### New Components (all new files)

| Component | File | Responsibility |
|-----------|------|----------------|
| `HeroCardView` | `Views/Dashboard/HeroCardView.swift` | Aggregate unclaimed $ with serif numeral, progress bar, claimed chip |
| `ExpandChip` | `Views/Dashboard/ExpandChip.swift` | Global expand/collapse toggle with chevron rotation animation |
| `CardThumbnail` | `Views/Dashboard/CardThumbnail.swift` | Card gradient chip (40×25pt), used everywhere |
| `SegmentPipRow` | `Views/Dashboard/SegmentPipRow.swift` | Row of 8pt colored pips (one per credit, status-coded) |
| `CollapsedCardRow` | `Views/Dashboard/CollapsedCardRow.swift` | Thumbnail + name + pip row (collapsed state) |
| `CardExpandedBlock` | `Views/Dashboard/CardExpandedBlock.swift` | Full card block: header + per-credit ring rows + tap-to-log sheet |
| `ExpiresSoonSection` | `Views/Dashboard/ExpiresSoonSection.swift` | Up to 2 urgent credits ≤14 days remaining, sorted by urgency |
| `CreditTrackerTokens.swift` | `Utilities/CreditTrackerTokens.swift` | `enum CT` with all color tokens + `Font` extensions |

### Existing Components (modified)

| File | Change |
|------|--------|
| `Models/PeriodLog.swift` | Add `daysUntilEnd: Int` computed property |
| `Views/Components/ProgressRingView.swift` | Update `onChange` spring: `response: 0.55, dampingFraction: 0.78` |
| `Views/Dashboard/CreditRowView.swift` | Update sheet detents to `.height(360)`, drag indicator to `.visible` |
| `Views/Dashboard/DashboardView.swift` | Full `body` replacement + new computed properties |

### Existing Components (unchanged, left in place)

`CardSectionView.swift` becomes dead code — the new dashboard no longer calls it. It is left in place (avoids touching `project.pbxproj`). Flagged as tech debt for a cleanup PR.

All other view files, all service files, all model files, all utilities: **untouched**.

---

## Data & Integration Strategy

### State Management

| State | Owner | Persistence |
|-------|-------|-------------|
| `expanded: Bool` | `DashboardView` via `@AppStorage("dashboardExpanded")` | Persisted across launches |
| `showAddCard: Bool` | `DashboardView` `@State` | Session-local |
| `logTarget: Credit?` | `CardExpandedBlock` `@State` | Session-local, per block |
| `expandHapticTrigger` | `DashboardView` `@State Bool` | Session-local, triggers `.sensoryFeedback` |

### Data Flow

```
DashboardView
  ├── @Query cards: [Card]
  ├── computed: unclaimedThisMonth, totalAvailable, claimedThisMonth
  │     └── calls PeriodEngine.activePeriodLog(for: credit) for each credit
  ├── HeroCardView(unclaimedAmount:, totalAvailable:, claimedAmount:)
  ├── ExpiresSoonSection(cards: cards)
  │     └── internally calls PeriodEngine.activePeriodLog + daysUntilEnd filter
  ├── CollapsedCardRow(card:) [collapsed state]
  │     └── SegmentPipRow(credits:) → per-credit PeriodEngine.activePeriodLog call
  └── CardExpandedBlock(card:) [expanded state]
        └── per credit: PeriodEngine.activePeriodLog, ProgressRingView, CreditLoggingView sheet
```

`PeriodEngine.activePeriodLog(for:)` is a pure function (no side effects). Safe to call in view body / computed properties.

### API/Integration Points

- **`PeriodEngine.activePeriodLog(for:)`** — used by 3 new views. No changes to this function needed.
- **`PeriodEngine.evaluateAndAdvancePeriods()`** — still called from `DashboardView.task {}`. Preserved.
- **`NotificationManager`** — no changes.
- **`CreditLoggingView`** — reused as-is. Only the sheet presentation params change (height 360, drag indicator visible).

### New Design Token Infrastructure

All new semantic colors live in `Assets.xcassets` as named color sets under the `CT/` group, with light + dark appearance variants. Accessed via `CT.accent`, `CT.surface`, etc. from `CreditTrackerTokens.swift`.

**Why named assets instead of `Color(hex:)`:** Named colors resolve light/dark at render time automatically. `Color(hex:)` is a single-environment value. Card gradients (user-defined, no dark variant needed) continue to use `Color(hex:)`.

---

## Phased Implementation Plan

### Phase 1 — Design Token Infrastructure
*Build must succeed after each step. No UI changes visible.*

**Step 1.1** — `CreditTracker/Models/PeriodLog.swift`
Add computed property:
```swift
var daysUntilEnd: Int {
    DateHelpers.daysUntil(periodEnd)
}
```
`DateHelpers.daysUntil(_:)` already exists. No migration needed (computed, not stored).

**Step 1.2** — `CreditTracker/Utilities/CreditTrackerTokens.swift` *(NEW)*
Create `enum CT` namespace with static `Color("CT/…")` references for all 18 tokens. Add `Font` extensions (`ctHeroNumeral`, `ctDollarPrefix`, `ctEyebrow`, `ctMeta`, `ctSectionLabel`, `ctRowTitle`).

**Step 1.3** — `CreditTracker/Assets.xcassets/CT/` *(NEW color sets)*
Create 18 named color sets with light/dark variants:

| Token | Light | Dark |
|-------|-------|------|
| CT/Background | #FAF7F2 | #1A1613 |
| CT/Surface | #FFFFFF | #25201B |
| CT/Surface2 | #F3EEE6 | #2E2822 |
| CT/Accent | #D97757 | #D97757 |
| CT/AccentDeep | #B85A3D | #B85A3D |
| CT/AccentSoft | #F6E3D8 | #3A2218 |
| CT/AccentFaint | #FBF0E9 | #2A1D14 |
| CT/Ink | #2B2620 | #F2EADD |
| CT/Ink2 | #5A5147 | #BCB0A0 |
| CT/Ink3 | #8A8278 | #8A8075 |
| CT/Ink4 | #B8B0A4 | #5A5249 |
| CT/Hairline | rgba(60,50,40,0.10) | rgba(255,240,220,0.10) |
| CT/Done | #3A8A5F | #3A8A5F |
| CT/DoneBg | #E3F1E8 | #1A3326 |
| CT/Partial | #C98A2B | #C98A2B |
| CT/PartialBg | #FAECD1 | #312208 |
| CT/Urgent | #C5533F | #C5533F |
| CT/UrgentBg | #FADDD3 | #301008 |

Also update `AccentColor.colorset` to `#D97757` (terracotta, was unset).

---

### Phase 2 — New Sub-Components
*Add new files; existing dashboard still works. Each gets a `#Preview` for isolated review.*

**Step 2.1** — `HeroCardView.swift`
- Container: `CT.surface` + `cornerRadius: 20` + `.shadow(color: .black.opacity(0.06), radius: 2, y: 1)`
- Eyebrow: `"UNCLAIMED THIS MONTH"` in `.ctEyebrow` + `.tracking(1.5)`, color `CT.ink3`
- Hero numeral: `HStack(alignment: .firstTextBaseline)` — `"$"` in `.ctDollarPrefix` with `baselineOffset(14)`, then `"\(Int(unclaimedAmount))"` in `.ctHeroNumeral`
  - `.contentTransition(.numericText(countsDown: true)).animation(.smooth(duration: 0.35), value: unclaimedAmount)`
- Progress bar: `GeometryReader` → `ZStack(alignment: .leading)` — track Capsule in `CT.accentSoft`, fill Capsule in `CT.accent`, height 6pt
- Chip: `"$\(Int(claimedAmount)) claimed"` pill in `CT.accentFaint` bg, `CT.accentDeep` fg + `" of $\(Int(totalAvailable)) available this period"` in `CT.ink2`

**Step 2.2** — `ExpandChip.swift`
- `Button` with chevron + label text
- Collapsed style: `CT.surface2` bg, `CT.ink3` fg, 0.5pt `CT.hairline` stroke
- Expanded style: `CT.accent` bg, `.white` fg, no stroke
- Chevron: `.rotationEffect(.degrees(expanded ? 180 : 0))` animated with spring `response: 0.42, dampingFraction: 0.86`
- `.sensoryFeedback(.selection, trigger: expanded)`

**Step 2.3** — `CardThumbnail.swift`
- `RoundedRectangle(cornerRadius: size * 0.18)` with card's `LinearGradient`
- Default `size: 40`, width = `size * 1.58` (card aspect ratio)

**Step 2.4** — `SegmentPipRow.swift`
- For each credit: call `PeriodEngine.activePeriodLog(for:)` → map to pip color:
  - `.claimed` → `CT.done`
  - `.partiallyClaimed` → `CT.partial`
  - `.pending` with `daysUntilEnd <= 4` → `CT.urgent`
  - `.pending` → `CT.ink4`
  - `nil` → `CT.ink4`
- `RoundedRectangle(cornerRadius: 2)` at 8×8pt in `HStack(spacing: 4)`

**Step 2.5** — `CollapsedCardRow.swift`
- `HStack(spacing: 12)`: `CardThumbnail(size: 36)` + VStack(name + `SegmentPipRow`) + Spacer + chevron-right icon
- Background: `CT.surface` fill, `cornerRadius: 16`, `CT.hairline` stroke 0.5pt
- Padding: `.horizontal, 16` + `.vertical, 12`
- Non-interactive (global toggle via `ExpandChip`; no per-row tap)

**Step 2.6** — `CardExpandedBlock.swift`
- Internal `@State var logTarget: Credit? = nil` drives `sheet(item:)`
- Header: `CardThumbnail(size: 40)` + card name (`.ctRowTitle`) + fee (`.ctMeta`, `CT.ink3`)
- Per-credit rows: 28pt `ProgressRingView` (ring colors from card gradient when pending, `CT.done`/`CT.done` when claimed) + credit name + period label + trailing "Done" pill or `"$used/$total"` amount
- Tapping a credit row: `logTarget = credit` + `.sensoryFeedback(.impact(weight: .light), trigger: openTap)`
- Sheet: `.sheet(item: $logTarget) { CreditLoggingView(credit: $0, card: card).presentationDetents([.height(360)]).presentationCornerRadius(28).presentationDragIndicator(.visible) }`
- Container: `CT.surface` + `cornerRadius: 20` + `CT.hairline` stroke

**Step 2.7** — `ExpiresSoonSection.swift`
- Receives `cards: [Card]`; internally filters: `activePeriodLog != nil`, `status != .claimed`, `daysUntilEnd <= 14`, sorted ASC, `prefix(2)`
- View is conditionally rendered only when count > 0
- Each row: `CardThumbnail(size: 32)` + credit name + card name + days badge
  - Badge: `"\(daysLeft)d left"` — if `daysLeft <= 4`: `CT.urgent` fg + `CT.urgentBg` bg; else: `CT.ink3` fg + `CT.surface2` bg
- Section label `"EXPIRES SOON"` in `.ctSectionLabel` + `.tracking(1.5)`
- Rows tappable → `CreditLoggingView` sheet with same params as `CardExpandedBlock`

---

### Phase 3 — Retrofit Existing Files

**Step 3.1** — `Views/Components/ProgressRingView.swift`
- Update `onChange(of: fraction)` spring: `response: 0.55, dampingFraction: 0.78` (was 0.6/0.7)
- No structural changes; backward compatible

**Step 3.2** — `Views/Dashboard/CreditRowView.swift`
- Sheet: `.presentationDetents([.height(360)])` (was `.height(320)`)
- Sheet: `.presentationDragIndicator(.visible)` (was `.hidden`)

---

### Phase 4 — Replace `DashboardView` Body

**File:** `Views/Dashboard/DashboardView.swift`

Preserve: all `@Environment`, `@Query`, `@State private var showAddCard`, `evaluatePeriods()` method, `.task {}` hook.

Add: `@AppStorage("dashboardExpanded") private var expanded = false`, `@State private var expandHapticTrigger = false`, and four computed properties (`allCurrentLogs`, `totalAvailable`, `claimedThisMonth`, `unclaimedThisMonth`).

New `body`:
```swift
NavigationStack {
    ScrollView {
        LazyVStack(spacing: 16) {
            HeroCardView(unclaimedAmount: unclaimedThisMonth, ...)
            ExpiresSoonSection(cards: cards)
            HStack { /* "ALL CARDS" label + ExpandChip */ }
            // Animated switch between CollapsedCardRow list and CardExpandedBlock list
            // .animation(.spring(response: 0.42, dampingFraction: 0.86), value: expanded)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
    .background(CT.background.ignoresSafeArea())
    .navigationTitle("Cards")
    .toolbar { /* + button with .glassEffect(in: Circle()) */ }
    .task { evaluatePeriods() }
}
.sheet(isPresented: $showAddCard) { AddCardView() }
```

The `LazyVStack` uses `.animation(.spring(response: 0.42, dampingFraction: 0.86), value: expanded)` for the expand/collapse transition. Cards in collapsed state use `VStack(spacing: 0)` (connected rows) with a single shared background. Cards in expanded state use a gap between each `CardExpandedBlock`.

---

### Phase 5 — Integration & Polish

- Verify empty state still renders (existing empty state preserved)
- Confirm dark mode with CT tokens across all new views
- Check layout on iPhone 16 Pro Max (430pt) — no clipping in ScrollView
- Run app with device date advanced to test "Expires Soon" section
- Test `@AppStorage` persistence by force-quitting and relaunching
- Confirm `NotificationManager` rescheduling still fires after `evaluatePeriods()`

---

## Motion Reference

| Interaction | SwiftUI Code | Haptic |
|-------------|-------------|--------|
| Expand/collapse toggle | `.spring(response: 0.42, dampingFraction: 0.86)` | `.sensoryFeedback(.selection, trigger: expanded)` |
| Progress ring fill | `.spring(response: 0.55, dampingFraction: 0.78)` on `fraction` | — |
| Claim sheet open | `.presentationDetents([.height(360)])`, `.presentationCornerRadius(28)`, `.presentationDragIndicator(.visible)` | `.sensoryFeedback(.impact(weight: .light), trigger: openTap)` |
| Hero numeral update | `.contentTransition(.numericText(countsDown: true))`, `.smooth(duration: 0.35)` | — |

---

## Open Questions

1. **Glass vs. Warm surface on card rows** — the handoff uses flat `CT.surface` fills (no `.glassEffect`) on card rows and the hero card. CLAUDE.md mandates `.glassEffect` on all cards. Which takes precedence? *Recommendation: follow the handoff (flat warm surfaces for content cards; retain `.glassEffect` only on tab bar, nav bar, toolbar buttons, and modal sheet backgrounds).*

2. **Navigation subtitle** — the handoff shows "April 2026" below "Cards" in the nav bar. iOS 26 SwiftUI doesn't expose a native `.navigationSubtitle` on mobile. Options: (a) `ToolbarItem(placement: .principal)` with custom `VStack`, (b) omit subtitle since the hero card eyebrow already says "UNCLAIMED THIS MONTH", (c) place month label as small text below the nav title area in the scroll content. *Recommendation: use hero card eyebrow alone (simplest, already spec'd).*

3. **Tab bar structure** — the handoff wireframe shows 4 tabs (Cards, History, Bonus, More). The existing app has 5 tabs (Credits, Cards, Bonuses, History, Settings). The tab structure is out of scope for this plan — confirm no tab changes are needed.

4. **`CardSectionView.swift` cleanup** — leave as dead code now, or delete from project file? *Recommendation: leave for now, schedule cleanup PR.*

---

## Verification Checklist

- [ ] `CT.*` color tokens resolve correctly (no console warning: "Named color not found")
- [ ] Dark mode: all 18 token colors invert per the table
- [ ] Hero serif numeral animates with `.numericText` after logging a transaction
- [ ] Progress bar in HeroCard animates correctly
- [ ] "Expires Soon" section: appears when a credit has ≤14 days remaining, red badge at ≤4 days, absent when no urgency
- [ ] Expand chip: toggles state, chevron animates, `.selection` haptic fires, state persists across app restarts
- [ ] Collapsed state: pip colors match credit status (done=green, partial=amber, urgent=red, pending=gray)
- [ ] Expanded state: per-credit rows with correct ring fill, "Done" pill on completed credits
- [ ] Tapping a credit row opens `CreditLoggingView` at height 360 with visible drag indicator
- [ ] Logging a transaction updates the pip and ring on the dashboard
- [ ] No layout clipping on iPhone 16 Pro Max (430×932pt)
- [ ] All other tabs (History, Cards, Bonus, Settings) function identically to before
- [ ] Notifications still schedule correctly after `evaluatePeriods()` runs
