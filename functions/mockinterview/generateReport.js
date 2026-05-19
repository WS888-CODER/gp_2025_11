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
        if (!audioUrl || audioUrl.trim() === "") continue;

        try {
          const audioResponse = await fetch(audioUrl);
          if (!audioResponse.ok) throw new Error("Audio download failed");

          const audioBuffer = await audioResponse.buffer();
          if (audioBuffer.length < 100) throw new Error('Audio file corrupted');

          const formData = new FormData();
          formData.append("file", audioBuffer, { filename: `audio_${i}.m4a`, contentType: "audio/m4a" });
          formData.append("model", "whisper-1");

          const transcriptionResponse = await fetch(
            "https://api.openai.com/v1/audio/transcriptions",
            { method: "POST", headers: { Authorization: `Bearer ${OPENAI_KEY}`, ...formData.getHeaders() }, body: formData }
          );

          if (!transcriptionResponse.ok) throw new Error("Whisper API error");

          const result = await transcriptionResponse.json();
          transcripts.push({ question: questions[i] || `Question ${i + 1}`, answer: result.text || "[No transcription]" });
        } catch (error) {
          transcripts.push({ question: questions[i] || `Question ${i + 1}`, answer: "[Transcription failed]" });
        }
      }

      const validTranscripts = transcripts.filter(t => t.answer !== "[Transcription failed]");
      const transcriptText = validTranscripts.map((t, i) => `Q${i + 1}: ${t.question}\nA${i + 1}: ${t.answer}`).join("\n\n");

      // Step 2: Voice Tone Analysis (SER Model)
      const voiceAnalysisResults = [];
      try {
        const spaceApiUrl = "https://huggingface.co/api/spaces/wsaifaleslam/jadeer-smart-assessment";
        let isAwake = false;
        let attempts = 0;

        while (!isAwake && attempts < 10) {
          const response = await fetch(spaceApiUrl);
          if (response.ok) {
            const metadata = await response.json();
            if (metadata.runtime?.stage === "RUNNING") {
              isAwake = true;
              break;
            }
          }
          attempts++;
          await fetch("https://wsaifaleslam-jadeer-smart-assessment.hf.space").catch(() => {});
          await new Promise(resolve => setTimeout(resolve, 4000));
        }

        const app = await Client.connect("wsaifaleslam/jadeer-smart-assessment");

        for (let i = 0; i < audioUrls.length; i++) {
          const audioUrl = audioUrls[i];
          if (!audioUrl || audioUrl.trim() === "") continue;

          try {
            const audioResponse = await fetch(audioUrl);
            const arrayBuffer = await audioResponse.arrayBuffer();
            const audioBlob = new Blob([arrayBuffer], { type: 'audio/wav' });

            const hfResult = await app.predict("predict_confidence", [audioBlob]);
            const resultText = hfResult.data && hfResult.data[0] ? String(hfResult.data[0]) : "Score: 0%";

            voiceAnalysisResults.push({ questionIndex: i, result: resultText });
          } catch (err) {
            voiceAnalysisResults.push({ questionIndex: i, result: "Score: 0%" });
          }
        }
      } catch (outerErr) {
        for (let i = 0; i < audioUrls.length; i++) {
          voiceAnalysisResults.push({ questionIndex: i, result: "Score: 0%" });
        }
      }

      let totalVoiceScore = 0.0;
      let validVoiceCount = 0;
      for (const v of voiceAnalysisResults) {
        const match = v.result.match(/Assessment Score:\s*([\d.]+)%/);
        if (match) {
          totalVoiceScore += parseFloat(match[1]);
          validVoiceCount++;
        }
      }
      const overallVoiceConfidenceScore = validVoiceCount > 0 ? Math.round(totalVoiceScore / validVoiceCount) : 0;

      // Step 3: Call GPT-4 to generate report and summarize voice confidence
      const gptPrompt = `You are an expert interview coach giving personal mock interview feedback to a jobseeker practicing for a ${specialty} position.
IMPORTANT: Address the user directly using "you" and "your".

Interview Transcripts:
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
        headers: { Authorization: `Bearer ${OPENAI_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          model: "gpt-4",
          messages: [
            { role: "system", content: "You are a friendly mock interview coach. Always respond with valid JSON only, no markdown." },
            { role: "user", content: gptPrompt }
          ],
          temperature: 0.7,
        }),
      });

      const gptResult = await gptResponse.json();
      let cleanedResponse = gptResult.choices[0].message.content.trim();
      if (cleanedResponse.startsWith("```json")) {
        cleanedResponse = cleanedResponse.replace(/```json\n?/g, "").replace(/```\n?/g, "");
      }

      const reportData = JSON.parse(cleanedResponse);

      const voiceCommentsArray = [
        {
          questionIndex: 0,
          result: reportData.mockVoiceComment || "Your delivery was steady and clear throughout the interview."
        }
      ];

      delete reportData.mockVoiceComment;

      await interviewRef.update({
        Report: reportData,
        VoiceToneAnalysis: voiceCommentsArray,
        VoiceToneRawResults: voiceAnalysisResults,
        VoiceConfidenceScore: overallVoiceConfidenceScore,
        ReportGeneratedAt: FieldValue.serverTimestamp(),
      });

      return { success: true, report: reportData };
    } catch (error) {
      throw new HttpsError("internal", error.message);
    }
  }
);