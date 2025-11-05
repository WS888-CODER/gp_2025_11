import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../config/theme.dart';

class PublishScreen extends StatelessWidget {
  final String cvUrl;
  const PublishScreen({super.key, required this.cvUrl});

  @override
  Widget build(BuildContext context) {
    // Example of long improvement suggestions in English
    const suggestions = '''
1. Use strong action verbs at the start of each bullet point (e.g., "Managed", "Developed", "Created").
2. Avoid generic phrases; focus on measurable achievements.
3. Add a section for technical skills and tools you are proficient in.
4. Make sure your CV layout is clean and professional.
5. Include a short summary at the top describing who you are and what you are looking for.
6. Use a clear and readable font.
7. Avoid long paragraphs; keep information concise.
8. Highlight your most recent and relevant experiences first.
9. Do not include unnecessary personal details.
10. Double-check for spelling and grammar mistakes.
''';

    return Scaffold(
      appBar: AppBar(
        title: const Text('CV Publish & Suggestions'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Display CV file link
            const Text('Uploaded CV File:',
                style: TextStyle(
                  color: AppTheme.primaryPurple,
                  fontWeight: FontWeight.bold,
                )),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                spacing: 12,
                children: [
                  const Icon(Iconsax.document_1, color: AppTheme.primaryPurple),
                  SelectableText(
                    cvUrl,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // CV suggestions section
            const Text('CV Improvement Suggestions:',
                style: TextStyle(
                  color: AppTheme.primaryPurple,
                  fontWeight: FontWeight.bold,
                )),
            const SizedBox(height: 8),

            // Fixed-height scrollable box for long text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              constraints: const BoxConstraints(
                maxHeight: 270, // roughly 7 lines of text
              ),
              child: const SingleChildScrollView(
                child: Text(
                  suggestions,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
