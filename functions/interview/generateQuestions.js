import * as v2 from "firebase-functions/v2";

// ===== Helpers =====
function getOpenAIKey() {
  return process.env.OPENAI_API_KEY || "";
}

function mapSpecialtyToCategories(specialtyRaw = "") {
  const s = (specialtyRaw || "").toLowerCase();

  const maps = [
    { key: "frontend", cats: ["React", "State Mgmt", "HTTP/REST", "Accessibility", "Performance"] },
    { key: "backend", cats: ["API Design", "Databases", "Scalability", "Auth/Security"] },
    { key: "full stack", cats: ["Frontend Basics", "API Design", "Databases", "DevOps Basics"] },
    { key: "mobile", cats: ["Flutter/Dart", "State Mgmt", "Offline/Sync", "CI/CD", "Store Guidelines"] },
    { key: "data science", cats: ["EDA", "Modeling", "Evaluation", "Deployment"] },
    { key: "machine", cats: ["ML Basics", "Model Training", "Evaluation", "MLOps"] },
    { key: "ai", cats: ["LLMs", "Prompt Engineering", "Evaluation", "Ethics"] },
    { key: "cyber", cats: ["Network Security", "AppSec/OWASP", "Threat Modeling", "Incident Response"] },
    { key: "devops", cats: ["CI/CD", "Containers", "Monitoring", "Infra as Code"] },
    { key: "cloud", cats: ["IAM", "Networking", "Cost/Scaling", "Managed Services"] },
    { key: "ui/ux", cats: ["User Research", "Wireframes", "Usability", "Accessibility"] },
    { key: "graphic", cats: ["Branding", "Layout", "Color/Typography", "Assets/Export"] },
    { key: "product", cats: ["Roadmapping", "Prioritization", "Discovery", "Metrics"] },
    { key: "project", cats: ["Planning", "Risk", "Cost/Schedule", "Comms"] },
    { key: "qa", cats: ["Test Design", "Automation", "CI Integration", "Bug Triage"] },
    { key: "network", cats: ["Routing/Switching", "TCP/IP", "Security", "Troubleshooting"] },
    { key: "database", cats: ["Modeling", "SQL/NoSQL", "Perf/Indexing", "Backup/HA"] },
    { key: "analysis", cats: ["Requirements", "Modeling", "Processes", "KPIs"] },
    { key: "marketing", cats: ["SEO", "Paid Ads", "Content", "Analytics"] },
    { key: "content", cats: ["Research", "Structure", "Editing", "Distribution"] },
  ];

  for (const m of maps) if (s.includes(m.key)) return m.cats;
  return ["General Knowledge", "Problem Solving", "Communication"];
}

function buildPrompt({
  title,
  position,
  specialty,           // <-- وحّدنا الاسم هنا
  requirements,
  description = "",
  techPct = 0.7,
  behPct = 0.3,
  easy = 0.3,
  med = 0.5,
  hard = 0.2,
}) {
  const categories = mapSpecialtyToCategories(specialty);
  const desc = String(description || "").trim().slice(0, 2000);

  return `
SYSTEM:
You are an expert technical interviewer. Generate high-quality interview questions tailored to the job.

USER:
Job Context:
- Title: ${title}
- Position/Seniority: ${position || "N/A"}
- Specialty: ${specialty || "N/A"}
- Must-have requirements: ${(requirements || []).join(", ") || "N/A"}
- Job Description (excerpt): ${desc || "N/A"}

Blueprint:
- Mix: ${Math.round(techPct * 100)}% technical / ${Math.round(behPct * 100)}% behavioral
- Difficulty distribution: easy ${Math.round(easy * 100)}%, medium ${Math.round(med * 100)}%, hard ${Math.round(hard * 100)}%
- Technical categories to cover: ${categories.join(", ")}
- Behavioral competencies: communication, teamwork, problem solving, ownership

Grounding rules:
- Ground technical questions in the description and requirements when possible.
- Prefer the same stack/keywords that appear in requirements/description.
- Keep questions concise; avoid multi-part compound questions.

Output:
Return ONLY a JSON object with an array named "questions".
Each item must be:
{
  "text": "...",
  "type": "technical|behavioral",
  "category": "e.g., React or Soft Skills",
  "difficulty": "easy|medium|hard"
}
`.trim();
}

function tryParseQuestions(raw) {
  const deFence = raw.replace(/```json|```/g, "");
  const first = deFence.indexOf("{");
  const last = deFence.lastIndexOf("}");
  if (first === -1 || last === -1 || last <= first) throw new Error("No JSON object found.");
  const parsed = JSON.parse(deFence.slice(first, last + 1));
  const arr = Array.isArray(parsed) ? parsed : parsed.questions;
  if (!Array.isArray(arr)) throw new Error("No 'questions' array.");
  return arr;
}

function sanitize(items) {
  const okType = new Set(["technical", "behavioral"]);
  const okDiff = new Set(["easy", "medium", "hard"]);
  const seen = new Set();
  const out = [];

  for (const q of items) {
    const text = String(q.text || "").trim();
    if (!text) continue;
    const key = text.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);

    const type = okType.has(String(q.type || "").toLowerCase()) ? String(q.type).toLowerCase() : "technical";
    const difficulty = okDiff.has(String(q.difficulty || "").toLowerCase()) ? String(q.difficulty).toLowerCase() : "medium";
    const category = String(q.category || "").trim() || (type === "technical" ? "General" : "Soft Skills");

    out.push({ text, type, category, difficulty });
  }
  return out;
}

// ===== Cloud Function (ESM export) =====
export const generateInterviewQuestions = v2.https.onRequest(
  { region: "us-central1", cors: true },   
  async (req, res) => {
    try {
      if (req.method !== "POST") return res.status(405).send("Method not allowed.");

      const OPENAI_KEY = getOpenAIKey();
      if (!OPENAI_KEY) return res.status(500).send("Missing OpenAI key.");

      const {
        jobId,
        title,
        position,
        specialty,        
        requirements = [],
        mix,
        difficulty,
        description,
      } = req.body || {};

      if (!jobId || !title) return res.status(400).send("Missing fields (jobId/title).");

      const techPct = mix?.technical ?? 0.7;
      const behPct = mix?.behavioral ?? 0.3;
      const easy = difficulty?.easy ?? 0.3;
      const med  = difficulty?.medium ?? 0.5;
      const hard = difficulty?.hard ?? 0.2;

      const prompt = buildPrompt({
        title,
        position,
        specialty,       // <-- تمرير صحيح
        requirements,
        description,
        techPct,
        behPct,
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
            { role: "system", content: "You are an expert interviewer that outputs strict JSON." },
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
      const cleaned = sanitize(parsed);

      const final = cleaned.slice(0, 12); // عددي النهائي لو تبين

      return res.status(200).json({ questions: final });
    } catch (e) {
      console.error(e);
      return res.status(500).send(e?.message || "Internal error");
    }
  });
