# CreditTracker v3 – CloudKit Sync, Home Screen Widgets, and UX Polish

## Role & Objective
You are an expert principal iOS developer. We are updating the "CreditTracker" iOS 26 application to version 3. Your task is to refactor the local data persistence to use CloudKit, implement a native iOS home screen widget, build a new ROI dashboard, and polish the UX with comprehensive haptics and swipe-to-delete functionalities.

Maintain the existing Swift 6, SwiftUI, and Liquid Glass design language from v2.

---

## 1. Architecture Refactor: SwiftData + CloudKit
The app must transition from a purely local SwiftData setup to iCloud synchronization so the user's setup persists across app updates and devices.
* **Refactor `@Model` Classes:** Update `Card`, `Credit`, `PeriodLog`, and `BonusCard` models to be fully compatible with CloudKit. Ensure all properties are either optional or have default values, and that relationships are explicitly mapped to avoid CloudKit schema sync errors.
* **ModelContainer Update:** Configure the `ModelContainer` to use the default CloudKit container identifier. Ensure the code handles offline-first capabilities seamlessly, syncing when the network is available.
* **Data Organization:** Structure the iCloud sync logic so future feature additions (like custom categories or user profiles) can be added to the schema without breaking existing cloud data.

## 2. Universal Haptic Feedback
Integrate tactile feedback throughout the entire application to make it feel premium and responsive.
* Use `.sensoryFeedback` and `UIImpactFeedbackGenerator` appropriately:
    * `.selection`: For picking dates, changing timeframe segments, or tapping minor list items.
    * `.impact(weight: .light)`: For toggling checkboxes in the Bonus section and opening modals.
    * `.impact(weight: .medium)`: For swiping actions.
    * `.success`: For saving a new card, completing a bonus requirement, or successfully logging a transaction.
    * `.warning`: For destructive actions (deleting) or invalid inputs.

## 3. Swipe-to-Delete Implementation
* Implement native SwiftUI `.swipeActions(edge: .trailing, allowsFullSwipe: true)` on the `Card` rows (in Dashboard/Settings) and `BonusCard` rows (in the Bonus tab).
* Include a `Button(role: .destructive)` with a trash icon.
* Trigger a `.warning` haptic and prompt a glass-themed confirmation dialog before executing the deletion to prevent accidental data loss.

## 4. History Page: ROI Dashboard
At the top of the History tab, implement a highly aesthetic, Liquid Glass-styled "Year in Review" Dashboard.
* **Calculations:** Sum up the total `annualFee` across all active cards. Sum up the total `claimedAmount` from all `PeriodLog` entries for the current calendar year.
* **UI:** Create a beautiful visualization showing "Total Fees" vs. "Value Extracted". Use dynamic text colors (e.g., green if Value > Fees, red if Fees > Value).
* **Charts:** Integrate Swift Charts (`Chart`) to show a clean, elegant bar or line graph of value extracted month-over-month. Keep the chart background translucent to blend with the Liquid Glass theme.

## 5. Native Home Screen Widget (WidgetKit)
Create a Widget Extension for the app.
* **Target:** iOS 26 home screen.
* **Functionality:** Display a miniaturized version of the ROI Dashboard (Total Fees vs. Value Extracted).
* **UI:** Use `.containerBackground` with a subtle gradient and a glass-like aesthetic to match the main app. Ensure it looks great in both Light and Dark modes, and supports the new iOS tinted widget styles.
* **Data Sharing:** Ensure the main app and the Widget Extension share the SwiftData ModelContainer via an App Group container so the widget displays real-time iCloud data.

## 6. Settings Page Easter Egg
Below the "About" section in the Settings tab, add a personalized developer signature.
* **Text:** "Built by Shekar"
* **Design:** Mimic the iconic Apple "hello" cursive aesthetic. Use a smooth, continuous cursive font (or a custom `Path` animation if a font isn't suitable) with an animated, colorful `.foregroundStyle` gradient that slowly shifts over time.

---
**Execution:** Please provide the updated CloudKit-compatible SwiftData models, the WidgetKit extension setup and views, the updated History view with the new ROI dashboard and Swift Charts, and the implementations for universal haptics and the new Settings page signature.