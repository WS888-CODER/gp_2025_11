import express from "express";
import OpenAI from "openai";
import * as functions from "firebase-functions";
import * as v2 from "firebase-functions/v2";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import nodemailer from "nodemailer";
import mammoth from "mammoth";
import path from "path";
import os from "os";
import fs from "fs";
import PDFDocument from "pdfkit";
import { generateInterviewQuestions } from "./interview/generateQuestions.js";

// ============================================
// 🔧 Initialize Services
// ============================================
const app = express();
app.use(express.json());

// Initialize Firebase Admin (NEW WAY)
if (getApps().length === 0) {
  initializeApp();
}
const db = getFirestore();

async function deleteByQuery(query) {
  const snap = await query.get();
  if (snap.empty) return;

  const batch = db.batch();
  snap.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
}

// ============================================
// 📧 EMAIL CONFIGURATION
// ============================================
const EMAIL_USER = "JadeerGp2025@gmail.com";
const ADMIN_EMAIL = "walaasaif47@gmail.com";
const EMAIL_APP_PASSWORD = "yfmitnbrrqwxfhvu";

const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: EMAIL_USER,
    pass: EMAIL_APP_PASSWORD,
  },
});

// ============================================
// 📧 EMAIL FUNCTIONS
// ============================================

/**
 * 1️⃣ Send OTP to Admin (Login)
 */
export const sendAdminOtp = functions.https.onCall(async (data, context) => {
  console.log("📥 Admin OTP - Full data:", data);

  const actualData = data.data || data;
  const email = actualData.email || actualData["email"] || "";
  const otp = actualData.otp || actualData["otp"] || "";

  console.log("📧 Email:", email);
  console.log("🔢 OTP:", otp);

  if (!email || !otp) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Email and OTP are required"
    );
  }

  try {
    const userSnapshot = await admin
      .firestore()
      .collection("Users")
      .where("Email", "==", email)
      .where("UserType", "==", "Admin")
      .limit(1)
      .get();

    if (userSnapshot.empty) {
      throw new functions.https.HttpsError(
        "not-found",
        "User not found or not an admin"
      );
    }

    const mailOptions = {
      from: `"Jadeer Admin" <${EMAIL_USER}>`,
      to: email,
      subject: "Verification Code - Jadeer Admin Panel",
      html: `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f5f5f5;">
          <div style="background-color: white; padding: 40px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1);">
            <div style="text-align: center; margin-bottom: 30px;">
              <h1 style="color: #4A5FBC; margin: 0; font-size: 28px;">🔐 Jadeer Admin</h1>
              <p style="color: #666; margin-top: 10px;">Smart Recruitment Management System</p>
            </div>
            <div style="text-align: center;">
              <h2 style="color: #333; font-size: 20px; margin-bottom: 20px;">Your Verification Code</h2>
              <div style="background: linear-gradient(135deg, #4A5FBC 0%, #FF7B7B 100%); padding: 20px; border-radius: 8px; margin: 30px 0;">
                <p style="color: white; font-size: 36px; font-weight: bold; letter-spacing: 8px; margin: 0; font-family: 'Courier New', monospace;">${otp}</p>
              </div>
              <div style="background-color: #fff3cd; border: 1px solid #ffc107; border-radius: 5px; padding: 15px; margin: 20px 0;">
                <p style="color: #856404; margin: 0; font-size: 14px;">⏱️ This code is valid for <strong>2 minutes only</strong></p>
              </div>
              <p style="color: #666; font-size: 14px; line-height: 1.6;">If you didn't request this code, please ignore this message.<br>Do not share this code with anyone.</p>
            </div>
            <div style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #eee; text-align: center;">
              <p style="color: #999; font-size: 12px; margin: 5px 0;">© 2025 Jadeer - All Rights Reserved</p>
            </div>
          </div>
        </div>
      `,
    };

    await transporter.sendMail(mailOptions);
    console.log(`✅ OTP sent to admin: ${email}`);

    return { success: true, message: "Verification code sent successfully" };
  } catch (error) {
    console.error("❌ Error sending admin OTP:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to send email: " + error.message
    );
  }
});

/**
 * 2️⃣ Send OTP during Signup (Company & JobSeeker)
 */
export const sendSignupOtp = functions.https.onCall(async (data, context) => {
  console.log("📥 Signup OTP - Full data:", data);

  const actualData = data.data || data;
  const email = actualData.email || actualData["email"] || "";
  const otp = actualData.otp || actualData["otp"] || "";

  if (!email || !otp) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Email and OTP are required"
    );
  }

  try {
    const mailOptions = {
      from: `"Jadeer Recruitment" <${EMAIL_USER}>`,
      to: email,
      subject: "Email Verification - Welcome to Jadeer!",
      html: `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f5f5f5;">
          <div style="background-color: white; padding: 40px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1);">
            <div style="text-align: center; margin-bottom: 30px;">
              <h1 style="color: #4A5FBC; margin: 0; font-size: 28px;">🎉 Welcome to Jadeer!</h1>
              <p style="color: #666; margin-top: 10px;">Smart Recruitment Management System</p>
            </div>
            <div style="text-align: center;">
              <h2 style="color: #333; font-size: 20px; margin-bottom: 20px;">Verify Your Email</h2>
              <p style="color: #666; font-size: 14px; margin-bottom: 20px;">Thank you for signing up! Please use the code below to verify your email address.</p>
              <div style="background: linear-gradient(135deg, #4A5FBC 0%, #FF7B7B 100%); padding: 20px; border-radius: 8px; margin: 30px 0;">
                <p style="color: white; font-size: 36px; font-weight: bold; letter-spacing: 8px; margin: 0; font-family: 'Courier New', monospace;">${otp}</p>
              </div>
              <div style="background-color: #fff3cd; border: 1px solid #ffc107; border-radius: 5px; padding: 15px; margin: 20px 0;">
                <p style="color: #856404; margin: 0; font-size: 14px;">⏱️ This code is valid for <strong>2 minutes only</strong></p>
              </div>
              <p style="color: #666; font-size: 14px; line-height: 1.6;">If you didn't create an account, please ignore this message.<br>Do not share this code with anyone.</p>
            </div>
            <div style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #eee; text-align: center;">
              <p style="color: #999; font-size: 12px; margin: 5px 0;">© 2025 Jadeer - All Rights Reserved</p>
            </div>
          </div>
        </div>
      `,
    };

    await transporter.sendMail(mailOptions);
    console.log(`✅ Signup OTP sent to: ${email}`);

    return { success: true, message: "Verification code sent successfully" };
  } catch (error) {
    console.error("❌ Error sending signup OTP:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to send email: " + error.message
    );
  }
});

/**
 * 3️⃣ Notify Admin about new Company registration
 */
export const notifyAdminNewCompany = functions.https.onCall(
  async (data, context) => {
    console.log("📥 Admin notification - Full data:", data);

    const actualData = data.data || data;
    const companyName =
      actualData.companyName || actualData["companyName"] || "";
    const companyEmail =
      actualData.companyEmail || actualData["companyEmail"] || "";

    if (!companyName || !companyEmail) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Company name and email are required"
      );
    }

    try {
      const mailOptions = {
        from: `"Jadeer System" <${EMAIL_USER}>`,
        to: ADMIN_EMAIL,
        subject: "🚀 New Company Registration - Action Required",
        html: `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f5f5f5;">
          <div style="background-color: white; padding: 40px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1);">
            <h2 style="color: #333; font-size: 20px;">New Company Registered!</h2>
            <p><strong>Company:</strong> ${companyName}</p>
            <p><strong>Email:</strong> ${companyEmail}</p>
            <p>Please review documents in the admin dashboard.</p>
          </div>
        </div>
      `,
      };

      await transporter.sendMail(mailOptions);
      console.log(`✅ Admin notified about: ${companyName}`);

      return { success: true, message: "Admin notification sent successfully" };
    } catch (error) {
      console.error("❌ Error sending admin notification:", error);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to send notification: " + error.message
      );
    }
  }
);

/**
 * 4️⃣ Send Company Document Request Email
 */
export const sendCompanyDocumentRequest = functions.https.onCall(
  async (data, context) => {
    console.log("📥 Document request - Full data:", data);

    const actualData = data.data || data;
    const email = actualData.email || actualData["email"] || "";
    const companyName =
      actualData.companyName || actualData["companyName"] || "";

    if (!email) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Email is required"
      );
    }

    try {
      const mailOptions = {
        from: `"Jadeer Recruitment" <${EMAIL_USER}>`,
        to: email,
        subject: "Action Required - Company Verification Documents",
        html: `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f5f5f5;">
          <div style="background-color: white; padding: 40px; border-radius: 10px;">
            <p>Dear ${companyName || "Company Representative"},</p>
            <p>Please provide us with an Employment Letter from your company to verify your employment status. The letter should include your name, job title, and employment start date.</p>
            <p>You will receive an email from Jadeer informing you whether your registration has been accepted or rejected.</p>
          </div>
        </div>
      `,
      };

      await transporter.sendMail(mailOptions);
      console.log(`✅ Document request sent to: ${email}`);

      return {
        success: true,
        message: "Document request email sent successfully",
      };
    } catch (error) {
      console.error("❌ Error sending document request:", error);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to send email: " + error.message
      );
    }
  }
);

/**
 * 🔔 Notify Company of Account Status Change (Accepted/Rejected)
 */
