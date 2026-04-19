# CreditTracker – Refactoring & Scalability Proposal

> **Date:** April 2026  
> **Based on:** ANALYSIS.md  
> **Goal:** A cleaner, more maintainable, and scalable architecture that offloads complexity from the client, eliminates cascading delete risks, and makes the sync layer easy to extend.

---

## 1. Proposed Architecture

### Core Principle: The Client is a View, the Backend is the Engine

The MVP treated Firestore as a "dumb mirror." The refactored architecture inverts this: **Firestore becomes the system of record for shared state**, and Cloud Functions enforce data integrity. The client becomes a thin consumer: write optimistically, let the backend confirm and cascade.

```
┌──────────────────────────────────────────────────┐
│                   iOS Client                      │
│                                                  │
│  SwiftUI Views                                   │
│       ↕ @Observable                              │
│  Repository Layer (per model type)               │
│       ↕ Codable                                  │
│  SyncCoordinator (lightweight orchestration)     │
│       ↕ FirebaseFirestore SDK                    │
└──────────────────────────────────────────────────┘
                    ↕ Firestore SDK
┌──────────────────────────────────────────────────┐
│              Firebase Backend                     │
│                                                  │
│  Firestore (subcollection schema)                │
│       ↕ Firestore triggers                       │
│  Cloud Functions                                 │
│    • onCardDeleted  → cascade delete children   │
│    • onCreditDeleted → cascade delete children  │
│    • aggregateYTDStats → pre-compute ROI         │
│    • validateFamilyID → secure family join       │
│    • onFamilySettingsUpdated (existing)          │
└──────────────────────────────────────────────────┘
```

### Key Architectural Shifts

| Concern | Current | Proposed |
|---|---|---|
| **Cascading deletes** | Client iterates and deletes individually | Cloud Function triggered by parent delete |
| **Relational data structure** | Flat sibling collections with foreign keys | Firestore subcollections |
| **Serialization** | Manual `[String: Any]` parsing (×60 lines) | `Codable` with a FirestoreDecoder |
| **Sync service design** | One 826-line singleton | `SyncCoordinator` + per-model `Repository` types |
| **History data** | HistoryViewModel queries Firestore directly | Reads from SwiftData; stats pre-aggregated by backend |
| **Family join** | Client-side wipe + listener restart | Server-validates ID; client receives data via listeners |
| **Soft deletes** | Hard deletes with orphan risk | `deletedAt` timestamp field + backend GC |

---

## 2. Revised Firestore Schema

### 2.1 Subcollection Hierarchy

Move Card → Credit → PeriodLog relationships into **native Firestore subcollections**. This gives Firestore's security rules, queries, and cascade operations a first-class expression of ownership:

```
users/{familyID}/
  ├── cards/{cardID}/
  │     │   name: String
  │     │   annualFee: Double
  │     │   gradientStartHex: String
  │     │   gradientEndHex: String
  │     │   sortOrder: Int
  │     │   paymentReminderEnabled: Bool
  │     │   paymentReminderDaysBefore: Int
  │     │   paymentDueDay: Int?
  │     │   annualFeeReminderEnabled: Bool
  │     │   annualFeeDate: Timestamp?
  │     │   deletedAt: Timestamp | null        ← NEW: soft delete
  │     │   updatedAt: Timestamp
  │     │
  │     └── credits/{creditID}/               ← MOVED: subcollection of card
  │           │   name: String
  │           │   totalValue: Double
  │           │   timeframe: String
  │           │   reminderDaysBefore: Int
  │           │   customReminderEnabled: Bool
  │           │   deletedAt: Timestamp | null
  │           │   updatedAt: Timestamp
  │           │
  │           └── periodLogs/{logID}/          ← MOVED: subcollection of credit
  │                   periodLabel: String
  │                   periodStart: Timestamp
  │                   periodEnd: Timestamp
  │                   status: String
  │                   claimedAmount: Double
  │                   deletedAt: Timestamp | null
  │                   updatedAt: Timestamp
  │
  ├── bonusCards/{id}/
  │     [same fields as today]
  │     deletedAt: Timestamp | null
  │
  ├── loyaltyPrograms/{id}/
  │     [same fields as today]
  │     deletedAt: Timestamp | null
  │
  ├── cardApplications/{id}/
  │     [same fields as today]
  │     deletedAt: Timestamp | null
  │
  ├── familySettings/
  │     └── settings                           ← rename from "family-discord-settings"
  │           discordReminderEnabled: Bool
  │           discordReminderHour: Int
  │           discordReminderMinute: Int
  │           lastModifiedByToken: String
  │           updatedAt: Timestamp
  │
  ├── deviceTokens/{fcmToken}/
  │     registeredAt: Timestamp
  │     platform: String
  │
  └── stats/
        └── ytd                               ← NEW: pre-aggregated by Cloud Function
              year: Int
              totalFees: Double
              totalExtracted: Double
              monthlyBreakdown: [{month: Int, value: Double}]
              computedAt: Timestamp
```

