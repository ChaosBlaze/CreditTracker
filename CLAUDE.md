# CreditTracker – iOS 26 Credit Card Statement Credit Tracker

## Role & Objective

You are an expert principal iOS developer specializing in Swift and SwiftUI. Your task is to architect and build a complete, compilable iOS application that tracks credit card statement credits. The app must output as a ready-to-archive Xcode project (for `.ipa` export), with a UI perfectly scaled for the **iPhone 16 Pro Max (430 x 932 pt)** and the **iPhone 17 Pro Max (440 x 956 pt)**.

**Target:** iOS 26+ only. Use the latest Swift 6.x and SwiftUI APIs without backward-compatibility constraints.

---

## Design Language & UI/UX

### Liquid Glass Integration (Primary Design Priority)

The app must fully embrace Apple's **Liquid Glass** design language introduced in iOS 26:

- **Glass material surfaces**: Apply `.glassEffect` modifiers to all card containers, navigation bars, tab bars, toolbars, and modal sheets. Cards should appear as frosted, translucent glass panels with depth and refraction.
- **Floating Liquid Glass Tab Bar**: Use the new iOS 26 floating glass tab bar style for the app's primary navigation (Dashboard, History, Settings). DO NOT use the legacy bottom-pinned tab bar.
- **Glass Navigation Bar**: NavigationStack titles and toolbars must use the Liquid Glass material, with large titles that blend into the translucent header.
- **Liquid Glass Buttons**: All primary action buttons (Add Card, Mark Claimed, Save) should use the new glass button style (`.buttonStyle(.glass)` or equivalent iOS 26 API).
- **Glass Sheets & Modals**: Modal sheets for adding/editing cards and credits must use the glass material background with the system-provided depth and blur.
- **Translucent Card Rows**: Each card in the dashboard list should render as a Liquid Glass container with the card's gradient tinting the glass material subtly from behind – the gradient should feel like colored light shining *through* frosted glass, not a flat painted background.
- **Depth & Shadows**: Use the system's glass-appropriate shadow and highlight behaviors. Avoid hard drop shadows – rely on the Liquid Glass depth system for spatial hierarchy.
- **Vibrant Labels**: Use `.foregroundStyle(.primary)` and `.foregroundStyle(.secondary)` for text on glass surfaces to ensure legibility through vibrancy.
- **Semantic Materials**: Where `.glassEffect` is not applicable, use `.ultraThinMaterial`, `.thinMaterial`, and `.regularMaterial` as fallbacks to maintain visual consistency.

### Apple-Native Aesthetic

- The app must look indistinguishable from a first-party Apple app (e.g., Apple Wallet, Fitness, or Reminders).
- Use **Large Titles**, `NavigationStack`, and native modal `Sheet` presentations.
- Use SF Symbols throughout – no custom icon assets except the App Icon.

### Card-Matched Theming

- Credit cards are represented by elegant, subtle **gradient tints** that bleed through Liquid Glass surfaces, mimicking the feel of their physical counterparts viewed through frosted glass.
- Gradients should be soft and desaturated when behind glass – not harsh or fully opaque.

### Visual Progress Rings

- For annual or pooled credits (e.g., a $300 travel credit), implement a **SwiftUI circular progress ring** (identical to Apple Fitness rings) that visually fills up as the user logs partial uses of the credit.
- The ring color should derive from the card's gradient colors.
- Use `Canvas` or `Shape` with `.trim(from:to:)` and `.animation(.spring)` for smooth, modern animation.

### Tactile Feedback

- Use `UIImpactFeedbackGenerator` to provide a satisfying haptic click when a credit is marked as claimed via native swipe actions.
- Use `.sensoryFeedback(.impact(weight: .medium), trigger:)` (the modern SwiftUI API) where possible.

---

## Core Architecture & Data Modeling (SwiftData)

Implement a **local-only** database using SwiftData. The `ModelContainer` must be configured with `ModelConfiguration(isStoredInMemoryOnly: false)` and **no CloudKit**. Ensure the user can easily add, edit, and delete both cards and credits.

### Data Models

**Card** (`@Model`):
| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | Default `.init()` |
| `name` | `String` | Card display name |
| `annualFee` | `Double` | For net ROI calculation |
| `gradientStartHex` | `String` | Hex color (e.g., `"#B76E79"`) |
| `gradientEndHex` | `String` | Hex color |
| `sortOrder` | `Int` | For user reordering |
| `credits` | `[Credit]` | `@Relationship(deleteRule: .cascade)` |

**Credit** (`@Model`):
| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | Default `.init()` |
| `name` | `String` | Credit display name |
| `totalValue` | `Double` | Dollar value per period |
| `timeframe` | `String` | Raw value of `TimeframeType` enum |
| `reminderDaysBefore` | `Int` | Default `5` |
| `customReminderEnabled` | `Bool` | Default `true` |
| `card` | `Card?` | Inverse relationship |
| `periodLogs` | `[PeriodLog]` | `@Relationship(deleteRule: .cascade)` |