export const notifyCompanyStatusChange = functions.https.onCall(
  async (data, context) => {
    console.log("📥 Company status notification - Full data:", data);

    const actualData = data.data || data;
    const companyEmail =
      actualData.companyEmail || actualData["companyEmail"] || "";
    const companyName =
      actualData.companyName || actualData["companyName"] || "";
    const status = actualData.status || actualData["status"] || "";

    if (!companyEmail || !status) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Company email and status are required"
      );
    }

    if (status !== "Accepted" && status !== "Rejected") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Status must be either Accepted or Rejected"
      );
    }

    console.log(
      `📧 Sending ${status} email to ${companyName} (${companyEmail})`
    );

    try {
      let mailOptions;

      if (status === "Accepted") {
        // ✅ Acceptance Email
        mailOptions = {
          from: `"Jadeer Recruitment" <${EMAIL_USER}>`,
          to: companyEmail,
          subject: "Your Registration Has Been Accepted - Jadeer",
          html: `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f5f5f5;">
            <div style="background-color: white; padding: 40px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1);">
              <div style="text-align: center; margin-bottom: 30px;">
                <h1 style="color: #4A5FBC; margin: 0; font-size: 28px;">Jadeer</h1>
                <p style="color: #666; margin-top: 10px;">Smart Recruitment Management System</p>
              </div>
              
              <div style="background: linear-gradient(135deg, #4A5FBC 0%, #FF7B7B 100%); padding: 30px; border-radius: 8px; margin: 30px 0;">
                <h2 style="color: white; margin: 0; font-size: 22px; text-align: center;">Registration Accepted</h2>
              </div>
              
              <div style="padding: 20px 0;">
                <p style="color: #333; font-size: 16px; line-height: 1.8;">Dear ${companyName},</p>
                
                <p style="color: #333; font-size: 16px; line-height: 1.8;">
                  We are pleased to inform you that <strong style="color: #4A5FBC;">your registration has been accepted</strong> on Jadeer application.
                </p>
                
                <p style="color: #333; font-size: 16px; line-height: 1.8;">
                  You can now access your account and use all application features.
                </p>

                <div style="text-align: center; margin: 30px 0;">
                  <p style="background-color: #4A5FBC; color: white; padding: 15px 40px; border-radius: 8px; display: inline-block; font-size: 16px; font-weight: bold; margin: 0;">
                    You can login now
                  </p>
                </div>
                
                <p style="color: #333; font-size: 16px; margin-top: 30px; line-height: 1.8;">
                  Best regards,<br>
                  <strong style="color: #4A5FBC;">Jadeer Team</strong>
                </p>
              </div>
              
              <div style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #eee; text-align: center;">
                <p style="color: #999; font-size: 12px; margin: 5px 0;">© 2025 Jadeer - All Rights Reserved</p>
              </div>
            </div>
          </div>
        `,
        };
      } else {
        // ❌ Rejection Email
        mailOptions = {
          from: `"Jadeer Recruitment" <${EMAIL_USER}>`,
          to: companyEmail,
          subject: "Registration Status - Jadeer Application",
          html: `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f5f5f5;">
            <div style="background-color: white; padding: 40px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1);">
              <div style="text-align: center; margin-bottom: 30px;">
                <h1 style="color: #4A5FBC; margin: 0; font-size: 28px;">Jadeer</h1>
                <p style="color: #666; margin-top: 10px;">Smart Recruitment Management System</p>
              </div>
              
              <div style="background-color: #fff3cd; border-left: 4px solid #FF7B7B; padding: 20px; margin: 30px 0;">
                <h2 style="color: #856404; margin: 0 0 10px 0; font-size: 18px;">Registration Not Accepted</h2>
              </div>
              
              <div style="padding: 20px 0;">
                <p style="color: #333; font-size: 16px; line-height: 1.8;">Dear ${companyName},</p>
                
                <p style="color: #333; font-size: 16px; line-height: 1.8;">
                  We apologize for not being able to accept your registration on Jadeer application.
                </p>
                
                <p style="color: #333; font-size: 16px; line-height: 1.8;">
                  <strong>Reason:</strong> The submitted documents are insufficient or incorrect.
                </p>
                
                <div style="background-color: #e3f2fd; border-radius: 8px; padding: 20px; margin: 30px 0;">
                  <p style="color: #1976d2; font-size: 15px; margin: 0; line-height: 1.6;">
                    <strong>💡 Note:</strong><br>
                    Please ensure all required documents are complete, valid, and match your company's official records before submitting a new registration.
                  </p>
                </div>

                <p style="color: #333; font-size: 16px; margin-top: 30px; line-height: 1.8;">
                  Best regards,<br>
                  <strong style="color: #4A5FBC;">Jadeer Team</strong>
                </p>
              </div>
              
              <div style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #eee; text-align: center;">
                <p style="color: #999; font-size: 12px; margin: 5px 0;">© 2025 Jadeer - All Rights Reserved</p>
              </div>
            </div>
          </div>
        `,
        };
      }

      await transporter.sendMail(mailOptions);
      console.log(`✅ ${status} email sent to ${companyEmail}`);

      return { success: true, message: `${status} email sent successfully` };
    } catch (error) {
      console.error(`❌ Error sending ${status} email:`, error);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to send email: " + error.message
      );
    }
  }
);