### 2.2 Soft Delete Strategy

Instead of hard-deleting documents (which requires client-side cascade walks), **mark documents as deleted with a timestamp**:

```typescript
// Cloud Function or client write:
await cardRef.update({
  deletedAt: FieldValue.serverTimestamp()
})
```

**Client behavior:** Listeners filter out `deletedAt != null` documents. The backend Cloud Function (`onCardDeleted`) physically removes all subcollection children on a delay (e.g., 24 hours), giving all devices time to receive the soft-delete signal and update their local SwiftData store.

**Benefits:**
- Eliminates the sequential N-delete cascade from the client.
- All devices converge on the deletion even if they were offline when it happened.
- Provides a grace period for accidental deletes (could expose an "undo" option).
- Backend handles the actual cleanup via a single, atomic Firestore batch.

**Firestore Security Rule addition:**
```
allow read: if resource.data.deletedAt == null || request.auth.uid == familyID;
```

---

## 3. Refactored Sync Logic

### 3.1 Replace the Monolith with a Repository Pattern

Break `FirestoreSyncService` into a lightweight `SyncCoordinator` and per-model repositories:

```
Services/Sync/
  ├── SyncCoordinator.swift       ← replaces FirestoreSyncService (lifecycle only)
  ├── SyncTypes.swift             ← SyncState, SyncError, FirestoreSyncable (kept)
  ├── Repositories/
  │     ├── CardRepository.swift
  │     ├── CreditRepository.swift
  │     ├── PeriodLogRepository.swift
  │     ├── BonusCardRepository.swift
  │     ├── LoyaltyProgramRepository.swift
  │     ├── CardApplicationRepository.swift
  │     └── FamilySettingsRepository.swift
  └── Codable/
        └── FirestoreDecoder.swift  ← Timestamp → Date bridge
```

**SyncCoordinator** only manages:
- `userID` and `setUserID(_:)`
- `startListening()` / `stopListening()` by calling each repository
- `joinFamilySync(id:context:)` with server-side validation

**Each Repository** is responsible for one model type:

```swift
// Example: CardRepository.swift
@MainActor
final class CardRepository {
    private let db: Firestore
    private let userID: String
    private weak var context: ModelContext?
    private var listener: ListenerRegistration?

    func startListening() { ... }
    func stopListening() { listener?.remove() }
    func upload(_ card: Card) async { ... }
    func softDelete(_ card: Card) async { ... }  // sets deletedAt
}
```

**Why this is better:**
- Adding a new model type = adding one new Repository file, zero changes to existing files.
- Each repository can be tested independently.
- Ownership is clear; merge conflicts are eliminated.
- The coordinator is trivially small and easy to reason about.

---

### 3.2 Codable-Based Serialization

Replace the ~60 lines of manual `[String: Any]` field-diffing with `Codable` conformance:

