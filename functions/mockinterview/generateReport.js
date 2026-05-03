import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import FormData from "form-data";
import fetch from "node-fetch";

export const generateMockInterviewReport = onCall(
  {
    secrets: ["OPENAI_API_KEY", "HF_TOKEN"],
    timeoutSeconds: 540,
    memory: "512MiB",
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

      // Step 1: Transcribe all audio files
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
          console.log(`[generateReport] Audio URL: ${audioUrl.substring(0, 100)}...`);

          // Download audio file
          const audioResponse = await fetch(audioUrl);
          if (!audioResponse.ok) {
            throw new Error(`Failed to download audio: ${audioResponse.statusText}`);
          }

          const audioBuffer = await audioResponse.buffer();
          console.log(`[generateReport] Downloaded ${audioBuffer.length} bytes`);

          if (audioBuffer.length < 100) {
            throw new Error('Audio file too small (likely corrupted)');
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
            console.error(`[generateReport] Whisper error: ${errorText}`);
            throw new Error(`Whisper API error: ${transcriptionResponse.statusText}`);
          }

          const result = await transcriptionResponse.json();
          const questionText = questions[i] || `Question ${i + 1}`;

          transcripts.push({
            question: questionText,
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
        throw new HttpsError(
          "internal",
          "Failed to transcribe any audio files"
        );
      }

      console.log(`[generateReport] Successfully transcribed ${transcripts.length} answers`);

      // Step 2: Filter out failed transcriptions
      const validTranscripts = transcripts.filter(t => t.answer !== "[Transcription failed]");

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
      const transcriptionNote = failedCount > 0 
        ? `Note: ${failedCount} answer(s) could not be transcribed and were excluded from analysis.\n\n`
        : '';

      // Step 3: Analyze with GPT-4
      const gptPrompt = `You are an expert interview coach giving personal feedback to someone who just completed a mock interview for a ${specialty} position.

IMPORTANT TONE: Address the user directly using "you" and "your" — NOT "the candidate". This is personal coaching feedback meant to help them improve.

${transcriptionNote}Based on the following interview transcripts, provide a comprehensive analysis in VALID JSON format with NO markdown code blocks.

Interview Transcripts:
${transcriptText}

Respond with a JSON object containing:
{
  "overallScore": <number between 1-10>,
  "overallSummary": "<2-3 sentences summarizing your overall performance, highlighting key strengths and main areas for improvement. Address the user as 'you'.>",
  "strengths": [
    "<specific strength 1 with example from the interview, using 'you' language>",
    "<specific strength 2 with example from the interview, using 'you' language>",
    "<specific strength 3 with example from the interview, using 'you' language>"
  ],
  "weaknesses": [
    "<specific area for improvement 1 with example, using 'you' language>",
    "<specific area for improvement 2 with example, using 'you' language>",
    "<specific area for improvement 3 with example, using 'you' language>"
  ],
  "advice": [
    "<actionable recommendation 1, using 'you' language>",
    "<actionable recommendation 2, using 'you' language>",
    "<actionable recommendation 3, using 'you' language>"
  ],
  "voiceToneAnalysis": {
    "available": false,
    "message": "Voice tone analysis will be available in future updates"
  }
}

IMPORTANT SCORING GUIDELINES:
- Score 8-10: Excellent responses, clear communication, strong examples, confident delivery
- Score 6-7: Good responses with room for improvement, adequate examples
- Score 1-5: Needs significant improvement, unclear answers, lack of examples

CRITICAL LANGUAGE RULE: NEVER say "the candidate", "the interviewee", or "the applicant". Always say "you" and "your". For example:
- BAD: "The candidate demonstrated strong communication skills"
- GOOD: "You demonstrated strong communication skills"
- BAD: "The candidate should practice more"
- GOOD: "You should practice more"

Make the overallSummary at least 2-3 full sentences that give a balanced, encouraging view of the performance. Be specific and reference actual content from the interview.`;

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
              content: "You are a friendly interview coach giving direct personal feedback. Always respond with valid JSON only, no markdown. CRITICAL: Always address the user as 'you' — NEVER say 'the candidate', 'the interviewee', or 'the applicant'. Write as if you're speaking directly to the person.",
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

      // Remove markdown code blocks if present
      let cleanedResponse = rawResponse;
      if (rawResponse.startsWith("```json")) {
        cleanedResponse = rawResponse.replace(/```json\n?/g, "").replace(/```\n?/g, "");
      } else if (rawResponse.startsWith("```")) {
        cleanedResponse = rawResponse.replace(/```\n?/g, "");
      }

      const reportData = JSON.parse(cleanedResponse);
      console.log("[generateReport] ✅ Successfully parsed GPT-4 response");

      // Step 4: Save report to Firestore
      await interviewRef.update({
        Report: reportData,
        ReportGeneratedAt: FieldValue.serverTimestamp(),
      });

      // Step 5: Voice Tone Analysis (SER Model)
      console.log("[generateReport] Starting voice tone analysis...");
      const voiceResults = [];
      const HF_TOKEN = process.env.HF_TOKEN;

      for (let i = 0; i < audioUrls.length; i++) {
        const audioUrl = audioUrls[i];
        if (!audioUrl || audioUrl.trim() === "") continue;

        try {
          console.log(`[generateReport] Analyzing voice ${i + 1}/${audioUrls.length}`);

          const audioResponse = await fetch(audioUrl);
          const audioBuffer = await audioResponse.buffer();

          const hfResponse = await fetch(
            "https://wsaifaleslam-jadeer-smart-assessment.hf.space/run/predict_confidence",
            {
              method: "POST",
              headers: {
                "Authorization": `Bearer ${HF_TOKEN}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({
                data: [{ name: `audio_${i}.m4a`, data: `data:audio/m4a;base64,${audioBuffer.toString("base64")}` }]
              }),
            }
          );

          if (!hfResponse.ok) {
            throw new Error(`HF API error: ${hfResponse.statusText}`);
          }

          const hfResult = await hfResponse.json();
          const resultText = hfResult.data?.[0] || "Analysis unavailable";

          voiceResults.push({
            questionIndex: i,
            result: resultText,
          });

          console.log(`[generateReport] ✅ Voice analysis Q${i + 1}: ${resultText}`);
        } catch (err) {
          console.error(`[generateReport] ❌ Voice analysis failed for Q${i + 1}:`, err);
          voiceResults.push({
            questionIndex: i,
            result: "Analysis unavailable",
          });
        }
      }

      await interviewRef.update({
        VoiceToneAnalysis: voiceResults,
      });

      console.log("[generateReport] ✅ Voice tone analysis saved");

      console.log(`[generateReport] ✅ Report saved successfully for ${mockInterviewID}`);

      return {
        success: true,
        message: "Report generated successfully",
        report: reportData,
      };
    } catch (error) {
      console.error("[generateReport] ❌ Error:", error);

      if (error instanceof HttpsError) {
        throw error;
      }

      throw new HttpsError("internal", `Failed to generate report: ${error.message}`);
    }
  }
);