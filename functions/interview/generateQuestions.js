import * as v2 from "firebase-functions/v2";

/* ===================== Helpers ===================== */

function getOpenAIKey() {
  return process.env.OPENAI_API_KEY || "";
}

/**
 * Returns a profile with:
 *  - tech: technical categories to guide technical questions
 *  - beh: psychometric / work-style dimensions for this specialty
 *
 * This is aligned with your _specialtyOptions list.
 */
function mapSpecialtyProfile(specialtyRaw = "") {
  const s = (specialtyRaw || "").toLowerCase().trim();

  const profileTable = {
    // --- Technology & IT ---
    "frontend development": {
      tech: ["JavaScript/Frameworks", "Component Design", "State Management", "HTTP/REST", "Accessibility"],
      beh: ["Collaboration", "Attention to detail", "User empathy", "Ownership"],
    },
    "backend development": {
      tech: ["API Design", "Databases", "Performance/Scalability", "Auth/Security", "Architecture"],
      beh: ["Problem solving", "Ownership", "Communication", "Cross-functional collaboration"],
    },
    "full-stack development": {
      tech: ["Frontend Basics", "API Design", "Databases", "System Design", "DevOps Basics"],
      beh: ["Context switching", "Collaboration", "Prioritization", "Ownership"],
    },
    "mobile development": {
      tech: ["Flutter/Native", "State Management", "Offline/Sync", "API Integration", "Store Guidelines/Release"],
      beh: ["Attention to detail", "User-centric thinking", "Collaboration", "Ownership"],
    },
    "software engineering": {
      tech: ["Software Design", "OOP/Patterns", "Testing", "Code Quality", "System Design"],
      beh: ["Ownership", "Collaboration", "Continuous improvement", "Communication"],
    },
    "cybersecurity": {
      tech: ["Threat Modeling", "Vulnerabilities/OWASP", "Network Security", "Monitoring/Detection", "Incident Response"],
      beh: ["Risk awareness", "Attention to detail", "Handling sensitive information", "Calm under pressure"],
    },
    "data science": {
      tech: ["EDA", "Modeling", "Feature Engineering", "Evaluation/Validation", "Deployment/Production"],
      beh: ["Storytelling with data", "Business understanding", "Experimentation mindset", "Stakeholder communication"],
    },
    "data engineering": {
      tech: ["ETL/ELT", "Data Modeling", "Data Pipelines", "Batch/Streaming", "Data Quality"],
      beh: ["Ownership", "Working with stakeholders", "Attention to data quality", "Documentation"],
    },
    "data analysis": {
      tech: ["Data Cleaning", "Exploratory Analysis", "Dashboards/Reporting", "SQL/Queries", "Basic Statistics"],
      beh: ["Storytelling", "Attention to detail", "Stakeholder communication", "Time management"],
    },
    "ai / machine learning": {
      tech: ["ML Basics", "Model Training", "Evaluation", "MLOps/Deployment", "LLMs/Prompting"],
      beh: ["Experimentation", "Ethical awareness", "Communication", "Collaboration with domain experts"],
    },
    "cloud / devops": {
      tech: ["CI/CD", "Containers", "Cloud Networking", "Infrastructure as Code", "Monitoring/Observability"],
      beh: ["Reliability mindset", "Ownership", "Incident handling", "Collaboration with dev teams"],
    },
    "it support / system administration": {
      tech: ["OS/Basics", "Networking Fundamentals", "User Management", "Monitoring", "Troubleshooting"],
      beh: ["Customer focus", "Patience", "Communication", "Time management"],
    },
    "product management": {
      tech: ["Roadmapping", "Prioritization Frameworks", "Discovery/Research", "Metrics/Experimentation"],
      beh: ["Stakeholder management", "Strategic thinking", "Communication", "Decision making"],
    },
    "ui/ux design": {
      tech: ["User Research", "Information Architecture", "Wireframes/Prototypes", "Usability/Testing", "Accessibility"],
      beh: ["User empathy", "Collaboration", "Feedback handling", "Communication"],
    },
    "qa / testing": {
      tech: ["Test Design", "Automation", "Regression/Smoke Testing", "CI Integration", "Bug Reporting"],
      beh: ["Attention to detail", "Communication", "Conflict management", "Persistence"],
    },

    // --- Engineering (generic) ---
    "engineering": {
      tech: ["Core Engineering Principles", "Problem Solving", "Design/Modeling", "Safety/Standards", "Project Execution"],
      beh: ["Attention to detail", "Teamwork", "Communication", "Ownership"],
    },

    // --- Business & Operations ---
    "business / operations": {
      tech: ["Process Analysis", "Operations KPIs", "Optimization", "Reporting"],
      beh: ["Stakeholder management", "Problem solving", "Prioritization", "Communication"],
    },
    "project management": {
      tech: ["Planning/Scheduling", "Scope/Requirements", "Risk Management", "Cost/Time Tracking", "Reporting"],
      beh: ["Leadership", "Stakeholder communication", "Conflict resolution", "Decision making"],
    },
    "supply chain / logistics": {
      tech: ["Demand Planning", "Inventory Management", "Logistics/Distribution", "Vendor Management"],
      beh: ["Negotiation", "Coordination", "Problem solving", "Time management"],
    },
    "procurement": {
      tech: ["Supplier Evaluation", "Contract Basics", "Cost Analysis", "Purchase Process"],
      beh: ["Negotiation", "Stakeholder management", "Ethics/Integrity", "Attention to detail"],
    },
    "quality management": {
      tech: ["Quality Standards", "Process Audits", "Root Cause Analysis", "Continuous Improvement"],
      beh: ["Attention to detail", "Communication", "Problem solving", "Change management"],
    },
    "strategy / consulting": {
      tech: ["Market/Competitor Analysis", "Problem Structuring", "Hypothesis/Testing", "Financial/Impact Modeling"],
      beh: ["Structured thinking", "Storytelling", "Client communication", "Influencing"],
    },

    // --- Sales & Marketing ---
    "sales & business development": {
      tech: ["Pipeline Management", "Lead Qualification", "CRM Usage", "Deal Closing"],
      beh: ["Negotiation", "Relationship building", "Resilience", "Handling objections"],
    },
    "digital marketing": {
      tech: ["SEO/SEM", "Paid Campaigns", "Social Media", "Analytics/Attribution"],
      beh: ["Creativity", "Experimentation", "Data-driven thinking", "Collaboration"],
    },
    "content creation / copywriting": {
      tech: ["Audience Understanding", "Content Structure", "Tone of Voice", "Editing/Proofreading"],
      beh: ["Creativity", "Attention to detail", "Time management", "Collaboration"],
    },
    "branding / creative": {
      tech: ["Brand Positioning", "Visual Identity", "Campaign Concepts", "Consistency"],
      beh: ["Creativity", "Storytelling", "Collaboration", "Feedback handling"],
    },
    "advertising / pr": {
      tech: ["Campaign Planning", "Channel Selection", "PR Messaging", "Crisis Comms Basics"],
      beh: ["Communication", "Relationship building", "Crisis handling", "Storytelling"],
    },

    // --- Finance & Legal ---
    "accounting / auditing": {
      tech: ["Financial Statements", "Accounting Standards", "Reconciliations", "Controls"],
      beh: ["Attention to detail", "Integrity", "Time management", "Communication"],
    },
    "finance / investment": {
      tech: ["Financial Analysis", "Valuation Basics", "Risk/Return", "Forecasting/Budgeting"],
      beh: ["Analytical thinking", "Communication", "Decision making", "Stakeholder alignment"],
    },
    "legal / compliance": {
      tech: ["Policies/Procedures", "Regulation Basics", "Contract Review", "Risk Assessment"],
      beh: ["Attention to detail", "Confidentiality", "Communication", "Integrity"],
    },

    // --- HR ---
    "human resources": {
      tech: ["Recruitment/Screening", "Onboarding", "HR Policies", "Performance/Feedback"],
      beh: ["Empathy", "Conflict resolution", "Confidentiality", "Communication"],
    },

    // --- Healthcare ---
    "healthcare / medical": {
      tech: ["Clinical Basics (role-specific)", "Patient Safety", "Documentation", "Protocols/Guidelines"],
      beh: ["Empathy", "Communication under pressure", "Teamwork", "Attention to detail"],
    },

    // --- Education ---
    "teaching / training": {
      tech: ["Lesson Planning", "Assessment", "Instructional Methods", "Use of Tools/Platforms"],
      beh: ["Clarity", "Patience", "Engagement", "Feedback"],
    },

    // --- Media & Creative ---
    "media / journalism": {
      tech: ["Research/Fact-checking", "Story Structure", "Interviewing", "Editing"],
      beh: ["Ethics", "Communication", "Time management", "Attention to detail"],
    },
    "graphic / motion design": {
      tech: ["Composition/Layout", "Typography/Color", "Tools (e.g., Adobe)", "Animation Basics"],
      beh: ["Creativity", "Collaboration", "Attention to detail", "Feedback handling"],
    },
    "photography / videography": {
      tech: ["Shooting Techniques", "Lighting", "Editing/Post-production", "Storytelling"],
      beh: ["Creativity", "Working with clients", "Time management", "Adaptability"],
    },

    // --- Customer Service ---
    "customer support / service": {
      tech: ["Ticketing/Systems", "Product Knowledge", "Escalation Basics", "Documentation"],
      beh: ["Empathy", "Patience", "Communication", "De-escalation"],
    },

    // --- Hospitality ---
    "hospitality & tourism": {
      tech: ["Guest Experience", "Operations Basics", "Service Standards", "Problem Handling"],
      beh: ["Customer focus", "Communication", "Teamwork", "Adaptability"],
    },

    // --- Other ---
    other: {
      tech: ["Domain Knowledge", "Core Tools/Practices", "Quality/Best Practices", "Collaboration"],
      beh: ["Communication", "Teamwork", "Problem solving", "Ownership"],
    },
  };

  if (profileTable[s]) {
    return profileTable[s];
  }

  // Simple keyword fallback
  if (s.includes("frontend")) return profileTable["frontend development"];
  if (s.includes("backend")) return profileTable["backend development"];
  if (s.includes("full") && s.includes("stack")) return profileTable["full-stack development"];
  if (s.includes("mobile")) return profileTable["mobile development"];
  if (s.includes("data") && s.includes("science")) return profileTable["data science"];
  if (s.includes("data") && s.includes("engineer")) return profileTable["data engineering"];
  if (s.includes("data") && (s.includes("analyst") || s.includes("analysis"))) return profileTable["data analysis"];
  if (s.includes("ai") || s.includes("machine learning")) return profileTable["ai / machine learning"];
  if (s.includes("cloud") || s.includes("devops")) return profileTable["cloud / devops"];
  if (s.includes("product")) return profileTable["product management"];
  if (s.includes("project")) return profileTable["project management"];
  if (s.includes("marketing")) return profileTable["digital marketing"];
  if (s.includes("sales") || s.includes("business development")) return profileTable["sales & business development"];
  if (s.includes("hr") || s.includes("human resources")) return profileTable["human resources"];
  if (s.includes("finance")) return profileTable["finance / investment"];
  if (s.includes("account")) return profileTable["accounting / auditing"];
  if (s.includes("legal") || s.includes("compliance")) return profileTable["legal / compliance"];

  return profileTable["other"];
}

