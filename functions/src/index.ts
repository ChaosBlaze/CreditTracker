/**
 * CreditTracker – Firebase Cloud Functions
 *
 * Function: onFamilySettingsUpdated
 * Trigger:  Firestore onDocumentUpdated — /users/{familyID}/familySettings/{docID}
 *
 * When User A changes the Discord Reminder time in SettingsView, the iOS app
 * writes the new values to Firestore. This function fires on that write and:
 *
 *  1. Reads all FCM registration tokens for the family from the `deviceTokens`
 *     sub-collection (each token was registered by AppDelegate.MessagingDelegate).
 *  2. Sends a silent push (content-available: 1) to every device in the family.
 *  3. Embeds the new time, enabled state, and the sender's FCM token in the
 *     payload so the receiving iOS device can:
 *       a. Update its local SwiftData cache.
 *       b. Reschedule its local UNCalendarNotificationTrigger.
 *       c. Show an immediate "Settings Updated" banner only if it isn't the sender.
 *  4. Cleans up stale/invalid FCM tokens to keep the `deviceTokens` collection tidy.
 *
 * Deploy with:
 *   cd functions && npm run build && firebase deploy --only functions
 */

import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

// Initialise the Admin SDK once for this Cloud Function instance.
// This is a no-op if another function in the same process already called it.
admin.initializeApp();

const db        = admin.firestore();
const messaging = admin.messaging();

// ─────────────────────────────────────────────────────────────────────────────
// Main Function Export
// ─────────────────────────────────────────────────────────────────────────────

export const onFamilySettingsUpdated = onDocumentUpdated(
  // Wildcard path: fires for any document in any family's familySettings collection.
  // In practice there is only one document per family: "family-discord-settings".
  "/users/{familyID}/familySettings/{docID}",

  async (event) => {
    const { familyID, docID } = event.params;
    const newData = event.data?.after.data();

    if (!newData) {
      console.log(`[${docID}] Document deleted or empty after update — skipping.`);
      return;
    }

    // ── Extract updated fields ────────────────────────────────────────────────
    const hour          = (newData.discordReminderHour   as number)  ?? 21;
    const minute        = (newData.discordReminderMinute as number)  ?? 30;
    const enabled       = (newData.discordReminderEnabled as boolean) ?? false;
    const senderToken   = (newData.lastModifiedByToken  as string)   ?? "";
    const formattedTime = formatTime(hour, minute);

    console.log(
      `[${familyID}/${docID}] FamilySettings updated. ` +
      `enabled=${enabled}, time=${formattedTime}, sender=${senderToken.slice(0, 20)}…`
    );

    // ── Fetch all registered device tokens for this family ────────────────────
    const tokensSnap = await db
      .collection(`users/${familyID}/deviceTokens`)
      .get();

    if (tokensSnap.empty) {
      console.log(`[${familyID}] No device tokens found — nothing to push.`);
      return;
    }

    const tokens = tokensSnap.docs.map((doc) => doc.id);
    console.log(`[${familyID}] Sending silent push to ${tokens.length} device(s).`);

    // ── Build the FCM multicast message ───────────────────────────────────────
    //
    // All FCM data payload values MUST be strings; the iOS handler parses them back.
    //
    // APNs headers:
    //   apns-push-type: "background"  — required for silent pushes on iOS 13+.
    //   apns-priority: "5"            — normal priority; 10 would wake a sleeping device
    //                                   immediately but Apple throttles it more aggressively.
    const message: admin.messaging.MulticastMessage = {
      tokens,
      data: {
        type:          "discordReminderUpdated", // iOS handler filters on this key
        hour:          String(hour),
        minute:        String(minute),
        enabled:       String(enabled),          // "true" or "false"
        formattedTime,                           // e.g. "9:30 PM" — shown in the alert
        senderToken,                             // iOS compares this against its own token
      },
      apns: {
        headers: {
          "apns-push-type": "background",
          "apns-priority":  "5",
        },
        payload: {
          aps: {
            // content-available: 1 is the silent-push signal.
            // iOS wakes the app in the background and calls
            // application(_:didReceiveRemoteNotification:fetchCompletionHandler:).
            "content-available": 1,
          },
        },
      },
    };

    // ── Send and collect results ──────────────────────────────────────────────
    const response = await messaging.sendEachForMulticast(message);

    console.log(
      `[${familyID}] Push results — ` +
      `success: ${response.successCount}, failure: ${response.failureCount}`
    );

    // ── Clean up invalid / expired tokens ────────────────────────────────────
    // "messaging/registration-token-not-registered" means the app was uninstalled
    // or the token rotated. Remove it so we don't waste quota on future sends.
    const staleTokens: string[] = [];
    response.responses.forEach((resp, idx) => {
      if (
        !resp.success &&
        resp.error?.code === "messaging/registration-token-not-registered"
      ) {
        staleTokens.push(tokens[idx]);
      }
    });

    if (staleTokens.length > 0) {
      console.log(`[${familyID}] Removing ${staleTokens.length} stale token(s).`);
      const batch = db.batch();
      for (const token of staleTokens) {
        batch.delete(db.doc(`users/${familyID}/deviceTokens/${token}`));
      }
      await batch.commit();
      console.log(`[${familyID}] Stale tokens removed.`);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Converts a 24-hour hour/minute pair into a 12-hour time string.
 *
 * @example formatTime(9, 5)  → "9:05 AM"
 * @example formatTime(21, 30) → "9:30 PM"
 * @example formatTime(0, 0)  → "12:00 AM"  (midnight)
 */
function formatTime(hour: number, minute: number): string {
  const period      = hour >= 12 ? "PM" : "AM";
  const displayHour = hour % 12 || 12;                      // 0 → 12 (midnight)
  const displayMin  = minute.toString().padStart(2, "0");   // 5 → "05"
  return `${displayHour}:${displayMin} ${period}`;
}
