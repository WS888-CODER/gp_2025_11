import * as v2 from "firebase-functions/v2";

/* ===================== Helpers ===================== */

function getOpenAIKey() {
  return process.env.OPENAI_API_KEY || "";
}

/**
 * Convert ANY selected specialty (including sub-specialties)
 * into one of the supported buckets in your table.
 */
function normalizeSpecialtyToBucket(specialtyRaw = "") {
  const s = (specialtyRaw || "").toLowerCase().trim();

  // Cybersecurity
  if (s.includes("cybersecurity")) return "cybersecurity";

  // Data / AI
  if (s.includes("data") || s.includes("ai") || s.includes("machine learning")) {
    return "data & artificial intelligence";
  }

  // Engineering (any branch)
  if (
    s.includes("engineering") ||
    s.includes("civil") ||
    s.includes("mechanical") ||
    s.includes("electrical") ||
    s.includes("chemical") ||
    s.includes("industrial") ||
    s.includes("petroleum")
  ) {
    return "engineering";
  }

  // Marketing / Media / Creative
  if (
    s.includes("marketing") ||
    s.includes("content") ||
    s.includes("copywriting") ||
    s.includes("branding") ||
    s.includes("creative") ||
    s.includes("advertising") ||
    s.includes("public relations") ||
    s.includes("media") ||
    s.includes("journalism") ||
    s.includes("photography") ||
    s.includes("videography") ||
    s.includes("motion") ||
    s.includes("graphic")
  ) {
    return "media & communication";
  }

  // Finance & Accounting
  if (
    s.includes("accounting") ||
    s.includes("auditing") ||
    s.includes("finance") ||
    s.includes("investment") ||
    s.includes("risk")
  ) {
    return "finance & accounting";
  }

  // HR
  if (s.includes("human resources") || s === "hr") return "human resources";

  // Law
  if (s.includes("legal") || s.includes("compliance")) return "law";

  // Education
  if (s.includes("teaching") || s.includes("training")) return "education";

  // Healthcare
  if (s.includes("health") || s.includes("medical")) return "healthcare & medical";

  // Business & Ops
  if (
    s.includes("business") ||
    s.includes("operations") ||
    s.includes("project") ||
    s.includes("supply chain") ||
    s.includes("procurement") ||
    s.includes("strategy") ||
    s.includes("consulting") ||
    s.includes("quality management")
  ) {
    return "business administration";
  }

  // Default (Tech/IT)
  return "computer & information technology";
}

/**
 * Mock specialties profile (ONLY your mock list).
 * No "other" and no additional fields.
 *
 * IMPORTANT: This expects a BUCKET specialty (normalized).
 */