**PeriodLog** (`@Model`):
| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | Default `.init()` |
| `periodLabel` | `String` | e.g., "Jan 2026", "Q1 2026", "H1 2026", "2026" |
| `periodStart` | `Date` | Start of the period window |
| `periodEnd` | `Date` | End of the period window |
| `status` | `String` | Raw value of `PeriodStatus` enum |
| `claimedAmount` | `Double` | Partial tracking – drives progress ring fill |
| `credit` | `Credit?` | Inverse relationship |

**Enums** (stored as `String`, Codable):
- `TimeframeType`: `.monthly`, `.quarterly`, `.semiAnnual`, `.annual`
- `PeriodStatus`: `.pending`, `.claimed`, `.partiallyClaimed`, `.missed`

---

## Timeframe & Reset Logic

- The main dashboard must strictly present the **current active period** for each credit based on its timeframe.
- When a period expires, the app **automatically evaluates** the credit:
  - If status is `.pending` -> log as `.missed` in history.
  - If status is `.partiallyClaimed` -> keep as `.partiallyClaimed` with recorded `claimedAmount`.
  - Then generate a new `PeriodLog` for the now-current period.
- The app must handle **cascading gaps**: if the user hasn't opened the app for multiple periods, it must generate `.missed` logs for all skipped periods, not just one.
- The app must handle **monthly, quarterly, semi-annual, and annual** timeframes simultaneously.
- Period evaluation runs on app launch and on `scenePhase` becoming `.active`.

---

## Notifications (UNUserNotificationCenter)

- Implement **local push notifications**.
- By default, schedule a reminder **5 days before** a credit's period expires if its status is still `.pending` or `.partiallyClaimed`.
- Use `UNCalendarNotificationTrigger` with the credit's `id.uuidString` as the notification identifier.
- Provide a UI for the user to:
  - Modify the reminder timeframe (1-30 days before) per credit.
  - Toggle reminders on/off per credit.
- Notification body format: *"Your {credit name} on {card name} expires in {N} days – don't forget to use it!"*
- Reschedule all reminders after period advancement.

---

## Default Seed Data

On first launch (tracked via `@AppStorage("hasSeededData")`), pre-populate with the following cards. The user can edit or add more later.

| Card | Gradient Start | Gradient End | Annual Fee | Default Credit |
|---|---|---|---|---|
| Amex Gold | `#B76E79` (rose gold) | `#C9A96E` (soft gold) | $250 | Monthly $10 Dining Credit |
| Amex Platinum | `#A8A9AD` (platinum) | `#E8E8E8` (light silver) | $695 | Monthly $15 Uber Cash |
| Chase Sapphire Preferred | `#0C2340` (deep sapphire) | `#1A5276` (sapphire blue) | $95 | Annual $50 Hotel Credit |
| Bank of America Premium Rewards | `#BB0000` (dark red) | `#C0392B` (crimson) | $95 | Annual $100 Airline Incidental Credit |
| Amex Delta Gold | `#C9A96E` (gold) | `#003366` (Delta navy) | $150 | *(no default credit)* |

After seeding, create current-period `PeriodLog` entries for each credit and schedule notifications.

---

## Project Structure

