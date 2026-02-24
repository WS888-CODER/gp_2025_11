import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";

// ✅ Ensure Firebase Admin initialized (safe even if called multiple times)
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
  { document: "Jobs/{jobId}", region: "us-central1" },
  async (event) => {
    const jobId = String(event.params.jobId || "");

    const before = event.data?.before?.data() || {};
    const after = event.data?.after?.data() || {};

    const beforeStatus = String(before.JobStatus || "");
    const afterStatus = String(after.JobStatus || "");
    if (beforeStatus === afterStatus) return;

    const jobTitle = String(after.JobTitle || "A job");

    // Applicants
    const appsSnap = await db
      .collection("Applications")
      .where("JobID", "==", jobId)
      .get();

    const applicantUserIds = new Set();
    appsSnap.forEach((doc) => {
      const d = doc.data() || {};
      if (d.UserID) applicantUserIds.add(String(d.UserID));
    });

    // Favorites
    const favSnap = await db
      .collection("Users")
      .where("favorite", "array-contains", jobId)
      .get();

    const favUserIds = new Set();
    favSnap.forEach((doc) => favUserIds.add(String(doc.id)));

    const targetUserIds = new Set([...applicantUserIds, ...favUserIds]);
    if (targetUserIds.size === 0) return;

    // Tokens
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

    const title = "Job Update";
    const body = buildBody(jobTitle, afterStatus);

    for (const batch of chunkArray(uniqueTokens, 500)) {
      await messaging.sendEachForMulticast({
        tokens: batch,
        notification: { title, body },
        data: { jobId, status: afterStatus },
      });
    }
  }
);