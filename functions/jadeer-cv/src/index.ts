import { onObjectFinalized } from "firebase-functions/v2/storage";
import admin from "firebase-admin";
import path from "path";
import os from "os";
import fs from "fs";
// @ts-ignore - ESM import issue
import { PDFParse } from "pdf-parse";
// @ts-ignore - CJS module
import textract from "textract";

// احمِ التهيئة على ESM
if (!admin.apps || admin.apps.length === 0) {
  admin.initializeApp();
}

/** Extended English stopwords (balanced size) */
const EN_STOP = new Set<string>([
  // Articles & Conjunctions
  "the","a","an","and","or","but","if","because","while","although","however",

  // Prepositions
  "in","on","at","to","from","for","by","of","with","about","between",
  "into","through","over","under","up","down","off","out","around",

  // Verbs (common auxiliaries)
  "is","am","are","was","were","be","been","being","have","has","had",
  "do","does","did","will","would","shall","should","can","could","may","might","must",

  // Pronouns
  "i","me","my","mine","you","your","yours","he","him","his",
  "she","her","hers","it","its","we","us","our","ours","they","them","their","theirs",
  "myself","yourself","himself","herself","ourselves","themselves",

  // Determiners & Quantifiers
  "this","that","these","those","any","some","each","every","no","not","none","few","many","much","more","most","such","very",

  // Adverbs / connectors
  "as","than","then","so","also","just","only","too","once","ever","never","again","yet","still","here","there","when","where","why","how",

  // Misc
  "etc","etc.","&","–","—","•"
]);


/** tech terms allowlist (short/symbolic allowed) */
const TECH_TERMS = [
  "c", "c++", "c#", ".net", "java", "python", "dart", "swift", "kotlin",
  "javascript", "typescript", "js", "ts", "node", "node.js", "react",
  "vue", "angular", "flutter", "android", "ios",
  "html", "css", "sass", "tailwind",
  "sql", "mysql", "postgres", "mongodb", "nosql", "redis",
  "graphql", "rest", "api", "oop", "mvc", "mvvm",
  "aws", "gcp", "azure", "s3", "ec2", "lambda",
  "docker", "k8s", "kubernetes", "ci", "cd", "ci/cd",
  "git", "github", "gitlab", "bitbucket",
  "linux", "bash", "powershell",
  "ml", "ai", "nlp", "cv", "llm",
  "ui", "ux", "figma", "jira", "agile", "scrum",
  "power bi", "powerbi", "excel", "tableau",
];

/** Escape a string for safe literal usage inside RegExp. */
function esc(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Extract top English keywords by frequency. */
function extractEnglishKeywords(text: string, limit = 20): string[] {
  const norm = text.normalize("NFKC");
  const lower = norm.toLowerCase();

  const freq: Record<string, number> = {};

  // 1) long simple tokens
  const tokens = lower.match(/\b[a-z]{3,}\b/g) || [];
  for (const t of tokens) {
    if (EN_STOP.has(t)) continue;
    freq[t] = (freq[t] || 0) + 1;
  }

  // 2) tech terms allowlist
  for (const term of TECH_TERMS) {
    const re = new RegExp(esc(term), "gi");
    const matches = lower.match(re);
    if (matches && matches.length > 0) {
      const key = term.toLowerCase();
      freq[key] = (freq[key] || 0) + matches.length;
    }
  }

  return Object.entries(freq)
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit)
    .map(([w]) => w);
}

export const extractCVKeywords = onObjectFinalized(
  {
    region: "us-central1",
    memory: "1GiB",
    timeoutSeconds: 120,
  },
  async (event) => {
    const file = event.data;
    if (!file?.name) {
      console.warn("No file data in event.");
      return;
    }

    const objectName = file.name; // e.g. cv/<uid>/filename.pdf
    const contentType = file.contentType || "";
    const size = Number(file.size || 0);

    console.log("Incoming object:", { objectName, contentType, size });

    // enforce folder
    if (!objectName.startsWith("cv/")) {
      console.log("Skip (not in cv/):", objectName);
      return;
    }

    // robust uid extraction
    const m = objectName.match(/^cv\/([^/]+)\//);
    const uid = m?.[1] ?? "";
    if (!uid) {
      console.error("Cannot resolve uid from path:", objectName);
      return;
    }

    const bucket = admin.storage().bucket(file.bucket);
    const tmp = path.join(os.tmpdir(), path.basename(objectName));
    await bucket.file(objectName).download({ destination: tmp });
    console.log("Downloaded to tmp:", tmp);

    let text = "";
    let errorMsg: string | null = null;

    try {
      const lowerName = objectName.toLowerCase();

      if (contentType.includes("pdf") || lowerName.endsWith(".pdf")) {
        const buf = fs.readFileSync(tmp);
        const parser = new PDFParse({ data: buf });
        const result = await parser.getText();
        text = (result.text || "").trim();
        await parser.destroy();
      } else if (
        contentType.includes("word") ||
        contentType.includes("officedocument.wordprocessingml") ||
        lowerName.endsWith(".docx")
      ) {
        text = await new Promise<string>((resolve, reject) => {
          textract.fromFileWithPath(tmp, (err: unknown, body?: string) => {
            if (err) return reject(err);
            resolve((body || "").trim());
          });
        });
      } else {
        text = await new Promise<string>((resolve, reject) => {
          textract.fromFileWithPath(tmp, (err: unknown, body?: string) => {
            if (err) return reject(err);
            resolve((body || "").trim());
          });
        });
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
        const msg = cleanupErr instanceof Error ? cleanupErr.message : String(cleanupErr);
        console.warn("Tmp cleanup warning:", msg);
      }
    }

    let keywords: string[] = [];
    if (!errorMsg && text.length > 0) {
      keywords = extractEnglishKeywords(text, 20);
    }

    const docRef = admin.firestore().collection("Users").doc(uid);
    const payload = {
      CVKeywords: keywords,
    };

    await docRef.set(payload, { merge: true });
    console.log("Saved keywords for uid:", uid, "count:", keywords.length);
  }
);
