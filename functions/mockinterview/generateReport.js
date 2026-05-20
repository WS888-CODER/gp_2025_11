import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import FormData from "form-data";
import fetch from "node-fetch";
import { Client } from "@gradio/client";

export const generateMockInterviewReport = onCall(
  {
    secrets: ["OPENAI_API_KEY", "HF_TOKEN"],
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (request) => {
    try {
      const { mockInterviewID } = request.data;

      if (!mockInterviewID) {
        throw new HttpsError("invalid-argument", "mockInterviewID is required");
      }

      console.log(`[generateReport] Starting for interview: ${mockInterviewID}`);

      const db = getFirestore();
      const interviewRef = db.collection("MockInterviews").doc(mockInterviewID);
      const interviewSnap = await interviewRef.get();

      if (!interviewSnap.exists) {
        throw new HttpsError("not-found", "Mock interview not found");
      }

      const interviewData = interviewSnap.data();
      const audioUrls = interviewData.AnswersRecordsURL || [];
      const questions = interviewData.Questions || [];
      const specialty = interviewData.Specialty || "Unknown";

      console.log(`[generateReport] Found ${audioUrls.length} audio files`);

      if (audioUrls.length === 0) {
        throw new HttpsError(
          "failed-precondition",
          "No audio recordings found for this interview"
        );
      }

      // ══════════════════════════════════════════════════════════
      // Step 1: Transcribe all audio files (Whisper)
      // ══════════════════════════════════════════════════════════
      const transcripts = [];
      const OPENAI_KEY = process.env.OPENAI_API_KEY;

      for (let i = 0; i < audioUrls.length; i++) {
        const audioUrl = audioUrls[i];
        if (!audioUrl || audioUrl.trim() === "") {
          console.log(`[generateReport] Skipping empty URL at index ${i}`);
          continue;
        }

        try {
          console.log(`[generateReport] Transcribing audio ${i + 1}/${audioUrls.length}`);

          const audioResponse = await fetch(audioUrl);
          if (!audioResponse.ok) {
            throw new Error(`Failed to download audio: ${audioResponse.statusText}`);
          }

          const audioBuffer = await audioResponse.buffer();
          console.log(`[generateReport] Downloaded ${audioBuffer.length} bytes`);

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
            console.error(`[generateReport] Whisper error: ${errorText}`);
            throw new Error(`Whisper API error: ${transcriptionResponse.statusText}`);
          }

          const result = await transcriptionResponse.json();
          transcripts.push({
            question: questions[i] || `Question ${i + 1}`,
            answer: result.text || "[No transcription]",
          });

          console.log(`[generateReport] ✅ Transcribed Q${i + 1}: ${result.text.substring(0, 50)}...`);
        } catch (error) {
          console.error(`[generateReport] ❌ Transcription failed for audio ${i}:`, error);
          transcripts.push({
            question: questions[i] || `Question ${i + 1}`,
            answer: "[Transcription failed]",
          });
        }
      }

      if (transcripts.length === 0) {
        throw new HttpsError("internal", "Failed to transcribe any audio files");
      }

      const validTranscripts = transcripts.filter((t) => t.answer !== "[Transcription failed]");

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

      console.log(`[generateReport] Successfully transcribed ${validTranscripts.length} answers`);

      // ══════════════════════════════════════════════════════════
      // Step 2: Voice Tone Analysis (SER Model) — EXACT OLD WORKING CODE
      // ══════════════════════════════════════════════════════════
      console.log("[generateReport] Starting voice tone analysis via Public Client...");
      const voiceResults = [];

      try {
        const spaceApiUrl = "https://huggingface.co/api/spaces/wsaifaleslam/jadeer-smart-assessment";
        let isAwake = false;
        let attempts = 0;

        console.log("[generateReport] Checking real-time Hugging Face Space status...");

        while (!isAwake && attempts < 10) {
          const response = await fetch(spaceApiUrl);
          if (response.ok) {
            const metadata = await response.json();
            const runtimeStatus = metadata.runtime?.stage;

            console.log(`[generateReport] Space status is currently: ${runtimeStatus}`);

            if (runtimeStatus === "RUNNING") {
              isAwake = true;
              break;
            }
          }

          attempts++;
          await fetch("https://wsaifaleslam-jadeer-smart-assessment.hf.space").catch(() => {});
          await new Promise((resolve) => setTimeout(resolve, 4000));
        }

        const app = await Client.connect("wsaifaleslam/jadeer-smart-assessment");
        console.log("[generateReport] ✅ Connected to Hugging Face Space successfully.");

        for (let i = 0; i < audioUrls.length; i++) {
          const audioUrl = audioUrls[i];
          if (!audioUrl || audioUrl.trim() === "") continue;

          try {
            console.log(`[generateReport] Connecting client for audio ${i + 1}/${audioUrls.length}`);

            const audioResponse = await fetch(audioUrl);
            if (!audioResponse.ok) throw new Error("Audio download failed");

            const arrayBuffer = await audioResponse.arrayBuffer();
            const audioBlob = new Blob([arrayBuffer], { type: "audio/wav" });

            const hfResult = await app.predict("predict_confidence", [audioBlob]);

            const resultText =
              hfResult.data && hfResult.data[0]
                ? String(hfResult.data[0])
                : "Analysis unavailable";

            voiceResults.push({
              questionIndex: i,
              result: resultText,
            });

            console.log(`[generateReport] ✅ Voice analysis Q${i + 1}: ${resultText}`);
          } catch (err) {
            console.error(`[generateReport] ❌ Voice analysis failed for Q${i + 1}:`, err.message || err);
            voiceResults.push({
              questionIndex: i,
              result: "Analysis unavailable",
            });
          }
        }
      } catch (outerErr) {
        console.error("[generateReport] ❌ Critical failure in SER Outer Block:", outerErr.message || outerErr);
        for (let i = 0; i < audioUrls.length; i++) {
          voiceResults.push({ questionIndex: i, result: "Analysis unavailable" });
        }
      }

      // ── Calculate voice confidence score from SER results ──
      let totalVoiceScore = 0.0;
      let validVoiceCount = 0;
      for (const v of voiceResults) {
        const match = v.result.match(/Assessment Score:\s*([\d.]+)%/);
        if (match) {
          totalVoiceScore += parseFloat(match[1]);
          validVoiceCount++;
        }
      }
      const overallVoiceConfidenceScore =
        validVoiceCount > 0 ? Math.round(totalVoiceScore / validVoiceCount) : 0;

      console.log(`[generateReport] Voice confidence score: ${overallVoiceConfidenceScore} (from ${validVoiceCount} samples)`);

      // ══════════════════════════════════════════════════════════
      // Step 3: GPT-4 Analysis (with voice score + voice comment)
      // ══════════════════════════════════════════════════════════
      const gptPrompt = `You are an expert interview coach giving personal mock interview feedback to a jobseeker practicing for a ${specialty} position.
IMPORTANT: Address the user directly using "you" and "your".

${transcriptionNote}Interview Transcripts:
${transcriptText}

Acoustic Tone Reading Parameters:
The microphone analysis registered an overall vocal confidence metric of ${overallVoiceConfidenceScore} out of 100.

Respond with a JSON object containing:
{
  "overallScore": <number between 0-100>,
  "overallSummary": "<2-3 sentences summarizing performance, using 'you' language.>",
  "strengths": ["<strength 1>", "<strength 2>", "<strength 3>"],
  "weaknesses": ["<weakness 1>", "<weakness 2>", "<weakness 3>"],
  "advice": ["<actionable recommendation 1>", "<actionable recommendation 2>", "<actionable recommendation 3>"],
  "mockVoiceComment": "<Based on the voice score of ${overallVoiceConfidenceScore}/100, generate a friendly comment offering voice tone advice. Do NOT mention the exact score number, percentages, or basic instructions like 'take a deep breath'. Instead, analyze their pacing, conviction, or hesitation, and provide constructive advice tailored to a jobseeker trying to sound confident in a ${specialty} interview. Speak to the user as 'you'.>"
}

SCORING GUIDELINES (0-100 scale):
- 80-100: Exceptional — strong knowledge, clear communication, confident delivery
- 60-79: Good — adequate knowledge and communication, room for improvement
- 40-59: Average — partial knowledge, needs development in key areas
- 0-39: Below expectations — unclear answers, significant gaps

CRITICAL: NEVER use references like "the candidate" inside this file. Always use "you" and "your".`;

      console.log("[generateReport] Sending to GPT-4 for analysis...");

      const gptResponse = await fetch("https://api.openai.com/v1/chat/completions", {
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
                "You are a friendly mock interview coach. Always respond with valid JSON only, no markdown.",
            },
            {
              role: "user",
              content: gptPrompt,
            },
          ],
          temperature: 0.7,
          max_tokens: 2000,
        }),
      });

      if (!gptResponse.ok) {
        const errorText = await gptResponse.text();
        throw new Error(`GPT-4 API error: ${gptResponse.statusText} - ${errorText}`);
      }

      const gptResult = await gptResponse.json();
      const rawResponse = gptResult.choices[0].message.content.trim();

      console.log("[generateReport] GPT-4 raw response:", rawResponse.substring(0, 200));

      let cleanedResponse = rawResponse;
      if (rawResponse.startsWith("```json")) {
        cleanedResponse = rawResponse.replace(/```json\n?/g, "").replace(/```\n?/g, "");
      } else if (rawResponse.startsWith("```")) {
        cleanedResponse = rawResponse.replace(/```\n?/g, "");
      }

      const reportData = JSON.parse(cleanedResponse);
      console.log("[generateReport] ✅ Successfully parsed GPT-4 response");

      // ── Extract voice comment from GPT ──
      const voiceCommentsArray = [
        {
          questionIndex: 0,
          result:
            reportData.mockVoiceComment ||
            "Your delivery was steady and clear throughout the interview.",
        },
      ];

      delete reportData.mockVoiceComment;

      // ══════════════════════════════════════════════════════════
      // Step 4: Save report first (like old working version)
      // ══════════════════════════════════════════════════════════
      await interviewRef.update({
        Report: reportData,
        ReportGeneratedAt: FieldValue.serverTimestamp(),
      });

      console.log("[generateReport] ✅ Report saved");

      // ══════════════════════════════════════════════════════════
      // Step 5: Save voice results separately (like old working version)
      // ══════════════════════════════════════════════════════════
      await interviewRef.update({
        VoiceToneAnalysis: voiceCommentsArray,
        VoiceToneRawResults: voiceResults,
        VoiceConfidenceScore: overallVoiceConfidenceScore,
      });

      console.log("[generateReport] ✅ Voice tone analysis saved");
      console.log(`[generateReport] ✅ Complete for ${mockInterviewID}`);

      return { success: true, report: reportData };
    } catch (error) {
      console.error("[generateReport] ❌ Error:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", `Failed to generate report: ${error.message}`);
    }
  }
);