function mapMockSpecialtyProfile(bucketSpecialty = "") {
  const s = (bucketSpecialty || "").toLowerCase().trim();

  const table = {
    "computer & information technology": {
      tech: ["Software Basics", "APIs", "Databases", "Debugging", "Security Awareness"],
      beh: ["Ownership", "Collaboration", "Learning mindset", "Attention to detail"],
    },
    cybersecurity: {
      tech: ["Threats/Phishing", "Access Control", "OWASP Basics", "Incident Response", "Risk Thinking"],
      beh: ["Calm under pressure", "Integrity", "Attention to detail", "Risk awareness"],
    },
    "data & artificial intelligence": {
      tech: ["Data Cleaning", "Basic Statistics", "Model Basics", "Evaluation", "Ethics/Privacy"],
      beh: ["Analytical thinking", "Communication", "Experimentation", "Stakeholder alignment"],
    },
    engineering: {
      tech: ["Design Thinking", "Constraints/Tradeoffs", "Safety/Standards", "Problem Solving", "Project Execution"],
      beh: ["Teamwork", "Ownership", "Communication", "Attention to detail"],
    },
    "business administration": {
      tech: ["Operations", "KPIs", "Process Improvement", "Planning", "Decision Making"],
      beh: ["Leadership", "Prioritization", "Communication", "Stakeholder management"],
    },
    marketing: {
      tech: ["Campaign Planning", "Audience Targeting", "Content Strategy", "Basic Analytics", "Brand Consistency"],
      beh: ["Creativity", "Communication", "Collaboration", "Learning mindset"],
    },
    "finance & accounting": {
      tech: ["Budgeting", "Reporting", "Accuracy/Controls", "Basic Analysis", "Reconciliation"],
      beh: ["Integrity", "Attention to detail", "Time management", "Communication"],
    },
    "human resources": {
      tech: ["Recruitment Basics", "Policies", "Conflict Handling", "Performance Feedback", "Confidentiality"],
      beh: ["Empathy", "Communication", "Fairness", "Confidentiality"],
    },
    "healthcare & medical": {
      tech: ["Patient Safety", "Protocols", "Documentation", "Team Coordination", "Ethics"],
      beh: ["Empathy", "Calm under pressure", "Communication", "Attention to detail"],
    },
    law: {
      tech: ["Ethics", "Compliance Basics", "Risk Thinking", "Client Communication", "Professional Responsibility"],
      beh: ["Integrity", "Confidentiality", "Attention to detail", "Professionalism"],
    },
    education: {
      tech: ["Lesson Planning", "Assessment", "Engagement", "Classroom Scenarios", "Use of Tools"],
      beh: ["Patience", "Clarity", "Empathy", "Adaptability"],
    },
    "media & communication": {
      tech: ["Storytelling", "Interviewing", "Fact-checking", "Messaging", "Crisis Basics"],
      beh: ["Communication", "Ethics", "Time management", "Adaptability"],
    },
  };

  // Fallback (shouldn't happen due to normalizer)
  return table[s] || table["computer & information technology"];
}

function buildMockPrompt({
  selectedSpecialty,
  bucketSpecialty,
  total,
  domainCount,
  psyCount,
  easy,
  med,
  hard,
}) {
  const profile = mapMockSpecialtyProfile(bucketSpecialty);
  const techCategories = profile.tech;
  const behThemes = profile.beh;

  return `
SYSTEM:
You are an expert interview coach. Create realistic mock interview questions in English for training.
This is a general mock interview based on the candidate's specialty, NOT a real job interview for a specific company or posting.

USER:
Mock Interview Context:
- Specialty (selected): ${selectedSpecialty || "N/A"}
- Specialty bucket: ${bucketSpecialty || "N/A"}

Blueprint:
- Output must be a single JSON object only.
- "questions" must contain exactly ${total} items.
- ${domainCount} domain questions.
- ${psyCount} psychometric/work-style questions.
- Difficulty must match exactly:
  - easy: 3
  - medium: 5
  - hard: 2

- Domain categories to rotate through: ${techCategories.join(", ")}
- Work-style themes to rotate through: ${behThemes.join(", ")}

Purpose:
- These questions are for mock interview practice.
- They should help the candidate practice speaking, explaining experience, and thinking through realistic situations.
- Do NOT make the questions too similar to a specific job interview or hiring assessment.
- Keep the questions broad enough for training, but still relevant to the selected specialty.

Interview style:
- Questions should sound natural, practical, and human.
- Use wording that an interviewer would realistically say.
- Include basic interview openers such as:
  - "Tell me about yourself."
  - "Why did you choose this specialty?"
  - "Walk me through a project or experience related to this field."
- Avoid overly formal HR language.
- Avoid generic AI-style questions that sound fake or repetitive.

Question mix:
- Include a balanced mix of:
  - introductory questions,
  - experience-based questions,
  - practical domain questions,
  - light situational questions,
  - and STAR-style behavioral questions.
- Use STAR-style where appropriate, but do NOT make every question a long scenario.
- Some questions should be simple and common because this is a mock interview.
- Avoid making all questions multi-part.

Domain question rules:
- Domain questions should be broad and specialty-focused, not tied to a specific company or job posting.
- Avoid textbook definition questions.
- Prefer questions about:
  - previous projects,
  - decision making,
  - problem solving,
  - tools or methods,
  - common challenges in the field,
  - and how the candidate would explain their thinking.
- Not every domain question needs a scenario.

Psychometric question rules:
- Use the Big Five personality traits:
  - Openness
  - Conscientiousness
  - Extraversion
  - Agreeableness
  - Emotional Stability
- Each psychometric question should implicitly assess ONE main trait and set "trait" accordingly.
- Psychometric questions should feel like real interview questions, not personality test questions.
- Include some STAR-style behavioral questions, but keep them natural.

Avoid:
- Do not ask questions that are too specific to a real job posting.
- Do not ask overly long scenario questions.
- Do not repeat the same idea in different wording.
- Avoid weak questions like:
  - "How do you handle challenges?"
  - "What are your strengths and weaknesses?"
  - "Tell me about a time you worked successfully in a team."

Better examples:
- "Tell me about yourself and what got you interested in this field."
- "Walk me through a project or task you worked on related to this specialty."
- "What part of this field do you feel most confident in?"
- "Tell me about a time you had to learn something quickly for a project or task."
- "If you faced a problem you did not know how to solve, how would you approach it?"

Output:
Return ONLY a JSON object with an array named "questions".

Each item must be:
{
  "text": "...",
  "type": "domain|psychometric",
  "category": "e.g., Data Cleaning, KPIs, Integrity, Communication",
  "difficulty": "easy|medium|hard",
  "trait": "Openness|Conscientiousness|Extraversion|Agreeableness|Emotional Stability|null"
}

- For domain questions, set "trait" to null.
- For psychometric questions, set "trait" to exactly one of the Big Five traits.
`.trim();
}

