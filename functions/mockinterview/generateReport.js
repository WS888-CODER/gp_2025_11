import * as v2 from "firebase-functions/v2";
import { getFirestore } from "firebase-admin/firestore";
import { FieldValue } from "firebase-admin/firestore";
import FormData from "form-data";
import fetch from "node-fetch";

/* ===================== CONFIGURATION ===================== */

function getOpenAIKey() {
  return process.env.OPENAI_API_KEY || "";
}

/* ===================== MAIN FUNCTION ===================== */

export const generateMockInterviewReport = v2.https.onCall(
  { 
    region: "us-central1", 
    memory: "1GiB", 
    timeoutSeconds: 540,
    secrets: ["OPENAI_API_KEY"]  // ← ADD THIS LINE!
  },
  async (request) => {
    try {
      const { mockInterviewID } = request.data;

      if (!mockInterviewID) {
        throw new Error("Missing mockInterviewID");
      }

      console.log(`✅ Generating report for interview: ${mockInterviewID}`);

      // Step 1: Get interview data from Firestore
      const db = getFirestore();
      const interviewDoc = await db
        .collection("MockInterviews")
        .doc(mockInterviewID)
        .get();

      if (!interviewDoc.exists) {
        throw new Error("Interview not found");
      }

      const interviewData = interviewDoc.data();
      const questions = interviewData.Questions || [];
      const answerURLs = interviewData.AnswersRecordsURL || [];  // ⬅️ FIXED: Correct field name
      const specialty = interviewData.Specialty || "";

      console.log(`📊 Found ${questions.length} questions and ${answerURLs.length} answers`);

      // Step 2: Transcribe audio answers using Whisper API
      console.log("🎤 Transcribing audio...");
      const transcripts = await transcribeAnswers(answerURLs);

      // Step 3: Analyze answers using GPT-4
      console.log("🤖 Analyzing with GPT-4...");
      const analysis = await analyzeWithGPT(transcripts, questions, specialty);

      // Step 4: Voice tone analysis placeholder (SER model - to be added later)
      const voiceAnalysis = {
        available: false,
        message: "Voice tone analysis will be available soon",
      };

      // Step 5: Build final report
      const report = {
        strengths: analysis.strengths || [],
        weaknesses: analysis.weaknesses || [],
        advice: analysis.advice || [],
        voiceToneAnalysis: voiceAnalysis,
        generatedAt: FieldValue.serverTimestamp(),
      };

      // Step 6: Save report to Firestore
      await db.collection("MockInterviews").doc(mockInterviewID).update({
        Report: report,  // ⬅️ Capital R to match your schema
      });

      console.log("✅ Report generated successfully");

      return { success: true, report };
    } catch (error) {
      console.error("❌ Error generating report:", error);
      throw new v2.https.HttpsError("internal", `Report generation failed: ${error.message}`);
    }
  }
);

/* ===================== HELPER FUNCTIONS ===================== */

async function transcribeAnswers(answerURLs) {
  const OPENAI_KEY = getOpenAIKey();
  console.log("🔑 API Key exists:", !!OPENAI_KEY);
  console.log("🔑 API Key length:", OPENAI_KEY?.length);
  console.log("🔑 API Key starts with:", OPENAI_KEY?.substring(0, 7));
  if (!OPENAI_KEY) {
    throw new Error("OpenAI API key not configured");
  }

  const transcripts = [];

  for (let i = 0; i < answerURLs.length; i++) {
    const audioURL = answerURLs[i];
    
    if (!audioURL || audioURL.trim() === "") {
      console.log(`⏭️ Skipping empty answer ${i}`);
      transcripts.push({
        questionIndex: i,
        transcript: "[No answer recorded]",
      });
      continue;
    }

    try {
      console.log(`📥 Downloading audio ${i + 1}/${answerURLs.length}...`);
      
      // Download audio file from URL
      const audioResponse = await fetch(audioURL);
      if (!audioResponse.ok) {
        throw new Error(`Failed to download audio: ${audioResponse.statusText}`);
      }
      
      const audioBuffer = await audioResponse.buffer();
      console.log(`✅ Downloaded ${audioBuffer.length} bytes`);

      // Call Whisper API for transcription
      const formData = new FormData();
      formData.append("file", audioBuffer, {
        filename: `audio_${i}.m4a`,
        contentType: "audio/m4a",
      });
      formData.append("model", "whisper-1");

      console.log(`🎤 Calling Whisper API for question ${i + 1}...`);
      
      const response = await fetch(
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

      if (!response.ok) {
        const errorText = await response.text();
        console.error(`❌ Whisper API error for question ${i}: ${errorText}`);
        transcripts.push({
          questionIndex: i,
          transcript: "[Transcription failed]",
        });
        continue;
      }

      const result = await response.json();
      console.log(`✅ Transcribed question ${i + 1}: ${result.text.substring(0, 50)}...`);

      transcripts.push({
        questionIndex: i,
        transcript: result.text || "[No transcription]",
      });
    } catch (error) {
      console.error(`❌ Error transcribing answer ${i}:`, error);
      transcripts.push({
        questionIndex: i,
        transcript: "[Transcription error]",
      });
    }
  }

  return transcripts;
}

async function analyzeWithGPT(transcripts, questions, specialty) {
  const OPENAI_KEY = getOpenAIKey();

  // Build the prompt
  const questionsAndAnswers = transcripts
    .map((t) => {
      const question = questions[t.questionIndex];
      return `
Question ${t.questionIndex + 1} (${question.type || 'general'}):
${question.text}

Answer:
${t.transcript}
`;
    })
    .join("\n---\n");

  const prompt = `
You are an expert interview coach. Analyze this mock interview for a ${specialty} role.

${questionsAndAnswers}

Provide constructive feedback in JSON format with:
{
  "strengths": ["strength 1", "strength 2", "strength 3"],
  "weaknesses": ["weakness 1", "weakness 2"],
  "advice": ["actionable advice 1", "actionable advice 2", "actionable advice 3"]
}

Focus on:
- Content quality and relevance
- Communication clarity
- Technical knowledge (for domain questions)
- Behavioral examples (for psychometric questions)
- Areas for improvement

Be specific, constructive, and encouraging.
`;

  console.log(`🤖 Calling GPT-4 for analysis...`);

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENAI_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      temperature: 0.7,
      messages: [
        {
          role: "system",
          content: "You are an interview coach. Return only valid JSON.",
        },
        { role: "user", content: prompt },
      ],
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`GPT-4 API error: ${response.statusText} - ${errorText}`);
  }

  const result = await response.json();
  const content = result.choices[0].message.content;

  console.log(`✅ Got GPT-4 response`);

  // Parse JSON response
  const cleanContent = content.replace(/```json|```/g, "").trim();
  const analysis = JSON.parse(cleanContent);

  return analysis;
}