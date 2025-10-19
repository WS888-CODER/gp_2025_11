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
  {memory: "1GiB", timeoutSeconds: 120},
  async (event) => {
    const file = event.data;
    if (!file || !file.name) {
      console.log("No file data in event.");
      return;
    }

    const objectName = file.name; // e.g., cv/UID/filename.pdf
    const contentType = file.contentType || "";
    const size = Number(file.size || 0);

    console.log("Incoming object:", {objectName, contentType, size});

    // Only process files under cv/
    if (!objectName.startsWith("cv/")) {
      console.log("Skip (not in cv/):", objectName);
      return;
    }

    // Expect path: cv/{uid}/...
    const parts = objectName.split("/");
    const uid = parts.length >= 2 ? parts[1] : "";
    if (!uid) {
      console.error("Cannot resolve uid from path:", objectName);
      return;
    }

    const bucket = admin.storage().bucket(file.bucket);
    const tmp = path.join(os.tmpdir(), path.basename(objectName));
    await bucket.file(objectName).download({destination: tmp});
    console.log("Downloaded to tmp:", tmp);

    let text = "";
    let parseSource = "unknown";
    let errorMsg: string|null = null;

    try {
      const lowerName = objectName.toLowerCase();

      if (contentType.includes("pdf") || lowerName.endsWith(".pdf")) {
        const buf = fs.readFileSync(tmp);
        const data = await pdfParse(buf);
        text = (data.text || "").trim();
        parseSource = "pdf-parse";
      } else if (
        contentType.includes("word") ||
        contentType.includes("officedocument.wordprocessingml") ||
        lowerName.endsWith(".docx")
      ) {
        text = await new Promise<string>((resolve, reject) => {
          textract.fromFileWithPath(
            tmp,
            (err: unknown, body: string|undefined) => {
              if (err) {
                reject(err);
                return;
              }
              resolve((body || "").trim());
            }
          );
        });
        parseSource = "textract-docx";
      } else {
        // Fallback: generic textract attempt
        text = await new Promise<string>((resolve, reject) => {
          textract.fromFileWithPath(
            tmp,
            (err: unknown, body: string|undefined) => {
              if (err) {
                reject(err);
                return;
              }
              resolve((body || "").trim());
            }
          );
        });
        parseSource = "textract-generic";
      }

      console.log("Text length:", text.length);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      errorMsg = msg;
      console.error("Parsing failed:", msg);
    } finally {
      try {
        fs.unlinkSync(tmp);
      } catch (cleanupErr) {
        const msg =
          cleanupErr instanceof Error ? cleanupErr.message : String(cleanupErr);
        console.warn("Tmp cleanup warning:", msg);
      }
    }

    // Build keywords even if text is empty (we still write LastCVProcess)
    let keywords: string[] = [];
    if (!errorMsg && text.length > 0) {
      const tokenizer = new natural.WordTokenizer();
      const words = tokenizer.tokenize(text);
      const freq: Record<string, number> = {};
      for (const w of words) {
        const word = w.toLowerCase();
        // keep simple alpha tokens (english) to reduce noise
        if (word.length < 3 || !/^[a-z]+$/.test(word)) continue;
        freq[word] = (freq[word] || 0) + 1;
      }
      keywords = Object.entries(freq)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 15)
        .map(([w]) => w);
    }

    const docRef = admin.firestore().collection("Users").doc(uid);
    const payload = {
      LastCVProcess: {
        at: admin.firestore.FieldValue.serverTimestamp(),
        objectName,
        contentType: contentType || null,
        size,
        parseSource,
        textChars: text.length,
        ok: !errorMsg,
        error: errorMsg || null,
      },
      CVKeywords: keywords,
    };

    await docRef.set(payload, {merge: true});
    console.log("Wrote CVKeywords and LastCVProcess for", uid, keywords);
  }
);