// Backward-compatible helper (لو تحتاجينه لمكان ثاني)
function mapSpecialtyToCategories(specialtyRaw = "") {
  return mapSpecialtyProfile(specialtyRaw).tech;
}

/**
 * Build the prompt for OpenAI. English only.
 * Uses: technical + psychometric (Big Five).
 */
function buildPrompt({
  title,
  position,
  specialty,
  requirements,
  description = "",
  techPct = 0.7,
  behPct = 0.3,
  easy = 0.3,
  med = 0.5,
  hard = 0.2,
}) {
  const profile = mapSpecialtyProfile(specialty);
  const techCategories = profile.tech;
  const psychometricDimensions = profile.beh;

  const desc = String(description || "").trim().slice(0, 2000);

  const TARGET_COUNT = 10;
  const targetTechCount = 5;
  const targetPsyCount = 5;

  return `
SYSTEM:
You are an expert interviewer. Generate high-quality interview questions in English tailored to the job,
split into technical and psychometric parts.

USER:
Job Context:
- Title: ${title}
- Position/Seniority: ${position || "N/A"}
- Specialty: ${specialty || "N/A"}
- Must-have requirements: ${(requirements || []).join(", ") || "N/A"}
- Job Description (excerpt): ${desc || "N/A"}

Blueprint:
- Total questions: exactly ${TARGET_COUNT} (no more, no fewer).
  - 5 technical questions.
  - 5 psychometric (personality/work-style) questions.
- Difficulty distribution (overall): easy ${Math.round(easy * 100)}%, medium ${Math.round(
    med * 100
  )}%, hard ${Math.round(hard * 100)}%.
- Technical categories to cover: ${techCategories.join(", ")}
- Psychometric dimensions / work-style themes to cover: ${psychometricDimensions.join(", ")}

Psychometric model:
- Use the Big Five personality model for psychometric questions:
  - Openness
  - Conscientiousness
  - Extraversion
  - Agreeableness
  - Emotional Stability (opposite of Neuroticism)

Guidelines:
- Technical questions:
  - Ground them in the job description, requirements, and mentioned technologies/tools.
  - Prefer technologies, tools, and frameworks that appear in the job description or requirements.
  - Keep each question concise and focused on a single idea.
- Psychometric questions:
  - Focus on personality traits and work style using the Big Five model.
  - Each psychometric question should target ONE main trait and set the "trait" field accordingly.
  - Use scenario-based questions (STAR-style) asking about specific past experiences.
  - Avoid generic questions like "Tell me about yourself" or "What are your strengths/weaknesses?".

Output:
Return ONLY a JSON object with an array named "questions".
Each item must be:
{
  "text": "...",
  "type": "technical|psychometric",
  "category": "e.g., React, Data Modeling, Stakeholder Management, Resilience, Empathy",
  "difficulty": "easy|medium|hard",
  "trait": "Openness|Conscientiousness|Extraversion|Agreeableness|Emotional Stability|null"
}
- For technical questions, set "trait" to null.
- For psychometric questions, set "trait" to exactly one of the Big Five traits.
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
  const okType = new Set(["technical", "psychometric"]);
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

  for (const q of items) {
    const text = String(q.text || "").trim();
    if (!text) continue;
    const key = text.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);

    let type = String(q.type || "").toLowerCase();
    if (!okType.has(type)) type = "technical";

    let difficulty = String(q.difficulty || "").toLowerCase();
    if (!okDiff.has(difficulty)) difficulty = "medium";

    const category =
      String(q.category || "").trim() ||
      (type === "technical" ? "General" : "Psychometric");

    let trait = q.trait;
    if (type === "technical") {
      trait = null;
    } else {
      const t = String(trait || "").trim();
      if (!okTraits.has(t)) {
        trait = null;
      } else if (t === "null" || t === "N/A" || t === "") {
        trait = null;
      } else {
        trait = t;
      }
    }

    out.push({ text, type, category, difficulty, trait });
  }
  return out;
}

/* ===================== Cloud Function ===================== */

export const generateInterviewQuestions = v2.https.onRequest(
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

      if (!jobId || !title) {
        return res.status(400).send("Missing fields (jobId/title).");
      }

      const techPct =
        mix && typeof mix.technical === "number" ? mix.technical : 0.7;
      const behPct =
        mix && typeof mix.psychometric === "number" ? mix.psychometric : 0.3;
      const easy =
        difficulty && typeof difficulty.easy === "number" ? difficulty.easy : 0.3;
      const med =
        difficulty && typeof difficulty.medium === "number" ? difficulty.medium : 0.5;
      const hard =
        difficulty && typeof difficulty.hard === "number" ? difficulty.hard : 0.2;

      const prompt = buildPrompt({
        title,
        position,
        specialty,
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
      const content =
        json &&
        json.choices &&
        json.choices[0] &&
        json.choices[0].message &&
        json.choices[0].message.content
          ? json.choices[0].message.content
          : "";

      const parsed = tryParseQuestions(content);
      let cleaned = sanitize(parsed);

      const TARGET_COUNT = 10;
      const profile = mapSpecialtyProfile(specialty || "");
      const techCats = profile.tech;
      const psyCats = profile.beh;

      let techCount = cleaned.filter((q) => q.type === "technical").length;
      let psyCount = cleaned.filter((q) => q.type === "psychometric").length;

      const targetTechCount = 5;
      const targetPsyCount = 5;

      if (cleaned.length > TARGET_COUNT) {
        cleaned = cleaned.slice(0, TARGET_COUNT);
      } else if (cleaned.length < TARGET_COUNT) {
        const diffCycle = ["easy", "medium", "hard"];
        const traitCycle = [
          "Conscientiousness",
          "Extraversion",
          "Agreeableness",
          "Openness",
          "Emotional Stability",
        ];

        while (cleaned.length < TARGET_COUNT) {
          const idx = cleaned.length;

          // Decide type based on remaining targets
          let type;
          if (techCount < targetTechCount && psyCount < targetPsyCount) {
            type = techCount <= psyCount ? "technical" : "psychometric";
          } else if (techCount < targetTechCount) {
            type = "technical";
          } else if (psyCount < targetPsyCount) {
            type = "psychometric";
          } else {
            type = techPct >= behPct ? "technical" : "psychometric";
          }

          const d = diffCycle[idx % diffCycle.length];

          let catPool = type === "technical" ? techCats : psyCats;
          if (!catPool || catPool.length === 0) {
            catPool =
              type === "technical"
                ? ["Core Skills"]
                : ["Personality/Work Style"];
          }
          const cat = catPool[idx % catPool.length];

          let text;
          let trait = null;

          if (type === "technical") {
            text = `Can you explain a key concept in ${cat} and describe how you applied it in a real project or task?`;
            techCount += 1;
          } else {
            const tIndex = psyCount % traitCycle.length;
            trait = traitCycle[tIndex];

            text = `Describe a situation that reveals your ${trait.toLowerCase()} in a work or academic context. What happened, how did you respond, and what does it say about your working style?`;
            psyCount += 1;
          }

          cleaned.push({
            text,
            type,
            category: cat,
            difficulty: d,
            trait,
          });
        }
      }

      const final = cleaned;

      return res.status(200).json({ questions: final });
    } catch (e) {
      console.error(e);
      return res.status(500).send((e && e.message) || "Internal error");
    }
  }
);