function tryParseQuestions(raw) {
  const deFence = String(raw || "").replace(/```json|```/g, "");
  const first = deFence.indexOf("{");
  const last = deFence.lastIndexOf("}");
  if (first === -1 || last === -1 || last <= first) {
    throw new Error("No JSON object found.");
  }
  const parsed = JSON.parse(deFence.slice(first, last + 1));
  const arr = Array.isArray(parsed) ? parsed : parsed.questions;
  if (!Array.isArray(arr)) throw new Error("No 'questions' array.");
  return arr;
}

function sanitize(items) {
  const okType = new Set(["domain", "psychometric"]);
  const okDiff = new Set(["easy", "medium", "hard"]);
  const okTraits = new Set([
    "Openness",
    "Conscientiousness",
    "Extraversion",
    "Agreeableness",
    "Emotional Stability",
    "null",
    "N/A",
    "",
  ]);

  const seen = new Set();
  const out = [];

  for (const q of items || []) {
    const text = String(q.text || "").trim();
    if (!text) continue;

    const key = text.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);

    let type = String(q.type || "").toLowerCase();
    if (!okType.has(type)) type = "domain";

    let difficulty = String(q.difficulty || "").toLowerCase();
    if (!okDiff.has(difficulty)) difficulty = "medium";

    const category =
      String(q.category || "").trim() || (type === "domain" ? "General" : "Psychometric");

    let trait = q.trait;
    if (type === "domain") {
      trait = null;
    } else {
      const t = String(trait || "").trim();
      if (!okTraits.has(t)) trait = null;
      else if (t === "null" || t === "N/A" || t === "") trait = null;
      else trait = t;
    }

    out.push({ text, type, category, difficulty, trait });
  }

  return out;
}

