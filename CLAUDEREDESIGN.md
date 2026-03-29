## Role & Objective

You are an expert principal iOS developer and interaction designer specializing in Swift 6.x and SwiftUI. Your task is to **completely redesign the UI/UX layer** of `CreditTracker` - a credit card statement credit tracker - while **preserving all existing core functionality** (`SwiftData` models, `PeriodEngine`, `NotificationManager`, `RemindersManager`, Bonuses system, and the 5-tab structure).

The current app is functional but visually flat: dark list views, thin progress rings, plain status pills, and minimal surface texture. The redesign must transform it into a **"premium, atmospheric, delightfully tactile"** experience - the kind of app people pull out to show friends.

**Target:** iOS 26+ only. Swift 6.x, SwiftUI, Canvas, CoreMotion, CoreHaptics. iPhone 16 Pro Max (430 x 932 pt) and iPhone 17 Pro Max (440 x 956 pt).

## Existing Functionality to Preserve

These features already exist and must carry forward unchanged in behavior. The redesign affects only how they look and feel.

## Design Philosophy: "Atmospheric Luxury"

Inspired by **Ultrahuman** (moody atmospheric card surfaces), **Minna Bank** (bold oversized typography, generous whitespace, playful minimalism), and **One Finance** (dashboard widgets with progress indicators and gamification steps).

### Core Pillars

1. **"Atmosphere"** - Rich, layered dark surfaces with depth. Subtle animated gradient textures behind cards, not flat black voids. The app should feel like staring into a premium watch face.
2. **"Bold Typography"** - Oversized titles, high-contrast weights. Section headers are unapologetically large. Numbers (dollar amounts, ROI) are the visual heroes on every screen.
3. **"Tactile Surfaces"** - Every card/tile has material presence: subtle noise textures, inner glows, soft gradient bleeds. Nothing should feel like a flat rectangle on a flat background.
4. **"Micro-Delight"** - Every tap, swipe, and state change is rewarded with purposeful animation and haptics. Claiming a credit should feel "satisfying".
5. **"Information Density without Clutter"** - Show more data per screen through smart visual encoding (ring sizes, color intensity, dot patterns) rather than more text.

## Global Design System

### Color & Material

- **"Background"**: NOT pure black (`#000000`). Use a very dark charcoal (`#0A0A0F`) with a subtle radial gradient that brightens slightly toward the center of the screen - creates depth and prevents the "OLED void" feeling.
- **"Card Surfaces"**: Each card/tile uses `.ultraThinMaterial` or `.thinMaterial` layered over a **"subtle mesh gradient"** that incorporates the card's brand colors at ~15% opacity. The card's gradient should feel like colored light leaking through frosted dark glass - not a painted background.
- **"Liquid Glass"**: Apply `.glassEffect` to the tab bar, navigation bar, modal sheets, and primary action buttons. Cards and tiles use the custom atmospheric material described above (glass + gradient bleed) for a richer look than plain liquid glass.
- **"Accent Colors"**: Each card's gradient pair defines an accent system. Status pills, progress rings, badges, and interactive elements on that card's section inherit its accent.
- **"Text"**: Primary text is `.primary` (white). Secondary text is `.secondary` (gray). Dollar amounts and key metrics in the card's accent gradient as a `LinearGradient` fill - numbers should shimmer, not be flat white.

### Typography Scale

| Usage | Style | Weight |
|---|---|---|
| Screen Titles | 34pt | Bold |
| Section headers (card names) | 22pt | SemiBold |
| Credit names | 17pt | Medium |
| Dollar amounts (Hero) | 34pt | Bold, monospaced |
| Dollar amounts (Inline) | 17pt | SemiBold, monospaced |
| Status labels | 13pt | Medium |
| Captions | 11pt | Regular |

### Card Surface Recipe

Every card/tile in the app should be built with this layered approach:

1. **Base**: `RoundedRectangle(cornerRadius: 20)` filled with `.ultraThinMaterial`
2. **Gradient Bleed**: An overlay of the card's `LinearGradient(colors: [startColor.opacity(0.15), endColor.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)`
3. **Noise Texture**: A subtle noise PNG overlay at 5% opacity (gives the surface "grain" like premium paper)
4. **Inner Glow**: A 1pt inner stroke of `white.opacity(0.15)` on the rounded rectangle - creates a subtle edge highlight
5. **Shadow**: `.shadow(color: .black.opacity(0.4), radius: 20, y: 10)` - soft, deep, not harsh
6. **Content padding**: 20pt all sides

