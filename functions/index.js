import express from "express";
import OpenAI from "openai";
import * as functions from "firebase-functions";
import * as v2 from "firebase-functions/v2";
import admin from "firebase-admin";
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

// Initialize Firebase Admin (only once)
if (!admin.apps.length) {
  admin.initializeApp();
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
export const notifyAdminNewCompany = functions.https.onCall(async (data, context) => {
  console.log("📥 Admin notification - Full data:", data);

  const actualData = data.data || data;
  const companyName = actualData.companyName || actualData["companyName"] || "";
  const companyEmail = actualData.companyEmail || actualData["companyEmail"] || "";

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
});

/**
 * 4️⃣ Send Company Document Request Email
 */
export const sendCompanyDocumentRequest = functions.https.onCall(async (data, context) => {
  console.log("📥 Document request - Full data:", data);

  const actualData = data.data || data;
  const email = actualData.email || actualData["email"] || "";
  const companyName = actualData.companyName || actualData["companyName"] || "";

  if (!email) {
    throw new functions.https.HttpsError("invalid-argument", "Email is required");
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
            <p>Please provide the following:</p>
            <ul>
              <li>Commercial Registration</li>
              <li>Tax Certificate</li>
              <li>Company License</li>
            </ul>
            <p>You will receive an email from Jadeer informing you whether your registration has been accepted or rejected.</p>
          </div>
        </div>
      `,
    };

    await transporter.sendMail(mailOptions);
    console.log(`✅ Document request sent to: ${email}`);

    return { success: true, message: "Document request email sent successfully" };
  } catch (error) {
    console.error("❌ Error sending document request:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to send email: " + error.message
    );
  }
});

/**
 * 🔔 Notify Company of Account Status Change (Accepted/Rejected)
 */
export const notifyCompanyStatusChange = functions.https.onCall(async (data, context) => {
  console.log("📥 Company status notification - Full data:", data);

  const actualData = data.data || data;
  const companyEmail = actualData.companyEmail || actualData["companyEmail"] || "";
  const companyName = actualData.companyName || actualData["companyName"] || "";
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

  console.log(`📧 Sending ${status} email to ${companyName} (${companyEmail})`);

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
});



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

    const prompt = `
      Write a concise and professional job description (under 100 words)
      for the following role:
      - Job Title: "${title}"
      - Position Level: "${position}"
      - Speciality/Field: "${speciality}"

      Focus on:
      - The role's main responsibilities tailored to the position level and speciality (2–3 short sentences)
      - Key expectations for someone in this position and speciality
      - One short, inviting closing line encouraging candidates to apply.
      Provide only the description text, no headers or sections.
    `;

    const response = await openai.responses.create({
      model: "gpt-4o-mini",
      input: prompt,
    });

    const text = response.output[0].content[0].text.trim();
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
      throw new v2.https.HttpsError("invalid-argument", "cvHistoryId is required");
    }

    if (request.auth) {
      console.log("✅ User authenticated:", request.auth.uid);
    } else {
      console.warn("⚠️ Proceeding without auth (TESTING ONLY)");
    }

    try {
      // Get CV data from Firestore
      const cvDoc = await admin.firestore().collection("CVHistory").doc(cvHistoryId).get();

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

Enhance the following CV text to make it:
- Professional and grammatically correct
- Optimized for ATS (Applicant Tracking Systems)
- Concise and well-structured
- Tailored for the target job if provided
- In the suggestions section, provide the CV owner with suggestions based on the content of the CV
- If important sections are missing (like skills, education, experience), mention them in the suggestions section
- Maximum 5 suggestions, but you can provide less if not needed

---

TARGET JOB INFORMATION:
Job Title: ${jobTitle || "Not specified"}
${jobDescription ? `Job Description: ${jobDescription}` : ""}
${(!jobTitle && !jobDescription) ? "(No specific job provided - enhance CV for general use)" : ""}

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
      "section": "Certifications",
      "content": [
        {"name": "...", "issuer": "...", "year": "..."}
      ]
    },
    {
      "section": "Languages",
      "content": [
        {"language": "...", "proficiency": "..."}
      ]
    }
  ],
  "suggestions": [
    "Suggestion 1",
    "Suggestion 2",
    "Suggestion 3",
    "Suggestion 4",
    "Suggestion 5"
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
            content: "You are a professional CV enhancement assistant. Always return valid JSON. CRITICAL: Never invent or create fake data - only use information that exists in the provided CV. If sections are empty, return empty values, NOT fake examples."
          },
          {
            role: "user",
            content: prompt
          }
        ],
        response_format: { type: "json_object" },
        temperature: 0.7,
        max_tokens: 4000
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
      await admin.firestore().collection("CVHistory").doc(cvHistoryId).update({
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
        await admin.firestore().collection("CVHistory").doc(cvHistoryId).update({
          NewCVURL: pdfUrl,
          PDFGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`✅ Firestore updated with PDF URL`);

        return {
          success: true,
          message: "CV enhanced and PDF generated successfully",
          sectionsCount: enhanced_cv.length,
          suggestionsCount: suggestions.length,
          pdfUrl: pdfUrl
        };

      } catch (pdfError) {
        console.error(`❌ PDF generation error:`, pdfError);

        // Still return success for CV enhancement
        return {
          success: true,
          message: "CV enhanced successfully (PDF generation failed)",
          sectionsCount: enhanced_cv.length,
          suggestionsCount: suggestions.length,
          pdfError: pdfError.message
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
      throw new v2.https.HttpsError("invalid-argument", "cvHistoryId is required");
    }

    try {
      // Get CV data from Firestore
      const cvDoc = await admin.firestore().collection("CVHistory").doc(cvHistoryId).get();

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

CRITICAL RULES:
- A section is MISSING if:
  * It doesn't exist at all in the CV, OR
  * It only has a title/header but NO actual content
  * For example, if the CV has "Experience:" or "Skills:" as a header but no actual experience entries or skills listed, that section is MISSING

- A section EXISTS and should NOT be included if:
  * It has actual data/content (not just the section title)
  * For example: actual job entries for Experience, actual skills listed for Skills, etc.

- Ignore section titles/headers - only check if there's actual content in each section

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
            content: "You are a CV analysis assistant. Always return valid JSON."
          },
          {
            role: "user",
            content: prompt
          }
        ],
        response_format: { type: "json_object" },
        temperature: 0.3,
        max_tokens: 500
      });

      const gptResponse = response.choices[0].message.content;
      console.log("✅ Got response from OpenAI");

      // Parse JSON response
      const parsedData = JSON.parse(gptResponse);
      const missingSections = parsedData.missingSections || [];

      console.log(`🔍 Missing sections detected: ${missingSections.join(", ") || "None"}`);

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
              content: "You are a career expert assistant. Always return valid JSON."
            },
            {
              role: "user",
              content: skillsPrompt
            }
          ],
          response_format: { type: "json_object" },
          temperature: 0.5,
          max_tokens: 800
        });

        const skillsData = JSON.parse(skillsResponse.choices[0].message.content);
        suggestedSkills = skillsData.skills || [];
        console.log(`✅ Generated ${suggestedSkills.length} suggested skills`);
      }

      return {
        success: true,
        missingSections: missingSections,
        hasMissingSections: missingSections.length > 0,
        suggestedSkills: suggestedSkills
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
export const sendPasswordResetOtp = functions.https.onCall(async (data, context) => {
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

    return { success: true, message: "Password reset code sent successfully" };
  } catch (error) {
    console.error("❌ Error sending password reset OTP:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to send password reset code: " + error.message
    );
  }
});

/**
 * 8️⃣ Reset User Password + Unlock Account (Admin SDK)
 */
export const resetUserPassword = functions.https.onCall(async (data, context) => {
  console.log("📥 Reset password - Full data:", data);

  const actualData = data.data || data;
  const email = actualData.email || actualData["email"] || "";
  const newPassword = actualData.newPassword || actualData["newPassword"] || "";

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

    await admin.firestore().collection("Users").doc(userRecord.uid).update({
      failedLoginAttempts: 0,
      lastFailedLoginDate: null,
      accountLocked: false,
      mustResetPassword: false,
    });

    console.log(`✅ Password updated and account unlocked for: ${email}`);

    return { success: true, message: "Password reset and account unlocked successfully" };
  } catch (error) {
    console.error("❌ Error resetting password:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to reset password: " + error.message
    );
  }
});

// ============================================
// 📄 CV TEXT EXTRACTION - FIXED VERSION
// ============================================

/**
 * 9️⃣ Extract text from uploaded CV (PDF or DOCX) - FIXED
 */
export const extractCVTextEnhancement = v2.storage.onObjectFinalized(async (event) => {
  const filePath = event.data.name;
  const contentType = event.data.contentType;

  if (!filePath || !filePath.startsWith('temp_cv_extraction/')) {
    console.log('⏭️ Skipping - not a CV extraction file');
    return null;
  }

  console.log(`📄 Processing CV: ${filePath}`);
  console.log(`📋 Content type: ${contentType}`);

  try {
    const metadata = event.data.metadata || {};
    const cvHistoryId = metadata.cvHistoryId;
    const userId = metadata.userId;

    if (!cvHistoryId) {
      console.error('❌ No cvHistoryId found in metadata');
      return null;
    }

    console.log(`📝 CVHistoryID: ${cvHistoryId}`);
    console.log(`👤 UserID: ${userId}`);

    const bucket = admin.storage().bucket();
    const file = bucket.file(filePath);
    const tempFilePath = path.join(os.tmpdir(), path.basename(filePath));

    await file.download({ destination: tempFilePath });
    console.log(`⬇️ Downloaded to: ${tempFilePath}`);

    let extractedText = '';

    // Extract text based on file type
    if (contentType === 'application/pdf' || filePath.toLowerCase().endsWith('.pdf')) {
      console.log('📕 Extracting from PDF...');
      const dataBuffer = fs.readFileSync(tempFilePath);

      // ✅ Using dynamic import with named export for pdf-parse v2.4.5
      const { PDFParse } = await import('pdf-parse');
      const parser = new PDFParse({ data: dataBuffer });
      const result = await parser.getText();
      extractedText = (result.text || '').trim();
      await parser.destroy();

      console.log(`📊 Extracted ${extractedText.length} characters`);
    } else if (
      contentType === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
      contentType === 'application/msword' ||
      filePath.toLowerCase().endsWith('.docx') ||
      filePath.toLowerCase().endsWith('.doc')
    ) {
      console.log('📘 Extracting from DOCX...');
      const result = await mammoth.extractRawText({ path: tempFilePath });
      extractedText = result.value;
    } else {
      console.error(`❌ Unsupported file type: ${contentType}`);
      extractedText = 'Error: Unsupported file format. Please upload PDF or DOCX.';
    }

    // Clean up temp file
    fs.unlinkSync(tempFilePath);
    console.log('🗑️ Temp file deleted');

    // Update Firestore
    if (extractedText.trim()) {
      await admin.firestore().collection('CVHistory').doc(cvHistoryId).update({
        OldCVText: extractedText.trim(),
      });
      console.log(`✅ Text extracted and saved to CVHistory/${cvHistoryId}`);
      console.log(`📊 Extracted ${extractedText.length} characters`);
    } else {
      console.warn('⚠️ No text extracted from file');
      await admin.firestore().collection('CVHistory').doc(cvHistoryId).update({
        OldCVText: 'Error: No text could be extracted from the file.',
      });
    }

    // Delete temp file from Storage
    await file.delete();
    console.log(`🗑️ Deleted temp file from Storage: ${filePath}`);

    return null;
  } catch (error) {
    console.error('❌ Error extracting CV text:', error);

    try {
      const metadata = event.data.metadata || {};
      const cvHistoryId = metadata.cvHistoryId;
      if (cvHistoryId) {
        await admin.firestore().collection('CVHistory').doc(cvHistoryId).update({
          OldCVText: `Error extracting text: ${error.message}`,
        });
      }
    } catch (updateError) {
      console.error('❌ Failed to update Firestore with error:', updateError);
    }

    return null;
  }
});

// ============================================
// 📄 CV PDF GENERATION
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

    await admin.firestore().collection("CVHistory").doc(cvHistoryId).update({
      NewCVURL: downloadURL,
      PDFGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
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
 */
async function createProfessionalCV(newCVText) {
  return new Promise((resolve, reject) => {
    try {
      const doc = new PDFDocument({
        size: "A4",
        margins: { top: 50, bottom: 50, left: 50, right: 50 },
      });

      const buffers = [];
      doc.on("data", buffers.push.bind(buffers));
      doc.on("end", () => {
        const pdfData = Buffer.concat(buffers);
        resolve(pdfData);
      });

      const colors = {
        primary: "#000000",
        accent: "#4A5FBC",
        gray: "#555555",
        lightGray: "#DDDDDD",
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

        // Page break check
        if (currentY > 680) {
          doc.addPage();
          currentY = 50;
        }

        if (sectionName === "PersonalInformation") {
          currentY = renderPersonalInfo(doc, content, colors, fonts, currentY);
        } else if (sectionName === "Summary" || sectionName === "ProfessionalSummary") {
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
        } else if (sectionName === "Certifications") {
          currentY = renderCertifications(doc, content, colors, fonts, currentY);
        } else if (sectionName === "Languages") {
          currentY = renderLanguages(doc, content, colors, fonts, currentY);
        }
      }

      doc.end();
    } catch (error) {
      reject(error);
    }
  });
}

function renderPersonalInfo(doc, content, colors, fonts, startY) {
  const fullName = content.full_name || content.name || "";
  const email = content.email || "";
  const phone = content.phone || "";
  const location = content.location || "";
  const links = content.links || [];

  let y = startY;

  // Full Name - Large and Bold
  doc
    .font(fonts.bold)
    .fontSize(24)
    .fillColor(colors.primary)
    .text(fullName.toUpperCase(), 50, y, {
      align: "center",
      width: 495,
    });

  y = doc.y + 12;

  // Contact Info Line
  const contactInfo = [];
  if (email) contactInfo.push(email);
  if (phone) contactInfo.push(phone);
  if (location) contactInfo.push(location);

  if (contactInfo.length > 0) {
    doc
      .font(fonts.regular)
      .fontSize(10)
      .fillColor(colors.gray)
      .text(contactInfo.join("  •  "), 50, y, {
        align: "center",
        width: 495,
      });
    y = doc.y + 6;
  }

  // Links
  if (links.length > 0) {
    doc
      .font(fonts.regular)
      .fontSize(10)
      .fillColor(colors.gray)
      .text(links.join("  •  "), 50, y, {
        align: "center",
        width: 495,
      });
    y = doc.y + 4;
  }

  y += 20;

  // Separator Line
  doc
    .moveTo(50, y)
    .lineTo(545, y)
    .strokeColor(colors.lightGray)
    .lineWidth(1)
    .stroke();

  return y + 25;
}

function renderSection(doc, title, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(14)
    .fillColor(colors.accent)
    .text(title, 50, y);

  y = doc.y + 8;

  doc
    .moveTo(50, y)
    .lineTo(200, y)
    .strokeColor(colors.accent)
    .lineWidth(1.5)
    .stroke();

  y += 18;

  doc
    .font(fonts.regular)
    .fontSize(11)
    .fillColor(colors.primary)
    .text(content, 50, y, {
      width: 495,
      align: "left",
      lineGap: 4,
    });

  return doc.y + 25;
}

function renderExperience(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(14)
    .fillColor(colors.accent)
    .text("EXPERIENCE", 50, y);

  y = doc.y + 8;

  doc
    .moveTo(50, y)
    .lineTo(200, y)
    .strokeColor(colors.accent)
    .lineWidth(1.5)
    .stroke();

  y += 18;

  for (let i = 0; i < content.length; i++) {
    const exp = content[i];
    const title = exp.title || "";
    const company = exp.company || "";
    const years = exp.years || "";
    const description = exp.description || "";

    // Page break check
    if (y > 680) {
      doc.addPage();
      y = 50;
    }

    // Job Title
    doc
      .font(fonts.bold)
      .fontSize(12)
      .fillColor(colors.primary)
      .text(title, 50, y);

    y = doc.y + 8;

    // Company | Years
    const companyLine = [company, years].filter((x) => x).join("  •  ");
    doc
      .font(fonts.regular)
      .fontSize(10)
      .fillColor(colors.gray)
      .text(companyLine, 50, y);

    y = doc.y + 12;

    // Description with bullet points
    if (description) {
      const descriptions = Array.isArray(description) ? description : [description];
      
      descriptions.forEach((desc) => {
        if (desc && desc.trim()) {
          // Page break check for bullets
          if (y > 680) {
            doc.addPage();
            y = 50;
          }

          doc
            .font(fonts.regular)
            .fontSize(10)
            .fillColor(colors.primary)
            .text("•", 60, y)
            .text(desc.trim(), 75, y, {
              width: 470,
              align: "left",
              lineGap: 4,
            });

          y = doc.y + 8;
        }
      });
    }

    // Separator between jobs
    if (i < content.length - 1) {
      y += 12;
      doc
        .moveTo(50, y)
        .lineTo(300, y)
        .strokeColor(colors.lightGray)
        .lineWidth(0.5)
        .stroke();
      y += 18;
    } else {
      y += 8;
    }
  }

  return y + 20;
}

function renderEducation(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(14)
    .fillColor(colors.accent)
    .text("EDUCATION", 50, y);

  y = doc.y + 8;

  doc
    .moveTo(50, y)
    .lineTo(200, y)
    .strokeColor(colors.accent)
    .lineWidth(1.5)
    .stroke();

  y += 18;

  for (const edu of content) {
    const degree = edu.degree || "";
    const institution = edu.institution || "";
    const years = edu.years || "";

    if (y > 680) {
      doc.addPage();
      y = 50;
    }

    doc
      .font(fonts.bold)
      .fontSize(12)
      .fillColor(colors.primary)
      .text(degree, 50, y);

    y = doc.y + 8;

    const institutionLine = [institution, years].filter((x) => x).join("  •  ");
    doc
      .font(fonts.regular)
      .fontSize(10)
      .fillColor(colors.gray)
      .text(institutionLine, 50, y);

    y = doc.y + 16;
  }

  return y + 15;
}

function renderSkills(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(14)
    .fillColor(colors.accent)
    .text("SKILLS", 50, y);

  y = doc.y + 8;

  doc
    .moveTo(50, y)
    .lineTo(200, y)
    .strokeColor(colors.accent)
    .lineWidth(1.5)
    .stroke();

  y += 18;

  const skillsText = content.join(" • ");

  doc
    .font(fonts.regular)
    .fontSize(11)
    .fillColor(colors.primary)
    .text(skillsText, 50, y, {
      width: 495,
      align: "left",
      lineGap: 4,
    });

  return doc.y + 25;
}

function renderCertifications(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(14)
    .fillColor(colors.accent)
    .text("CERTIFICATIONS", 50, y);

  y = doc.y + 8;

  doc
    .moveTo(50, y)
    .lineTo(200, y)
    .strokeColor(colors.accent)
    .lineWidth(1.5)
    .stroke();

  y += 18;

  for (const cert of content) {
    const name = cert.name || "";
    const issuer = cert.issuer || "";
    const year = cert.year || "";

    if (y > 680) {
      doc.addPage();
      y = 50;
    }

    doc
      .font(fonts.bold)
      .fontSize(11)
      .fillColor(colors.primary)
      .text(name, 50, y);

    y = doc.y + 6;

    const certLine = [issuer, year].filter((x) => x).join("  •  ");
    if (certLine) {
      doc
        .font(fonts.regular)
        .fontSize(10)
        .fillColor(colors.gray)
        .text(certLine, 50, y);

      y = doc.y + 14;
    }
  }

  return y + 15;
}

function renderLanguages(doc, content, colors, fonts, startY) {
  let y = startY;

  doc
    .font(fonts.bold)
    .fontSize(14)
    .fillColor(colors.accent)
    .text("LANGUAGES", 50, y);

  y = doc.y + 8;

  doc
    .moveTo(50, y)
    .lineTo(200, y)
    .strokeColor(colors.accent)
    .lineWidth(1.5)
    .stroke();

  y += 18;

  const languagesText = content
    .map((lang) => {
      const language = lang.language || "";
      const proficiency = lang.proficiency || "";
      return `${language}${proficiency ? ` (${proficiency})` : ""}`;
    })
    .join(" • ");

  doc
    .font(fonts.regular)
    .fontSize(11)
    .fillColor(colors.primary)
    .text(languagesText, 50, y, {
      width: 495,
      align: "left",
      lineGap: 4,
    });

  return doc.y + 25;
}

export { generateInterviewQuestions };