import * as v2 from "firebase-functions/v2";

/* ===================== Helpers ===================== */

function getOpenAIKey() {
  return process.env.OPENAI_API_KEY || "";
}

/**
 * Mock specialties profile (ONLY your mock list).
 * No "other" and no additional fields.
 */
function mapMockSpecialtyProfile(specialtyRaw = "") {
  const s = (specialtyRaw || "").toLowerCase().trim();

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

  // No "other": if not matched, throw to force correct specialty usage.
  if (!table[s]) {
    throw new Error(`Unsupported specialty: ${specialtyRaw}`);
  }
  return table[s];
}

function buildMockPrompt({ specialty, total, domainCount, psyCount, easy, med, hard }) {
  const profile = mapMockSpecialtyProfile(specialty);
  const techCategories = profile.tech;
  const behThemes = profile.beh;

  return `
SYSTEM:
You are an expert interview coach. Create mock interview questions in English for training.
This is NOT tied to a specific company or job posting.

USER:
Mock Interview Context:
- Specialty: ${specialty || "N/A"}

Blueprint:
- Total questions: exactly ${total} (no more, no fewer).
  - ${domainCount} domain questions (broad, specialty-focused, NOT job-specific).
  - ${psyCount} psychometric/work-style questions.
- Difficulty distribution overall:
  - easy ${Math.round(easy * 100)}%, medium ${Math.round(med * 100)}%, hard ${Math.round(hard * 100)}%.
- Domain categories to rotate through: ${techCategories.join(", ")}
- Work-style themes to rotate through: ${behThemes.join(", ")}

Psychometric model:
- Use the Big Five personality traits:
  - Openness
  - Conscientiousness
  - Extraversion
  - Agreeableness
  - Emotional Stability

Guidelines:
- Questions must be practical and answerable by speaking.
- Avoid generic filler like "Tell me about yourself".
- Domain questions should focus on fundamentals and reasoning, not specific tools unless universally common.
- Psychometric questions must target ONE main Big Five trait and set "trait" accordingly.

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

function topUpToExactCount({ questions, specialty, total, domainTarget, psyTarget }) {
  const profile = mapMockSpecialtyProfile(specialty);
  const techCats = profile.tech || ["Core Skills"];
  const behCats = profile.beh || ["Work Style"];

  const diffCycle = ["easy", "medium", "hard"];
  const traitCycle = [
    "Conscientiousness",
    "Extraversion",
    "Agreeableness",
    "Openness",
    "Emotional Stability",
  ];

  let domainCount = questions.filter((q) => q.type === "domain").length;
  let psyCount = questions.filter((q) => q.type === "psychometric").length;

  while (questions.length < total) {
    const idx = questions.length;
    const difficulty = diffCycle[idx % diffCycle.length];

    const needDomain = domainCount < domainTarget;
    const type = needDomain ? "domain" : "psychometric";

    if (type === "domain") {
      const cat = techCats[idx % techCats.length];
      questions.push({
        text: `Explain a key idea in ${cat} and how you would apply it in a real situation.`,
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
        text: `Describe a situation that demonstrates your ${trait.toLowerCase()}. What did you do and what was the outcome?`,
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

      const { specialty, count, difficulty } = req.body || {};
      if (!specialty) {
        return res.status(400).send("Missing field: specialty.");
      }

      const total = typeof count === "number" ? count : 8;
      const domainTarget = Math.floor(total / 2);
      const psyTarget = total - domainTarget;

      const easy =
        difficulty && typeof difficulty.easy === "number" ? difficulty.easy : 0.35;
      const med =
        difficulty && typeof difficulty.medium === "number" ? difficulty.medium : 0.45;
      const hard =
        difficulty && typeof difficulty.hard === "number" ? difficulty.hard : 0.2;

      const prompt = buildMockPrompt({
        specialty,
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
          specialty,
          total,
          domainTarget,
          psyTarget,
        });
      }

      return res.status(200).json({ questions: cleaned });
    } catch (e) {
      console.error(e);
      return res.status(500).send((e && e.message) || "Internal error");
    }
  }
);