function topUpToExactCount({ questions, bucketSpecialty, total, domainTarget, psyTarget }) {
  const profile = mapMockSpecialtyProfile(bucketSpecialty);
  const techCats = profile.tech || ["Core Skills"];
  const behCats = profile.beh || ["Work Style"];

  const diffCycle = ["easy", "medium", "medium", "hard"];
  const traitCycle = [
    "Conscientiousness",
    "Openness",
    "Agreeableness",
    "Emotional Stability",
    "Extraversion",
  ];

  let domainCount = questions.filter((q) => q.type === "domain").length;
  let psyCount = questions.filter((q) => q.type === "psychometric").length;

  const domainFallbacks = [
    "Tell me about yourself and what got you interested in this field.",
    "Walk me through a project or task you worked on related to this specialty.",
    "What part of this field do you feel most confident in?",
    "What is a common problem in this field, and how would you approach solving it?",
    "Tell me about a tool, method, or concept in this field that you have used or learned.",
  ];

  const psyFallbacks = [
    "Tell me about a time you had to learn something quickly for a project or task.",
    "How do you usually stay organized when working on multiple tasks?",
    "Tell me about a time you received feedback and how you responded to it.",
    "If you faced a problem you did not know how to solve, how would you approach it?",
    "Tell me about a time you had to stay calm under pressure.",
  ];

  while (questions.length < total) {
    const idx = questions.length;
    const difficulty = diffCycle[idx % diffCycle.length];

    const needDomain = domainCount < domainTarget;
    const type = needDomain ? "domain" : "psychometric";

    if (type === "domain") {
      const cat = techCats[domainCount % techCats.length];
      questions.push({
        text: domainFallbacks[domainCount % domainFallbacks.length],
        type: "domain",
        category: cat,
        difficulty,
        trait: null,
      });
      domainCount += 1;
    } else {
      const cat = behCats[psyCount % behCats.length];
      const trait = traitCycle[psyCount % traitCycle.length];

      questions.push({
        text: psyFallbacks[psyCount % psyFallbacks.length],
        type: "psychometric",
        category: cat,
        difficulty,
        trait,
      });
      psyCount += 1;
    }
  }

  return questions.slice(0, total);
}

/* ===================== Cloud Function ===================== */

export const generateMockInterviewQuestions = v2.https.onRequest(
  { region: "us-central1", cors: true },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).send("Method not allowed.");
      }

      const OPENAI_KEY = getOpenAIKey();
      if (!OPENAI_KEY) {
        return res.status(500).send("Missing OpenAI key.");
      }

      const { specialty, difficulty } = req.body || {};
      if (!specialty) {
        return res.status(400).send("Missing field: specialty.");
      }

      const selectedSpecialty = String(specialty || "").trim();
      const bucketSpecialty = normalizeSpecialtyToBucket(selectedSpecialty);

      const total = 10;
      const domainTarget = 5;
      const psyTarget = 5;

      const easy =
        difficulty && typeof difficulty.easy === "number" ? difficulty.easy : 0.35;
      const med =
        difficulty && typeof difficulty.medium === "number" ? difficulty.medium : 0.45;
      const hard =
        difficulty && typeof difficulty.hard === "number" ? difficulty.hard : 0.2;

      const prompt = buildMockPrompt({
        selectedSpecialty,
        bucketSpecialty,
        total,
        domainCount: domainTarget,
        psyCount: psyTarget,
        easy,
        med,
        hard,
      });

      const resp = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${OPENAI_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          temperature: 0.7,
          messages: [
            { role: "system", content: "You output strict JSON only." },
            { role: "user", content: prompt },
          ],
        }),
      });

      if (!resp.ok) {
        const errBody = await resp.text();
        return res.status(500).send(`OpenAI error: ${resp.status} ${errBody}`);
      }

      const json = await resp.json();
      const content = json?.choices?.[0]?.message?.content || "";

      const parsed = tryParseQuestions(content);
      let cleaned = sanitize(parsed);

      if (cleaned.length > total) cleaned = cleaned.slice(0, total);

      if (cleaned.length < total) {
        cleaned = topUpToExactCount({
          questions: cleaned,
          bucketSpecialty,
          total,
          domainTarget,
          psyTarget,
        });
      }

      // ✅ Keep response compatible with Flutter: still has "questions"
      return res.status(200).json({
        specialty: selectedSpecialty,
        bucket: bucketSpecialty,
        questions: cleaned,
      });
    } catch (e) {
      console.error(e);
      return res.status(500).send((e && e.message) || "Internal error");
    }
  }
);
