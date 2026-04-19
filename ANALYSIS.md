# CreditTracker – Architecture Analysis

> **Date:** April 2026  
> **Analyst:** Architecture Review  
> **Scope:** Full codebase review — SwiftData models, FirestoreSyncService, Cloud Functions, AppDelegate, and all supporting services.

---

## 1. System Overview

CreditTracker is an iOS 26 app for tracking credit card statement credits. It was built in phases, and a cloud-sync layer was added after the initial local-only MVP. The result is a two-layer persistence architecture:

| Layer | Technology | Role |
|---|---|---|
| Local | SwiftData | **Authoritative source of truth** on-device |
| Cloud | Firebase Firestore | Mirror for cross-device / family sync |

### Component Map

```
┌─────────────────────────────────────────────────────┐
│                   CreditTrackerApp.swift             │
│  • ModelContainer setup                              │
│  • Firebase.configure()                              │
│  • Seed data on first launch                        │
│  • Period evaluation on scenePhase → .active        │
│  • Wires FirestoreSyncService                       │
└────────────────┬────────────────────────────────────┘
                 │
     ┌───────────▼───────────┐
     │    AppDelegate.swift   │
     │  • APNs registration   │
     │  • FCM token handoff   │
     │  • Silent push handler │
     │    (FamilySettings)    │
     └───────────────────────┘

┌─────────────────────────────────────────────────────┐
│              FirestoreSyncService.swift              │  ← 826-line singleton
│  • 7 Firestore listeners                            │
│  • upload<T>(_ item: T)                             │
│  • deleteDocument / deleteCardCascading /           │
│    deleteCreditCascading                            │
│  • handleSnapshot → applyXxxChange (×7)             │
│  • joinFamilySync / wipeLocalData                   │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│                SwiftData Models                      │
│  Card → Credit → PeriodLog  (cascade delete)        │
│  BonusCard (independent)                            │
│  FamilySettings (singleton)                         │
│  LoyaltyProgram (independent)                       │
│  CardApplication (independent)                      │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│              Supporting Services                     │
│  PeriodEngine     – pure period logic               │
│  NotificationManager – UNUserNotificationCenter     │
│  SeedDataManager  – first-launch data               │
│  HistoryViewModel – reads Firestore directly        │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│          Cloud Functions (functions/src/index.ts)    │
│  onFamilySettingsUpdated — FCM multicast push       │
└─────────────────────────────────────────────────────┘
```

---

## 2. Data Flow Diagrams

### 2.1 Outbound: Local Write → Firestore

```
User Action (UI)
      │
      ▼
SwiftData model mutation
      │
      ▼
context.save()
      │
      ▼
FirestoreSyncService.upload(_:)
  │
  ├─ pendingUploadIDs.insert(docID)   ← guards against self-echo
  │
  ├─ item.firestorePayload()          ← manual [String: Any] dict
  │    + FieldValue.serverTimestamp()
  │
  └─ collection.document(id).setData(payload, merge: true)
        │
        ▼
    Firestore (cloud write, queued offline if no network)
```

### 2.2 Inbound: Firestore → SwiftData

```
Firestore document change (remote write on another device)
      │
      ▼
QuerySnapshot delivered to snapshot listener
      │
      ▼
handleSnapshot(_ snapshot:, type: SyncModelType)
  │
  ├─ for each DocumentChange:
  │     ├─ .removed → context.delete(localModel)
  │     │
  │     └─ .added / .modified:
  │           ├─ Skip if hasPendingWrites  (local write in-flight)
  │           ├─ Skip & drain if docID in pendingUploadIDs (our own write confirmed)
  │           └─ applyXxxChange(docID:data:context:)
  │                 ├─ Fetch existing local record by UUID
  │                 ├─ Create stub if missing ("Syncing..." placeholder)
  │                 ├─ Diff each field; update only changed fields
  │                 └─ Wire parent relationship (stub parent if missing)
  │
  └─ context.save() if any change applied → SwiftUI UI refresh
```

### 2.3 Family Sync — Discord Reminder Settings