### Animated Background

Behind all content on every tab, render a **full-screen `MeshGradient`** with a 3x3 control point grid:
- Colors derived from the first two cards' gradients + deep charcoal anchors
- Control points drift slowly in Lissajous curves using `.animation(.easeInOut(duration: 12).repeatForever(autoreverses: true))`
- Opacity: 30% - subtle, never distracting
- This replaces the flat black background and makes the app feel "alive"

### Tab Bar

- Use the iOS 26 **floating liquid glass tab bar**
- 5 tabs: Credits (`creditcard.fill`), Cards (`rectangle.on.rectangle.angled`), Bonuses (`star.circle.fill`), History (`clock.arrow.trianglehead.counterclockwise.rotate.90`), Settings (`gearshape.fill`)
- Active tab icon uses the primary accent color; inactive tabs use `.secondary`
- The glass tab bar floats above the `MeshGradient` background, creating a layered depth effect

## Screen-by-Screen Redesign

### 1. Credits Tab (Home - Primary Screen)

This is the app's centerpiece. It must be visually stunning at first glance.

**Top Hero Area (New):**
- A full-width "Savings pulse" hero card at the top, spanning edge-to-edge with 16pt horizontal margin
- Shows **"Total Saved"** (current month, large), **"30 / 50 Claimed"** (large hero dollar amount with monospaced digits, gradient-filled text using an interpolated gradient from all cards' colors), and a **slim horizontal progress bar** beneath it showing aggregate claim progress for the current month
- Below the bar: small text showing how many credits are pending vs. claimed vs. missed this period
- The hero card uses the atmospheric card surface recipe with a slightly more intense gradient bleed (30% opacity)
- The progress bar fills with a smooth animated gradient and pulses gently when there are unclaimed credits

**Card Sections (redesigned):**
- Each card group is a large atmospheric card surface (the full recipe: material + gradient bleed + noise + inner glow)
- **"Card header row"**: The card's gradient rendered as a wide, short accent bar (4pt tall, full width, top of the card) instead of a thin left border. Below it: Card name in 22pt semiBold, "$Y/yr • N credits" in secondary text, and a subtle chevron for expand/collapse. The header also shows a **mini dot status badge** (a small capsule: green if claimed > 0, gray if nothing claimed yet) showing the current period's claim total.
- **"Expand/collapse animation"**: Sections expand with a `.spring(response: 0.4, dampingFraction: 0.8)` animation. Use `DisclosureGroup` or a custom toggle with matched geometry.

**Credit Rows (redesigned):**
- Each credit row lives inside the card's atmospheric surface (no separate card per credit - they're grouped)
- **Left**: A **"chunky progress ring"** (6pt stroke + **6pt stroke**) with the card's gradient as the ring color. At 0%, the track is visible as a dark gray ring. At 100%, a subtle glow effect radiates from the ring (a blurred duplicate of the ring behind it at 50% opacity). Ring diameter: 44pt.
- **Center column**: Credit name (17pt medium), period label in secondary text ("Mar 2026"), and the dollar amount as **"$X / $10"** with the claimed portion in the card's accent color and the total in secondary. Below the amount: a **micro progress bar** (2pt tall, 40pt wide) as a secondary visual reinforcement of the ring.
- **Right**: Status pill redesigned - instead of a flat rounded rectangle, use a **"glass capsule"** with the status color as a tint:
  - Claimed: green tint, checkmark icon + "Claimed"
  - Pending: amber tint, clock icon + "Pending", with a subtle pulse animation
  - Partial: blue tint, "Partial" with the percentage
  - Missed: red tint, X icon + "Missed"
- **Tap Interaction**: Tapping the entire credit row opens the Log Transaction sheet (not just a specific button). The row briefly scales down to 0.97 with a haptic tap (`.sensoryFeedback(.impact(weight: .light), trigger: )`) before the sheet presents.