// ============================================
// 🤖 OPENAI API (SAFE FIXED VERSION)
// ============================================
export const generateJobPost = functions.https.onRequest(async (req, res) => {
  try {
    const { title, position, speciality } = req.body;

    // Initialize OpenAI with environment variable (Firebase injects secret automatically)
    const openai = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
    });

    const prompt = `You are an expert HR professional writing job descriptions. Create a comprehensive, professional, and engaging job description for the following role:

Job Title: "${title}"
Position Level: "${position || "Not specified"}"
Speciality/Field: "${speciality || "Not specified"}"

Write a detailed job description (approximately 300-500 words) that includes:

1. **Role Overview** (5-6 sentences): Clear, detailed description of what this position entails, its importance and impact, and what success looks like in this role. Focus on the value this position brings and the exciting challenges it offers.

2. **Key Responsibilities** (8-12 detailed bullet points): Specific, actionable responsibilities that match the position level and speciality. Be concrete and detailed. For senior positions, include leadership, strategic planning, and decision-making responsibilities. For junior positions, include learning opportunities, mentorship, and growth paths. Make each point substantial and meaningful.

3. **Closing Statement** (2-3 sentences): Encouraging, inclusive call-to-action that invites candidates to apply and highlights what makes this opportunity special.

CRITICAL guidelines:
- DO NOT invent or mention ANY company names, company details, or specific organizations
- Keep it general and focused on the role itself
- Match the tone and expectations to the position level (Junior vs Senior vs Lead, etc.)
- Make responsibilities highly specific to the speciality field
- Be detailed and thorough - use the full word count
- Use professional yet engaging language
- Focus on what makes this role attractive and impactful
- Avoid generic corporate jargon
- Write in a warm, inclusive tone
- Make it compelling and inspiring

Note: Do NOT include qualifications, requirements, or "what we offer" sections as those are handled separately.

Provide ONLY the job description text without any markdown headers, labels, bold text, asterisks, or meta-commentary. Write it as a flowing, well-structured description with clear paragraphs.`;

    const response = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "system",
          content:
            "You are an expert HR professional who writes compelling, detailed job descriptions that attract top talent.",
        },
        {
          role: "user",
          content: prompt,
        },
      ],
      max_tokens: 2000,
      temperature: 0.7,
    });

    const text = response.choices[0].message.content.trim();
    res.status(200).json({ job_post: text });
  } catch (error) {
    console.error("❌ Error generating job post:", error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================
// 🤖 CV ENHANCEMENT WITH AI
// ============================================

/**
 * 6️⃣ Enhance CV with OpenAI GPT-4 Turbo (Gen 2) - FIXED VERSION
 */
export const enhanceCV = v2.https.onCall(
  { memory: "1GiB", timeoutSeconds: 540 },
  async (request) => {
    console.log("📥 CV Enhancement request (Gen 2)");
    console.log("📋 Auth UID:", request.auth?.uid || "NOT authenticated");
    console.log("📋 Request data:", request.data);

    const cvHistoryId = request.data.cvHistoryId || "";
    const additionalSections = request.data.additionalSections || null;

    console.log("📝 CVHistoryID:", cvHistoryId);
    console.log("📝 Has additional sections:", !!additionalSections);

    if (!cvHistoryId || cvHistoryId.trim() === "") {
      throw new v2.https.HttpsError(
        "invalid-argument",
        "cvHistoryId is required"
      );
    }

    if (request.auth) {
      console.log("✅ User authenticated:", request.auth.uid);
    } else {
      console.warn("⚠️ Proceeding without auth (TESTING ONLY)");
    }

    try {
      // Get CV data from Firestore
      const cvDoc = await admin
        .firestore()
        .collection("CVHistory")
        .doc(cvHistoryId)
        .get();

      if (!cvDoc.exists) {
        throw new v2.https.HttpsError("not-found", "CV not found");
      }

      const cvData = cvDoc.data();
      const oldCVText = cvData.OldCVText || "";
      const jobTitle = cvData.JobTitle || "";
      const jobDescription = cvData.Description || "";
      const userId = cvData.UserID || request.auth?.uid || "unknown";

      if (!oldCVText) {
        throw new v2.https.HttpsError(
          "failed-precondition",
          "CV text not extracted yet"
        );
      }

      console.log(`📄 Enhancing CV for job: ${jobTitle || "Not specified"}`);
      console.log(`📄 Has job description: ${!!jobDescription}`);
      console.log(`📊 CV text length: ${oldCVText.length} characters`);

      // Initialize OpenAI
      const openai = new OpenAI({
        apiKey: process.env.OPENAI_API_KEY,
      });

      // Build the prompt
      let additionalSectionsText = "";
      if (additionalSections) {
        additionalSectionsText = `

---

### ADDITIONAL SECTIONS PROVIDED BY USER:
The user has provided the following additional information to be included in their CV:

${JSON.stringify(additionalSections, null, 2)}

IMPORTANT: Include these additional sections in the enhanced CV. Merge them with any existing information from the original CV text.

---`;
      }

      const prompt = `You are an expert career coach and CV optimization assistant.

CRITICAL RULES - READ CAREFULLY:
1. ONLY use information that EXISTS in the original CV or additional sections provided
2. DO NOT invent, create, or generate ANY fake data (names, companies, dates, skills, etc.)
3. If a section is empty in the original CV AND no additional data was provided for it, DO NOT include that section in the output
4. If ALL sections are empty, return ONLY empty arrays/objects for each section
5. You can improve grammar and formatting of EXISTING content, but NEVER add new content that wasn't there

CV TAILORING RULES (when job title/description is provided):

1. SMART SELECTION:
   - Include items that are RELEVANT to the target job
   - It's OK to REMOVE or OMIT items that are not relevant to the position
   - Keep major achievements (awards, patents, publications, significant recognitions) even if not directly related
   - Keep all education and core work experience
   - Can remove: minor projects, irrelevant volunteer work, hobbies that don't add value, outdated skills

2. CONTENT OPTIMIZATION:
   - For relevant items: Write detailed, impactful descriptions (2-3 bullet points)
   - For less relevant items you decide to keep: Make them brief (1 short line)
   - Rewrite descriptions to emphasize skills/outcomes that match the job requirements
   - Use keywords from the job description where naturally applicable

3. ONE-PAGE FOCUS:
   - Be selective - quality over quantity
   - Keep descriptions concise and impactful
   - Use bullet points, not paragraphs
   - Remove fluff and redundancy
   - Aim to keep the CV content that would fit on approximately one page

4. WHEN NO JOB IS PROVIDED:
   - Keep ALL sections and items
   - Just enhance grammar, formatting, and professionalism
   - Don't remove or condense anything

5. IN SUGGESTIONS (what was improved):
   - Provide a high-level summary of the changes you made to enhance this CV
   - List the main improvements and enhancements applied (e.g., "Restructured work experience for better readability", "Enhanced summary with key achievements")
   - Mention if you optimized any sections for ATS or the target job
   - Be clear and concise about what was actually changed
   - Maximum 5 items, but you can provide less if not needed

Enhance the following CV text to make it:
- Professional and grammatically correct
- Optimized for ATS (Applicant Tracking Systems)
- Concise and well-structured
- Tailored for the target job if provided
- In the suggestions field, provide a summary of what improvements you made to this CV (high-level changes only)
- Focus on what YOU changed, not what the user should do in the future

---

TARGET JOB INFORMATION:
Job Title: ${jobTitle || "Not specified"}
${jobDescription ? `Job Description: ${jobDescription}` : ""}
${
  !jobTitle && !jobDescription
    ? "(No specific job provided - enhance CV for general use)"
    : ""
}

Original CV Text:
${oldCVText}
${additionalSectionsText}

---

### OUTPUT REQUIREMENTS:
Return ONLY valid JSON in the following structure:

{
  "enhanced_cv": [
    {
      "section": "PersonalInformation",
      "content": {
        "full_name": "...",
        "email": "...",
        "phone": "...",
        "location": "...",
        "links": ["..."]
      }
    },
    {
      "section": "Summary",
      "content": "..."
    },
    {
      "section": "Experience",
      "content": [
        {"title": "...", "company": "...", "years": "...", "description": "..."}
      ]
    },
    {
      "section": "Education",
      "content": [
        {"degree": "...", "institution": "...", "years": "..."}
      ]
    },
    {
      "section": "Skills",
      "content": ["Skill1", "Skill2", "Skill3"]
    },
    {
      "section": "Projects",
      "content": [
        {"name": "...", "year": "..."}
      ]
    },
    {
      "section": "Awards",
      "content": [
        {"name": "...", "issuer": "...", "year": "..."}
      ]
    },
    {
      "section": "Publications",
      "content": [
        {"title": "...", "publisher": "...", "year": "..."}
      ]
    },
    {
      "section": "Patents",
      "content": [
        {"title": "...", "patent_number": "...", "year": "..."}
      ]
    },
    {
      "section": "Research",
      "content": [
        {"title": "...", "institution": "...", "years": "..."}
      ]
    },
    {
      "section": "Certifications",
      "content": [
        {"name": "...", "issuer": "...", "year": "..."}
      ]
    },
    {
      "section": "Internships",
      "content": [
        {"title": "...", "company": "...", "years": "..."}
      ]
    },
    {
      "section": "VolunteerWork",
      "content": [
        {"role": "...", "organization": "...", "years": "..."}
      ]
    },
    {
      "section": "Courses",
      "content": [
        {"name": "...", "institution": "...", "year": "..."}
      ]
    },
    {
      "section": "Training",
      "content": [
        {"name": "...", "provider": "...", "year": "..."}
      ]
    },
    {
      "section": "Workshops",
      "content": [
        {"name": "...", "organizer": "...", "year": "..."}
      ]
    },
    {
      "section": "Conferences",
      "content": [
        {"name": "...", "role": "...", "year": "..."}
      ]
    },
    {
      "section": "Achievements",
      "content": [
        {"name": "...", "year": "..."}
      ]
    },
    {
      "section": "ProfessionalMemberships",
      "content": [
        {"organization": "...", "role": "...", "years": "..."}
      ]
    },
    {
      "section": "Portfolio",
      "content": [
        {"name": "...", "url": "..."}
      ]
    },
    {
      "section": "Languages",
      "content": [
        {"language": "...", "proficiency": "..."}
      ]
    },
    {
      "section": "ExtracurricularActivities",
      "content": [
        {"activity": "...", "role": "...", "years": "..."}
      ]
    },
    {
      "section": "Interests",
      "content": ["Interest1", "Interest2", "Interest3"]
    }
  ],
  "suggestions": [
    "...",
    "...",
    "...",
    "...",
    "..."
  ]
}

IMPORTANT REMINDERS:
- If a section has NO data in the original CV or additional sections, use empty values:
  * For PersonalInformation: {"full_name": "", "email": "", "phone": "", "location": "", "links": []}
  * For Summary: ""
  * For arrays (Experience, Education, Skills, Certifications, Languages): []
- NEVER create fake examples like "John Doe", "ABC Corp", "Project Manager", etc.
- ONLY enhance what actually exists in the provided data

Do not include explanations or commentary outside this JSON.`;

      // Call OpenAI
      const response = await openai.chat.completions.create({
        model: "gpt-4o",
        messages: [
          {
            role: "system",
            content:
              "You are a professional CV enhancement assistant. Always return valid JSON. CRITICAL: Never invent or create fake data - only use information that exists in the provided CV. If sections are empty, return empty values, NOT fake examples.",
          },
          {
            role: "user",
            content: prompt,
          },
        ],
        response_format: { type: "json_object" },
        temperature: 0.7,
        max_tokens: 4000,
      });

      const gptResponse = response.choices[0].message.content;
      console.log("✅ Got response from OpenAI");

      // Parse JSON response
      const parsedData = JSON.parse(gptResponse);
      const enhanced_cv = parsedData.enhanced_cv || [];
      const suggestions = parsedData.suggestions || [];

      console.log(`📝 Enhanced CV sections: ${enhanced_cv.length}`);
      console.log(`💡 Suggestions count: ${suggestions.length}`);

      // Update Firestore with native objects/arrays
      await db.collection("CVHistory").doc(cvHistoryId).update({
        NewCVText: enhanced_cv,
        Suggestions: suggestions,
      });

      console.log(`✅ CV enhanced and saved for: ${cvHistoryId}`);

      // 🔥 Generate PDF automatically after enhancement
      console.log(`📄 Starting PDF generation for: ${cvHistoryId}`);

      try {
        // Create PDF directly
        const pdfBuffer = await createProfessionalCV(enhanced_cv);
        console.log(`✅ PDF buffer created, size: ${pdfBuffer.length} bytes`);

        // Upload to Storage
        const bucket = admin.storage().bucket();
        const fileName = `${userId}_${cvHistoryId}.pdf`;
        const filePath = `NewCV/${fileName}`;
        const file = bucket.file(filePath);

        await file.save(pdfBuffer, {
          metadata: {
            contentType: "application/pdf",
          },
        });
        console.log(`✅ PDF uploaded to Storage: ${filePath}`);

        // Make public
        await file.makePublic();
        const pdfUrl = `https://storage.googleapis.com/${bucket.name}/${filePath}`;
        console.log(`✅ PDF URL: ${pdfUrl}`);

        // Update Firestore
        await admin
          .firestore()
          .collection("CVHistory")
          .doc(cvHistoryId)
          .update({
            NewCVURL: pdfUrl,
            PDFGeneratedAt: FieldValue.serverTimestamp(),
          });
        console.log(`✅ Firestore updated with PDF URL`);

        return {
          success: true,
          message: "CV enhanced and PDF generated successfully",
          sectionsCount: enhanced_cv.length,
          suggestionsCount: suggestions.length,
          pdfUrl: pdfUrl,
        };
      } catch (pdfError) {
        console.error(`❌ PDF generation error:`, pdfError);

        // Still return success for CV enhancement
        return {
          success: true,
          message: "CV enhanced successfully (PDF generation failed)",
          sectionsCount: enhanced_cv.length,
          suggestionsCount: suggestions.length,
          pdfError: pdfError.message,
        };
      }
    } catch (error) {
      console.error("❌ Error enhancing CV:", error);
      throw new v2.https.HttpsError(
        "internal",
        `Failed to enhance CV: ${error.message}`
      );
    }
  }
);

/**
 * 7️⃣ Detect Missing Sections in CV
 */
export const detectMissingSections = v2.https.onCall(
  { memory: "512MiB", timeoutSeconds: 60 },
  async (request) => {
    console.log("📥 Detect Missing Sections request");
    console.log("📋 Request data:", request.data);

    const cvHistoryId = request.data.cvHistoryId || "";

    if (!cvHistoryId || cvHistoryId.trim() === "") {
      throw new v2.https.HttpsError(
        "invalid-argument",
        "cvHistoryId is required"
      );
    }

    try {
      // Get CV data from Firestore
      const cvDoc = await admin
        .firestore()
        .collection("CVHistory")
        .doc(cvHistoryId)
        .get();

      if (!cvDoc.exists) {
        throw new v2.https.HttpsError("not-found", "CV not found");
      }

      const cvData = cvDoc.data();
      const oldCVText = cvData.OldCVText || "";
      const jobTitle = cvData.JobTitle || "";
      const jobDescription = cvData.Description || "";
      const hasJob = jobTitle.trim() !== "" || jobDescription.trim() !== "";

      if (!oldCVText) {
        throw new v2.https.HttpsError(
          "failed-precondition",
          "CV text not extracted yet"
        );
      }

      console.log(`📄 Analyzing CV for missing sections`);
      console.log(`📊 CV text length: ${oldCVText.length} characters`);
      console.log(`💼 Has job: ${hasJob}`);

      // If CV is blank or only contains page numbers, return all sections as missing
      if (oldCVText.trim().length < 20) {
        console.log(`⚠️ CV is blank (only ${oldCVText.trim().length} chars: "${oldCVText.trim()}"), returning all sections as missing`);
        return {
          success: true,
          missingSections: [
            "PersonalInformation",
            "Summary",
            "Experience",
            "Education",
            "Skills",
            "Certifications",
            "Languages"
          ],
          hasMissingSections: true,
          suggestedSkills: null,
        };
      }

      // Initialize OpenAI
      const openai = new OpenAI({
        apiKey: process.env.OPENAI_API_KEY,
      });

      // Build the detection prompt
      const prompt = `You are a CV analysis expert. Analyze the following CV text and determine which sections are COMPLETELY MISSING or EMPTY.

The CV should ideally contain these sections:
1. PersonalInformation (name, email, phone, location)
2. Summary (professional summary or objective)
3. Experience (work history)
4. Education (degrees, institutions)
5. Skills (technical and soft skills)
6. Certifications (professional certifications)
7. Languages (spoken languages and proficiency)

Review the CV text below and return the names of sections that are MISSING or have NO ACTUAL CONTENT.

IMPORTANT: If the CV has no text or is completely empty, return ALL seven sections as missing.

CRITICAL RULES:
- BE SMART about recognizing sections even WITHOUT explicit headers
- A section EXISTS if the information is present ANYWHERE in the CV, regardless of formatting

SPECIFIC DETECTION RULES:
- PersonalInformation EXISTS if you can find: name, email, phone, OR location in the CV (even without a "Personal Info" header)
  * Contact info at the top of a CV = PersonalInformation section EXISTS
- Summary EXISTS if there's a professional summary/objective paragraph (even without "Summary:" header)
- Experience EXISTS if there are job titles, company names, or work descriptions
- Education EXISTS if there are degree names, universities, or graduation years
- Skills EXISTS if there's a list of skills/technologies/competencies (even without "Skills:" header)
- Certifications EXISTS if there are certification names or credential mentions
- Languages EXISTS if languages are mentioned with or without proficiency levels

A section is MISSING if:
  * The content truly does not exist anywhere in the CV, OR
  * It has ONLY a header/title but NO actual content (e.g., "Skills:" with no skills listed)
  * Example: "Experience:" with no job entries = MISSING

A section EXISTS if:
  * It has actual content/data, even without a section header
  * Example: Contact info at top without "Personal Info:" header = EXISTS

CV Text:
${oldCVText}

---

Return ONLY valid JSON in this format:
{
  "missingSections": ["SectionName1", "SectionName2"]
}

Rules:
- Only include section names from the list above
- Use exact names: "PersonalInformation", "Summary", "Experience", "Education", "Skills", "Certifications", "Languages"
- If a section has actual content (not just a title), DO NOT include it
- If ALL sections have actual content, return an empty array: {"missingSections": []}
- Do not include explanations outside the JSON`;

      // Call OpenAI
      const response = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content:
              "You are a CV analysis assistant. Always return valid JSON.",
          },
          {
            role: "user",
            content: prompt,
          },
        ],
        response_format: { type: "json_object" },
        temperature: 0.3,
        max_tokens: 500,
      });

      const gptResponse = response.choices[0].message.content;
      console.log("✅ Got response from OpenAI");

      // Parse JSON response
      const parsedData = JSON.parse(gptResponse);
      const missingSections = parsedData.missingSections || [];

      console.log(
        `🔍 Missing sections detected: ${missingSections.join(", ") || "None"}`
      );

      // Generate suggested skills if there's a job
      let suggestedSkills = null;
      if (hasJob) {
        console.log(`🎯 Generating suggested skills for job`);

        const skillsPrompt = `You are a career expert. Based on the job information below, suggest 15-20 relevant skills that would be valuable for this position.

TARGET JOB:
Job Title: ${jobTitle || "Not specified"}
${jobDescription ? `Job Description: ${jobDescription}` : ""}

Return a list of specific, relevant skills. Include both technical skills and important soft skills for this role.
Focus on skills that are commonly required or highly valued for this position.

Return ONLY valid JSON in this format:
{
  "skills": ["Skill 1", "Skill 2", "Skill 3", ...]
}

Keep each skill concise (1-3 words). Return 15-20 skills.`;

        const skillsResponse = await openai.chat.completions.create({
          model: "gpt-4o-mini",
          messages: [
            {
              role: "system",
              content:
                "You are a career expert assistant. Always return valid JSON.",
            },
            {
              role: "user",
              content: skillsPrompt,
            },
          ],
          response_format: { type: "json_object" },
          temperature: 0.5,
          max_tokens: 800,
        });

        const skillsData = JSON.parse(
          skillsResponse.choices[0].message.content
        );
        suggestedSkills = skillsData.skills || [];
        console.log(`✅ Generated ${suggestedSkills.length} suggested skills`);
      }

      return {
        success: true,
        missingSections: missingSections,
        hasMissingSections: missingSections.length > 0,
        suggestedSkills: suggestedSkills,
      };
    } catch (error) {
      console.error("❌ Error detecting missing sections:", error);
      throw new v2.https.HttpsError(
        "internal",
        `Failed to detect missing sections: ${error.message}`
      );
    }
  }
);

