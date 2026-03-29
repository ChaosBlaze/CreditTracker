# CreditTracker v5.0 — Redesign Changes (TLDR)

## Design Direction
"Atmospheric Luxury" — dark charcoal app (#0A0A0F base), layered glass surfaces with
gradient bleeds, bold monospaced dollar amounts, per-tick haptics on every interaction.
Inspired by Ultrahuman, Minna Bank, and One Finance.

---

## New Files Created

### Components (Views/Components/)
| File | What it does |
|---|---|
| AtmosphericCardView.swift | Reusable card surface: ultraThinMaterial + gradient bleed + noise texture + inner glow + shadow. Replaces GlassCardContainer everywhere. |
| MeshGradientBackground.swift | Animated 3×3 MeshGradient behind all tabs. Colors derived from first two cards. Drifts slowly at 30% opacity — makes the app feel "alive". |
| ParallaxModifier.swift | CoreMotion tilt-based X/Y offset on card surfaces. No-op in Simulator. |
| ChunkyProgressRing.swift | 6pt stroke progress ring (up from thin 4–5pt). Gradient fill, glow at 100%, spring animation. Replaces ProgressRingView everywhere. |
| GlassStatusPill.swift | Tinted glass capsule for status (Claimed/Pending/Partial/Missed). Includes pulse animation for Pending. Replaces flat StatusPill. |
| OdometerText.swift | Per-digit vertical roll animation (airport departure board effect). Used in hero cards and History totals. |
| SparklineView.swift | 60×24pt inline Swift Charts line. Draws on with animation on appear. Used in History per-card rows. |
| RadialClaimDial.swift | The signature claim interaction. Large frosted glass circle with tick marks. Drag clockwise to set amount. CoreHaptics fires on every tick increment. Snaps at max with strong haptic. |
| ConfettiCanvasView.swift | 50-particle Canvas burst triggered on full claim. Physics with gravity, rotation, fade. Auto-dismisses in 2.5s. |
| StepProgressView.swift | Horizontal milestone tracker for Bonuses. Completed = green+checkmark, Current = pulsing accent, Future = gray. |
| ROIGaugeView.swift | Semicircular speedometer gauge (red→yellow→green). Animated needle shows net ROI position. Used in History tab. |

### Services (Services/)
| File | What it does |
|---|---|
| HapticEngine.swift | CoreHaptics singleton. Patterns: dialTick() (0.4 intensity), dialSnapToMax() (1.0 + brief continuous), easterEgg() (three rapid escalating transients). |
| GamificationEngine.swift | Achievement evaluation on claim, streak tracking on period evaluation, lifetime stats updates. Seeding of all 9 achievements on first launch. |

### Models (Models/)
| File | What it does |
|---|---|
| Achievement.swift | SwiftData model. 9 achievements: First Claim, Hot Streak, Inferno, Diamond Hands, In the Green, Perfect Month, Speed Demon, Big Saver, Collector. |
| UserStats.swift | SwiftData model. Tracks currentStreak, longestStreak, lifetimeSaved, totalClaimCount, lastClaimDate. |

---

## Modified Files

### App Entry
**CreditTrackerApp.swift**
- ModelContainer now includes Achievement + UserStats schemas.
- GamificationEngine.seedAchievements() called on every launch (idempotent).
- GamificationEngine.updateStreak() called on scenePhase activation.

**MainTabView** (in CreditTrackerApp.swift)
- MeshGradientBackground + dark radial gradient layered behind all tabs.
- Tab icons updated to spec: rectangle.on.rectangle.angled, star.circle.fill, clock.arrow.trianglehead.counterclockwise.rotate.90.

### Credits Tab
**DashboardView.swift**
- Hero "Savings Pulse" card at top: OdometerText total, aggregate progress bar, claimed/pending/missed counts, streak badge.
- AtmosphericCardView replaces flat list background.
- Background set to #0A0A0F.

**CardSectionView.swift**
- Full-width 4pt gradient accent bar at top (replaces left-border strip).
- Card name now 22pt semibold.
- Mini dot badge (green/gray) shows if anything claimed this period.
- Empty state shows plus.circle.dashed icon.

**CreditRowView.swift**
- ChunkyProgressRing (6pt, 44pt diameter).
- Claimed dollar amount uses card's gradient as text fill.
- 40pt micro progress bar below amount.
- GlassStatusPill replaces flat StatusPill.
- Row tap animates scale to 0.97 before sheet opens.
- Swipe right = Quick Claim Full (green), swipe left = Edit.
- Quick claim triggers GamificationEngine.recordClaim().

### Log Transaction Sheet
**CreditLoggingView.swift** — complete rewrite
- Default input: RadialClaimDial (200pt diameter frosted glass).
- Fallback: numeric keypad (tapping "Enter amount" toggles; preference saved via @AppStorage).
- Per-tick CoreHaptics on dial drag.
- Full claim triggers ConfettiCanvasView burst + 1.5s delay before dismiss.
- Partial claim dismisses immediately.
- Sheet uses .presentationBackground(.thinMaterial).

### Cards Tab
**CardsView.swift** — complete rewrite
- Physical card tiles (AtmosphericCardView, 25% gradient opacity).
- Shows card name, annual fee, due date, credit status dots (filled=claimed, hollow=pending, red=missed).
- Dashed-outline "Add Card" button at bottom.
- parallaxEffect(magnitude: 3) on each tile.

### Bonuses Tab
**BonusView.swift** — complete rewrite
- Section headers with count badges.
- Lifetime bonus earned counter above completed section.
- Completed rows use AtmosphericCardView + GlassStatusPill "Earned" badge.
- Empty state has sparkle decorations around gift.circle icon.

**BonusCardRowView.swift** — complete rewrite
- AtmosphericCardView with gradient bleed.
- StepProgressView shows milestone progress (Open Account → Requirements → Done).
- Detailed progress bars still present below the step indicator.
- Step count summary text ("2 of 3 steps complete").

### History Tab
**HistoryView.swift** — complete rewrite
- Hero summary card: year selector with ← → arrows, three metric capsules (Fees/Claimed/Net ROI) with OdometerText roll animation.
- ROIGaugeView below hero: semicircular arc, animated needle, motivational text.
- Gradient area chart (AreaMark + LineMark) replaces plain BarMark. Current month gets a pulsing dot.
- Month filter pills (horizontal scroll, glass capsules). Tap to filter card rows.
- Your Stats card: lifetime savings, current streak, achievement badge icons, "View All Achievements" link.
- Per-card rows: gradient accent bar, SparklineView inline, ROI with arrow icon + weight-encoded font size.
- AchievementsGallerySheet: 3-column grid, unlocked = full color + glow, locked = grayscale + lock overlay.

**CreditHistoryDetailView.swift** — restyled
- AtmosphericCardView for header and each period log row.
- ChunkyProgressRing (64pt, 8pt stroke) in header.
- GlassStatusPill replaces StatusPill in log rows.

### Cards Tab (Payment Detail)
**CardPaymentDetailView.swift** — restyled
- AtmosphericCardView for card preview header.
- Gradient accent bar in preview.

### Settings Tab
**SettingsView.swift** — complete rewrite
- Each section (Notifications, Reminders, Data, About) is an AtmosphericCardView with appropriate gradient tint.
- Custom glass stepper (ultraThinMaterial +/− buttons) for default reminder days.
- GlassStatusPill for notification permission status.
- Bell icon bounces with .symbolEffect on test tap.
- Version number: tap 7× to trigger easter egg.
- Easter egg: MatrixRainView (Canvas-based falling $ symbols, 3s, then reveals debug panel).
- Debug panel: pending notification count, total PeriodLog count, Force Period Evaluation button.

### CRUD Views
**AddCreditView.swift**
- Preview section uses ChunkyProgressRing instead of ProgressRingView.

### Widget
**ROIProvider.swift**
- ModelContainer schema updated to include Achievement + UserStats.

---

## Gamification System

9 achievements tracked automatically:
- first_claim — first time any credit is claimed
- hot_streak_7 / hot_streak_30 — consecutive periods without a miss
- diamond_hands — all credits claimed 3 months straight
- roi_positive — total claimed > total annual fees
- perfect_month — every credit fully claimed in one month
- speed_demon — claimed within 24h of period start
- big_saver — lifetime savings exceed $1,000
- collector — 5+ cards tracked simultaneously

Stats tracked in UserStats: currentStreak, longestStreak, lifetimeSaved, totalClaimCount.
Streak shown in Credits tab hero card (flame icon, only if ≥ 2).
All stats + badge gallery accessible via History tab "Your Stats" card.

---

## What Was NOT Changed
- All SwiftData model relationships (Card, Credit, PeriodLog, BonusCard) — untouched
- PeriodEngine logic — untouched
- NotificationManager — untouched
- SeedDataManager — untouched
- AddCardView / EditCardView / EditCreditView — untouched (still use Form/native style)
- AddBonusView — untouched
- Widget entry view and ROIEntry — untouched
