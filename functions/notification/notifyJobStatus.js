import { onDocumentUpdated, onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
// ✅ Ensure Firebase Admin initialized
if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const messaging = getMessaging();

function chunkArray(arr, size) {
  const out = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

function buildBody(jobTitle, status) {
  if (status === "Closed") return `“${jobTitle}” is now closed.`;
  if (status === "Open") return `“${jobTitle}” is now open.`;
  if (status === "Soon") return `“${jobTitle}” will open soon.`;
  return `“${jobTitle}” status changed to ${status}.`;
}

export const notifyOnJobStatusChange = onDocumentUpdated(
  { document: "Jobs/{jobId}", region: "us-central1", secrets: ["OPENAI_API_KEY"], },
  async (event) => {
    const jobId = String(event.params.jobId || "");

    const before = event.data?.before?.data() || {};
    const after = event.data?.after?.data() || {};

    const beforeStatus = String(before.JobStatus || "");
    const afterStatus = String(after.JobStatus || "");
    if (beforeStatus === afterStatus) return;

    const jobTitle = String(after.JobTitle || "A job");

    // 1) Applicants
    const appsSnap = await db
      .collection("Applications")
      .where("JobID", "==", jobId)
      .get();

    const applicantUserIds = new Set();
    appsSnap.forEach((doc) => {
      const d = doc.data() || {};
      if (d.UserID) applicantUserIds.add(String(d.UserID));
    });

    // 2) Favorites
    const favSnap = await db
      .collection("Users")
      .where("favorite", "array-contains", jobId)
      .get();

    const favUserIds = new Set();
    favSnap.forEach((doc) => favUserIds.add(String(doc.id)));

    const targetUserIds = new Set([...applicantUserIds, ...favUserIds]);
    if (targetUserIds.size === 0) return;

    // 3) Build notification message
    const title = "Job Update";
    const body = buildBody(jobTitle, afterStatus);

    // ✅ 4) Save in-app notifications (Firestore)
    const now = FieldValue.serverTimestamp();

    const commits = [];
    let writeBatch = db.batch();
    let ops = 0;

    for (const uid of targetUserIds) {
      const notifRef = db.collection("Notification").doc();
      writeBatch.set(notifRef, {
        UserID: uid,
        JobID: jobId,
        JobTitle: jobTitle,
        Status: afterStatus,
        Message: body,
        Date: now,
        Read: false,
      });

      ops += 1;

      // Firestore batch limit = 500 (خلّيناها 450 احتياط)
      if (ops === 450) {
        commits.push(writeBatch.commit());
        writeBatch = db.batch();
        ops = 0;
      }
    }

    if (ops > 0) commits.push(writeBatch.commit());
    await Promise.all(commits);

    // 5) Tokens (only enabled users)
    const tokens = [];
    const userDocs = await Promise.all(
      [...targetUserIds].map((uid) => db.collection("Users").doc(uid).get())
    );

    userDocs.forEach((snap) => {
      const u = snap.data() || {};
      if (u.notificationsEnabled === true && Array.isArray(u.fcmTokens)) {
        u.fcmTokens.forEach((t) => {
          const token = String(t || "").trim();
          if (token) tokens.push(token);
        });
      }
    });

    const uniqueTokens = [...new Set(tokens)];
    if (uniqueTokens.length === 0) return;

    // 6) Send FCM (500 tokens per multicast)
    for (const batchTokens of chunkArray(uniqueTokens, 500)) {
      await messaging.sendEachForMulticast({
        tokens: batchTokens,
        notification: { title, body },
        data: { jobId, status: afterStatus },
      });
    }
  }
);

export const deleteOldNotifications = onSchedule(
  {
    schedule: "every 24 hours",
    region: "us-central1",
    secrets: ["OPENAI_API_KEY"],
  },
  async () => {
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const oldNotificationsSnap = await db
      .collection("Notification")
      .where("Date", "<", Timestamp.fromDate(thirtyDaysAgo))
      .limit(450)
      .get();

    if (oldNotificationsSnap.empty) {
      console.log("No old notifications to delete.");
      return;
    }

    const batch = db.batch();

    oldNotificationsSnap.docs.forEach((doc) => {
      batch.delete(doc.ref);
    });

    await batch.commit();

    console.log(`Deleted ${oldNotificationsSnap.size} old notifications.`);
  }
);

export const notifyAdminOnNewCompanyRegistration = onDocumentCreated(
  { document: "Users/{userId}", region: "us-central1" },
  async (event) => {
    const user = event.data?.data() || {};

    // only companies
    if (user.UserType !== "Company") return;

    const companyName = String(user.CompanyName || "New Company");
    const companyEmail = String(user.Email || "");

    // get admins
    const adminsSnap = await db
      .collection("Users")
      .where("UserType", "==", "Admin")
      .get();

    if (adminsSnap.empty) return;

    const title = "New Company Registration";

    const body =
      `${companyName} has registered and is waiting for review.`;

    const tokens = [];

    for (const adminDoc of adminsSnap.docs) {
      const adminId = adminDoc.id;
      const adminData = adminDoc.data() || {};

      // save in-app notification
      await db.collection("Notification").add({
        UserID: adminId,
        UserType: "Admin",
        Type: "NewCompanyRegistration",
        CompanyName: companyName,
        CompanyEmail: companyEmail,
        Message: body,
        Read: false,
        Date: FieldValue.serverTimestamp(),
      });

      // collect FCM tokens
      if (
        adminData.notificationsEnabled === true &&
        Array.isArray(adminData.fcmTokens)
      ) {
        adminData.fcmTokens.forEach((t) => {
          const token = String(t || "").trim();
          if (token) tokens.push(token);
        });
      }
    }

    const uniqueTokens = [...new Set(tokens)];

    if (uniqueTokens.length === 0) return;

    await messaging.sendEachForMulticast({
      tokens: uniqueTokens,
      notification: {
        title,
        body,
      },
      data: {
        type: "newCompanyRegistration",
      },
    });
  }
);