/**
 * 8️⃣ Send Password Reset OTP
 */
export const sendPasswordResetOtp = functions.https.onCall(
  async (data, context) => {
    console.log("📥 Password reset OTP - Full data:", data);

    const actualData = data.data || data;
    const email = actualData.email || actualData["email"] || "";
    const otp = actualData.otp || actualData["otp"] || "";

    if (!email || !otp) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Email and OTP are required"
      );
    }

    try {
      const usersSnapshot = await admin
        .firestore()
        .collection("Users")
        .where("Email", "==", email.toLowerCase())
        .limit(1)
        .get();

      if (usersSnapshot.empty) {
        throw new functions.https.HttpsError("not-found", "Email not found");
      }

      const mailOptions = {
        from: `"Jadeer System" <${EMAIL_USER}>`,
        to: email,
        subject: "🔐 Password Reset Code - Jadeer",
        html: `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f5f5f5;">
          <div style="background-color: white; padding: 40px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1);">
            <div style="text-align: center; margin-bottom: 30px;">
              <h1 style="color: #4A5FBC; margin: 0; font-size: 28px;">🔐 Password Reset</h1>
              <p style="color: #666; margin-top: 10px;">Jadeer - Smart Recruitment System</p>
            </div>
            <div style="text-align: center;">
              <h2 style="color: #333; font-size: 20px; margin-bottom: 20px;">Your Reset Code</h2>
              <p style="color: #666; font-size: 16px; margin-bottom: 20px;">Enter this code in the app to reset your password.</p>
              <div style="background: linear-gradient(135deg, #4A5FBC 0%, #FF7B7B 100%); padding: 20px; border-radius: 8px; margin: 30px 0;">
                <p style="color: white; font-size: 36px; font-weight: bold; letter-spacing: 8px; margin: 0; font-family: 'Courier New', monospace;">${otp}</p>
              </div>
              <div style="background-color: #fff3cd; border: 1px solid #ffc107; border-radius: 5px; padding: 15px; margin: 20px 0;">
                <p style="color: #856404; margin: 0; font-size: 14px;">
                  ⏱️ This code is valid for <strong>2 minutes only</strong>
                </p>
              </div>
              <p style="color: #666; font-size: 14px; line-height: 1.6;">
                If you didn't request a password reset, please ignore this email. 
                Your password will remain unchanged.
              </p>
            </div>
            <div style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #eee; text-align: center;">
              <p style="color: #999; font-size: 12px; margin: 5px 0;">© 2025 Jadeer - All Rights Reserved</p>
            </div>
          </div>
        </div>
      `,
      };

      await transporter.sendMail(mailOptions);
      console.log(`✅ Password reset OTP sent to: ${email}`);

      return {
        success: true,
        message: "Password reset code sent successfully",
      };
    } catch (error) {
      console.error("❌ Error sending password reset OTP:", error);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to send password reset code: " + error.message
      );
    }
  }
);