```
Device A (User changes Discord reminder time)
      │
      ▼
SettingsView binding setter
  ├─ FamilySettings.discordReminderHour/Minute = newValue
  ├─ FamilySettings.lastModifiedByToken = myFCMToken
  ├─ context.save()
  ├─ NotificationManager.scheduleDiscordReminder(hour:minute:)
  └─ FirestoreSyncService.upload(settings)
          │
          ▼
      Firestore: users/{familyID}/familySettings/family-discord-settings
          │
          ▼
      Cloud Function: onFamilySettingsUpdated (Firestore trigger)
          │
          ├─ Read users/{familyID}/deviceTokens collection
          │
          └─ FCM MulticastMessage → all registered devices
                  │
        ┌─────────┴────────────┐
        ▼                      ▼
    Device A               Device B
  (senderToken == myToken) (senderToken != myToken)
        │                      │
        ▼                      ▼
  completionHandler(.noData)  AppDelegate.didReceiveRemoteNotification
                               ├─ Update FamilySettings in background ModelContext
                               ├─ Mirror to UserDefaults
                               ├─ NotificationManager.scheduleDiscordReminder(hour:minute:)
                               └─ Show "Settings Updated" banner (if enabled)

  Also on Device B:
  Firestore snapshot listener fires (duplicate path) →
  applyFamilySettingsChange → mirrors UserDefaults again → reschedules again
```

> **Note:** Device B processes the settings change via **two separate code paths** — the FCM silent push (AppDelegate) and the Firestore snapshot listener (FirestoreSyncService). Both paths update SwiftData and reschedule the notification, creating redundant work and potential race conditions.

---

## 3. Firestore Data Model

All data lives under a flat namespace:

```
users/
  └── {familyID}/                   ← UUID string; shared across family devices
        ├── cards/
        │     └── {UUID}
        │           name: String
        │           annualFee: Double
        │           gradientStartHex: String
        │           gradientEndHex: String
        │           sortOrder: Int
        │           paymentReminderEnabled: Bool
        │           paymentReminderDaysBefore: Int
        │           paymentDueDay: Int?
        │           annualFeeReminderEnabled: Bool
        │           annualFeeDate: Timestamp?
        │           updatedAt: Timestamp  (server-set)
        │
        ├── credits/
        │     └── {UUID}
        │           name: String
        │           totalValue: Double
        │           timeframe: String          ← enum raw value
        │           reminderDaysBefore: Int
        │           customReminderEnabled: Bool
        │           cardID: String             ← foreign key → cards/{UUID}
        │           updatedAt: Timestamp
        │
        ├── periodLogs/
        │     └── {UUID}
        │           periodLabel: String        ← e.g. "Apr 2026", "Q2 2026"
        │           periodStart: Timestamp
        │           periodEnd: Timestamp
        │           status: String             ← enum raw value
        │           claimedAmount: Double
        │           creditID: String           ← foreign key → credits/{UUID}
        │           updatedAt: Timestamp
        │
        ├── bonusCards/
        │     └── {UUID}
        │           cardName: String
        │           bonusAmount: String
        │           dateOpened: Timestamp
        │           accountHolderName: String
        │           miscNotes: String
        │           requiresPurchases: Bool
        │           purchaseTarget: Double
        │           currentPurchaseAmount: Double
        │           requiresDirectDeposit: Bool
        │           directDepositTarget: Double
        │           currentDirectDepositAmount: Double
        │           requiresOther: Bool
        │           otherDescription: String
        │           isOtherCompleted: Bool
        │           isCompleted: Bool
        │           updatedAt: Timestamp
        │
        ├── familySettings/
        │     └── "family-discord-settings"   ← hardcoded singleton document ID
        │           discordReminderEnabled: Bool
        │           discordReminderHour: Int
        │           discordReminderMinute: Int
        │           lastModifiedByToken: String  ← FCM token of writing device
        │           updatedAt: Timestamp
        │
        ├── loyaltyPrograms/
        │     └── {UUID}
        │           programName: String
        │           category: String           ← enum raw value
        │           ownerName: String
        │           pointBalance: Int
        │           lastUpdated: Timestamp
        │           gradientStartHex: String
        │           gradientEndHex: String
        │           notes: String | null
        │           updatedAt: Timestamp
        │
        ├── cardApplications/
        │     └── {UUID}
        │           cardName: String
        │           issuer: String
        │           cardType: String           ← enum raw value
        │           applicationDate: Timestamp
        │           isApproved: Bool
        │           player: String             ← "P1" or "P2"
        │           creditLimit: Double
        │           annualFee: Double
        │           notes: String
        │           updatedAt: Timestamp
        │
        └── deviceTokens/
              └── {fcmToken}                  ← FCM token as document ID
                    registeredAt: Timestamp
                    platform: String          ← "ios"
```