```swift
// FirestoreCard.swift — thin DTO matching the Firestore document schema
struct FirestoreCard: Codable {
    let name: String
    let annualFee: Double
    let gradientStartHex: String
    let gradientEndHex: String
    let sortOrder: Int
    let paymentReminderEnabled: Bool
    let paymentReminderDaysBefore: Int
    @OptionalTimestamp var annualFeeDate: Date?
    @OptionalTimestamp var deletedAt: Date?
}
```

The **FirestoreDecoder** converts Firestore's `[String: Any]` (with `Timestamp` objects) into Swift value types in a single line:

```swift
// In CardRepository.handleSnapshot:
guard let dto = try? FirestoreDecoder().decode(FirestoreCard.self, from: doc.data()) else { return }
card.apply(dto)  // single method updates only changed fields
```

**Apply method on the SwiftData model:**

```swift
extension Card {
    func apply(_ dto: FirestoreCard) {
        if name             != dto.name             { name = dto.name }
        if annualFee        != dto.annualFee        { annualFee = dto.annualFee }
        // ...
    }
}
```

This is still field-diffing but now it is **type-safe** (a type mismatch is a compiler error, not a silent nil) and the boilerplate lives in one place per model, not scattered across a monolith.

**Note:** Firebase's `FirebaseFirestoreSwift` library already provides a `Firestore.Decoder` that handles `Timestamp → Date` conversion via a `@ServerTimestamp` property wrapper. Use this library directly rather than writing a custom decoder.

---

### 3.3 Eliminate pendingUploadIDs

The `pendingUploadIDs` mechanism exists because snapshot listeners can echo our own writes. With subcollections, this problem is reduced because each repository only listens to its own collection path. But a cleaner solution is to include a **device ID in every uploaded document**:

```swift
payload["deviceID"] = myDeviceID  // stable UUID stored in UserDefaults
payload["updatedAt"] = FieldValue.serverTimestamp()
```

Then in the snapshot listener:
```swift
// Skip writes we authored — check deviceID instead of managing a pending set
if doc.data()["deviceID"] as? String == myDeviceID,
   !doc.metadata.fromCache { continue }
```

This is **stateless** — no set to insert/remove, no ordering dependency. Any device restart automatically resets the filter correctly.

---

### 3.4 HistoryView — SwiftData-First with Pre-Aggregated Backend Stats

**Change:** `HistoryViewModel` should read from SwiftData for all display data, and receive pre-computed stats from a Cloud Function.

```swift
// New HistoryViewModel.swift
@Observable
@MainActor
final class HistoryViewModel {
    // Reads from SwiftData via @Query — works offline, always current
    // Stats come from Firestore's stats/ytd document — updated by Cloud Function

    func loadStats() async {
        let snap = try await db.document("users/\(userID)/stats/ytd").getDocument()
        stats = try snap.data(as: HistoryStats.self)
    }
}
```

**Benefits:**
- Works offline (SwiftData is always available).
- Eliminates 3 parallel Firestore reads on every History tab open.
- Stats are pre-aggregated; the client does zero computation.
- Removes `HistoryCard`, `HistoryCredit`, `RawPeriodLog` mirror structs — the real SwiftData models are used directly.

---

## 4. New Cloud Functions

### 4.1 `onCardDeleted` — Backend Cascade Delete

```typescript
// Trigger: when cards/{cardID} gets deletedAt field set (soft delete)
export const onCardDeleted = onDocumentUpdated(
  "users/{familyID}/cards/{cardID}",
  async (event) => {
    const before = event.data?.before.data();
    const after  = event.data?.after.data();

    // Only proceed when deletedAt transitions from null to a Timestamp
    if (before?.deletedAt != null || after?.deletedAt == null) return;

    const { familyID, cardID } = event.params;
    const db = getFirestore();

    // Get all credits in this card's subcollection
    const credits = await db.collection(`users/${familyID}/cards/${cardID}/credits`).get();

    const batch = db.batch();

    for (const creditDoc of credits.docs) {
      // Soft-delete each credit
      batch.update(creditDoc.ref, { deletedAt: FieldValue.serverTimestamp() });

      // Get and soft-delete all period logs for this credit
      const logs = await creditDoc.ref.collection("periodLogs").get();
      for (const logDoc of logs.docs) {
        batch.update(logDoc.ref, { deletedAt: FieldValue.serverTimestamp() });
      }
    }

    await batch.commit();

    // Schedule physical deletion after 48 hours (via a Cloud Tasks queue)
    // ...
  }
);
```