```text
CreditTracker/
├── CreditTracker.xcodeproj/
│   └── project.pbxproj
├── CreditTracker/
│   ├── CreditTrackerApp.swift
│   ├── Info.plist
│   ├── Assets.xcassets/
│   │   ├── AppIcon.appiconset/
│   │   │   └── Contents.json
│   │   ├── AccentColor.colorset/
│   │   │   └── Contents.json
│   │   └── Contents.json
│   ├── Models/
│   │   ├── Card.swift
│   │   ├── Credit.swift
│   │   ├── PeriodLog.swift
│   │   └── Enums.swift
│   ├── Services/
│   │   ├── NotificationManager.swift
│   │   ├── PeriodEngine.swift
│   │   └── SeedDataManager.swift
│   ├── Views/
│   │   ├── Dashboard/
│   │   │   ├── DashboardView.swift
│   │   │   ├── CardSectionView.swift
│   │   │   └── CreditRowView.swift
│   │   ├── History/
│   │   │   ├── HistoryView.swift
│   │   │   └── CreditHistoryDetailView.swift
│   │   ├── CRUD/
│   │   │   ├── AddCardView.swift
│   │   │   ├── EditCardView.swift
│   │   │   ├── AddCreditView.swift
│   │   │   └── EditCreditView.swift
│   │   ├── Settings/
│   │   │   └── SettingsView.swift
│   │   └── Components/
│   │       ├── ProgressRingView.swift
│   │       ├── GlassCardContainer.swift
│   │       └── GradientTintedGlass.swift
│   ├── Utilities/
│   │   ├── Color+Hex.swift
│   │   ├── DateHelpers.swift
│   │   └── Constants.swift

## Execution Steps

### Step 1: Define SwiftData Models
- Create Card.swift, Credit.swift, PeriodLog.swift, and Enums.swift with all properties, relationships, and cascade delete rules as specified above.

### Step 2: Build PeriodEngine Service
- Pure logic layer (no UI). Implement:
- currentPeriod(for:referenceDate:) – computes active period window and label.
- evaluateAndAdvancePeriods(credits:now:) – auto-evaluates expired periods, fills gaps with .missed logs, creates new current periods.
- ensureCurrentPeriodExists(for:now:) – idempotent period creation.

### Step 3: Build NotificationManager Service
- Singleton wrapping UNUserNotificationCenter. Implement permission requests, per-credit scheduling, cancellation, and bulk rescheduling.

### Step 4: Build SeedDataManager
- First-launch seed logic with the five default cards, their credits, initial period logs, and notification scheduling.

### Step 5: Build Liquid Glass Components
- GlassCardContainer – a reusable container view that applies .glassEffect with a configurable gradient tint.
- GradientTintedGlass – renders a card's gradient subtly behind a glass material surface.
- ProgressRingView – Apple Fitness-style ring with gradient coloring and spring animation.

### Step 6: Build DashboardView
- Grouped list with Liquid Glass card sections, credit rows with progress rings, swipe actions for claiming (with haptics), and period status indicators. Runs period evaluation in .task {}.

### Step 7: Build HistoryView
- Per-card expandable sections showing: annual fee, total claimed this year, net ROI (claimed - annual fee, green if positive, red if negative), and chronological period log list with status pills.

### Step 8: Build CRUD Views
- Modal sheets with glass material backgrounds for adding/editing cards (name, annual fee, color pickers) and credits (name, value, timeframe picker, reminder settings). Handle notification scheduling on save, cancellation on delete.

### Step 9: Build SettingsView
- Notification permission status, global default reminder days, reset seed data option, about section.

### Step 10: Wire Up App Entry Point
- CreditTrackerApp.swift with ModelContainer, floating Liquid Glass TabView (Dashboard, History, Settings), seed data on appear, period evaluation on scene activation.

### Step 11: Configure for IPA Export
- Set deployment target to iOS 26.0+.
- Set SWIFT_VERSION to 6.x.
- Bundle identifier: com.credittracker.app.
- Signing: Automatic with team placeholder (DEVELOPMENT_TEAM = "").
- Include an ExportOptions.plist for Ad Hoc or Development distribution.
- Add a build note: Archive via Product -> Archive, then Distribute App -> Ad Hoc / Development to produce the .ipa.

Verification Checklist
[ ] Opens in Xcode and builds with zero errors, zero warnings for iOS 26 Simulator.
[ ] Liquid Glass effects render on all cards, navigation bars, tab bar, sheets, and buttons.
[ ] Five seed cards appear on first launch with correct gradients tinting glass surfaces.
[ ] Swipe to claim fires haptic feedback and updates progress ring.
[ ] Partial claim updates ring to fractional fill.
[ ] Period rollover: advancing device date past period end -> expired pending credits become .missed, new periods auto-created.
[ ] Notifications schedule correctly (verify via getPendingNotificationRequests).
[ ] HistoryView shows correct net ROI (total claimed - annual fee) per card.
[ ] CRUD: add, edit, delete cards and credits with persistence across restarts.
[ ] No layout clipping on iPhone 16 Pro Max (430 x 932) or iPhone 17 Pro Max (440 x 956).
[ ] Successful Archive -> .ipa export via Xcode Organizer.

Key Decisions
Decision	Rationale
iOS 26+ only	Full Liquid Glass API access, latest SwiftData and SwiftUI features, no backward-compat code paths.
Liquid Glass as primary design language	Matches Apple's current iOS 26 aesthetic - app looks native and modern.
Local-only SwiftData	No CloudKit complexity; simpler setup, easier IPA sideloading without entitlements.
Annual fee per card	Enables meaningful net ROI calculation in HistoryView.
Full Xcode project	Ready to open, build, archive, and export .ipa without manual project setup.
Hex strings for colors	Avoids SwiftData serialization issues with Color; converted at render time via Color+Hex.swift.
Explicit PeriodLog records	Concrete rows per period make history queries trivial and support gap-filling for missed periods.
Floating glass TabView	Uses iOS 26's new tab bar style - not the legacy pinned bottom bar.
ExportOptions.plist included	Streamlines .ipa export for Ad Hoc / Development distribution.