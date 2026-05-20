import { Client } from "@gradio/client";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import FormData from "form-data";
import fetch from "node-fetch";
import PDFDocument from "pdfkit";

/**
 * generateJobInterviewReport
 *
 * Pipeline:
 *  1. Read Application + Job data
 *  2. Transcribe audio (Whisper)
 *  3. Voice Tone Analysis (SER model on HuggingFace)
 *  4. GPT-4 analysis → 4 scores + requirements checklist
 *  5. Calculate VoiceToneScore from SER results
 *  6. Calculate weighted final score (Story 36)
 *  7. Generate PDF report
 *  8. Upload PDF to Storage
 *  9. Save everything to Firestore
 */
export const generateJobInterviewReport = onCall(
  {
    secrets: ["OPENAI_API_KEY"],
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (request) => {
    try {
      const { applicationsID } = request.data;

      if (!applicationsID) {
        throw new HttpsError(
          "invalid-argument",
          "applicationsID is required"
        );
      }

      console.log(`[jobReport] Starting for application: ${applicationsID}`);

      const db = getFirestore();

      // ── 1. Read Application doc ──────────────────────────────
      const appRef = db.collection("Applications").doc(applicationsID);
      const appSnap = await appRef.get();

      if (!appSnap.exists) {
        throw new HttpsError("not-found", "Application not found");
      }

      const appData = appSnap.data();
      const audioUrls = appData.AnswersRecordsURL || [];
      const jobID = appData.JobID || "";
      const cvUrl = appData.ApplicationCVURL || "";
      const applicantUserId = appData.UserID || "";

      console.log(`[jobReport] Found ${audioUrls.length} audio files, JobID: ${jobID}`);

      if (audioUrls.length === 0) {
        throw new HttpsError(
          "failed-precondition",
          "No audio recordings found for this application"
        );
      }

      // ── 2. Read Job doc → questions + job context ────────────
      let questions = [];
      let questionObjects = [];
      let jobTitle = appData.JobTitle || "";
      let companyName = appData.CompanyName || "";
      let specialty = "";
      let requirements = [];
      let description = "";

      if (jobID) {
        const jobSnap = await db.collection("Jobs").doc(jobID).get();

        if (jobSnap.exists) {
          const jobData = jobSnap.data();

          const rawQ = jobData.Questions || [];
          questionObjects = rawQ.map((q) => {
            if (typeof q === "string") {
              return { text: q, type: "technical", category: "General" };
            }
            return {
              text: q.Text || q.text || String(q),
              type: q.type || "technical",
              category: q.category || "General",
              trait: q.trait || null,
            };
          });
          questions = questionObjects.map((q) => q.text);

          jobTitle = jobTitle || jobData.JobTitle || "Unknown Position";
          specialty = jobData.Specialty || "";
          requirements = jobData.Requirements || [];
          description = jobData.Description || "";

          if (!companyName && jobData.UserID) {
            try {
              const compSnap = await db
                .collection("Users")
                .doc(jobData.UserID)
                .get();
              if (compSnap.exists) {
                companyName = compSnap.data().CompanyName || "";
              }
            } catch (e) {
              console.warn("[jobReport] Could not fetch company name:", e);
            }
          }
        }
      }

      if (questions.length === 0) {
        questions = audioUrls.map((_, i) => `Question ${i + 1}`);
      }

      console.log(`[jobReport] Job: ${jobTitle}, Specialty: ${specialty}, ${questions.length} questions`);

      // ── 3. Transcribe audio with Whisper ─────────────────────
      const transcripts = [];
      const OPENAI_KEY = process.env.OPENAI_API_KEY;

      for (let i = 0; i < audioUrls.length; i++) {
        const audioUrl = audioUrls[i];
        if (!audioUrl || audioUrl.trim() === "") {
          console.log(`[jobReport] Skipping empty URL at index ${i}`);
          continue;
        }

        try {
          console.log(`[jobReport] Transcribing audio ${i + 1}/${audioUrls.length}`);

          const audioResponse = await fetch(audioUrl);
          if (!audioResponse.ok) {
            throw new Error(`Failed to download audio: ${audioResponse.statusText}`);
          }

          const audioBuffer = await audioResponse.buffer();
          console.log(`[jobReport] Downloaded ${audioBuffer.length} bytes`);

          if (audioBuffer.length < 100) {
            throw new Error("Audio file too small (likely corrupted)");
          }

          const formData = new FormData();
          formData.append("file", audioBuffer, {
            filename: `audio_${i}.m4a`,
            contentType: "audio/m4a",
          });
          formData.append("model", "whisper-1");

          const transcriptionResponse = await fetch(
            "https://api.openai.com/v1/audio/transcriptions",
            {
              method: "POST",
              headers: {
                Authorization: `Bearer ${OPENAI_KEY}`,
                ...formData.getHeaders(),
              },
              body: formData,
            }
          );

          if (!transcriptionResponse.ok) {
            const errorText = await transcriptionResponse.text();
            console.error(`[jobReport] Whisper error: ${errorText}`);
            throw new Error(`Whisper API error: ${transcriptionResponse.statusText}`);
          }

          const result = await transcriptionResponse.json();
          const questionText = questions[i] || `Question ${i + 1}`;
          const qObj = questionObjects[i] || { type: "technical", category: "General" };

          transcripts.push({
            question: questionText,
            answer: result.text || "[No transcription]",
            type: qObj.type,
            category: qObj.category,
            trait: qObj.trait || null,
          });

          console.log(`[jobReport] ✅ Transcribed Q${i + 1}: ${result.text.substring(0, 50)}...`);
        } catch (error) {
          console.error(`[jobReport] ❌ Transcription failed for audio ${i}:`, error);
          const qObj = questionObjects[i] || { type: "technical", category: "General" };
          transcripts.push({
            question: questions[i] || `Question ${i + 1}`,
            answer: "[Transcription failed]",
            type: qObj.type,
            category: qObj.category,
            trait: qObj.trait || null,
          });
        }
      }

      if (transcripts.length === 0) {
        throw new HttpsError("internal", "Failed to transcribe any audio files");
      }

      console.log(`[jobReport] Successfully transcribed ${transcripts.length} answers`);

      // ── 4. Filter valid transcripts ──────────────────────────
      const validTranscripts = transcripts.filter(
        (t) => t.answer !== "[Transcription failed]"
      );

      if (validTranscripts.length === 0) {
        throw new HttpsError(
          "failed-precondition",
          "All audio transcriptions failed. Please check your microphone and try again."
        );
      }

      const transcriptText = validTranscripts
        .map((t, i) => `Q${i + 1} [${t.type}]: ${t.question}\nA${i + 1}: ${t.answer}`)
        .join("\n\n");

      const failedCount = transcripts.length - validTranscripts.length;
      const transcriptionNote =
        failedCount > 0
          ? `Note: ${failedCount} answer(s) could not be transcribed and were excluded from analysis.\n\n`
          : "";

      // ── 5. Voice Tone Analysis (SER Model) ───────────────────
      console.log("[jobReport] Starting voice tone analysis via Public Client...");
      const voiceAnalysisResults = [];

      try {
        const spaceApiUrl = "https://huggingface.co/api/spaces/wsaifaleslam/jadeer-smart-assessment";
        let isAwake = false;
        let attempts = 0;

        console.log("[jobReport] Checking real-time Hugging Face Space status...");

        while (!isAwake && attempts < 10) {
          const response = await fetch(spaceApiUrl);
          if (response.ok) {
            const metadata = await response.json();
            const runtimeStatus = metadata.runtime?.stage;

            console.log(`[jobReport] Space status is currently: ${runtimeStatus}`);

            if (runtimeStatus === "RUNNING") {
              isAwake = true;
              break;
            }
          }

          attempts++;
          await fetch("https://wsaifaleslam-jadeer-smart-assessment.hf.space").catch(() => {});
          await new Promise(resolve => setTimeout(resolve, 4000));
        }

        const app = await Client.connect("wsaifaleslam/jadeer-smart-assessment");
        console.log("[jobReport] ✅ Connected to Hugging Face Space successfully.");

        for (let i = 0; i < audioUrls.length; i++) {
          const audioUrl = audioUrls[i];
          if (!audioUrl || audioUrl.trim() === "") continue;

          try {
            console.log(`[jobReport] Voice analysis for audio ${i + 1}/${audioUrls.length}`);

            const audioResponse = await fetch(audioUrl);
            if (!audioResponse.ok) throw new Error("Audio download failed");

            const arrayBuffer = await audioResponse.arrayBuffer();
            const audioBlob = new Blob([arrayBuffer], { type: "audio/wav" });

            const hfResult = await app.predict("predict_confidence", [audioBlob]);

            const resultText = hfResult.data && hfResult.data[0]
              ? String(hfResult.data[0])
              : "Analysis unavailable";

            voiceAnalysisResults.push({
              questionIndex: i,
              result: resultText,
            });

            console.log(`[jobReport] ✅ Voice analysis Q${i + 1}: ${resultText}`);
          } catch (err) {
            console.error(`[jobReport] ❌ Voice analysis failed for Q${i + 1}:`, err.message || err);
            voiceAnalysisResults.push({
              questionIndex: i,
              result: "Analysis unavailable",
            });
          }
        }
      } catch (outerErr) {
        console.error("[jobReport] ❌ Critical failure in SER Outer Block:", outerErr.message || outerErr);
        for (let i = 0; i < audioUrls.length; i++) {
          voiceAnalysisResults.push({ questionIndex: i, result: "Analysis unavailable" });
        }
      }

      // ── 5b. Calculate VoiceToneScore from SER results ─────────
      const voiceScores = voiceAnalysisResults
        .map((v) => {
          const match = v.result.match(/Assessment Score:\s*([\d.]+)%/);
          return match ? parseFloat(match[1]) : null;
        })
        .filter((s) => s !== null);

      const voiceToneScore =
        voiceScores.length > 0
          ? Math.round(voiceScores.reduce((a, b) => a + b, 0) / voiceScores.length)
          : 0;

      console.log(`[jobReport] VoiceToneScore: ${voiceToneScore} (from ${voiceScores.length} samples)`);

      // ── 6. Build job context for GPT prompt ──────────────────
      let jobContext = `Position: ${jobTitle}`;
      if (specialty) jobContext += `\nSpecialty: ${specialty}`;
      if (companyName) jobContext += `\nCompany: ${companyName}`;
      if (requirements.length > 0) {
        jobContext += `\nJob Requirements:\n${requirements.map((r) => `- ${r}`).join("\n")}`;
      }
      if (description) {
        jobContext += `\nJob Description: ${description.substring(0, 500)}`;
      }

      // ── 7. Analyse with GPT-4 (updated prompt for 4 scores + checklist) ──
      const requirementsJson = requirements.length > 0
        ? `\n\nFor each of the following job requirements, evaluate whether the candidate demonstrated meeting it based on their interview answers. Return a "requirementsChecklist" array:\n${requirements.map((r) => `- "${r}"`).join("\n")}`
        : "";

      const gptPrompt = `You are an expert recruiter writing a candidate evaluation report for a hiring manager. Always refer to the candidate in third person ("the candidate", "they"). NEVER use second person ("you"). This report is viewed by the company, not the candidate.

${jobContext}

${transcriptionNote}Based on the following interview transcripts, provide a comprehensive evaluation in VALID JSON format with NO markdown code blocks.

Note: Questions marked [technical] assess domain knowledge. Questions marked [psychometric] assess personality traits and work style.

Interview Transcripts:
${transcriptText}
${requirementsJson}

Respond with a JSON object containing:
{
  "cvAnalysisScore": <number 0-100, score how well the candidate's demonstrated experience and qualifications align with the job requirements based on what they revealed in their answers>,
  "jobRequirementsMatchScore": <number 0-100, score how many job requirements the candidate clearly meets based on their answers>,
  "psychometricScore": <number 0-100, score based on the candidate's responses to psychometric questions — evaluate confidence, communication skills, personality traits, teamwork, and work style>,
  "technicalScore": <number 0-100, score based on the candidate's responses to technical questions — evaluate domain-specific knowledge, problem solving, and technical depth>,
  "overallSummary": "<2-3 sentences in third person summarizing the candidate's overall performance and suitability for this specific role>",
  "strengths": [
    "<specific strength 1 in third person with example from the interview>",
    "<specific strength 2 with example>",
    "<specific strength 3 with example>"
  ],
  "weaknesses": [
    "<specific weakness 1 in third person with example from the interview>",
    "<specific weakness 2 with example>",
    "<specific weakness 3 with example>"
  ],
  "advice": [
    "<actionable recommendation 1 in third person>",
    "<actionable recommendation 2>",
    "<actionable recommendation 3>"
  ],
  "requirementsChecklist": [
    {
      "requirement": "<the job requirement text>",
      "met": <true or false>
    }
  ],
  "psychometricAnalysis": {
    "confidence": <number 0-100>,
    "communication": <number 0-100>,
    "personalityTraits": "<brief description of observed personality traits in third person>",
    "workStyle": "<brief description of work style in third person>"
  },
  "questionsAndAnswers": [
    {
      "question": "<the interview question>",
      "answer": "<the transcribed answer>"
    }
  ]
}

SCORING GUIDELINES (0-100 scale):
- 80-100: Excellent — strong domain knowledge, clear communication, confident delivery, strong role fit
- 60-79: Good — adequate knowledge and communication, room for improvement
- 40-59: Average — partial knowledge, needs development in key areas
- 0-39: Below expectations — unclear answers, significant gaps

CRITICAL: Write ALL feedback in third person ("the candidate demonstrated", "they showed", "the candidate should"). NEVER use second person ("you"). This report is for the hiring company. Evaluate specifically against the job requirements listed above. Be specific and reference actual content from the interview.`;

      console.log("[jobReport] Sending to GPT-4 for analysis...");

      const gptResponse = await fetch(
        "https://api.openai.com/v1/chat/completions",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${OPENAI_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model: "gpt-4",
            messages: [
              {
                role: "system",
                content:
                  "You are an expert recruiter writing a candidate evaluation report for a hiring manager. Always use third person ('the candidate', 'they'). Never use second person ('you'). Always respond with valid JSON only, no markdown.",
              },
              {
                role: "user",
                content: gptPrompt,
              },
            ],
            temperature: 0.7,
            max_tokens: 4000,
          }),
        }
      );

      if (!gptResponse.ok) {
        const errorText = await gptResponse.text();
        throw new Error(
          `GPT-4 API error: ${gptResponse.statusText} - ${errorText}`
        );
      }

      const gptResult = await gptResponse.json();
      const rawResponse = gptResult.choices[0].message.content.trim();

      console.log(
        "[jobReport] GPT-4 raw response:",
        rawResponse.substring(0, 300)
      );

      let cleanedResponse = rawResponse;
      if (rawResponse.startsWith("```json")) {
        cleanedResponse = rawResponse
          .replace(/```json\n?/g, "")
          .replace(/```\n?/g, "");
      } else if (rawResponse.startsWith("```")) {
        cleanedResponse = rawResponse.replace(/```\n?/g, "");
      }

      const reportData = JSON.parse(cleanedResponse);
      console.log("[jobReport] ✅ Successfully parsed GPT-4 response");

      // ── 8. Calculate weighted final score (Story 36) ──────────
      const clamp = (v) => Math.min(100, Math.max(0, Math.round(Number(v) || 0)));

      const cvScore = clamp(reportData.cvAnalysisScore);
      const jobMatchScore = clamp(reportData.jobRequirementsMatchScore);
      const psychoScore = clamp(reportData.psychometricScore);
      const techScore = clamp(reportData.technicalScore);
      const voiceScore = clamp(voiceToneScore);

      // Weights from Story 36:
      // CV Analysis 30%, Job Requirements 20%, Psychometric 20%, Voice Tone 10%, Technical 20%
      const finalScore = Math.round(
        cvScore * 0.30 +
        jobMatchScore * 0.20 +
        psychoScore * 0.20 +
        voiceScore * 0.10 +
        techScore * 0.20
      );

      console.log(`[jobReport] Score breakdown: CV=${cvScore}, JobMatch=${jobMatchScore}, Psycho=${psychoScore}, Voice=${voiceScore}, Tech=${techScore} → Final=${finalScore}`);

      // ── 9. Generate PDF report ────────────────────────────────
      let reportUrl = "";

      try {
        console.log("[jobReport] Generating PDF report...");

        const pdfBuffer = await generatePDF({
          jobTitle,
          companyName,
          specialty,
          finalScore,
          cvScore,
          jobMatchScore,
          psychoScore,
          voiceScore,
          techScore,
          reportData,
          voiceAnalysisResults,
          cvUrl,
        });

        // Upload to Firebase Storage
        const bucket = getStorage().bucket();
        const fileName = `reports/${applicantUserId}/${applicationsID}_report.pdf`;
        const file = bucket.file(fileName);

        await file.save(pdfBuffer, {
          metadata: {
            contentType: "application/pdf",
            cacheControl: "public, max-age=31536000",
          },
        });

        await file.makePublic();

        reportUrl = `https://storage.googleapis.com/${bucket.name}/${fileName}`;
        console.log(`[jobReport] ✅ PDF uploaded: ${reportUrl}`);
      } catch (pdfError) {
        console.error("[jobReport] ❌ PDF generation failed:", pdfError.message);
        // Continue without PDF — report data is still saved to Firestore
      }

      // ── 10. Save everything to Firestore ──────────────────────
      await appRef.update({
        // Full report object
        Report: reportData,

        // 5 individual scores (for company_reports_page.dart UI)
        CVAnalysisScore: cvScore,
        JobRequirementsMatchScore: jobMatchScore,
        PsychometricScore: psychoScore,
        VoiceToneScore: voiceScore,
        TechnicalEvaluationScore: techScore,

        // Weighted final score
        Score: finalScore,

        // Score breakdown object (alternative access)
        ScoreBreakdown: {
          CV: cvScore,
          JobRequirementsMatch: jobMatchScore,
          Psychometric: psychoScore,
          VoiceTone: voiceScore,
          TechnicalEvaluation: techScore,
        },

        // Transcribed answers
        Answers: transcripts.map((t) => t.answer),

        // Voice analysis from SER
        VoiceToneAnalysis: voiceAnalysisResults,

        // Requirements checklist
        RequirementsChecklist: reportData.requirementsChecklist || [],

        // Psychometric details
        PsychometricAnalysis: reportData.psychometricAnalysis || {},

        // PDF URL
        ReportURL: reportUrl,

        // Timestamp
        ReportGeneratedAt: FieldValue.serverTimestamp(),
      });

      console.log(
        `[jobReport] ✅ Report saved for ${applicationsID} (final score: ${finalScore})`
      );

      return {
        success: true,
        message: "Report generated successfully",
        score: finalScore,
        reportUrl: reportUrl,
      };
    } catch (error) {
      console.error("[jobReport] ❌ Error:", error);

      if (error instanceof HttpsError) {
        throw error;
      }

      throw new HttpsError(
        "internal",
        `Failed to generate report: ${error.message}`
      );
    }
  }
);