**Why this is better than the current client-side approach:**
- **Atomic:** A single Firestore batch updates all children in one network round-trip.
- **Reliable:** Runs on Google's infrastructure — no device connectivity required.
- **Consistent:** All family devices receive the `deletedAt` updates via their listeners; no orphans.
- **Fast client UX:** The user's delete action returns instantly (optimistic local delete); the backend catches up asynchronously.

---

### 4.2 `onCreditDeleted` — Credit-Level Cascade

```typescript
// Same pattern as onCardDeleted but for the credit → periodLog relationship.
export const onCreditDeleted = onDocumentUpdated(
  "users/{familyID}/cards/{cardID}/credits/{creditID}",
  async (event) => { /* soft-delete all periodLogs */ }
);
```

---

### 4.3 `aggregateYTDStats` — Pre-Computed ROI Dashboard

```typescript
// Trigger: any PeriodLog update — debounced via Cloud Tasks to avoid write storms
export const aggregateYTDStats = onDocumentUpdated(
  "users/{familyID}/cards/{cardID}/credits/{creditID}/periodLogs/{logID}",
  async (event) => {
    // Debounce: enqueue a Cloud Task to run aggregation in 30 seconds
    // The task reads all period logs for the current year and writes stats/ytd
    const { familyID } = event.params;
    await enqueueAggregationTask(familyID);
  }
);

async function runAggregation(familyID: string) {
  // Collection group query: all periodLogs for this family for the current year
  const startOfYear = new Date(new Date().getFullYear(), 0, 1);
  const logs = await getFirestore()
    .collectionGroup("periodLogs")
    .where("periodStart", ">=", Timestamp.fromDate(startOfYear))
    .where("__name__", ">=", `users/${familyID}/`)
    .where("__name__", "<",  `users/${familyID}/~`)
    .get();

  // Aggregate
  let totalExtracted = 0;
  const monthMap: Record<number, number> = {};
  for (const doc of logs.docs) {
    const data = doc.data();
    totalExtracted += data.claimedAmount ?? 0;
    const month = (data.periodStart as Timestamp).toDate().getMonth() + 1;
    monthMap[month] = (monthMap[month] ?? 0) + (data.claimedAmount ?? 0);
  }

  // Get total fees from cards
  const cards = await getFirestore()
    .collection(`users/${familyID}/cards`)
    .where("deletedAt", "==", null)
    .get();
  const totalFees = cards.docs.reduce((sum, d) => sum + (d.data().annualFee ?? 0), 0);

  // Write pre-aggregated result
  await getFirestore().doc(`users/${familyID}/stats/ytd`).set({
    year: new Date().getFullYear(),
    totalFees,
    totalExtracted,
    monthlyBreakdown: Object.entries(monthMap).map(([m, v]) => ({ month: Number(m), value: v })),
    computedAt: FieldValue.serverTimestamp()
  });
}
```

**Why this is better:**
- HistoryView loads one document (`stats/ytd`) instead of fetching all period logs.
- Stats update automatically whenever any period log is claimed.
- The client has zero aggregation code.

---

### 4.4 `validateFamilyJoin` — Server-Side Family Join

```typescript
// Callable Cloud Function — client calls via Firebase SDK
export const validateFamilyJoin = onCall(async (request) => {
  const { familyID } = request.data as { familyID: string };

  if (!familyID || typeof familyID !== "string") {
    throw new HttpsError("invalid-argument", "familyID is required.");
  }

  // Check the family exists by looking for at least one card
  const cards = await getFirestore()
    .collection(`users/${familyID}/cards`)
    .limit(1)
    .get();

  if (cards.empty) {
    throw new HttpsError("not-found", "No family found with this ID. Please check and try again.");
  }

  return { valid: true, cardCount: cards.size };
});
```

