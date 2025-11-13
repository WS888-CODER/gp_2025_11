import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../config/theme.dart';

class CVEnhancementScreen extends StatefulWidget {
  const CVEnhancementScreen({super.key});

  @override
  State<CVEnhancementScreen> createState() => _CVEnhancementScreenState();
}

class _CVEnhancementScreenState extends State<CVEnhancementScreen> {
  final TextEditingController _jobTitleController = TextEditingController();
  final TextEditingController _jobDescriptionController =
      TextEditingController();

  File? _selectedFile;
  double _uploadProgress = 0.0;
  bool _isUploading = false;
  bool _isExtracting = false;
  bool _extractionComplete = false;
  String? _cvHistoryId;
  StreamSubscription<DocumentSnapshot>? _extractionListener;

  int _currentStep = 0;
  String _jobSelectionType = 'none';
  String? _selectedJobId;
  List<Map<String, dynamic>> _allJobs = [];
  List<Map<String, dynamic>> _wishlistJobs = [];
  bool _loadingJobs = false;
  bool _showAllJobs = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  @override
  void dispose() {
    _jobTitleController.dispose();
    _jobDescriptionController.dispose();
    _extractionListener?.cancel();
    super.dispose();
  }

  Future<void> _loadJobs() async {
    setState(() {
      _loadingJobs = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(() {
          _loadingJobs = false;
        });
        return;
      }

      final jobsSnapshot = await FirebaseFirestore.instance
          .collection('Jobs')
          .orderBy('StartDate', descending: true)
          .get();

      List<Map<String, dynamic>> allJobsList = [];
      for (var doc in jobsSnapshot.docs) {
        final data = doc.data();
        allJobsList.add({
          'id': doc.id,
          'title': data['JobTitle'] ?? 'Untitled',
          'description': data['JobDescription'] ?? '',
          'position': data['Position'] ?? '',
          'status': data['JobStatus'] ?? 'Open',
        });
      }

      final wishlistDocs = await FirebaseFirestore.instance
          .collection('Favourite')
          .where('UserID', isEqualTo: currentUser.uid)
          .get();

      final wishlistJobIds = wishlistDocs.docs
          .map((d) => d.data()['JobID']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      List<Map<String, dynamic>> wishlistJobsList = allJobsList
          .where((job) => wishlistJobIds.contains(job['id']))
          .toList();

      setState(() {
        _allJobs = allJobsList;
        _wishlistJobs = wishlistJobsList;
        _loadingJobs = false;
      });
    } catch (e) {
      print('Error loading jobs: $e');
      setState(() {
        _loadingJobs = false;
      });
    }
  }

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

      await _uploadAndExtractCV();
    }
  }

  Future<void> _uploadAndExtractCV() async {
    if (_selectedFile == null) return;

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

      final fileName = _selectedFile!.path.split(Platform.pathSeparator).last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance.ref().child(
          'temp_cv_extraction/${currentUser.uid}/${timestamp}_$fileName');

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
          }
        }
      });
    } catch (e) {
      setState(() {
        _isUploading = false;
        _isExtracting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error uploading CV: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _goToNextStep() {
    if (_currentStep == 0) {
      if (!_extractionComplete) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please wait for extraction to complete.'),
          ),
        );
        return;
      }
      setState(() {
        _currentStep = 1;
      });
    } else if (_currentStep == 1) {
      _saveAndNavigate();
    }
  }

  Future<void> _saveAndNavigate() async {
    if (_cvHistoryId == null) return;

    if (_jobSelectionType == 'jadeer' && _selectedJobId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a job.')),
      );
      return;
    }

    if (_jobSelectionType == 'other' &&
        _jobTitleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a job title.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      String? savedJobTitle;
      String? savedJobDescription;

      if (_jobSelectionType == 'jadeer' && _selectedJobId != null) {
        final selectedJob = (_showAllJobs ? _allJobs : _wishlistJobs)
            .firstWhere((job) => job['id'] == _selectedJobId);
        savedJobTitle = selectedJob['title'];
        savedJobDescription = selectedJob['description'];

        await FirebaseFirestore.instance
            .collection('CVHistory')
            .doc(_cvHistoryId)
            .update({
          'JobTitle': savedJobTitle,
          'Description': savedJobDescription,
        });
      } else if (_jobSelectionType == 'other') {
        savedJobTitle = _jobTitleController.text.trim();
        savedJobDescription = _jobDescriptionController.text.trim();

        await FirebaseFirestore.instance
            .collection('CVHistory')
            .doc(_cvHistoryId)
            .update({
          'JobTitle': savedJobTitle,
          'Description': savedJobDescription,
        });
      }

      setState(() {
        _isSaving = false;
      });

      Navigator.pushReplacementNamed(
        context,
        '/cv-next-steps',
        arguments: {
          'cvHistoryId': _cvHistoryId,
          'jobTitle': savedJobTitle,
          'hasJobSelection': _jobSelectionType != 'none',
        },
      );
    } catch (e) {
      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: AppTheme.primaryPurple, size: 28),
            const SizedBox(width: 10),
            const Text('Job Selection'),
          ],
        ),
        content: const Text(
          'If you select a specific job you want to apply for, we will help you enhance your CV and highlight your strengths to increase your chances of getting the job.',
          style: TextStyle(fontSize: 16, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryPurple,
        foregroundColor: Colors.white,
        title: const Text('CV Upload'),
        elevation: 0,
      ),
      body: _currentStep == 0 ? _buildUploadStep() : _buildJobSelectionStep(),
    );
  }

  Widget _buildUploadStep() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Upload your CV to enhance',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryPurple,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: (_isUploading || _isExtracting) ? null : _pickFile,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primaryPurple, width: 2),
                  ),
                  child: _selectedFile == null
                      ? const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Iconsax.document_upload,
                                size: 60, color: AppTheme.primaryPurple),
                            SizedBox(height: 16),
                            Text('Click to upload CV',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600)),
                            SizedBox(height: 8),
                            Text('Supported: PDF, DOC, DOCX (Max 10MB)',
                                style: TextStyle(
                                    fontSize: 14, color: Colors.grey)),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle,
                                size: 60, color: Colors.green),
                            const SizedBox(height: 16),
                            Text(
                                'Selected: ${_selectedFile!.path.split('/').last}',
                                textAlign: TextAlign.center),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_isUploading) ...[
            const Text('Uploading CV...',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _uploadProgress),
            const SizedBox(height: 8),
            Text('${(_uploadProgress * 100).toStringAsFixed(0)}%'),
          ],
          if (_isExtracting) ...[
            const Text('Extracting text...',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (_extractionComplete) ...[
            const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text('Extraction complete!',
                    style: TextStyle(
                        color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: (_isUploading || _isExtracting || !_extractionComplete)
                  ? null
                  : _goToNextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryPurple,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Next',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobSelectionStep() {
    final jobsToShow = _showAllJobs ? _allJobs : _wishlistJobs;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Are you interested in applying for a Jadeer job?',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryPurple),
                ),
              ),
              IconButton(
                onPressed: _showInfoDialog,
                icon: const Icon(Icons.help_outline,
                    color: AppTheme.primaryPurple, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                RadioListTile<String>(
                  title: const Text('Select a Jadeer job'),
                  value: 'jadeer',
                  groupValue: _jobSelectionType,
                  activeColor: AppTheme.primaryPurple,
                  onChanged: (value) {
                    setState(() {
                      _jobSelectionType = value!;
                      _selectedJobId = null;
                      _jobTitleController.clear();
                      _jobDescriptionController.clear();
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Apply for another job'),
                  value: 'other',
                  groupValue: _jobSelectionType,
                  activeColor: AppTheme.primaryPurple,
                  onChanged: (value) {
                    setState(() {
                      _jobSelectionType = value!;
                      _selectedJobId = null;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('I don\'t want to specify a job'),
                  value: 'none',
                  groupValue: _jobSelectionType,
                  activeColor: AppTheme.primaryPurple,
                  onChanged: (value) {
                    setState(() {
                      _jobSelectionType = value!;
                      _selectedJobId = null;
                      _jobTitleController.clear();
                      _jobDescriptionController.clear();
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_jobSelectionType == 'jadeer') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_showAllJobs ? 'All Jadeer Jobs' : 'Your Wishlist Jobs',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showAllJobs = !_showAllJobs;
                      _selectedJobId = null;
                    });
                  },
                  icon: Icon(_showAllJobs ? Icons.favorite : Icons.grid_view),
                  label: Text(_showAllJobs ? 'Show Wishlist' : 'Show All Jobs'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryPurple),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingJobs)
              const Center(child: CircularProgressIndicator())
            else if (jobsToShow.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12)),
                child: Center(
                  child: Text(
                      _showAllJobs
                          ? 'No jobs available'
                          : 'No jobs in wishlist',
                      style: const TextStyle(color: Colors.grey)),
                ),
              )
            else
              Column(
                children: jobsToShow.map((job) {
                  final isClosed =
                      job['status']?.toString().toLowerCase() == 'closed';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _selectedJobId == job['id']
                            ? AppTheme.primaryPurple
                            : Colors.grey[300]!,
                        width: _selectedJobId == job['id'] ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      color: isClosed ? Colors.grey[100] : null,
                    ),
                    child: RadioListTile<String>(
                      title: Text(job['title'],
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isClosed ? Colors.grey : Colors.black)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (job['position']?.toString().isNotEmpty == true)
                            Text(job['position'],
                                style: TextStyle(
                                    color: isClosed
                                        ? Colors.grey
                                        : Colors.black54)),
                          Text(
                            job['description'].length > 100
                                ? '${job['description'].substring(0, 100)}...'
                                : job['description'],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: isClosed ? Colors.grey : Colors.black54),
                          ),
                          if (isClosed)
                            const Text('(Closed)',
                                style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold)),
                        ],
                      ),
                      value: job['id'],
                      groupValue: _selectedJobId,
                      activeColor: AppTheme.primaryPurple,
                      onChanged: isClosed
                          ? null
                          : (value) => setState(() => _selectedJobId = value),
                    ),
                  );
                }).toList(),
              ),
          ],
          if (_jobSelectionType == 'other') ...[
            const Text('Or do you want to apply for another job?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _jobTitleController,
              decoration: InputDecoration(
                labelText: 'Job Title',
                hintText: 'Enter the job title',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppTheme.primaryPurple, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _jobDescriptionController,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: 'Job Description',
                hintText: 'Enter the job description (optional)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppTheme.primaryPurple, width: 2),
                ),
                alignLabelWithHint: true,
              ),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _goToNextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryPurple,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _isSaving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Next',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
