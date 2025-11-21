import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

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
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          // ✅ Fixed: Removed Expanded from Dialog actions
          SizedBox(
            width: 120,
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
          SizedBox(
            width: 120,
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

  // ✅ Fixed: Better PDF opening with fallback
  Future<void> _openPDF(String url) async {
    try {
      final uri = Uri.parse(url);

      // Try to launch with external application
      final canLaunch = await canLaunchUrl(uri);

      if (canLaunch) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        // Fallback: Try platform default
        await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
        );
      }
    } catch (e) {
      print('❌ Error opening PDF: $e');

      if (mounted) {
        SnackHelper.error(context, 'Could not open PDF: ${e.toString()}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.primaryPurple,
          foregroundColor: Colors.white,
          title: const Text('CV Enhancement Results',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              )),
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('CVHistory')
              .doc(widget.cvUrl)
              .snapshots(),
          builder: (context, snapshot) {
            final scheme = Theme.of(context).colorScheme;

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

            // ✅ Handle both String and List types for Suggestions
            final suggestionsRaw = cvData['Suggestions'];
            final List<dynamic> suggestions;

            if (suggestionsRaw == null) {
              suggestions = [];
            } else if (suggestionsRaw is List) {
              suggestions = suggestionsRaw;
            } else if (suggestionsRaw is String) {
              suggestions = [suggestionsRaw];
            } else {
              suggestions = [];
            }

            final jobTitle = cvData['JobTitle'] as String? ?? 'Not specified';
            final pdfUrl = cvData['NewCVURL'] as String?;

            return SingleChildScrollView(
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

                  // 📄 PDF Preview Box
                  if (pdfUrl == null || pdfUrl.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: scheme.surfaceVariant.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: scheme.outline.withOpacity(0.4)),
                      ),
                      child: Column(
                        children: [
                          const CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation(AppTheme.primaryPurple),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Generating your enhanced CV...',
                            style: TextStyle(
                              fontSize: 14,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surfaceVariant.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.primaryPurple.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryPurple.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Iconsax.document_text,
                              size: 48,
                              color: AppTheme.primaryPurple,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Enhanced CV (PDF)',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryPurple,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your professionally enhanced CV is ready!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ✅ Fixed: Removed Expanded from Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // View Button
                              SizedBox(
                                width: 140,
                                child: ElevatedButton.icon(
                                  onPressed: () => _openPDF(pdfUrl),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryPurple,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(Iconsax.eye, size: 20),
                                  label: const Text('View'),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Download Button
                              SizedBox(
                                width: 140,
                                child: ElevatedButton.icon(
                                  onPressed: () => _openPDF(pdfUrl),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Color(0xFFFD6C67),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(Iconsax.document_download,
                                      size: 20),
                                  label: const Text('Download'),
                                ),
                              ),
                            ],
                          ),

                          // ✅ NEW: Debug URL button
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              print('📋 PDF URL: $pdfUrl');
                              SnackHelper.success(
                                  context, 'URL copied to console');
                            },
                            child: const Text(
                              'Show URL (Debug)',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  // AI Suggestions Section
                  const Text(
                    'Suggestions:',
                    style: TextStyle(
                      color: AppTheme.primaryPurple,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Suggestions List
                  suggestions.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: scheme.surfaceVariant.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: scheme.outline.withOpacity(0.4)),
                          ),
                          child: Center(
                            child: Text(
                              'No suggestions available yet.',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.surfaceVariant.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: scheme.outline.withOpacity(0.4)),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: suggestions.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '• ',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primaryPurple,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        suggestions[index].toString(),
                                        style: TextStyle(
                                          fontSize: 15,
                                          height: 1.5,
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        )
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