**Client usage (before wipe):**
```swift
// In JoinFamilySheet:
let result = try await Functions.functions().httpsCallable("validateFamilyJoin")
    .call(["familyID": inputID])
// Only proceed with wipe if result is valid
```

**Why this is better:**
- Prevents accidental data loss from a mistyped ID.
- The server can add rate limiting and auth checks later.

---

### 4.5 Retained: `onFamilySettingsUpdated`

The existing Cloud Function is well-designed and should be kept. The only change: **remove the duplicate processing path** from `AppDelegate`. Let Firestore be the single delivery mechanism for FamilySettings changes. The FCM silent push becomes purely a background-wake mechanism to ensure the app's Firestore listener fires even when the app is suspended — not a second data delivery channel.

```swift
// Simplified AppDelegate:
func application(_ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    guard userInfo["type"] as? String == "discordReminderUpdated" else {
        completionHandler(.noData)
        return
    }

    // Just wake the app so the Firestore listener re-attaches and delivers the update.
    // All actual processing happens in FamilySettingsRepository.handleSnapshot().
    Task { @MainActor in
        FirestoreSyncService.shared.startListening()
        completionHandler(.newData)
    }
}
```

---

## 5. Migration Strategy

### Phase 0: Preparation (no user impact)

1. **Add `deletedAt: Timestamp?` field** to all Firestore payload extensions. Default to `nil` for new writes. Old documents without the field are treated as `deletedAt == nil` by the new client.
2. **Deploy Cloud Functions** `onCardDeleted` and `onCreditDeleted` (they do nothing until a `deletedAt` field appears).
3. **Add `deviceID` field** to all Firestore payloads. Replace `pendingUploadIDs` logic.
4. **Deploy `validateFamilyJoin`** callable function.
5. **Add `FirebaseFirestoreSwift`** to the iOS package dependencies.

### Phase 1: Repository Split (client refactor, same Firestore schema)

1. Create `CardRepository`, `CreditRepository`, `PeriodLogRepository`, `BonusCardRepository`, `LoyaltyProgramRepository`, `CardApplicationRepository`, `FamilySettingsRepository`.
2. Each repository extracts the corresponding `applyXxxChange` and `fetchXxx` methods from `FirestoreSyncService`.
3. Create `SyncCoordinator` to replace `FirestoreSyncService` as the public API. Forward all calls to the appropriate repository.
4. **Delete** the old `FirestoreSyncService`. Call sites remain unchanged (they call `SyncCoordinator.shared.upload(card)`, etc.).
5. Ship this as a refactor release — no user-visible change, zero data migration required.

### Phase 2: Codable DTO Layer (client refactor, same Firestore schema)

1. Create `FirestoreCard`, `FirestoreCredit`, `FirestorePeriodLog`, etc. `Codable` structs.
2. Replace `[String: Any]` parsing in each repository with `Firestore.Decoder().decode(FirestoreCard.self, from: doc.data())`.
3. Each SwiftData model gets an `apply(_ dto: FirestoreXxx)` method.
4. **Delete** all `applyXxxChange` methods and their field-by-field `if let` chains.
5. No user-visible change, no data migration required.

### Phase 3: HistoryView — SwiftData-First (client refactor)

1. Rewrite `HistoryViewModel` to use `@Query` / `FetchDescriptor` against SwiftData.
2. Deploy `aggregateYTDStats` Cloud Function. Manually trigger it once per family to generate the initial `stats/ytd` document.
3. `HistoryViewModel.loadStats()` reads from `stats/ytd` (Firestore) for ROI numbers; all list data comes from SwiftData.
4. Delete `HistoryCard`, `HistoryCredit`, `RawPeriodLog` mirror structs.
5. **Existing user impact:** History tab is now available offline. Stats may be slightly delayed (up to ~30 seconds) after a claim, but the feed is always current.