### Relationship Representation

Relationships between Card → Credit → PeriodLog are modeled as **foreign keys in flat sibling collections**, not as Firestore subcollections. For example:

```
cards/A1B2C3
credits/D4E5F6  { cardID: "A1B2C3" }
periodLogs/G7H8  { creditID: "D4E5F6" }
```

There is no native way to query "all period logs for card A" without first resolving the credit IDs — the query must be done in two steps (client-side join) or using Firestore's `in` operator with credit ID lists.

---

## 4. Architectural Pain Points

### 4.1 Monolithic FirestoreSyncService

`FirestoreSyncService.swift` is an 826-line singleton that handles:
- Listener lifecycle for 7 collections
- Upload logic for all 7 model types
- Delete logic (simple + cascading)
- Snapshot routing via an internal `SyncModelType` enum
- Stub creation for 7 model types
- Field-level diffing for 7 model types
- Relational linking for Card → Credit → PeriodLog
- FamilySettings-specific notification logic
- userID management and Family Sync join

Every new model type added to the app requires changes in **at least 5 locations** within this single file:
1. A new `SyncModelType` enum case
2. A new listener registration in `startListening()`
3. A new `case` in `handleSnapshot`'s switch statement
4. A new `applyXxxChange(...)` method
5. A new `fetchXxx(id:in:)` helper method

This violates the Open/Closed Principle and makes the file a merge conflict magnet in a team environment.

---

### 4.2 Client-Side Cascading Deletes

```swift
func deleteCardCascading(_ card: Card) async {
    let logIDs    = card.credits.flatMap { $0.periodLogs }.map { $0.syncID }
    let creditIDs = card.credits.map { $0.syncID }

    for id in logIDs    { await deleteDocument(for: PeriodLog.self, id: id) }
    for id in creditIDs { await deleteDocument(for: Credit.self, id: id) }
    await deleteDocument(for: Card.self, id: card.syncID)
}
```

**Problems:**

1. **Sequential API calls.** For a card with 6 credits, each with 12 months of period logs, this issues **79 sequential Firestore delete operations** (72 + 6 + 1). Each `await` adds network round-trip latency.

2. **No atomicity.** If the device loses connectivity after deleting 30 of 79 documents, the remaining 49 documents become permanently orphaned in Firestore. On the next sync, those orphaned documents may be re-applied to SwiftData, resurrecting deleted credits.

3. **Race condition window.** The call site requires: `await deleteCardCascading(card)` *then* `context.delete(card)`. If the snapshot listener fires between the delete calls and the local deletion, stale data can re-appear.

4. **`SettingsView.resetData()` is incomplete.** It only deletes Card/Credit/PeriodLog — it does not delete BonusCard, LoyaltyProgram, or CardApplication documents from Firestore, leaving them as orphans in the cloud.

---

### 4.3 Out-of-Order Document Delivery and Stub Logic

Firestore snapshot listeners do not guarantee delivery order across collections. A `Credit` document can arrive at the client before its parent `Card` document exists in the local SwiftData store. The current solution creates a **stub object**:

```swift
// In applyCreditChange:
if parentCard == nil {
    let stub = Card(name: "Syncing...", annualFee: 0,
                    gradientStartHex: "#000000", gradientEndHex: "#000000", sortOrder: 0)
    stub.id = parentID
    context.insert(stub)
    parentCard = stub
}
```

**Problems:**

1. **UI flicker.** A card briefly displays as "Syncing..." with a black gradient before the real snapshot arrives and fills in the real values. This is especially visible on family join ("wipe and sync") flows where all data arrives from scratch.

2. **Persistent stubs.** If the parent document is deleted on another device *before* the child arrives, or if a network error prevents the parent snapshot from ever arriving, the stub persists indefinitely in SwiftData. The app will display "Syncing..." cards/credits that never resolve.

3. **Three layers of stubs.** `applyCreditChange` can create a stub Card. `applyPeriodLogChange` can create a stub Credit (which itself might have no parent Card). This cascades — a single out-of-order PeriodLog delivery can create two stubs and the real parent never populates either one if only the PeriodLog snapshot arrives.

---

### 4.4 wipeLocalData and the Join Family Hazard