/**
 * 8️⃣ Reset User Password + Unlock Account (Admin SDK)
 */
export const resetUserPassword = functions.https.onCall(
  async (data, context) => {
    console.log("📥 Reset password - Full data:", data);

    const actualData = data.data || data;
    const email = actualData.email || actualData["email"] || "";
    const newPassword =
      actualData.newPassword || actualData["newPassword"] || "";

    if (!email || !newPassword) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Email and new password are required"
      );
    }

    try {
      const userRecord = await admin.auth().getUserByEmail(email.toLowerCase());

      await admin.auth().updateUser(userRecord.uid, {
        password: newPassword,
      });

      await db.collection("Users").doc(userRecord.uid).update({
        failedLoginAttempts: 0,
        lastFailedLoginDate: null,
        accountLocked: false,
        mustResetPassword: false,
      });

      console.log(`Password updated and account unlocked for: ${email}`);

      return {
        success: true,
        message: "Password reset and account unlocked successfully",
      };
    } catch (error) {
      console.error("Error resetting password:", error);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to reset password: " + error.message
      );
    }
  }
);

export const deleteUserAccount = functions.https.onCall(
  async (data, context) => {
    console.log("📥 Delete user account - Full data:", data);

    const actualData = (data && data.data) || data || {};
    const userId = actualData.userId || actualData["userId"] || "";
    const userType = actualData.userType || actualData["userType"] || "";

    if (!userId || !userType) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "userId and userType are required."
      );
    }

    const requesterUid = context.auth?.uid;

    if (requesterUid && requesterUid !== userId) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "You can only delete your own account."
      );
    }

    try {
      const userDocRef = db.collection("Users").doc(userId);
      const userSnap = await userDocRef.get();

      let photoPath;
      let cvPath;

      if (userSnap.exists) {
        const userData = userSnap.data() || {};
        photoPath =
          userData.PhotoPath ||
          userData.photoPath ||
          userData.profilePhotoPath ||
          null;
        cvPath = userData.CVPath || userData.CvPath || userData.cvPath || null;
      }

      const deleteUserScopedCollection = async (collectionName, fieldNames) => {
        for (const field of fieldNames) {
          await deleteByQuery(
            db.collection(collectionName).where(field, "==", userId)
          );
        }
      };

      // User-scoped collections
      await deleteUserScopedCollection("CVHistory", ["UserID", "userID"]);
      await deleteUserScopedCollection("CVEnhancement", ["UserID", "userID"]);
      await deleteUserScopedCollection("MockInterview", ["UserID", "userID"]);
      await deleteUserScopedCollection("MockInterviews", ["UserID", "userID"]);
      await deleteUserScopedCollection("Interview", ["UserID", "userID"]);
      await deleteUserScopedCollection("Interviews", ["UserID", "userID"]);
      await deleteUserScopedCollection("ReportGenerator", ["UserID", "userID"]);
      await deleteUserScopedCollection("Reports", ["UserID", "userID"]);
      await deleteUserScopedCollection("WebSchedule", ["UserID", "userID"]);
      await deleteUserScopedCollection("WebSchedules", ["UserID", "userID"]);
      await deleteUserScopedCollection("Favorites", ["UserID", "userID"]);
      await deleteUserScopedCollection("Applications", ["UserID", "userID"]);
      await deleteUserScopedCollection("AIServiceRequests", [
        "UserID",
        "userID",
      ]);

      // Company-specific: delete its jobs and related data
      if (userType === "Company") {
        const jobQueries = [
          db.collection("Jobs").where("UserID", "==", userId),
          db.collection("Jobs").where("userId", "==", userId),
        ];

        for (const jobQuery of jobQueries) {
          const jobsSnap = await jobQuery.get();

          for (const jobDoc of jobsSnap.docs) {
            const jobId = jobDoc.id;

            await deleteByQuery(
              db.collection("Applications").where("JobID", "==", jobId)
            );
            await deleteByQuery(
              db.collection("Applications").where("jobID", "==", jobId)
            );

            await deleteByQuery(
              db.collection("MockInterviews").where("JobID", "==", jobId)
            );
            await deleteByQuery(
              db.collection("MockInterviews").where("jobID", "==", jobId)
            );

            await deleteByQuery(
              db.collection("Interviews").where("JobID", "==", jobId)
            );
            await deleteByQuery(
              db.collection("Interviews").where("jobID", "==", jobId)
            );

            await deleteByQuery(
              db.collection("Favourite").where("JobID", "==", jobId)
            );
            await deleteByQuery(
              db.collection("Favorite").where("JobID", "==", jobId)
            );

            await jobDoc.ref.delete();
          }
        }
      }

      await userDocRef.delete().catch((err) => {
        console.warn("User document delete warning:", err);
      });

      const bucket = admin.storage().bucket();

      if (photoPath) {
        try {
          await bucket.file(photoPath).delete();
          console.log("Deleted profile photo:", photoPath);
        } catch (err) {
          console.warn("Profile photo delete warning:", err);
        }
      }

      if (cvPath) {
        try {
          await bucket.file(cvPath).delete();
          console.log("Deleted CV file:", cvPath);
        } catch (err) {
          console.warn("CV file delete warning:", err);
        }
      }
      try {
        const prefix = `NewCV/${userId}_`;
        const [files] = await bucket.getFiles({ prefix });

        if (files.length) {
          await Promise.all(
            files.map(async (file) => {
              await file.delete();
              console.log("Deleted NewCV file:", file.name);
            })
          );
          console.log(
            `Deleted ${files.length} NewCV file(s) for user: ${userId}`
          );
        } else {
          console.log(`No NewCV files found for user: ${userId}`);
        }
      } catch (err) {
        console.warn("NewCV files delete warning:", err);
      }

      await admin
        .auth()
        .deleteUser(userId)
        .catch((err) => {
          console.warn("Auth delete warning:", err);
        });
      await admin
        .auth()
        .deleteUser(userId)
        .catch((err) => {
          console.warn("Auth delete warning:", err);
        });

      console.log(`Account deleted for user: ${userId}`);

      return {
        success: true,
        status: "ok",
        message: "User account and related data deleted successfully.",
      };
    } catch (error) {
      console.error("Error deleting user account:", error);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to delete user account: " + error.message
      );
    }
  }
);

// ============================================
// 📄 CV TEXT EXTRACTION - FIXED VERSION
// ============================================

/**
 * 9️⃣ Extract text from uploaded CV (PDF or DOCX) - FIXED
 */
export const extractCVTextEnhancement = v2.storage.onObjectFinalized(
  async (event) => {
    const filePath = event.data.name;
    const contentType = event.data.contentType;

    if (!filePath || !filePath.startsWith("temp_cv_extraction/")) {
      console.log("⏭️ Skipping - not a CV extraction file");
      return null;
    }

    console.log(`📄 Processing CV: ${filePath}`);
    console.log(`📋 Content type: ${contentType}`);

    try {
      const metadata = event.data.metadata || {};
      const cvHistoryId = metadata.cvHistoryId;
      const userId = metadata.userId;

      if (!cvHistoryId) {
        console.error("❌ No cvHistoryId found in metadata");
        return null;
      }

      console.log(`📝 CVHistoryID: ${cvHistoryId}`);
      console.log(`👤 UserID: ${userId}`);

      const bucket = admin.storage().bucket();
      const file = bucket.file(filePath);
      const tempFilePath = path.join(os.tmpdir(), path.basename(filePath));

      await file.download({ destination: tempFilePath });
      console.log(`⬇️ Downloaded to: ${tempFilePath}`);

      let extractedText = "";

      // Extract text based on file type
      if (
        contentType === "application/pdf" ||
        filePath.toLowerCase().endsWith(".pdf")
      ) {
        console.log("📕 Extracting from PDF...");
        const dataBuffer = fs.readFileSync(tempFilePath);

        // ✅ Using dynamic import with named export for pdf-parse v2.4.5
        const { PDFParse } = await import("pdf-parse");
        const parser = new PDFParse({ data: dataBuffer });
        const result = await parser.getText();
        extractedText = (result.text || "").trim();
        await parser.destroy();

        console.log(`📊 Extracted ${extractedText.length} characters`);
      } else if (
        contentType ===
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ||
        contentType === "application/msword" ||
        filePath.toLowerCase().endsWith(".docx") ||
        filePath.toLowerCase().endsWith(".doc")
      ) {
        console.log("📘 Extracting from DOCX...");
        const result = await mammoth.extractRawText({ path: tempFilePath });
        extractedText = result.value;
      } else {
        console.error(`❌ Unsupported file type: ${contentType}`);
        extractedText =
          "Error: Unsupported file format. Please upload PDF or DOCX.";
      }

      // Clean up temp file
      fs.unlinkSync(tempFilePath);
      console.log("🗑️ Temp file deleted");

      // Update Firestore
      if (extractedText.trim()) {
        await admin
          .firestore()
          .collection("CVHistory")
          .doc(cvHistoryId)
          .update({
            OldCVText: extractedText.trim(),
          });
        console.log(`✅ Text extracted and saved to CVHistory/${cvHistoryId}`);
        console.log(`📊 Extracted ${extractedText.length} characters`);
      } else {
        console.warn("⚠️ No text extracted from file");
        await admin
          .firestore()
          .collection("CVHistory")
          .doc(cvHistoryId)
          .update({
            OldCVText: "Error: No text could be extracted from the file.",
          });
      }

      // Delete temp file from Storage
      await file.delete();
      console.log(`🗑️ Deleted temp file from Storage: ${filePath}`);

      return null;
    } catch (error) {
      console.error("❌ Error extracting CV text:", error);

      try {
        const metadata = event.data.metadata || {};
        const cvHistoryId = metadata.cvHistoryId;
        if (cvHistoryId) {
          await admin
            .firestore()
            .collection("CVHistory")
            .doc(cvHistoryId)
            .update({
              OldCVText: `Error extracting text: ${error.message}`,
            });
        }
      } catch (updateError) {
        console.error("❌ Failed to update Firestore with error:", updateError);
      }

      return null;
    }
  }
);
// ============================================
// 📄 CV PDF GENERATION - OPTIMIZED & PROFESSIONAL
// ============================================