**Swipe Actions (enhanced):**
- Swipe right on a credit row = **"Quick Claim Full Amount"** (green, checkmark icon). Fires a medium haptic and the progress ring animates to 100% with a spring. If the credit is already fully claimed, the swipe action shows "Unclaim" (orange, arrow.uturn.backward icon).
- Swipe left = **"Edit"** (blue) and **"Details"** (gray, shows history for this specific credit).

**Empty State:**
- If a card has no credits, show a tasteful empty state inside the card surface: a large SF Symbol (`plus.circle.dashed`, 40pt, secondary color), "Add your first credit" in secondary text, tappable to open `AddCreditSheet`.

### 2. Cards Tab (Card Collection)

Transform the plain list into a visually rich **card collection** that showcases each card's identity.

**Layout:**
- Vertical scroll of **"physical-feeling card tiles"** - each one wider and shorter than the current rows, at roughly a **8.5:1 aspect ratio** (full width minus 16pt margin, ~180pt tall)
- Each tile uses the **atmospheric card surface** recipe, but with the gradient bleed at **25% opacity** (stronger than Credits tab tiles) - the card's brand colors should be clearly visible as a moody gradient wash across the surface
- The gradient flows diagonally from top-leading to bottom-trailing, with the `gradientStartHex` color dominating the top and `gradientEndHex` at the bottom

**Card Tile Content:**
- **Left column**: Card name in 20pt semiBold (white), annual fee ("$XXX/yr") in secondary text below.
- **Right column**: Annual fee due date - if set, show as a styled date with a calendar icon; if "No due date set", show as a tappable "Set date" link in the card's accent color
- **Bottom edge**: A row of tiny dots representing the card's credits - filled dots for claimed credits this period, hollow for pending, red for missed. This gives an at-a-glance status without navigating to Credits tab. Each dot is 4pt, spaced 4pt apart, colored with the card's gradient.
- **Chevron**: Right-aligned, secondary color, indicating tappable for detail/edit

**Tap**: Opens an **"Edit Card sheet"** (not a navigation push - use a modal sheet with glass material). The sheet shows the card's physical preview at the top.

**Add Card Button**:
- A dashed-outline rounded rectangle at the bottom of the list, same dimensions as a card tile.
- Large "+" icon centered, secondary color
- "Add Card" text below the icon
- Tapping opens `AddCardSheet` with a spring presentation

**Reordering**:
- Long-press a card tile = enter reorder mode with a gentle scale animation (0.95) and a continuous light haptic. Drag to reorder. Uses `.onMove` with custom drag preview.

### 3. Bonuses Tab (Sign-Up Bonus Tracker - Enhanced)

The current Bonuses tab is almost empty. Elevate it into a proper **bonus milestone tracker** with gamification.

**Layout:**

**Active Bonuses Section:**
- Each active bonus is a **large atmospheric card** (full width, ~180pt tall)
- **Top**: Card name + bonus amount in large text ("Wells Fargo - $400 bonus")
- **Center**: A **"step progress indicator"** inspired by One Finance - a horizontal row of circles connected by lines:
  - Each step represents a milestone requirement (e.g., "Open account", "Direct deposit", "Spend $1000", "3 months")
  - Completed steps: filled with green, checkmark inside
  - Current step: larger, pulsing with the card's accent color, showing the requirement text below
  - Future steps: hollow, gray
  - Connecting lines between steps fill with green as steps complete (animated)
- **Bottom**: "X of Y steps complete • Estimated: [date]" in secondary text
- **Swipe left**: Edit or Delete

**Completed Bonuses Section:**
- Section header: "Completed" with a count badge
- Completed bonuses shown as compact rows (similar to current but with the atmospheric card surface)
- Green "Earned" glass capsule badge on the right
- Keep track of total bonuses earned: show a **lifetime bonus counter** at the top of the Completed section ("$X,XXX earned from bonuses")