The `joinFamilySync(id:context:)` flow is one of the most dangerous operations in the app:

```swift
func joinFamilySync(id: String, context: ModelContext) throws {
    stopListening()          // 1. Stop listeners
    try wipeLocalData(...)   // 2. Delete ALL local data
    userID = id              // 3. Change identity
    startListening()         // 4. Start listeners for new family
}
```

**Problems:**

1. **No confirmation before destruction.** The `wipeLocalData` call is immediate and irreversible. SwiftData's cascade delete rules mean that `context.delete(card)` will also delete all children, and the `try context.save()` at the end commits the wipe. There is no undo.

2. **Partial wipe on failure.** If `wipeLocalData` throws after deleting Cards (and their cascading children) but before deleting BonusCards, the app is left with BonusCards and LoyaltyPrograms belonging to the *old* family but Card/Credit data from the *new* family.

3. **No server-side validation.** The app accepts any UUID string as a family ID. There is no check that the entered ID corresponds to a real family with data in Firestore. If a user types an incorrect ID, they wipe their local data and are listening to an empty Firestore namespace.

4. **Race condition between stop and wipe.** The Firestore SDK may buffer one final snapshot delivery after `stopListening()` is called. That buffered snapshot could arrive and trigger `handleSnapshot` on the main actor concurrently with the `wipeLocalData` call, potentially writing the old family's data back into the store just before or just after the wipe.

---

### 4.5 Duplicate Code Path for FamilySettings

When Discord reminder settings change, Device B processes the update via **two independent code paths** that both write to SwiftData and reschedule the local notification:

**Path 1 — FCM Silent Push (AppDelegate):**
```swift
settings.discordReminderHour = hour
settings.discordReminderMinute = minute
try? bgContext.save()
NotificationManager.shared.scheduleDiscordReminder(hour: hour, minute: minute)
```

**Path 2 — Firestore Snapshot Listener (FirestoreSyncService):**
```swift
if settings.discordReminderMinute != minute { settings.discordReminderMinute = minute; changed = true }
// → context.save() → rescheduleDiscordReminder()
```

Both paths run on `@MainActor` but use different `ModelContext` instances (the background context in AppDelegate vs. the main context in FirestoreSyncService). This can result in:
- Two separate `context.save()` calls for the same change.
- Two notification reschedule operations, briefly creating a duplicate notification request.
- Potential SwiftData dirty-state conflicts if both contexts are open simultaneously.

---

### 4.6 HistoryViewModel Bypasses SwiftData

`HistoryViewModel` queries Firestore directly, performing its own card/credit resolution in memory:

```swift
async let cardTask   = fetchCards()     // → userCollection("cards").getDocuments()
async let creditTask = fetchCredits()   // → userCollection("credits").getDocuments()
async let yearLogs   = fetchCurrentYearLogs()  // → periodLogs where periodStart >= startOfYear

cardMap   = Dictionary(uniqueKeysWithValues: cards.map   { ($0.id, $0) })
creditMap = Dictionary(uniqueKeysWithValues: credits.map { ($0.id, $0) })
// → in-memory join
```

**Problems:**

1. **Offline breakage.** When there is no network connectivity, `getDocuments()` will fail (or return cached data that may be stale). SwiftData has all the data locally but this ViewModel never consults it.

2. **Stale data.** If the app is in the foreground and a credit is updated, SwiftData reflects the change immediately, but HistoryViewModel's in-memory `creditMap` is stale until the next explicit `reload()` call.

3. **Duplication of schema knowledge.** `HistoryCard`, `HistoryCredit`, and `RawPeriodLog` are parallel Firestore-centric representations of the same models that exist in SwiftData. Any schema change (e.g., adding a field to `Card`) must be updated in three places: the SwiftData model, the Firestore payload extension, and the `HistoryCard` struct.

4. **Firestore read cost.** Every time the History tab is opened, it fetches all cards, all credits, and all period logs from the current year — three separate collection reads. This is expensive for large data sets and doesn't benefit from SwiftData's in-memory cache.

---

### 4.7 Repetitive Boilerplate in apply...Change Methods

Each of the 7 `applyXxxChange` methods follows the same pattern:

1. Guard UUID parsing
2. Fetch existing local record or create stub
3. Compare each field individually; update if changed
4. Return `Bool` indicating whether changes were made