/**
 * 🔟 Generate Professional PDF from NewCVText (Manual call)
 */
export const generateCVPDF = functions.https.onCall(async (data, context) => {
  console.log("📥 Generate PDF - Full data:", data);

  const actualData = data.data || data;
  const cvHistoryId = actualData.cvHistoryId || actualData["cvHistoryId"] || "";

  if (!cvHistoryId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "cvHistoryId is required"
    );
  }

  try {
    const cvDoc = await admin
      .firestore()
      .collection("CVHistory")
      .doc(cvHistoryId)
      .get();

    if (!cvDoc.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "CV document not found"
      );
    }

    const cvData = cvDoc.data();
    const newCVText = cvData.NewCVText;
    const userId = cvData.UserID;

    if (!newCVText || !Array.isArray(newCVText) || newCVText.length === 0) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "NewCVText is empty or invalid"
      );
    }

    console.log(`📄 Generating PDF for CVHistoryID: ${cvHistoryId}`);

    const pdfBuffer = await createProfessionalCV(newCVText);

    const bucket = admin.storage().bucket();
    const fileName = `${userId}_${cvHistoryId}.pdf`;
    const filePath = `NewCV/${fileName}`;
    const file = bucket.file(filePath);

    await file.save(pdfBuffer, {
      metadata: {
        contentType: "application/pdf",
        metadata: {
          cvHistoryId: cvHistoryId,
          userId: userId,
          generatedAt: new Date().toISOString(),
        },
      },
    });

    await file.makePublic();

    const downloadURL = `https://storage.googleapis.com/${bucket.name}/${filePath}`;

    await db.collection("CVHistory").doc(cvHistoryId).update({
      NewCVURL: downloadURL,
      PDFGeneratedAt: FieldValue.serverTimestamp(),
    });

    console.log(`✅ PDF generated and saved: ${downloadURL}`);

    return {
      success: true,
      message: "PDF generated successfully",
      pdfUrl: downloadURL,
    };
  } catch (error) {
    console.error("❌ Error generating PDF:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to generate PDF: " + error.message
    );
  }
});

/**
 * Helper function to create professional CV PDF
 * ✅ OPTIMIZED: Smaller margins, black only, compact spacing
 */
async function createProfessionalCV(newCVText) {
  return new Promise((resolve, reject) => {
    try {
      const doc = new PDFDocument({
        size: "A4",
        margins: { top: 30, bottom: 30, left: 30, right: 30 }, // ✅ Reduced from 50
      });

      const buffers = [];
      doc.on("data", buffers.push.bind(buffers));
      doc.on("end", () => {
        const pdfData = Buffer.concat(buffers);
        resolve(pdfData);
      });

      // ✅ BLACK ONLY - No colors!
      const colors = {
        primary: "#000000",
        gray: "#333333",
        lightGray: "#666666",
      };

      const fonts = {
        regular: "Helvetica",
        bold: "Helvetica-Bold",
      };

      let currentY = doc.y;

      for (const section of newCVText) {
        const sectionName = section.section;
        const content = section.content;

        if (
          !content ||
          (Array.isArray(content) && content.length === 0) ||
          (typeof content === "string" && content.trim() === "") ||
          (typeof content === "object" &&
            !Array.isArray(content) &&
            Object.keys(content).length === 0)
        ) {
          continue;
        }

        // ✅ Page break check - adjusted for smaller margins
        if (currentY > 750) {
          doc.addPage();
          currentY = 30;
        }

        // ✅ ALL SECTIONS - Original + 16 New Sections
        if (sectionName === "PersonalInformation") {
          currentY = renderPersonalInfo(doc, content, colors, fonts, currentY);
        } else if (
          sectionName === "Summary" ||
          sectionName === "ProfessionalSummary"
        ) {
          currentY = renderSection(
            doc,
            "PROFESSIONAL SUMMARY",
            content,
            colors,
            fonts,
            currentY
          );
        } else if (sectionName === "Experience") {
          currentY = renderExperience(doc, content, colors, fonts, currentY);
        } else if (sectionName === "Education") {
          currentY = renderEducation(doc, content, colors, fonts, currentY);
        } else if (sectionName === "Skills") {
          currentY = renderSkills(doc, content, colors, fonts, currentY);
        } else if (sectionName === "Projects") {
          currentY = renderProjects(doc, content, colors, fonts, currentY);
        } else if (sectionName === "Certifications") {
          currentY = renderCertifications(
            doc,
            content,
            colors,
            fonts,
            currentY
          );
        } else if (sectionName === "Languages") {
          currentY = renderLanguages(doc, content, colors, fonts, currentY);
        } else if (sectionName === "Awards") {
          currentY = renderAwards(doc, content, colors, fonts, currentY);
        } else if (sectionName === "Publications") {
          currentY = renderPublications(doc, content, colors, fonts, currentY);
        } else if (sectionName === "Patents") {
          currentY = renderPatents(doc, content, colors, fonts, currentY);
        } else if (sectionName === "Research") {
          currentY = renderResearch(doc, content, colors, fonts, currentY);
        } else if (sectionName === "Internships") {
          currentY = renderInternships(doc, content, colors, fonts, currentY);
        } else if (sectionName === "VolunteerWork") {
          currentY = renderVolunteerWork(doc, content, colors, fonts, currentY);
        } else if (sectionName === "Courses") {
          currentY = renderCourses(doc, content, colors, fonts, currentY);
        } else if (sectionName === "Training") {
          currentY = renderTraining(doc, content, colors, fonts, currentY);
        } else if (sectionName === "Workshops") {
          currentY = renderWorkshops(doc, content, colors, fonts, currentY);
        } else if (sectionName === "Conferences") {
          currentY = renderConferences(doc, content, colors, fonts, currentY);
        } else if (sectionName === "Achievements") {
          currentY = renderAchievements(doc, content, colors, fonts, currentY);
        } else if (sectionName === "ProfessionalMemberships") {
          currentY = renderMemberships(doc, content, colors, fonts, currentY);
        } else if (sectionName === "Portfolio") {
          currentY = renderPortfolio(doc, content, colors, fonts, currentY);
        } else if (sectionName === "ExtracurricularActivities") {
          currentY = renderExtracurricular(
            doc,
            content,
            colors,
            fonts,
            currentY
          );
        } else if (sectionName === "Interests") {
          currentY = renderInterests(doc, content, colors, fonts, currentY);
        }
      }

      doc.end();
    } catch (error) {
      reject(error);
    }
  });
}

// ============================================
// 📝 RENDER FUNCTIONS - OPTIMIZED & COMPACT
// ============================================

/**
 * ✅ Personal Information - Compact & Professional
 */
function renderPersonalInfo(doc, content, colors, fonts, startY) {
  const fullName = content.full_name || content.name || "";
  const email = content.email || "";
  const phone = content.phone || "";
  const location = content.location || "";
  const links = content.links || [];

  let y = startY;

  // Name - Bold & Large (Black only)
  doc
    .font(fonts.bold)
    .fontSize(20)
    .fillColor(colors.primary)
    .text(fullName.toUpperCase(), 30, y, {
      align: "center",
      width: 535,
    });

  y = doc.y + 6;

  // Contact Info (Compact)
  const contactInfo = [];
  if (email) contactInfo.push(email);
  if (phone) contactInfo.push(phone);
  if (location) contactInfo.push(location);

  if (contactInfo.length > 0) {
    doc
      .font(fonts.regular)
      .fontSize(9)
      .fillColor(colors.gray)
      .text(contactInfo.join("  •  "), 30, y, {
        align: "center",
        width: 535,
      });
    y = doc.y + 3;
  }

  // Links (Compact)
  if (links.length > 0) {
    doc
      .font(fonts.regular)
      .fontSize(9)
      .fillColor(colors.gray)
      .text(links.join("  •  "), 30, y, {
        align: "center",
        width: 535,
      });
    y = doc.y + 3;
  }

  y += 8;

  // Separator Line (Thin & Black)
  doc
    .moveTo(30, y)
    .lineTo(565, y)
    .strokeColor(colors.lightGray)
    .lineWidth(0.5)
    .stroke();

  return y + 12;
}

/**
 * ✅ Generic Section (Summary, etc.) - Compact
 */