**Add Bonus Button:**
- Floating "+" glass button in the top-right (matching the Credits tab's add button style)

**Empty State:**
- Playful illustration-style empty state (using SF Symbols composed creatively): a large `gift.circle` icon with sparkle symbols around it
- "Track your sign-up bonuses" text, "Add Bonus" tappable link

### 4. History Tab (Year-in-Review - Transformed)

The current History tab has good data but presents it plainly. Make it a **visual storytelling experience**.

**Hero Summary Card (redesigned):**
- Full-width atmospheric card at the top with intensified gradient bleed
- Year selector: "2026" with left/right arrows to navigate years (if history exists). Year displayed in 34pt bold.
- Three metrics in a horizontal row, each in its own mini glass capsule:
  - **Annual Fees**: "$4,600" in white, label "Fees Paid" below in secondary
  - **Value Extracted**: "$X,XXX" in **green gradient text** (linear gradient from green to emerald), label "Claimed" below
  - **Net ROI**: "$+XXX" in green or "$-X,XXX" in red, with a subtle glow matching the color. Label "Net ROI" below.
- **Animated Odometer Effect**: When the History tab appears (or when switching years), the dollar amounts roll up from zero to their final values using a staggered per-digit animation (each digit scrolls vertically to its target, staggered by 50ms). This creates the airport departure board / odometer effect.

**Monthly Chart (redesigned):**
- Replace the basic bar chart with a **gradient area chart** (Swift Charts `AreaMark`) with the area filled by an interpolated gradient from all cards' accent colors
- X-axis: months (Jan-Dec). Y-axis: dollar value claimed
- The current month's data point has a **pulsing dot** indicator
- Below the chart: a horizontally scrollable row of **month pills** - glass capsules showing "Jan", "Feb", etc. Tapping a month filters the card rows below to show only that month's detail. Active month pill is highlighted with the accent gradient.

**Per-Card ROI Rows (redesigned):**
- Each card gets an atmospheric card row with the card's gradient accent bar at top (same as Credits tab style)
- **Left**: Card name, "Fee: $X • Claimed: $Y" in secondary text
- **Right**: Net ROI amount - green if positive (with a small upward arrow icon), red if negative (with a small downward arrow icon). The number size scales slightly larger for larger absolute values (visual weight encoding).
- **Inline sparkline**: Between the card name and the ROI number, show a tiny **SparklineChartView** - a 60pt x 24pt Swift Charts line showing monthly claim amounts for that card over the year. No axes. Line color matches the card's gradient. This gives instant trend visibility without tapping into detail.
- **Tap**: Expands the row (or navigates) to show a full credit-by-credit breakdown for that card in that year, with period logs listed chronologically.

**Net ROI Gauge (new - hero element):**
- Below the summary card, above the chart, add a **large semicircular gauge** (like a speedometer or Apple's battery widget gauge)
- The gauge arc goes from red (left, negative ROI) through yellow (break-even at center) to green (right, positive ROI)
- A needle/indicator shows where your current net ROI sits on the scale
- The gauge needle animates to its position on appear with a spring
- Total scale: -$5000 (left) to +$5000 (right), auto-adjusting based on max potential
- Below the gauge: text "You're $X away from breaking even" (if negative) or "You're $X ahead!" (if positive) - motivational framing

### 5. Settings Tab (Refined)

Keep it functional and clean but with the atmospheric card treatment.

**Layout:**
- Each settings section (Notifications, Reminders, Data, About) is an atmospheric card surface
- **Notifications section**: Permission status as a glass capsule (green "Enabled" or red "Disabled" with a "Fix" action button). "Test Notification" as a tappable row with a bell icon and a spring animation on the icon when tapped.
- **Reminders section**: Default reminder days with a custom stepper (glass +/- buttons flanking the number, number animates when changed). Discord Redeem Reminder toggle with the iOS 26 glass toggle style. Reminder Time picker in a compact `.datePickerStyle(.compact)`.
- **Data section**: "Reset to Default Data" in a destructive red tint, with a confirmation dialog.
- **About section**: App name, version, iOS target. Version number is tappable.
- **Easter Egg**: Tap version number 7 times = trigger a brief "matrix rain" animation of dollar sign characters (Canvas-based, green $ symbols falling down the screen for 3 seconds), then reveal a hidden debug panel showing: pending notifications count, last period evaluation timestamp, total PeriodLog count, and a "Force Period Evaluation" button.

---

## Log Transaction Sheet (Redesigned - Signature Interaction)

The half-sheet for logging claims is the most-used interaction. Make it feel "premium".

**Presentation:**
- Glass material background (`.presentationBackground(.thinMaterial)`)
- Slides up as a medium-detent sheet (not full screen)
- The card content behind blurs and dims

**Layout (top to bottom):**
1. **Credit identity bar**: Credit name + card name in a compact row. Card's gradient as a small accent dot (10pt circle) next to the card name. Period label ("Monthly - Mar 2026") below in secondary.
2. **Ring + Stats**: centered progress ring (64pt diameter, chunky 8pt stroke, card gradient color) with animation. To the left: "$X used" in secondary. To the right: "$Y remaining" in the card's accent color.
3. **Amount Input - The Radial Dial** (**NEW - replaces numeric keypad**):
   - Instead of a plain number field + keypad, present a **radial dial** - a large circle (200pt diameter) in the center of the sheet
   - The dial is a frosted glass circle (`.ultraThinMaterial`) with the card's gradient tinting it at 10% opacity
   - Around the circumference: tick marks representing dollar increments. For credits ≤ $20, each tick = $1. For credits $21-$100, each tick = $5. For credits > $100, each tick = $10.
   - A **draggable handle** (a bright glass circle, 24pt) sits on the dial's edge. Drag it clockwise to increase the amount, counterclockwise to decrease.
   - The **dollar amount displays in the center** of the dial in 40pt bold monospaced text, updating in real-time as you drag
   - **Per-tick haptic**: Each tick fires a `CHHapticEngine` transient event (intensity 0.4, sharpness 0.8) - the user "feels" each dollar
   - **Snap to max**: When the handle reaches the full amount, it **snaps** with a strong haptic (intensity 1.0) and the ring preview above pulses with a glow
   - A "Max" glass capsule button below the dial to instantly set to full amount
   - The progress ring above updates in real-time as the dial turns
4. **Fallback Direct Input**: Below the dial, a small "Enter amount" text link for users who prefer typing. Tapping it replaces the dial with the numeric keypad (preserving accessibility). The app remembers the user's preference via `@AppStorage`.
5. **Log Transaction Button**: Full-width glass button with the card's gradient as a subtle tint. Text: "Log Transaction". On tap:
   - Button scales down briefly (0.95) with a medium haptic
   - If claiming the full amount: a **confetti burst** erupts from the button (see Confetti Canvas spec below) before the sheet dismisses
   - If partial claim: the sheet dismisses with a standard spring, no confetti
   - The progress ring on the Credits tab animates to the new fill level with a satisfying spring

## Component Library

### `AtmosphericCardView`
Reusable container implementing the full card surface recipe (material + gradient bleed + noise texture + inner glow + shadow). Parameters: `gradientStart: Color`, `gradientEnd: Color`, `gradientOpacity: Double = 0.15`, `cornerRadius: CGFloat = 20`, `@ViewBuilder content`.

### `ChunkyProgressRing`
Progress ring with configurable stroke width (default 6pt), gradient color, track color, and glow effect at 100%. Built with two `Circle().trim()` shapes (track + fill) and a blurred duplicate behind for the glow. Animated with `.spring(response: 0.6, dampingFraction: 0.7)`.

### `GlassStatusPill`
Status capsule with tinted glass background. Parameters: `label: String`, `icon: String` (SF Symbol), `tint: Color`. Uses `.ultraThinMaterial` with the tint at 20% overlay. Supports pulse animation for pending/urgent states.

### `RadialClaimDial`
The full radial dial component. Parameters: `maxAmount: Double`, `currentAmount: Binding<Double>`, `accentGradient: LinearGradient`, `tickIncrement: Double`. Manages its own `CHHapticEngine` for per-tick feedback. Returns the selected amount via binding.

### `ConfettiCanvasView`
Canvas-based particle system. On trigger:
- Emits 50 particles from a configurable origin point
- Shapes: small rectangles (4x8pt) and circles (6pt)
- Colors: 6 random picks from card gradient interpolation + gold + silver
- Initial velocity: radial outward, 200-400 pt/s, random angle
- Gravity: 500 pt/s² applied after 0.3s delay
- Rotation: random ±720°/s
- Opacity: fades to 0 over final 30% of lifetime
- Lifetime: 1.5-2.5s per particle
- Auto-dismisses after 2.5s

### `OdometerText`
Animated numeric display where each digit rolls vertically to target. Parameters: `value: Double`, `format: FloatingPointFormatStyle`. Each digit column animates with `.spring(response: 0.4, dampingFraction: 0.9)`, staggered 50ms per digit from right to left. Used in History hero and anywhere lifetime/aggregate dollar amounts appear.

### `MeshGradientBackground`
Full-screen animated `MeshGradient` with 3x3 control points. Colors derived from first two seed cards' gradients + charcoal anchors. Points animate slowly (12s period, repeating) for organic movement. Rendered at 30% opacity behind all tab content as a shared background.

### `SparklineView`
Inline mini chart using Swift Charts `LineMark`. Parameters: `data: [Double]`, `color: LinearGradient`. No axes, labels, or grid. 60x24pt. Line draws on with `.trim(from: 0, to: 1)` animation on appear.

### `StepProgressView`
Horizontal step indicator for Bonuses. Parameters: `steps: [BonusStep]`, `currentStep: Int`. Circles connected by lines. Completed = filled green + checkmark. Current = pulsing accent. Future = hollow gray. Lines fill with green between completed steps.

### `ROIGaugeView`
Semicircular gauge for History. Parameters: `currentROI: Double`, `maxScale: Double`, Arc gradient from red -> yellow -> green. Animated needle with `.spring`. Label below showing motivational text.

### `ParallaxModifier`
`ViewModifier` using `CMMotionManager` to apply subtle X/Y offset based on device tilt. Parameters: `magnitude: CGFloat = 10`. Used on card surfaces for perceived depth. Falls back to no-op in Simulator.

## Animation & Haptics Specification

### Animation Curves
| Interaction | Curve |
|---|---|
| Section expand/collapse | `.spring(response: 0.4, dampingFraction: 0.8)` |
| Progress ring fill | `.spring(response: 0.6, dampingFraction: 0.7)` |
| Tab switch content | `.easeInOut(duration: 0.25)` |
| Sheet presentation | `.spring(response: 0.45, dampingFraction: 0.85)` |
| Odometer digit roll | `.spring(response: 0.4, dampingFraction: 0.9)`, stagger 50ms |
| Confetti burst | Linear, randomized per-particle (0.0-2.5s) |
| Mesh background drift | `.easeInOut(duration: 12).repeatForever(autoreverses: true)` |
| ROI gauge needle | `.spring(response: 0.7, dampingFraction: 0.6)` - bouncy settle |
| Row tap scale | `.spring(response: 0.2, dampingFraction: 0.7)` to 0.97, back to 1.0 |
| Status pill pulse | `.easeInOut(duration: 1.5).repeatForever(autoreverses: true)` on opacity 0.7 <-> 1.0 |
| Dial tick snap | `.interactiveSpring(response: 0.15, dampingFraction: 0.6)` |

### Haptic Patterns
| Interaction | Haptic |
|---|---|
| Credit row tap | `.sensoryFeedback(.impact(weight: .light), trigger: )` |
| Quick claim swipe | `.sensoryFeedback(.impact(weight: .medium), trigger: )` |
| Dial per-tick | CoreHaptics transient: intensity 0.4, sharpness 0.8 |
| Dial snap to max | CoreHaptics transient: intensity 1.0, sharpness 0.5 + 100ms continuous at 0.5 |
| Full claim confetti | `.notification(.success)` |
| Log Transaction button | `.impact(weight: .medium)` |
| Card reorder drag | `.selectionChanged` (continuous) |
| Achievement unlock | `.notification(.success)` |
| Easter egg trigger | Three rapid transients: intensity 0.4, 0.7, 1.0 spaced 80ms |

---

## Gamification Layer (New Feature - Additive)

*Add these without modifying existing models. Create new `SwiftData` models alongside.*

### New Models

**`Achievement` (`@Model`):**
| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | Default `.init()` |
| `key` | `String` | Unique identifier ("first_claim", "hot_streak_7") |
| `name` | `String` | Display name |
| `icon` | `String` | SF Symbol name |
| `unlockedAt` | `Date?` | nil = locked |
| `requirement` | `String` | Human-readable requirement |

**`UserStats` (`@Model`):**
| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | Default `.init()` |
| `currentStreak` | `Int` | Consecutive periods without a miss |
| `longestStreak` | `Int` | All-time best |
| `lifetimeSaved` | `Double` | Running total claimed |
| `totalClaimCount` | `Int` | Number of individual claims |
| `lastClaimDate` | `Date?` | For streak calculation |

### Achievements List
| Key | Name | Icon | Requirement |
|---|---|---|---|
| `first_claim` | First Claim | `checkmark.seal.fill` | Claim any credit for the first time |
| `hot_streak_7` | Hot Streak | `flame.fill` | 7 consecutive periods without a miss |
| `hot_streak_30` | Inferno | `flame.circle.fill` | 30 consecutive periods without a miss |
| `diamond_hands` | Diamond Hands | `diamond.fill` | Claim every credit for 3 months straight |
| `roi_positive` | In the Green | `chart.line.uptrend.xyaxis` | Total claimed exceeds total annual fees |
| `perfect_month` | Perfect Month | `star.fill` | Every credit claimed in full in one month |
| `speed_demon` | Speed Demon | `bolt.fill` | Claim a credit within 24h of period start |
| `big_saver` | Big Saver | `banknote.fill` | Lifetime savings exceed $1,000 |
| `collector` | Collector | `rectangle.stack.fill` | Track 5+ cards simultaneously |

### Gamification UI Integration

- **Credits Tab Hero Card**: Add a small streak counter next to the monthly savings summary - flame icon + "X-period streak" in accent text. Only shows if streak ≥ 2.
- **Full Claim Celebration**: When a credit is fully claimed AND it triggers an achievement unlock, show the confetti + a brief achievement toast (glass card sliding down from top, showing badge icon + "Achievement Unlocked: [name]", auto-dismisses after 3s).
- **History Tab**: Add a "Your Stats" glass card below the ROI gauge showing: lifetime saved (odometer), current streak (flame), achievements earned (X/Y with a horizontal scroll of earned badge icons). Tapping opens a full achievements gallery sheet.
- **Achievements Gallery Sheet**: Grid of `AchievementBadgeView` components - unlocked badges are full color with a soft glow; locked badges are grayscale with a lock overlay and a subtle shimmer animation hinting at the hidden icon.

### Step 1: Build Foundation Components
`AtmosphericCardView`, `MeshGradientBackground`, `ParallaxModifier`, `HapticEngine`, `MotionManager`, noise texture asset.

### Step 2: Build Progress & Status Components
`ChunkyProgressRing`, `GlassStatusPill`, `OdometerText`, `SparklineView`.

### Step 3: Build RadialClaimDial + ConfettiCanvasView
The signature interaction component. Test per-tick haptics, snap-to-max behavior, and confetti particle system in isolation.

### Step 4: Redesign Credits Tab
`CreditsView` with hero savings card, `CardSectionView` with atmospheric surfaces and gradient accent bars, `CreditRowView` with chunky rings and glass status pills. Integrate tap-to-claim with the redesigned `LogTransactionSheet` (radial dial + fallback keypad).

### Step 5: Redesign Cards Tab
`CardsView` with physical card tiles, gradient bleeds at 25%, credit status dots, reordering. `AddCardSheet` with live preview and color wheel.

### Step 6: Redesign Bonuses Tab
`BonusesView` with `StepProgressView` milestone cards, completed section with lifetime counter, empty state.

### Step 7: Redesign History Tab
`HistoryView` with odometer hero summary, `ROIGaugeView`, gradient area chart with month pills, per-card rows with `SparklineView` and animated ROI. Year navigation.

### Step 8: Redesign Settings Tab
Atmospheric card sections. Easter egg.

### Step 9: Build Gamification Layer
`Achievement` + `UserStats` models, `GamificationEngine` service, achievement evaluation on claim, streak tracking, `AchievementsGallerySheet`, achievement unlock toasts, stats card in History.

### Step 10: Wire Up App Entry Point
Integrate `MeshGradientBackground` as shared background across all tabs. Add new models to `ModelContainer`. Seed achievements on first launch. Connect gamification hooks to claim actions.

### Step 11: Polish Pass
- Verify all animations hit specified spring curves
- Test haptic patterns on physical device
- Verify confetti renders at 60fps
- Test parallax with CoreMotion on device
- Ensure MeshGradient opacity doesn't interfere with readability
- Validate atmospheric card noise texture is visible but subtle
- Test odometer roll stagger timing
- Verify ROI gauge animates cleanly on tab appear
- Test all swipe actions and sheet presentations
- Ensure no layout clipping on both target device sizes

---

## Verification Checklist

- [ ] Builds with zero errors, zero warnings for iOS 26 Simulator
- [ ] `MeshGradient` background renders behind all tabs with slow organic animation
- [ ] All card surfaces use the full atmospheric recipe (material + gradient bleed + noise + inner glow + shadow)
- [ ] Credits tab shows hero savings card with aggregate monthly progress
- [ ] Card sections expand/collapse with spring animation
- [ ] Progress rings are chunky (6pt stroke) with glow effect at 100%
- [ ] Status pills are glass capsules with appropriate tint and icons
- [ ] Tapping a credit row fires light haptic and opens Log Transaction sheet
- [ ] Radial claim dial maps clockwise drag to dollar increase with per-tick haptics
- [ ] Dial snaps at max amount with strong haptic
- [ ] Full claim triggers confetti burst
- [ ] Fallback keypad input works when "Enter amount" is tapped
- [ ] Cards tab shows physical card tiles with 25% gradient bleed and credit dots
- [ ] Bonuses tab shows step progress indicators for active bonuses
- [ ] History tab ROI gauge animates needle on appear
- [ ] Odometer text rolls digits on History tab appear / year change
- [ ] Per-card history rows show inline sparklines
- [ ] Month pills filter the card detail display
- [ ] Gamification streaks track correctly across period rollovers
- [ ] Achievement unlock shows confetti + toast notification
- [ ] Easter egg triggers on 7 version taps in Settings
- [ ] Swipe-right quick claim works with haptic and ring animation
- [ ] Layout correct on iPhone 16 Pro Max (430 x 932) and iPhone 17 Pro Max (440 x 956)
- [ ] All five tabs functional with glass floating tab bar
- [ ] Parallax effect works on physical device (no-op in simulator)
- [ ] Successful Archive -> `.ipa` export

## Key Design Decisions

| Decision | Rationale |
|---|---|
| **Keep 5-tab navigation** | The app has evolved to 5 tabs (Credits, Cards, Bonuses, History, Settings). Users are familiar with this structure. Enhance it rather than replace it. |
| **Atmospheric surfaces over flat black** | Inspired by Ultrahuman: dark ≠ empty. Gradient bleeds + noise texture + inner glow make surfaces feel material, not void. |
| **Radial dial for claiming** | Physical metaphor: turning a dial to "fill up" a credit. Per-tick haptics make each dollar tangible. More engaging than a keypad. |
| **Keypad fallback preserved** | Accessibility and user preference. Some users prefer direct input. Remember choice via `@AppStorage`. |
| **Confetti only on full claim** | Partial claims are routine. Full claims are achievements worth celebrating. Keeps the reward meaningful. |
| **Chunky progress rings (6pt)** | Thin rings disappear on OLED screens. Thick rings are more visually impactful and readable at small sizes. |
| **Gradient accent bar (top) not left border** | A top-spanning bar is more visible and utilizes horizontal space better. The card's brand identity reads immediately. |
| **Step progress for bonuses** | Inspired by One Finance's bonus dots. Sign-up bonuses have multi-step requirements — visualizing steps makes progress tangible. |
| **ROI gauge in History** | A speedometer metaphor makes ROI intuitive. Red -> green arc, needle position — instant comprehension of financial standing. |
| **Inline sparklines** | Inspired by Tufte: small multiples. Seeing 12 months of trend data without tapping into detail is powerful information density. |
| **MeshGradient background** | Makes the app feel alive. Slow organic movement subconsciously signals "this app is active and running." Binds all tabs visually. |
| **Gamification as additive layer** | Streaks and achievements are new but don't modify existing data models. They're layered on top — easy to build, easy to disable. |
| **Bold typography** | Inspired by Minna Bank: numbers (dollar amounts) should be heroes. 34pt monospaced amounts command attention and feel like a premium financial app. |
| **Easter egg** | Delight. Power users love secrets. Zero cost, pure reward. |