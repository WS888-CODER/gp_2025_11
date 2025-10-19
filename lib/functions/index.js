import { onObjectFinalized } from "firebase-functions/v2/storage";
import * as admin from "firebase-admin";
import pdf from "pdf-parse";
import textract from "textract";
import natural from "natural";
import path from "path";
import os from "os";
import fs from "fs";

admin.initializeApp();

export const extractCVKeywords = onObjectFinalized(
  { bucket: "YOUR_PROJECT_ID.appspot.com" },
  async (event) => {
    const file = event.data;
    if (!file || !file.name) return;

    // Only process files inside cv/{uid}/
    if (!file.name.startsWith("cv/")) return;
    const uid = file.name.split("/")[1];
    if (!uid) return;

    const bucket = admin.storage().bucket(file.bucket);
    const tempFilePath = path.join(os.tmpdir(), path.basename(file.name));
    await bucket.file(file.name).download({ destination: tempFilePath });

    let text = "";

    if (file.contentType?.includes("pdf")) {
      const data = await pdf(fs.readFileSync(tempFilePath));
      text = data.text;
    } else if (file.contentType?.includes("word") || file.name.endsWith(".docx")) {
      text = await new Promise((resolve, reject) => {
        textract.fromFileWithPath(tempFilePath, (error, text) => {
          if (error) reject(error);
          else resolve(text);
        });
      });
    }

    fs.unlinkSync(tempFilePath);

    // Tokenize and extract keywords
    const tokenizer = new natural.WordTokenizer();
    const words = tokenizer.tokenize(text || "");
    const freqMap = {};

    words.forEach((w) => {
      const word = w.toLowerCase();
      if (word.length < 3) return;
      if (!/^[a-z]+$/.test(word)) return;
      freqMap[word] = (freqMap[word] || 0) + 1;
    });

    const sorted = Object.entries(freqMap)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 15)
      .map(([word]) => word);

    // Update Firestore
    await admin.firestore().collection("Users").doc(uid).set(
      {
        CVKeywords: sorted,
      },
      { merge: true }
    );

    console.log(`✅ Keywords saved for user ${uid}:`, sorted);
  }
);