### Phase 4: Subcollection Migration (Firestore schema change — most complex)

> This is the highest-risk phase and may be deferred if the Phase 1-3 improvements already meet scalability needs.

**Step 4a: Write a one-time migration Cloud Function**

```typescript
// Run once, on-demand, for each family:
export const migrateToSubcollections = onCall(async (request) => {
  const { familyID } = request.data;
  // Dual-write: for each card, copy credits to cards/{cardID}/credits/
  // For each credit, copy logs to cards/{cardID}/credits/{creditID}/periodLogs/
  // Mark old flat documents with migrated: true (do not delete yet)
});
```

**Step 4b: Update client to write to subcollections**

Update `CardRepository.upload()` to write to `users/{familyID}/cards/{cardID}` (unchanged) and `CreditRepository.upload()` to write to `users/{familyID}/cards/{cardID}/credits/{creditID}`.

**Step 4c: Dual-read window (2-4 weeks)**

Deploy a client version that:
- Writes to new subcollection paths.
- Reads from both old flat collections (for legacy documents) and new subcollections.
- The `migrated: true` flag on old documents tells the client which schema version to use.

**Step 4d: Deprecate flat collections**

Once all active clients are on the new version (monitor via Firebase App Distribution / App Store analytics), remove the old flat collection listeners and delete the migrated documents via a cleanup Cloud Function.

**Step 4e: Update `validateFamilyJoin`**

Update to query `cards` subcollection instead of the flat `cards` collection.

### Risk Mitigation

| Risk | Mitigation |
|---|---|
| Data loss during migration | Keep flat collections read-only during migration; delete only after confirming subcollection parity |
| Old app versions (no subcollection support) | Force-update notice in app (already possible via `remoteConfig`); old clients read from flat collections which remain until Phase 4d |
| Subcollection migration incomplete for a family | `migrated: true` flag is per-document; clients can fall back to flat for unmigrated docs |
| `onCardDeleted` fires during migration | Guard on `deletedAt != null`; migration function does not set `deletedAt` |

---

## 6. Justification for Each Major Change

### Subcollections vs. Flat Collections

**Current:** `credits` is a sibling collection of `cards`, linked by a `cardID` string field.  
**Proposed:** `credits` is a subcollection of each `cards` document.

| Benefit | Explanation |
|---|---|
| **Security** | Firestore rules can enforce that only members of a family can read a card's credits, without complex `get()` calls. `match /cards/{cardID}/credits/{creditID}` is cleaner than `match /credits/{creditID} { if resource.data.cardID in ... }`. |
| **Cascading** | Deleting a card document also deletes the subcollection (via the Cloud Function). No client-side walking. |
| **Queries** | Collection group queries (`collectionGroup("periodLogs")`) work cleanly when scoped to a user. |
| **Cost** | Listeners for `cards/{cardID}/credits` only fire when *that card's* credits change, not when any credit in the family changes. |

### Cloud Function Cascading Deletes vs. Client-Side

**Current:** Client collects all child IDs, issues N sequential `await deleteDocument(...)` calls.  
**Proposed:** Client sets `deletedAt` on the parent (1 write). Cloud Function handles children.

| Benefit | Explanation |
|---|---|
| **Reliability** | Backend runs even if the client disconnects mid-operation. |
| **Atomicity** | Firestore batched writes update all children at once (up to 500 docs). |
| **Speed** | Client write returns immediately (offline-safe). Backend runs async. |
| **Security** | Clients cannot accidentally (or maliciously) leave orphan documents. |
| **Auditability** | Soft deletes create a tamper-evident audit trail. |

### Repository Pattern vs. Monolith

**Current:** One 826-line singleton, 5 code sites per new model type.  
**Proposed:** One ~80-line repository per model type.