The field-comparison logic (`if let v = data["field"] as? Type, v != model.field { model.field = v; changed = true }`) is copy-pasted approximately **60 times** across the 7 methods. This manual `[String: Any]` parsing is:
- Not type-safe (wrong types silently fail)
- Not exhaustive (missing fields are silently ignored)
- A maintenance burden (field renames require updates in both the model and the apply method)

Swift's `Codable` protocol with a custom `FirestoreDecoder` could eliminate all of this boilerplate.

---

### 4.8 pendingUploadIDs — Fragile Self-Echo Prevention

```swift
// Upload:
pendingUploadIDs.insert(docID)  // Must be BEFORE await
try await collection.document(docID).setData(payload, merge: true)

// Snapshot handler:
if self.pendingUploadIDs.remove(docID) != nil { continue }  // Skip our own echo
```

This mechanism is correct but fragile:
- The comment itself acknowledges the ordering dependency: "Insert BEFORE the await."
- If a future refactor moves the insert after the `await`, the listener will re-apply our own write to SwiftData on every upload.
- If an upload succeeds but the snapshot confirmation is never delivered (unlikely but possible with offline transitions), the ID stays in `pendingUploadIDs` forever, blocking all future remote updates to that document.
- There is no cleanup sweep for stale IDs in `pendingUploadIDs`.

---

### 4.9 Potential Scalability Bottlenecks

| Issue | Current Behavior | Impact at Scale |
|---|---|---|
| **Flat listeners** | 7 listeners fetch ALL documents in all collections on every foreground | 1000 period logs = 1000 documents read on every app open |
| **Sequential cascading deletes** | N individual delete API calls for each card/credit | Slow for cards with years of history; O(n) Firestore writes |
| **In-memory history join** | HistoryViewModel fetches all cards + credits + year's logs simultaneously | 3 full collection reads; no pagination for card/credit lookups |
| **History stats computed client-side** | `buildStats()` aggregates all year's PeriodLogs in Swift | Cannot pre-aggregate; all raw data must be fetched |
| **No Firestore indexes** | `whereField("periodStart", isGreaterThanOrEqualTo:)` requires a composite index | Missing indexes cause runtime query failures; not documented |

---

### 4.10 `UserDefaults` as Secondary Truth Store

Discord reminder settings are stored in three places simultaneously:
1. `FamilySettings` (SwiftData) — the "authoritative" model
2. `UserDefaults` (keys: `discordReminderEnabled`, `discordReminderHour`, `discordReminderMinute`) — legacy/compat mirror
3. Firestore `familySettings/family-discord-settings` — cloud mirror

The two-overload `scheduleDiscordReminder()` design (one with explicit hour/minute params, one reading from UserDefaults) exists specifically to work around the risk of UserDefaults not being updated yet when `rescheduleAll()` is called. This is a symptom of the dual-truth problem, not a solution to it.

---

## 5. Summary of Pain Points

| # | Pain Point | Severity | Affected Files |
|---|---|---|---|
| 1 | Monolithic FirestoreSyncService (826 lines, 7 model types) | High | FirestoreSyncService.swift |
| 2 | Client-side cascading deletes (sequential, non-atomic) | High | FirestoreSyncService.swift, SettingsView.swift |
| 3 | Out-of-order stub logic ("Syncing..." artifacts) | Medium | FirestoreSyncService.swift |
| 4 | Dangerous `wipeLocalData` / join family flow | High | FirestoreSyncService.swift, SettingsView.swift |
| 5 | Duplicate FamilySettings update path (APNs + Firestore) | Medium | AppDelegate.swift, FirestoreSyncService.swift |
| 6 | HistoryViewModel bypasses SwiftData (offline breakage) | High | HistoryViewModel.swift |
| 7 | ~60 lines of copy-paste field-diff boilerplate | Medium | FirestoreSyncService.swift |
| 8 | `pendingUploadIDs` ordering dependency | Low-Medium | FirestoreSyncService.swift |
| 9 | Global listeners — no pagination or incremental fetch | Medium | FirestoreSyncService.swift |
| 10 | Three sources of truth for Discord reminder settings | Low | AppDelegate.swift, SettingsView.swift, FirestoreSyncService.swift |
| 11 | Flat Firestore schema limits query efficiency | Medium | All sync code |
| 12 | No atomic multi-document writes (Firestore batch) | Medium | FirestoreSyncService.swift |
