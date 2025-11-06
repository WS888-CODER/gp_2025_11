import 'dart:io';
import 'dart:async';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../config/theme.dart';
import 'publish_screen.dart';

class CVEnhancementScreen extends StatefulWidget {
  const CVEnhancementScreen({super.key});

  @override
  State<CVEnhancementScreen> createState() => _CVEnhancementScreenState();
}

class _CVEnhancementScreenState extends State<CVEnhancementScreen> {
  final TextEditingController _jobTitleController = TextEditingController();

  File? _selectedFile;
  double _uploadProgress = 0.0;
  bool _isUploading = false;
  bool _isExtracting = false;
  bool _extractionComplete = false;
  bool _isEnhancing = false;
  String? _cvHistoryId;
  StreamSubscription<DocumentSnapshot>? _extractionListener;

  @override
  void dispose() {
    _jobTitleController.dispose();
    _extractionListener?.cancel();
    super.dispose();
  }

  // دالة لاختيار ملف PDF أو DOCX
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final fileSize = await file.length();
      final sizeInMB = fileSize / (1024 * 1024);

      if (sizeInMB > 10) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File is larger than 10MB.')),
        );
        return;
      }

      setState(() {
        _selectedFile = file;
      });

      // Automatically upload and extract after file is picked
      await _uploadAndExtractCV();
    }
  }

  // Enhancement button handler - calls AI to enhance CV
  void _handleEnhancement() async {
    if (!_extractionComplete || _cvHistoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for text extraction to complete first.'),
        ),
      );
      return;
    }

    // Check authentication
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User not authenticated. Please log in.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isEnhancing = true;
    });

    try {
      // Debug: Check cvHistoryId
      print('🔍 DEBUG: _cvHistoryId = $_cvHistoryId');

      if (_cvHistoryId == null || _cvHistoryId!.isEmpty) {
        throw Exception('cvHistoryId is null or empty!');
      }

      // Check AI usage limit
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        throw Exception('User data not found');
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final aiUsage = userData['AiUsage'] as Map<String, dynamic>?;

      // Check if we need to reset daily usage
      final lastReset = aiUsage?['LastReset'] as Timestamp?;
      final now = DateTime.now();
      bool needsReset = false;

      if (lastReset != null) {
        final lastResetDate = lastReset.toDate();
        needsReset = lastResetDate.year != now.year ||
            lastResetDate.month != now.month ||
            lastResetDate.day != now.day;
      } else {
        needsReset = true;
      }

      int cvEnhancementCount;

      if (needsReset) {
        // Reset CvEnhancement count for the new day
        await FirebaseFirestore.instance
            .collection('Users')
            .doc(currentUser.uid)
            .update({
          'AiUsage.LastReset': FieldValue.serverTimestamp(),
          'AiUsage.CvEnhancement': 2,
        });
        cvEnhancementCount = 2;
      } else {
        cvEnhancementCount = (aiUsage?['CvEnhancement'] ?? 2) as int;
      }

      // Check if user has credits remaining
      if (cvEnhancementCount <= 0) {
        setState(() {
          _isEnhancing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You have used all your daily CV enhancement credits. Please try again tomorrow.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      // Update JobTitle in Firestore before enhancement
      await FirebaseFirestore.instance
          .collection('CVHistory')
          .doc(_cvHistoryId)
          .update({
        'JobTitle': _jobTitleController.text.trim(),
      });

      // Ensure token is fresh
      await currentUser.getIdToken(true);

      // Call Cloud Function to enhance CV with AI (specify region)
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('enhanceCV');

      print('🔍 DEBUG: Calling function with cvHistoryId: $_cvHistoryId');

      // Pass as a map
      final result = await callable.call(<String, dynamic>{
        'cvHistoryId': _cvHistoryId,
      });

      print('🔍 DEBUG: Got result: $result');

      // Decrement AI usage count after successful enhancement
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(currentUser.uid)
          .update({
        'AiUsage.CvEnhancement': cvEnhancementCount - 1,
      });

      setState(() {
        _isEnhancing = false;
      });

      // Show success dialog
      AwesomeDialog(
        context: context,
        dialogType: DialogType.success,
        body: Container(
          margin: const EdgeInsets.symmetric(vertical: 20),
          child: const Text(
            'CV enhanced successfully with AI!',
            textAlign: TextAlign.center,
          ),
        ),
        btnOkOnPress: () {
          // Navigate to PublishScreen (results screen) and replace current screen
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => PublishScreen(
                  cvUrl: _cvHistoryId ?? '',
                ),
              ),
            );
          }
        },
      ).show();

    } catch (e) {
      setState(() {
        _isEnhancing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error enhancing CV: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // Upload and extract CV automatically after file is picked
  Future<void> _uploadAndExtractCV() async {
    // Validation
    if (_selectedFile == null) {
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated.')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _isExtracting = false;
      _extractionComplete = false;
    });

    try {
      // Step 1: Create CVHistory document
      final cvHistoryRef =
          FirebaseFirestore.instance.collection('CVHistory').doc();
      final cvHistoryId = cvHistoryRef.id;

      await cvHistoryRef.set({
        'CVHistoryID': cvHistoryId,
        'Date': FieldValue.serverTimestamp(),
        'JobTitle': '',
        'OldCVText': '',
        'NewCVText': '',
        'Suggestions': '',
        'NewCVURL': '',
        'UserID': currentUser.uid,
      });

      setState(() {
        _cvHistoryId = cvHistoryId;
      });

      // Step 2: Upload file to temporary location with metadata
      final fileName = _selectedFile!.path.split(Platform.pathSeparator).last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance.ref().child(
          'temp_cv_extraction/${currentUser.uid}/${timestamp}_$fileName');

      // Upload with metadata from the start
      final uploadTask = storageRef.putFile(
        _selectedFile!,
        SettableMetadata(
          customMetadata: {
            'cvHistoryId': cvHistoryId,
            'userId': currentUser.uid,
          },
        ),
      );

      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        setState(() {
          _uploadProgress = progress;
        });
      });

      await uploadTask;

      setState(() {
        _isUploading = false;
        _isExtracting = true;
      });

      // Step 3: Listen for OldCVText to be populated by Cloud Function
      _extractionListener = cvHistoryRef.snapshots().listen((snapshot) {
        if (!mounted) return;

        final data = snapshot.data();
        if (data != null && data['OldCVText'] != null) {
          final oldCVText = data['OldCVText'].toString().trim();
          if (oldCVText.isNotEmpty) {
            setState(() {
              _isExtracting = false;
              _extractionComplete = true;
            });

            _extractionListener?.cancel();

            AwesomeDialog(
              context: context,
              dialogType: DialogType.success,
              body: Container(
                margin: const EdgeInsets.symmetric(vertical: 20),
                child: const Text(
                  'CV uploaded and text extracted successfully!',
                  textAlign: TextAlign.center,
                ),
              ),
            ).show();
          }
        }
      });

      // Timeout after 60 seconds
      Future.delayed(const Duration(seconds: 60), () {
        if (_isExtracting && mounted) {
          _extractionListener?.cancel();
          setState(() {
            _isExtracting = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Text extraction is taking longer than expected. Please try again.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      });
    } catch (e) {
      setState(() {
        _isUploading = false;
        _isExtracting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // نافذة المساعدة
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('The Importance of a CV',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 18,
              color: AppTheme.primaryPurple,
              fontWeight: FontWeight.bold,
            )),
        content: const Text(
          'Your CV is the first impression you make on an employer.\n\n'
          '- Focus on the skills that match the desired job.\n'
          '- Use professional and clear language.\n'
          '- Add your achievements and experiences briefly.\n'
          '- Ensure your layout is attractive and easy to read.\n\n'
          'Improving your CV will help highlight your strengths and increase your chances.',
          textDirection: TextDirection.ltr,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CV Enhancement')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Job title + info icon
            TextField(
              controller: _jobTitleController,
              decoration: const InputDecoration(
                labelText: 'Job Title',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide(color: AppTheme.primaryPurple)),
              ),
            ),
            const SizedBox(height: 5),
            TextButton.icon(
              onPressed: _showHelpDialog,
              label: const Text('Why is CV important?'),
              icon: const Icon(Icons.help_outline),
            ),

            Divider(color: Colors.grey.shade100),
            const SizedBox(height: 5),
            const Text('Choose your CV file (PDF or DOCX):',
                style: TextStyle(
                  color: AppTheme.primaryPurple,
                  fontWeight: FontWeight.bold,
                )),
            const SizedBox(height: 12),
            // اختيار الملف
            DottedBorder(
                options: const RoundedRectDottedBorderOptions(
                  radius: Radius.circular(12),
                  color: AppTheme.primaryPurple,
                  strokeWidth: 1.5,
                  dashPattern: [6, 3], // طول الشرطة + المسافة
                ),
                child: InkWell(
                  onTap: _pickFile,
                  child: Container(
                    height: 150,
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: _selectedFile == null
                          ? const Icon(Iconsax.document_upload,
                              size: 60, color: AppTheme.primaryPurple)
                          : Text(
                              'Selected: ${_selectedFile!.path.split('/').last}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                )),

            const SizedBox(height: 20),

            // Progress bar and status
            if (_isUploading) ...[
              const Text('Uploading CV...', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _uploadProgress),
              const SizedBox(height: 8),
              Text('${(_uploadProgress * 100).toStringAsFixed(0)}%'),
            ],
            if (_isExtracting) ...[
              const Text('Extracting text from CV...', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('This may take a few seconds...'),
            ],
            if (_extractionComplete) ...[
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text('Text extracted successfully!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
            if (_isEnhancing) ...[
              const Text('AI is enhancing your CV...', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('This may take a few moments...'),
            ],
            const SizedBox(height: 8),
            Divider(color: Colors.grey.shade100),

            const Spacer(),

            // زر Enhancement
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (_isUploading || _isExtracting || !_extractionComplete || _isEnhancing)
                    ? null
                    : _handleEnhancement,
                child: _isEnhancing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Enhancement'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