// ═══════════════════════════════════════════════════════════════
//  PDF GENERATION HELPER
// ═══════════════════════════════════════════════════════════════
function generatePDF({
  jobTitle,
  companyName,
  specialty,
  finalScore,
  cvScore,
  jobMatchScore,
  psychoScore,
  voiceScore,
  techScore,
  reportData,
  voiceAnalysisResults,
  cvUrl,
}) {
  return new Promise((resolve, reject) => {
    try {
      const doc = new PDFDocument({ margin: 50, size: "A4" });
      const chunks = [];

      doc.on("data", (chunk) => chunks.push(chunk));
      doc.on("end", () => resolve(Buffer.concat(chunks)));
      doc.on("error", reject);

      const blue = "#4A5FBC";
      const darkText = "#1A1D2E";
      const grey = "#6B7394";
      const green = "#2ED8A3";
      const red = "#FF5C5C";
      const pageWidth = 495; // A4 width minus margins

      // ── Header ──
      doc
        .rect(0, 0, 595, 120)
        .fill(blue);

      doc
        .fontSize(22)
        .fillColor("#FFFFFF")
        .font("Helvetica-Bold")
        .text("Jadeer", 50, 35);

      doc
        .fontSize(10)
        .fillColor("#FFFFFF")
        .font("Helvetica")
        .text("AI-Powered Candidate Evaluation Report", 50, 60);

      doc
        .fontSize(11)
        .text(`${jobTitle}${companyName ? " — " + companyName : ""}`, 50, 80);

      if (specialty) {
        doc.fontSize(9).text(`Specialty: ${specialty}`, 50, 96);
      }

      doc.fillColor(darkText);
      doc.y = 140;

      // ── Final Score Section ──
      doc
        .font("Helvetica-Bold")
        .fontSize(16)
        .text("Overall Score", 50, doc.y);

      doc.moveDown(0.5);

      const scoreColor = finalScore >= 80 ? green : finalScore >= 60 ? "#FFB347" : finalScore >= 40 ? "#FF8E53" : red;

      doc
        .font("Helvetica-Bold")
        .fontSize(36)
        .fillColor(scoreColor)
        .text(`${finalScore}`, 50, doc.y, { continued: true })
        .fontSize(16)
        .fillColor(grey)
        .text(" / 100");

      doc.fillColor(darkText);
      doc.moveDown(1);

      // ── Score Breakdown ──
      doc
        .font("Helvetica-Bold")
        .fontSize(14)
        .text("Score Breakdown", 50, doc.y);
      doc.moveDown(0.5);

      const scores = [
        { label: "CV Analysis (30%)", score: cvScore, contribution: (cvScore * 0.30).toFixed(1) },
        { label: "Job Requirements Match (20%)", score: jobMatchScore, contribution: (jobMatchScore * 0.20).toFixed(1) },
        { label: "Psychometric Analysis (20%)", score: psychoScore, contribution: (psychoScore * 0.20).toFixed(1) },
        { label: "Voice Tone Analysis (10%)", score: voiceScore, contribution: (voiceScore * 0.10).toFixed(1) },
        { label: "Technical Evaluation (20%)", score: techScore, contribution: (techScore * 0.20).toFixed(1) },
      ];

      doc.font("Helvetica").fontSize(10);
      for (const s of scores) {
        const barY = doc.y;
        doc.fillColor(darkText).text(`${s.label}`, 50, barY);
        doc.fillColor(grey).text(`${s.score}/100 (${s.contribution} pts)`, 400, barY);

        // Progress bar
        doc.y = barY + 16;
        doc.rect(50, doc.y, pageWidth, 6).fill("#E8E8EE");
        const barWidth = Math.max(0, (s.score / 100) * pageWidth);
        if (barWidth > 0) {
          doc.rect(50, doc.y, barWidth, 6).fill(blue);
        }
        doc.y += 14;
      }

      doc.moveDown(1);

      // ── Overall Summary ──
      doc
        .font("Helvetica-Bold")
        .fontSize(14)
        .fillColor(darkText)
        .text("Overall Summary", 50, doc.y);
      doc.moveDown(0.3);
      doc
        .font("Helvetica")
        .fontSize(10)
        .fillColor(darkText)
        .text(reportData.overallSummary || "No summary available.", 50, doc.y, { width: pageWidth });

      doc.moveDown(1);

      // ── Requirements Checklist ──
      if (reportData.requirementsChecklist && reportData.requirementsChecklist.length > 0) {
        checkPageBreak(doc, 50);
        doc
          .font("Helvetica-Bold")
          .fontSize(14)
          .fillColor(darkText)
          .text("Job Requirements Checklist", 50, doc.y);
        doc.moveDown(0.5);

        doc.font("Helvetica").fontSize(10);
        for (const item of reportData.requirementsChecklist) {
          checkPageBreak(doc, 30);
          const icon = item.met ? "✓" : "✗";
          const color = item.met ? green : red;

          doc
            .fillColor(color)
            .font("Helvetica-Bold")
            .text(icon, 50, doc.y, { continued: true })
            .fillColor(darkText)
            .font("Helvetica")
            .text(`  ${item.requirement}`);

          doc.moveDown(0.3);
        }
        doc.moveDown(0.5);
      }

      // ── Psychometric Analysis ──
      if (reportData.psychometricAnalysis) {
        checkPageBreak(doc, 80);
        doc
          .font("Helvetica-Bold")
          .fontSize(14)
          .fillColor(darkText)
          .text("Psychometric Analysis", 50, doc.y);
        doc.moveDown(0.3);

        const pa = reportData.psychometricAnalysis;
        doc.font("Helvetica").fontSize(10);

        if (pa.confidence !== undefined) {
          doc.fillColor(darkText).text(`Confidence: ${pa.confidence}/100`, 55, doc.y);
        }
        if (pa.communication !== undefined) {
          doc.text(`Communication: ${pa.communication}/100`, 55, doc.y);
        }
        if (pa.personalityTraits) {
          doc.text(`Personality Traits: ${pa.personalityTraits}`, 55, doc.y, { width: pageWidth - 10 });
        }
        if (pa.workStyle) {
          doc.text(`Work Style: ${pa.workStyle}`, 55, doc.y, { width: pageWidth - 10 });
        }
        doc.moveDown(0.5);
      }

      // ── Voice Tone Analysis ──
      if (voiceAnalysisResults && voiceAnalysisResults.length > 0) {
        checkPageBreak(doc, 80);
        doc
          .font("Helvetica-Bold")
          .fontSize(14)
          .fillColor(darkText)
          .text("Voice Tone Analysis", 50, doc.y);
        doc.moveDown(0.4);

        // Info message
        doc
          .font("Helvetica")
          .fontSize(9)
          .fillColor(grey)
          .text(
            "These results are based on an AI analysis of the candidate's vocal confidence during the interview. The model evaluates tone, pacing, and delivery for each answer.",
            50,
            doc.y,
            { width: pageWidth }
          );
        doc.moveDown(0.6);

        // Per-question results
        doc
          .font("Helvetica-Bold")
          .fontSize(11)
          .fillColor(darkText)
          .text("Per-Question Analysis", 50, doc.y);
        doc.moveDown(0.4);

        for (const v of voiceAnalysisResults) {
          checkPageBreak(doc, 40);
          const qNum = v.questionIndex + 1;
          const scoreMatch = v.result.match(/Assessment Score:\s*([\d.]+)%/);
          const score = scoreMatch ? parseFloat(scoreMatch[1]).toFixed(1) : "0.0";
          const insight = v.result.includes("Insight:")
            ? v.result.split("Insight:")[1].trim()
            : v.result;

          // Question label + score
          doc
            .font("Helvetica-Bold")
            .fontSize(10)
            .fillColor(blue)
            .text(`Q${qNum}`, 50, doc.y, { continued: true })
            .fillColor(darkText)
            .text(`                                                                                    ${score} / 100`, {
              align: "right",
            });

          // Progress bar
          const barY = doc.y;
          doc.rect(50, barY, pageWidth, 5).fill("#E8E8EE");
          const barWidth = Math.max(0, (parseFloat(score) / 100) * pageWidth);
          if (barWidth > 0) {
            const barColor = parseFloat(score) >= 70 ? green : parseFloat(score) >= 40 ? "#FFB347" : red;
            doc.rect(50, barY, barWidth, 5).fill(barColor);
          }
          doc.y = barY + 10;

          // Insight text
          doc
            .font("Helvetica")
            .fontSize(9)
            .fillColor(grey)
            .text(insight, 50, doc.y, { width: pageWidth });
          doc.moveDown(0.5);
        }

        doc.moveDown(0.3);

        // Average voice score footer
        checkPageBreak(doc, 30);
        doc
          .font("Helvetica-Bold")
          .fontSize(10)
          .fillColor(darkText)
          .text(`Average Voice Confidence: ${voiceScore} / 100`, 50, doc.y);
        doc.moveDown(0.8);
      }

      // ── Interview Questions & Answers ──
      if (reportData.questionsAndAnswers && reportData.questionsAndAnswers.length > 0) {
        checkPageBreak(doc, 50);
        doc
          .font("Helvetica-Bold")
          .fontSize(14)
          .fillColor(darkText)
          .text("Interview Questions & Answers", 50, doc.y);
        doc.moveDown(0.5);

        for (let i = 0; i < reportData.questionsAndAnswers.length; i++) {
          const qa = reportData.questionsAndAnswers[i];
          checkPageBreak(doc, 70);

          doc
            .font("Helvetica-Bold")
            .fontSize(10)
            .fillColor(blue)
            .text(`Q${i + 1}: ${qa.question}`, 50, doc.y, { width: pageWidth });

          doc.moveDown(0.2);
          doc
            .font("Helvetica")
            .fontSize(10)
            .fillColor(darkText)
            .text(`Answer: ${qa.answer}`, 55, doc.y, { width: pageWidth - 10 });

          doc.moveDown(0.8);
        }
      }

      // ── CV Reference ──
      if (cvUrl) {
        checkPageBreak(doc, 40);
        doc.moveDown(0.5);
        doc
          .font("Helvetica-Bold")
          .fontSize(12)
          .fillColor(darkText)
          .text("Attached CV", 50, doc.y);
        doc.moveDown(0.3);
        doc
          .font("Helvetica")
          .fontSize(9)
          .fillColor(blue)
          .text(cvUrl, 50, doc.y, { link: cvUrl, underline: true, width: pageWidth });
      }

      // ── Footer ──
      doc.moveDown(2);
      doc
        .font("Helvetica")
        .fontSize(8)
        .fillColor(grey)
        .text(`Generated by Jadeer AI — ${new Date().toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric" })}`, 50, doc.y, { align: "center", width: pageWidth });

      doc.end();
    } catch (err) {
      reject(err);
    }
  });
}

function checkPageBreak(doc, neededSpace) {
  if (doc.y + neededSpace > 760) {
    doc.addPage();
  }
}