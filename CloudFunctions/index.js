/**
 * sendFamilyDiscordPush
 *
 * Firebase Cloud Function called by the iOS app (via DiscordFamilyPushService) whenever
 * a family member changes their Discord reminder settings.  It reads all registered FCM
 * device tokens for the family and sends a silent APNs push (content-available: 1) to
 * each of them so they can reschedule the local notification without opening the app.
 *
 * DEPLOYMENT
 * ----------
 * 1. Install the Firebase CLI:       npm install -g firebase-tools
 * 2. Log in:                          firebase login
 * 3. Set your project:                firebase use <your-project-id>
 * 4. From this directory:
 *      npm install
 *      firebase deploy --only functions
 *
 * REQUIRED ENVIRONMENT
 * --------------------
 * The function uses the Firebase Admin SDK which is automatically initialised with the
 * project's default service account when deployed via the Firebase CLI — no extra config
 * needed.
 *
 * PAYLOAD (sent by the iOS app)
 * --------------------------------
 * {
 *   "data": {
 *     "familyID":      "<shared Firestore user ID>",
 *     "hour":          14,
 *     "minute":        0,
 *     "enabled":       true,
 *     "senderToken":   "<FCM token of the device that made the change>",
 *     "formattedTime": "2:00 PM",
 *     "isTest":        false   // true → send to ALL devices including sender (for testing)
 *   }
 * }
 *
 * FIRESTORE STRUCTURE EXPECTED
 * ----------------------------
 * /users/{familyID}/deviceTokens/{fcmToken}  { registeredAt, platform }
 */

const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp }  = require("firebase-admin/app");
const { getFirestore }   = require("firebase-admin/firestore");
const { getMessaging }   = require("firebase-admin/messaging");

initializeApp();

exports.sendFamilyDiscordPush = onRequest(
    { region: "us-central1", cors: false },
    async (req, res) => {
        if (req.method !== "POST") {
            res.status(405).send("Method Not Allowed");
            return;
        }

        // Firebase callable convention wraps the payload under "data".
        const payload = req.body?.data ?? req.body ?? {};

        const {
            familyID,
            hour     = 21,
            minute   = 30,
            enabled  = true,
            senderToken   = "",
            formattedTime = "",
            isTest   = false,
        } = payload;

        if (!familyID) {
            res.status(400).json({ error: "familyID is required" });
            return;
        }

        const db        = getFirestore();
        const messaging = getMessaging();

        // Read all registered device tokens for this family.
        const tokenSnap = await db
            .collection("users")
            .doc(familyID)
            .collection("deviceTokens")
            .get();

        if (tokenSnap.empty) {
            res.status(200).json({ result: { sent: 0, message: "No device tokens registered" } });
            return;
        }

        // isTest=true → push every device (useful for verifying end-to-end delivery).
        // isTest=false → skip the sender (they already updated their own notification schedule).
        const targets = tokenSnap.docs
            .map(d => d.id)
            .filter(token => isTest ? true : token !== senderToken);

        if (targets.length === 0) {
            res.status(200).json({ result: { sent: 0, message: "No other devices to notify" } });
            return;
        }

        // Send a silent background push to each target device.
        // content-available:1 wakes the app in the background and calls
        // AppDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:).
        const results = await Promise.allSettled(
            targets.map(token =>
                messaging.send({
                    token,
                    data: {
                        type:          "discordReminderUpdated",
                        hour:          String(hour),
                        minute:        String(minute),
                        enabled:       String(enabled),
                        senderToken:   senderToken,
                        formattedTime: formattedTime,
                    },
                    apns: {
                        payload: {
                            aps: {
                                // content-available:1 is required for background delivery.
                                "content-available": 1,
                            },
                        },
                        headers: {
                            // priority 5 = normal (background).  Use 10 only for visible alerts.
                            "apns-priority":   "5",
                            "apns-push-type":  "background",
                        },
                    },
                    // Android equivalent (if you ever port the app).
                    android: { priority: "normal" },
                })
            )
        );

        const sent   = results.filter(r => r.status === "fulfilled").length;
        const failed = results.filter(r => r.status === "rejected").length;

        // Log any FCM errors so you can see them in Cloud Logging.
        results.forEach((r, i) => {
            if (r.status === "rejected") {
                console.error(`FCM send failed for token[${i}]:`, r.reason?.message ?? r.reason);
            }
        });

        console.log(`Family ${familyID}: sent ${sent}/${targets.length} push(es), ${failed} failed.`);

        res.status(200).json({ result: { sent, failed, total: targets.length } });
    }
);
