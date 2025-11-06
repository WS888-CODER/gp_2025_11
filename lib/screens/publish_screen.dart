import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/theme.dart';

class PublishScreen extends StatefulWidget {
  final String cvUrl; // Actually cvHistoryId
  const PublishScreen({super.key, required this.cvUrl});

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {

  Future<bool> _onWillPop() async {
    const Color dialogBaseColor = Color(0xFF4A5FBC);
    const Color cancelBgColor = Color(0xFFE5E7EB);
    const Color cancelTextColor = Color(0xFF4B5563);
    const Color leaveBgColor = Color(0xFFFC686A);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBaseColor.withOpacity(0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text(
          'Leave Results?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        content: const Text(
          'Are you sure you want to leave the CV enhancement results?',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(
                backgroundColor: cancelBgColor,
                foregroundColor: cancelTextColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(
                backgroundColor: leaveBgColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: const Text(
                'Leave',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('CV Enhancement Results'),
        ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('CVHistory')
            .doc(widget.cvUrl) // cvHistoryId
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text('CV data not found'),
            );
          }

          final cvData = snapshot.data!.data() as Map<String, dynamic>;
          final suggestions = cvData['Suggestions'] as List<dynamic>? ?? [];
          final jobTitle = cvData['JobTitle'] as String? ?? 'Not specified';

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Job Title
                Text(
                  'Job Title: $jobTitle',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),

                // CV suggestions section
                const Text(
                  'AI Enhancement Suggestions:',
                  style: TextStyle(
                    color: AppTheme.primaryPurple,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),

                // Suggestions list
                Expanded(
                  child: suggestions.isEmpty
                      ? const Center(
                          child: Text('No suggestions available yet.'),
                        )
                      : Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: ListView.builder(
                            itemCount: suggestions.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${index + 1}. ',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primaryPurple,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        suggestions[index].toString(),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                ),
                const SizedBox(height: 16),

                // Download PDF button (placeholder for friend's feature)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // TODO: Friend will implement PDF download
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('PDF download feature coming soon!'),
                        ),
                      );
                    },
                    icon: const Icon(Iconsax.document_download),
                    label: const Text('Download Enhanced CV (PDF)'),
                  ),
                ),
              ],
            ),
          );
        },
        ),
      ),
    );
  }
}
