import 'dart:io';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
  String? _uploadedFileUrl;

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
          const SnackBar(content: Text('الملف أكبر من 10 ميجا.')),
        );
        return;
      }

      setState(() {
        _selectedFile = file;
      });
    }
  }

  void _publishFile() async {
    if (_isUploading) return;

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PublishScreen(
            cvUrl: _selectedFile?.path.split('/').last ?? '',
          ),
        ),
      );
    }
  }

  // دالة رفع الملف إلى Firebase Storage
  Future<void> _uploadFile() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء اختيار ملف السيرة الذاتية.')),
      );
      return;
    }

    final fileName = _selectedFile!.path.split('/').last;
    final storageRef = FirebaseStorage.instance.ref().child(
        'enhancement_cv/${DateTime.now().millisecondsSinceEpoch}_$fileName');

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final uploadTask = storageRef.putFile(_selectedFile!);

      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        setState(() {
          _uploadProgress = progress;
        });
      });

      await uploadTask;
      _uploadedFileUrl = await storageRef.getDownloadURL();

      setState(() {
        _isUploading = false;
      });

      final AwesomeDialog awesomeDialog = AwesomeDialog(
        context: context,
        dialogType: DialogType.success,
        body: Container(
          margin: const EdgeInsets.symmetric(vertical: 20),
          child: const Text(
            'تم رفع السيرة الذاتية بنجاح!',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
      awesomeDialog.show();

      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(
      //     backgroundColor: Colors.green,
      //     content: Text(
      //       'تم رفع السيرة الذاتية بنجاح!',
      //       textDirection: TextDirection.rtl,
      //     ),
      //   ),
      // );
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء رفع الملف: $e'),
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

            // Progress bar
            if (_isUploading) ...[
              LinearProgressIndicator(value: _uploadProgress),
              const SizedBox(height: 8),
              Text('${(_uploadProgress * 100).toStringAsFixed(0)}%'),
            ],
            Divider(color: Colors.grey.shade100),

            const Spacer(),

            // زر Enhancement
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _uploadFile,
                child: _isUploading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Enhancement'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _publishFile,
                child: _isUploading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Publish'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
