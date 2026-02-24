import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import FormData from "form-data";
import fetch from "node-fetch";

/**
 * generateJobInterviewReport
 *
 * Called by job_interview_service.dart after the job seeker
 * finishes all interview questions.
 *
 * Pipeline:
 *   1. Read Applications doc → get audio URLs, JobID, CV URL
 *   2. Read Jobs doc        → get Questions, JobTitle, Specialty, Requirements
 *   3. Transcribe audio     → Whisper API
 *   4. Analyse with GPT-4   → strengths, weaknesses, advice, score
 *   5. Save Report + Score  → back to Applications doc
 *
 * Report schema matches MockInterviewReport so the Flutter UI can
 * reuse the same widgets (strengths[], weaknesses[], advice[],
 * overallScore, overallSummary, voiceToneAnalysis).
 *
 * Score is on a 0-100 scale (matching Applications.Score field).
 */
export const generateJobInterviewReport = onCall(
  {
    secrets: ["OPENAI_API_KEY"],
    timeoutSeconds: 540,
    memory: "512MiB",
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

      console.log(
        `[jobReport] Starting for application: ${applicationsID}`
      );

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

      console.log(
        `[jobReport] Found ${audioUrls.length} audio files, JobID: ${jobID}`
      );

      if (audioUrls.length === 0) {
        throw new HttpsError(
          "failed-precondition",
          "No audio recordings found for this application"
        );
      }

      // ── 2. Read Job doc → questions + job context ────────────
      let questions = [];
      let jobTitle = appData.JobTitle || "";
      let companyName = appData.CompanyName || "";
      let specialty = "";
      let requirements = [];
      let description = "";

      if (jobID) {
        const jobSnap = await db.collection("Jobs").doc(jobID).get();

        if (jobSnap.exists) {
          const jobData = jobSnap.data();

          // Questions may be ["text"] or [{Text:"text"}]
          const rawQ = jobData.Questions || [];
          questions = rawQ.map((q) =>
            typeof q === "string" ? q : q.Text || q.text || String(q)
          );

          // Job context for GPT prompt
          jobTitle = jobTitle || jobData.JobTitle || "Unknown Position";
          specialty = jobData.Specialty || "";
          requirements = jobData.Requirements || [];
          description = jobData.Description || "";

          // Get company name if not already on application
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

      // Fallback: use stored answers count for question numbering
      if (questions.length === 0) {
        questions = audioUrls.map((_, i) => `Question ${i + 1}`);
      }

      console.log(
        `[jobReport] Job: ${jobTitle}, Specialty: ${specialty}, ${questions.length} questions`
      );

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
          console.log(
            `[jobReport] Transcribing audio ${i + 1}/${audioUrls.length}`
          );

          // Download audio file
          const audioResponse = await fetch(audioUrl);
          if (!audioResponse.ok) {
            throw new Error(
              `Failed to download audio: ${audioResponse.statusText}`
            );
          }

          const audioBuffer = await audioResponse.buffer();
          console.log(
            `[jobReport] Downloaded ${audioBuffer.length} bytes`
          );

          if (audioBuffer.length < 100) {
            throw new Error("Audio file too small (likely corrupted)");
          }

          // Call Whisper API using FormData
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
            throw new Error(
              `Whisper API error: ${transcriptionResponse.statusText}`
            );
          }

          const result = await transcriptionResponse.json();
          const questionText = questions[i] || `Question ${i + 1}`;

          transcripts.push({
            question: questionText,
            answer: result.text || "[No transcription]",
          });

          console.log(
            `[jobReport] ✅ Transcribed Q${i + 1}: ${result.text.substring(0, 50)}...`
          );
        } catch (error) {
          console.error(
            `[jobReport] ❌ Transcription failed for audio ${i}:`,
            error
          );
          transcripts.push({
            question: questions[i] || `Question ${i + 1}`,
            answer: "[Transcription failed]",
          });
        }
      }

      if (transcripts.length === 0) {
        throw new HttpsError(
          "internal",
          "Failed to transcribe any audio files"
        );
      }

      console.log(
        `[jobReport] Successfully transcribed ${transcripts.length} answers`
      );

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
        .map((t, i) => `Q${i + 1}: ${t.question}\nA${i + 1}: ${t.answer}`)
        .join("\n\n");

      const failedCount = transcripts.length - validTranscripts.length;
      const transcriptionNote =
        failedCount > 0
          ? `Note: ${failedCount} answer(s) could not be transcribed and were excluded from analysis.\n\n`
          : "";

      // ── 5. Build job context for GPT prompt ──────────────────
      let jobContext = `Position: ${jobTitle}`;
      if (specialty) jobContext += `\nSpecialty: ${specialty}`;
      if (companyName) jobContext += `\nCompany: ${companyName}`;
      if (requirements.length > 0) {
        jobContext += `\nJob Requirements:\n${requirements.map((r) => `- ${r}`).join("\n")}`;
      }
      if (description) {
        jobContext += `\nJob Description: ${description.substring(0, 500)}`;
      }

      // ── 6. Analyse with GPT-4 ───────────────────────────────
      const gptPrompt = `You are an expert recruiter writing a personal feedback report directly to the job applicant. Always address them as "you" (second person), never "the candidate" or "the applicant".

${jobContext}

${transcriptionNote}Based on the following interview transcripts, provide a comprehensive evaluation in VALID JSON format with NO markdown code blocks.

Interview Transcripts:
${transcriptText}

Respond with a JSON object containing:
{
  "overallScore": <number between 0-100>,
  "overallSummary": "<2-3 sentences addressing the applicant directly as 'you', summarizing their overall performance and suitability for this specific role>",
  "strengths": [
    "<specific strength 1 addressing the applicant as 'you' with example from the interview>",
    "<specific strength 2 addressing the applicant as 'you' with example from the interview>",
    "<specific strength 3 addressing the applicant as 'you' with example from the interview>"
  ],
  "weaknesses": [
    "<specific weakness 1 addressing the applicant as 'you' with example from the interview>",
    "<specific weakness 2 addressing the applicant as 'you' with example from the interview>",
    "<specific weakness 3 addressing the applicant as 'you' with example from the interview>"
  ],
  "advice": [
    "<actionable recommendation 1 addressed as 'you' for improving in this role>",
    "<actionable recommendation 2>",
    "<actionable recommendation 3>"
  ],
  "questionsAndAnswers": [
    {
      "question": "<the interview question>",
      "answer": "<your transcribed answer>",
      "evaluation": "<brief evaluation of this specific answer, addressing the applicant as 'you'>"
    }
  ],
  "voiceToneAnalysis": {
    "available": false,
    "message": "Voice tone analysis will be available in future updates"
  }
}

IMPORTANT SCORING GUIDELINES (0-100 scale):
- Score 80-100: Excellent responses demonstrating strong domain knowledge, clear communication, confident delivery, and strong fit for the role
- Score 60-79: Good responses with adequate knowledge and communication but room for improvement
- Score 40-59: Average responses, partial knowledge, needs development in key areas
- Score 0-39: Below expectations, unclear answers, significant gaps in required knowledge

CRITICAL: Write ALL feedback in second person ("you demonstrated", "you should", "your answer showed"). NEVER use third person ("the candidate", "the applicant", "they"). This report is shown directly to the applicant. Evaluate specifically against the job requirements listed above. Be specific and reference actual content from the interview.`;

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
                  "You are an expert recruiter writing personal feedback directly to a job applicant. Always use second person ('you'). Never use third person ('the candidate'). Always respond with valid JSON only, no markdown.",
              },
              {
                role: "user",
                content: gptPrompt,
              },
            ],
            temperature: 0.7,
            max_tokens: 3000,
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
        rawResponse.substring(0, 200)
      );

      // Remove markdown code blocks if present
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

      // Extract score (0-100)
      const score =
        typeof reportData.overallScore === "number"
          ? Math.min(100, Math.max(0, Math.round(reportData.overallScore)))
          : 0;

      // ── 7. Save report + score to Firestore ──────────────────
      await appRef.update({
        Report: reportData,
        Score: score,
        Answers: transcripts.map((t) => t.answer),
        ReportGeneratedAt: FieldValue.serverTimestamp(),
      });

      console.log(
        `[jobReport] ✅ Report saved for ${applicationsID} (score: ${score})`
      );

      return {
        success: true,
        message: "Report generated successfully",
        score: score,
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