function renderSection(doc, title, content, colors, fonts, startY) {
  let y = startY;

  // Section Title (Black, Bold)
  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text(title, 30, y);

  y = doc.y + 4;

  // Underline (Thin, Black)
  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  // Content
  doc
    .font(fonts.regular)
    .fontSize(10)
    .fillColor(colors.primary)
    .text(content, 30, y, {
      width: 535,
      align: "left",
      lineGap: 2,
    });

  return doc.y + 12;
}

/**
 * ✅ Experience - Compact & Professional
 */
function renderExperience(doc, content, colors, fonts, startY) {
  let y = startY;

  // Section Title
  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("EXPERIENCE", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (let i = 0; i < content.length; i++) {
    const exp = content[i];
    const title = exp.title || "";
    const company = exp.company || "";
    const years = exp.years || "";
    const description = exp.description || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    // Job Title (Bold)
    doc
      .font(fonts.bold)
      .fontSize(11)
      .fillColor(colors.primary)
      .text(title, 30, y);

    y = doc.y + 5;

    // Company | Years
    const companyLine = [company, years].filter((x) => x).join("  •  ");
    doc
      .font(fonts.regular)
      .fontSize(9)
      .fillColor(colors.gray)
      .text(companyLine, 30, y);

    y = doc.y + 8;

    // Description with bullets (Compact)
    if (description) {
      const descriptions = Array.isArray(description)
        ? description
        : [description];

      descriptions.forEach((desc) => {
        if (desc && desc.trim()) {
          if (y > 750) {
            doc.addPage();
            y = 30;
          }

          doc
            .font(fonts.regular)
            .fontSize(9)
            .fillColor(colors.primary)
            .text("•", 40, y)
            .text(desc.trim(), 50, y, {
              width: 515,
              align: "left",
              lineGap: 2,
            });

          y = doc.y + 4;
        }
      });
    }

    // Separator (Thinner)
    if (i < content.length - 1) {
      y += 6;
    } else {
      y += 6;
    }
  }

  return y + 8;
}

/**
 * ✅ Education - Compact
 */
function renderEducation(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("EDUCATION", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (const edu of content) {
    const degree = edu.degree || "";
    const institution = edu.institution || "";
    const years = edu.years || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    doc
      .font(fonts.bold)
      .fontSize(11)
      .fillColor(colors.primary)
      .text(degree, 30, y);

    y = doc.y + 5;

    const institutionLine = [institution, years].filter((x) => x).join("  •  ");
    doc
      .font(fonts.regular)
      .fontSize(9)
      .fillColor(colors.gray)
      .text(institutionLine, 30, y);

    y = doc.y + 10;
  }

  return y + 8;
}

/**
 * ✅ Skills - Compact
 */
function renderSkills(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("SKILLS", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  const skillsText = content.join(" • ");

  doc
    .font(fonts.regular)
    .fontSize(10)
    .fillColor(colors.primary)
    .text(skillsText, 30, y, {
      width: 535,
      align: "left",
      lineGap: 2,
    });

  return doc.y + 12;
}

/**
 * ✅ Projects - NEW SECTION
 */
function renderProjects(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("PROJECTS", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (const proj of content) {
    const name = proj.name || "";
    const year = proj.year || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    const projectLine = [name, year].filter((x) => x).join("  •  ");
    doc
      .font(fonts.regular)
      .fontSize(10)
      .fillColor(colors.primary)
      .text(projectLine, 30, y);

    y = doc.y + 8;
  }

  return y + 8;
}

/**
 * ✅ Certifications - Compact
 */
function renderCertifications(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("CERTIFICATIONS", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (const cert of content) {
    const name = cert.name || "";
    const issuer = cert.issuer || "";
    const year = cert.year || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    doc
      .font(fonts.bold)
      .fontSize(10)
      .fillColor(colors.primary)
      .text(name, 30, y);

    y = doc.y + 4;

    const certLine = [issuer, year].filter((x) => x).join("  •  ");
    if (certLine) {
      doc
        .font(fonts.regular)
        .fontSize(9)
        .fillColor(colors.gray)
        .text(certLine, 30, y);

      y = doc.y + 10;
    }
  }

  return y + 8;
}

/**
 * ✅ Languages - Compact
 */
function renderLanguages(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("LANGUAGES", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  const languagesText = content
    .map((lang) => {
      const language = lang.language || "";
      const proficiency = lang.proficiency || "";
      return `${language}${proficiency ? ` (${proficiency})` : ""}`;
    })
    .join(" • ");

  doc
    .font(fonts.regular)
    .fontSize(10)
    .fillColor(colors.primary)
    .text(languagesText, 30, y, {
      width: 535,
      align: "left",
      lineGap: 2,
    });

  return doc.y + 12;
}

/**
 * ✅ Awards - NEW SECTION
 */
function renderAwards(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("AWARDS", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (const award of content) {
    const name = award.name || "";
    const issuer = award.issuer || "";
    const year = award.year || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    doc
      .font(fonts.bold)
      .fontSize(10)
      .fillColor(colors.primary)
      .text(name, 30, y);

    y = doc.y + 4;

    const awardLine = [issuer, year].filter((x) => x).join("  •  ");
    if (awardLine) {
      doc
        .font(fonts.regular)
        .fontSize(9)
        .fillColor(colors.gray)
        .text(awardLine, 30, y);

      y = doc.y + 10;
    }
  }

  return y + 8;
}

/**
 * ✅ Publications - NEW SECTION
 */
function renderPublications(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("PUBLICATIONS", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (const pub of content) {
    const title = pub.title || "";
    const publisher = pub.publisher || "";
    const year = pub.year || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    doc
      .font(fonts.bold)
      .fontSize(10)
      .fillColor(colors.primary)
      .text(title, 30, y);

    y = doc.y + 4;

    const pubLine = [publisher, year].filter((x) => x).join("  •  ");
    if (pubLine) {
      doc
        .font(fonts.regular)
        .fontSize(9)
        .fillColor(colors.gray)
        .text(pubLine, 30, y);

      y = doc.y + 10;
    }
  }

  return y + 8;
}

/**
 * ✅ Patents - NEW SECTION
 */
function renderPatents(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("PATENTS", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (const patent of content) {
    const title = patent.title || "";
    const patent_number = patent.patent_number || "";
    const year = patent.year || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    doc
      .font(fonts.bold)
      .fontSize(10)
      .fillColor(colors.primary)
      .text(title, 30, y);

    y = doc.y + 4;

    const patentLine = [patent_number, year].filter((x) => x).join("  •  ");
    if (patentLine) {
      doc
        .font(fonts.regular)
        .fontSize(9)
        .fillColor(colors.gray)
        .text(patentLine, 30, y);

      y = doc.y + 10;
    }
  }

  return y + 8;
}

/**
 * ✅ Research - NEW SECTION
 */
function renderResearch(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("RESEARCH", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (const research of content) {
    const title = research.title || "";
    const institution = research.institution || "";
    const years = research.years || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    doc
      .font(fonts.bold)
      .fontSize(10)
      .fillColor(colors.primary)
      .text(title, 30, y);

    y = doc.y + 4;

    const researchLine = [institution, years].filter((x) => x).join("  •  ");
    if (researchLine) {
      doc
        .font(fonts.regular)
        .fontSize(9)
        .fillColor(colors.gray)
        .text(researchLine, 30, y);

      y = doc.y + 10;
    }
  }

  return y + 8;
}

/**
 * ✅ Internships - NEW SECTION
 */
function renderInternships(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("INTERNSHIPS", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (const intern of content) {
    const title = intern.title || "";
    const company = intern.company || "";
    const years = intern.years || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    doc
      .font(fonts.bold)
      .fontSize(10)
      .fillColor(colors.primary)
      .text(title, 30, y);

    y = doc.y + 4;

    const internLine = [company, years].filter((x) => x).join("  •  ");
    if (internLine) {
      doc
        .font(fonts.regular)
        .fontSize(9)
        .fillColor(colors.gray)
        .text(internLine, 30, y);

      y = doc.y + 10;
    }
  }

  return y + 8;
}

/**
 * ✅ Volunteer Work - NEW SECTION
 */
function renderVolunteerWork(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("VOLUNTEER WORK", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (const vol of content) {
    const role = vol.role || "";
    const organization = vol.organization || "";
    const years = vol.years || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    doc
      .font(fonts.bold)
      .fontSize(10)
      .fillColor(colors.primary)
      .text(role, 30, y);

    y = doc.y + 4;

    const volLine = [organization, years].filter((x) => x).join("  •  ");
    if (volLine) {
      doc
        .font(fonts.regular)
        .fontSize(9)
        .fillColor(colors.gray)
        .text(volLine, 30, y);

      y = doc.y + 10;
    }
  }

  return y + 8;
}

/**
 * ✅ Courses - NEW SECTION
 */
function renderCourses(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("COURSES", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (const course of content) {
    const name = course.name || "";
    const institution = course.institution || "";
    const year = course.year || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    doc
      .font(fonts.bold)
      .fontSize(10)
      .fillColor(colors.primary)
      .text(name, 30, y);

    y = doc.y + 4;

    const courseLine = [institution, year].filter((x) => x).join("  •  ");
    if (courseLine) {
      doc
        .font(fonts.regular)
        .fontSize(9)
        .fillColor(colors.gray)
        .text(courseLine, 30, y);

      y = doc.y + 10;
    }
  }

  return y + 8;
}

/**
 * ✅ Training - NEW SECTION
 */
function renderTraining(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("TRAINING", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (const training of content) {
    const name = training.name || "";
    const provider = training.provider || "";
    const year = training.year || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    doc
      .font(fonts.bold)
      .fontSize(10)
      .fillColor(colors.primary)
      .text(name, 30, y);

    y = doc.y + 4;

    const trainingLine = [provider, year].filter((x) => x).join("  •  ");
    if (trainingLine) {
      doc
        .font(fonts.regular)
        .fontSize(9)
        .fillColor(colors.gray)
        .text(trainingLine, 30, y);

      y = doc.y + 10;
    }
  }

  return y + 8;
}

/**
 * ✅ Workshops - NEW SECTION
 */
function renderWorkshops(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("WORKSHOPS", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (const workshop of content) {
    const name = workshop.name || "";
    const organizer = workshop.organizer || "";
    const year = workshop.year || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    doc
      .font(fonts.bold)
      .fontSize(10)
      .fillColor(colors.primary)
      .text(name, 30, y);

    y = doc.y + 4;

    const workshopLine = [organizer, year].filter((x) => x).join("  •  ");
    if (workshopLine) {
      doc
        .font(fonts.regular)
        .fontSize(9)
        .fillColor(colors.gray)
        .text(workshopLine, 30, y);

      y = doc.y + 10;
    }
  }

  return y + 8;
}

/**
 * ✅ Conferences - NEW SECTION
 */
function renderConferences(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("CONFERENCES", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (const conf of content) {
    const name = conf.name || "";
    const role = conf.role || "";
    const year = conf.year || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    doc
      .font(fonts.bold)
      .fontSize(10)
      .fillColor(colors.primary)
      .text(name, 30, y);

    y = doc.y + 4;

    const confLine = [role, year].filter((x) => x).join("  •  ");
    if (confLine) {
      doc
        .font(fonts.regular)
        .fontSize(9)
        .fillColor(colors.gray)
        .text(confLine, 30, y);

      y = doc.y + 10;
    }
  }

  return y + 8;
}

/**
 * ✅ Achievements - NEW SECTION
 */
function renderAchievements(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("ACHIEVEMENTS", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (const ach of content) {
    const name = ach.name || "";
    const year = ach.year || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    const achLine = [name, year].filter((x) => x).join("  •  ");
    doc
      .font(fonts.regular)
      .fontSize(10)
      .fillColor(colors.primary)
      .text(achLine, 30, y);

    y = doc.y + 8;
  }

  return y + 8;
}

/**
 * ✅ Professional Memberships - NEW SECTION
 */
function renderMemberships(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("PROFESSIONAL MEMBERSHIPS", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (const mem of content) {
    const organization = mem.organization || "";
    const role = mem.role || "";
    const years = mem.years || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    doc
      .font(fonts.bold)
      .fontSize(10)
      .fillColor(colors.primary)
      .text(organization, 30, y);

    y = doc.y + 4;

    const memLine = [role, years].filter((x) => x).join("  •  ");
    if (memLine) {
      doc
        .font(fonts.regular)
        .fontSize(9)
        .fillColor(colors.gray)
        .text(memLine, 30, y);

      y = doc.y + 10;
    }
  }

  return y + 8;
}

/**
 * ✅ Portfolio - NEW SECTION
 */
function renderPortfolio(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("PORTFOLIO", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (const port of content) {
    const name = port.name || "";
    const url = port.url || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    const portLine = [name, url].filter((x) => x).join("  •  ");
    doc
      .font(fonts.regular)
      .fontSize(10)
      .fillColor(colors.primary)
      .text(portLine, 30, y);

    y = doc.y + 8;
  }

  return y + 8;
}

/**
 * ✅ Extracurricular Activities - NEW SECTION
 */
function renderExtracurricular(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("EXTRACURRICULAR ACTIVITIES", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  for (const extra of content) {
    const activity = extra.activity || "";
    const role = extra.role || "";
    const years = extra.years || "";

    if (y > 750) {
      doc.addPage();
      y = 30;
    }

    doc
      .font(fonts.bold)
      .fontSize(10)
      .fillColor(colors.primary)
      .text(activity, 30, y);

    y = doc.y + 4;

    const extraLine = [role, years].filter((x) => x).join("  •  ");
    if (extraLine) {
      doc
        .font(fonts.regular)
        .fontSize(9)
        .fillColor(colors.gray)
        .text(extraLine, 30, y);

      y = doc.y + 10;
    }
  }

  return y + 8;
}

/**
 * ✅ Interests - NEW SECTION
 */
function renderInterests(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(12)
    .fillColor(colors.primary)
    .text("INTERESTS", 30, y);

  y = doc.y + 4;

  doc
    .moveTo(30, y)
    .lineTo(120, y)
    .strokeColor(colors.primary)
    .lineWidth(1)
    .stroke();

  y += 10;

  const interestsText = content.join(" • ");

  doc
    .font(fonts.regular)
    .fontSize(10)
    .fillColor(colors.primary)
    .text(interestsText, 30, y, {
      width: 535,
      align: "left",
      lineGap: 2,
    });

  return doc.y + 12;
}

// ============================================
// 📅 SCHEDULED FUNCTION: Auto-close expired jobs
// ============================================
// Runs daily at midnight (00:00) to check and close jobs with passed EndDate
export const autoCloseExpiredJobs = v2.scheduler.onSchedule(
  {
    schedule: "0 0 * * *", // Run at midnight every day (cron format)
    timeZone: "Asia/Riyadh", // Adjust to your timezone
  },
  async (event) => {
    try {
      const now = Timestamp.now();

      // Query all jobs that are Open but have EndDate in the past
      const expiredJobsQuery = await db
        .collection("Jobs")
        .where("JobStatus", "==", "Open")
        .where("EndDate", "<", now)
        .get();

      if (expiredJobsQuery.empty) {
        console.log("No expired jobs found");
        return null;
      }

      // Batch update all expired jobs
      const batch = db.batch();
      let count = 0;

      expiredJobsQuery.docs.forEach((doc) => {
        batch.update(doc.ref, { JobStatus: "Closed" });
        count++;
      });

      await batch.commit();

      console.log(`Successfully closed ${count} expired job(s)`);
      return { success: true, closedCount: count };
    } catch (error) {
      console.error("Error auto-closing expired jobs:", error);
      return { success: false, error: error.message };
    }
  }
);

export { generateInterviewQuestions };
export { generateMockInterviewQuestions } from "./mockinterview/mock_interview_questions.js";
export { generateMockInterviewReport } from "./mockinterview/generateReport.js";

export const deleteOldCVHistory = onSchedule(
  {
    schedule: "0 0 * * *",
    timeZone: "UTC",
    region: "us-central1",
  },
  async (event) => {
    console.log("Starting deleteOldCVHistory function");

    try {
      //const db = admin.firestore();
      
      const oneMonthAgo = new Date();
      oneMonthAgo.setDate(oneMonthAgo.getDate() - 30);
      const oneMonthAgoTimestamp = Timestamp.fromDate(oneMonthAgo);

      console.log("Querying CVHistory older than:", oneMonthAgo.toISOString());

      const oldCVsQuery = db
        .collection("CVHistory")
        .where("Date", "<", oneMonthAgoTimestamp);

      const snapshot = await oldCVsQuery.get();

      if (snapshot.empty) {
        console.log("No old CV history records found to delete");
        return;
      }

      console.log(`Found ${snapshot.size} CV history records to delete`);

      const batchSize = 500;
      let deletedCount = 0;
      let batch = db.batch();
      let batchCount = 0;

      for (const doc of snapshot.docs) {
        batch.delete(doc.ref);
        batchCount++;

        if (batchCount >= batchSize) {
          await batch.commit();
          deletedCount += batchCount;
          console.log(`Deleted ${deletedCount} records so far...`);
          batch = db.batch();
          batchCount = 0;
        }
      }

      if (batchCount > 0) {
        await batch.commit();
        deletedCount += batchCount;
      }

      console.log(`Successfully deleted ${deletedCount} old CV history records`);
    } catch (error) {
      console.error("Error in deleteOldCVHistory:", error);
      throw error;
    }
  }
);

// ✅ Add this function to your functions/index.js file
// This should be added AFTER the deleteOldCVHistory function

// Auto-delete Mock Interviews older than 30 days (runs daily at midnight)
export const deleteOldMockInterviews = onSchedule(
  {
    schedule: "0 0 * * *",
    timeZone: "UTC",
    region: "us-central1",
  },
  async (event) => {
    const now = new Date();
    const oneMonthAgo = new Date(now);
    oneMonthAgo.setDate(oneMonthAgo.getDate() - 30);

    try {
      //const db = admin.firestore();
      
      // Query for Mock Interviews older than 30 days
      const oldMockInterviewsSnapshot = await db
        .collection("MockInterviews")
        .where("Date", "<", oneMonthAgo)
        .get();

      if (oldMockInterviewsSnapshot.empty) {
        console.log("No old mock interviews to delete");
        return null;
      }

      // Delete in batches of 500 (Firestore limit)
      const batch = db.batch();
      let deleteCount = 0;

      oldMockInterviewsSnapshot.forEach((doc) => {
        batch.delete(doc.ref);
        deleteCount++;
      });

      await batch.commit();
      console.log(`Deleted ${deleteCount} old mock interviews`);

      return { success: true, deletedCount: deleteCount };
    } catch (error) {
      console.error("Error deleting old mock interviews:", error);
      return { success: false, error: error.message };
    }
  }
);