| Benefit | Explanation |
|---|---|
| **Single Responsibility** | Each repository owns exactly one model type. |
| **Testability** | Repositories can be unit-tested with a mock Firestore. The monolith cannot easily be tested in isolation. |
| **Extensibility** | New model type = new file. Zero changes to existing files. |
| **Discoverability** | A new developer can read `CardRepository.swift` to understand exactly how cards sync, without reading 826 lines of unrelated code. |

### Codable DTOs vs. Manual [String: Any] Parsing

**Current:** ~60 `if let v = data["field"] as? Type` lines across 7 methods.  
**Proposed:** `Firestore.Decoder().decode(FirestoreCard.self, from: doc.data())`.

| Benefit | Explanation |
|---|---|
| **Type safety** | A field renamed in Firestore will fail at decode time, not silently produce nil. |
| **Completeness** | `Codable` synthesizes all fields; manual parsing can miss a field and silently fail. |
| **Schema documentation** | The DTO struct *is* the schema documentation. |
| **Maintenance** | Adding a new field = add one line to the struct and one line to `apply()`. Currently = add one line in two places (payload + apply method). |

### SwiftData-First History vs. Firestore-Direct

**Current:** `HistoryViewModel` fetches 3 Firestore collections on every History tab open; breaks offline.  
**Proposed:** Reads SwiftData for list data; reads `stats/ytd` for pre-aggregated ROI.

| Benefit | Explanation |
|---|---|
| **Offline** | SwiftData is always available. History works on airplane mode. |
| **Performance** | Zero Firestore reads for the list; one read for stats (and it's cached). |
| **Consistency** | SwiftData is already the source of truth — HistoryView should use the same truth as DashboardView. |
| **Simplicity** | Eliminates `HistoryCard`, `HistoryCredit`, `RawPeriodLog`, the in-memory join, and the pagination cursor logic (SwiftData `FetchDescriptor` handles pagination natively). |

### Soft Deletes vs. Hard Deletes

**Current:** Deletes are permanent and client-originated. Orphans are possible.  
**Proposed:** Client sets `deletedAt`; backend handles physical removal after a delay.

| Benefit | Explanation |
|---|---|
| **Undo** | `deletedAt` documents can be restored by clearing the field. Adds accidental-delete recovery. |
| **Convergence** | All devices see the deletion via their snapshot listeners, regardless of when they come online. |
| **No orphans** | The backend cascade guarantees all children are marked deleted before the parent is physically removed. |
| **Audit trail** | Soft-deleted documents are queryable for debugging and analytics. |

---

## 7. What NOT to Change

| Item | Reason to Keep |
|---|---|
| `PeriodEngine` | Pure Swift logic, zero dependencies, well-tested behavior. No sync concerns. |
| `NotificationManager` | Clean singleton, UNUserNotificationCenter is local-only. No Firestore coupling. |
| `FirestoreSyncable` protocol + `SyncState`/`SyncError` types | Well-designed protocol surface. Keep the protocol; update the conformances to write DTOs. |
| `SeedDataManager` | First-launch seeding is a client concern. Keep it local. |
| SwiftData cascade delete rules | They still apply for the local SwiftData store, preventing orphaned local models. |
| `onFamilySettingsUpdated` Cloud Function | Works correctly. Only change: remove the redundant AppDelegate processing path. |

---

## 8. Estimated Impact Summary

| Metric | Current | After Refactor |
|---|---|---|
| `FirestoreSyncService.swift` line count | 826 | ~100 (SyncCoordinator only) |
| Lines of boilerplate field-diffing | ~60 | ~10 per model (type-safe) |
| Firestore writes to delete a card (10 credits × 12 logs) | 123 sequential writes | 1 write (client); 1 batch (backend) |
| History tab Firestore reads on open | 3 collection fetches | 1 document fetch (stats/ytd) |
| History tab offline support | None | Full (SwiftData) |
| New model type integration effort | 5 code sites in 1 file | 1 new file |
| Risk of orphaned Firestore documents | High | Near zero |
| `pendingUploadIDs` ordering dependency | Present | Eliminated |
| Duplicate FamilySettings update paths | 2 | 1 |
