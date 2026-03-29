# CreditTracker v2 – iOS 26 Feature Expansion & UX Overhaul

## Role & Objective
You are an expert principal iOS developer. We are updating the "CreditTracker" iOS 26 application (built with Swift 6, SwiftData, and the Liquid Glass design language) to version 2. Your task is to implement UX fixes, expand the data model, add new default seed data, and build a brand new "Bonus" tracking tab.

Maintain the existing Liquid Glass aesthetic, iOS 26 floating tab bar, and SwiftData architecture from v1, but apply the following critical updates.

---

## 1. UX Fix: The Credit Logging Interface
The v1 swipe-to-log interface was non-intuitive for partial credit usage. 
* **Remove** the swipe-to-claim action for logging partial/full amounts.
* **Implement a "Tap-to-Log" Modal:** Tapping a credit row should now present a compact Liquid Glass modal (`.presentationDetents([.height(300)])` or similar).
* **Modal UI:** It should feature a large, clear numeric input field for the amount used, a "Max" button to auto-fill the remaining available credit, and a prominent "Log Transaction" glass button.
* **Visual Feedback:** Upon saving, the modal should dismiss, and the progress ring should animate to its new state.

## 2. Expanded Haptic Feedback
Enhance the tactile feel of the app using `.sensoryFeedback` and `UIImpactFeedbackGenerator`:
* Trigger a `.success` haptic when successfully logging a credit.
* Trigger a `.selection` or `.impact(weight: .light)` haptic when toggling checkboxes or opening modals.
* Trigger a `.warning` haptic if the user tries to log an amount greater than the remaining credit balance.

## 3. Multiple Credits Per Card & Seed Data Update
Ensure the UI and `Card` -> `[Credit]` relationship gracefully displays multiple credits under a single card section. Update the `SeedDataManager` to include these specific cards and comprehensive credits:

1.  **Amex Platinum** ($895 fee):
    * $15 Monthly Uber Cash ($35 in December)
    * $50 Semi-Annual Saks Fifth Avenue Credit
    * $200 Annual Airline Fee Credit
    * $20 Monthly Digital Entertainment Credit
2.  **Capital One Venture X** ($395 fee):
    * $300 Annual Travel Credit
3.  **Marriott Bonvoy Bevy™ American Express® Card** ($250 fee):
    * *(Leave credits blank/empty by default, but ensure the card generates beautifully).*
4.  **Citi Strata Premier** ($95 fee):
    * $100 Annual Hotel Credit

## 4. New Feature: Bonus Tracker (Sign-Up Bonuses)
Create a new primary tab in the floating tab bar called **Bonus** (using an appropriate SF Symbol like `sparkles` or `gift`).

### Data Model (`BonusCard` - `@Model`)
Create a new SwiftData model to track active Sign-Up Bonuses.
* `id`: UUID
* `cardName`: String
* `bonusAmount`: String (e.g., "75,000 Points" or "$200")
* `dateOpened`: Date
* **Requirements (Booleans & Associated Values):**
    * `requiresDirectDeposit`: Bool
    * `directDepositTarget`: Double? (Ask for amount if bool is true)
    * `requiresPurchases`: Bool
    * `purchaseTarget`: Double? (Ask for amount if bool is true)
    * `requiresOther`: Bool
    * `otherDescription`: String? (Allow text input if bool is true)
* **Progress:**
    * Add corresponding "current progress" fields for the active requirements (e.g., `currentPurchaseAmount`) so the user can track how close they are.
    * `isCompleted`: Bool

### Bonus Tab UI/UX
* **Dashboard:** A beautiful, easy-to-reference list or grid of active Bonus cards. Use the Liquid Glass design language.
* **Progress Indicators:** For cards with a `purchaseTarget`, show a linear or circular progress bar indicating how close they are to hitting the minimum spend.
* **Adding a Bonus:** A modal sheet with a clean form. If the user toggles `requiresDirectDeposit`, `requiresPurchases`, or `requiresOther`, dynamically reveal (`withAnimation`) the corresponding input fields for the targets.
* **Completion:** Allow the user to check off completed requirements. When all requirements are met, mark the card as `isCompleted`, trigger a celebratory haptic, and move it to a "Completed" section at the bottom of the view.

---
**Execution:** Please provide the updated SwiftData models, the revised `SeedDataManager`, the new `CreditLoggingView` modal, and the complete implementation for the new `BonusView` and its associated components.