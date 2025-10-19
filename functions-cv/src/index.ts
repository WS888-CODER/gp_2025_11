import {onObjectFinalized} from "firebase-functions/v2/storage";
import * as admin from "firebase-admin";
import pdfParse from "pdf-parse";
import textract from "textract";
import natural from "natural";
import path from "path";
import os from "os";
import fs from "fs";

admin.initializeApp();

export const extractCVKeywords = onObjectFinalized(
  {bucket: "jadeer-b4953.firebasestorage.app"},
  async (event) => {
    const file = event.data;
    if (!file || !file.name) return;
    if (!file.name.startsWith("cv/")) return;

    const uid = file.name.split("/")[1];
    if (!uid) return;

    const bucket = admin.storage().bucket(file.bucket);
    const tempFilePath = path.join(os.tmpdir(), path.basename(file.name));
    await bucket.file(file.name).download({destination: tempFilePath});

    let text = "";

    if (file.contentType?.includes("pdf")) {
      const pdfBuf = fs.readFileSync(tempFilePath);
      const data = await pdfParse(pdfBuf);
      text = data.text || "";
    } else if (
      file.contentType?.includes("word") || file.name.endsWith(".docx")
    ) {
      text = await new Promise<string>((resolve, reject) => {
        textract.fromFileWithPath(
          tempFilePath,
          (error: Error | null, body: string | undefined) => {
            if (error) reject(error);
            else resolve(body || "");
          }
        );
      });
    }

    fs.unlinkSync(tempFilePath);

    const tokenizer = new natural.WordTokenizer();
    const words = tokenizer.tokenize(text || "");
    const freqMap: Record<string, number> = {};

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

    await admin.firestore().collection("Users").doc(uid).set(
      {CVKeywords: sorted},
      {merge: true}
    );

    console.log(`Keywords saved for user ${uid}:`, sorted);
  }
);
