import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
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
  final TextEditingController _searchController = TextEditingController();

  File? _selectedFile;
  double _uploadProgress = 0.0;
  bool _isUploading = false;
  bool _isExtracting = false;
  bool _extractionComplete = false;
  String? _cvHistoryId;
  bool _navigatedSuccessfully = false;
  StreamSubscription<DocumentSnapshot>? _extractionListener;

  int _currentStep = 0;
  String _jobSelectionType = 'none';
  String? _selectedJobId;
  List<Map<String, dynamic>> _allJobs = [];
  List<Map<String, dynamic>> _wishlistJobs = [];
  List<Map<String, dynamic>> _filteredJobs = [];
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
    if (!_navigatedSuccessfully && _cvHistoryId != null) {
      FirebaseFirestore.instance
          .collection('CVHistory')
          .doc(_cvHistoryId)
          .delete();
    }
    _jobTitleController.dispose();
    _jobDescriptionController.dispose();
    _searchController.dispose();
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
        final userId = data['UserID'] ?? '';

        // Fetch company info
        String companyName = 'Company';
        String companyLogo = '';
        if (userId.isNotEmpty) {
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('Users')
                .doc(userId)
                .get();
            if (userDoc.exists) {
              final userData = userDoc.data();
              companyName =
                  userData?['CompanyName'] ?? userData?['Name'] ?? 'Company';
              companyLogo = userData?['PhotoURL'] ?? '';
            }
          } catch (e) {
            print('Error fetching company: $e');
          }
        }

        allJobsList.add({
          'id': doc.id,
          'title': data['JobTitle'] ?? 'Untitled',
          'description': data['JobDescription'] ?? '',
          'position': data['Position'] ?? '',
          'status': data['JobStatus'] ?? 'Open',
          'companyName': companyName,
          'companyLogo': companyLogo,
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

  void _filterJobs(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredJobs = [];
      } else {
        final jobsToFilter = _showAllJobs ? _allJobs : _wishlistJobs;
        _filteredJobs = jobsToFilter.where((job) {
          final title = job['title']?.toString().toLowerCase() ?? '';
          final company = job['companyName']?.toString().toLowerCase() ?? '';
          final position = job['position']?.toString().toLowerCase() ?? '';
          final searchLower = query.toLowerCase();

          return title.contains(searchLower) ||
              company.contains(searchLower) ||
              position.contains(searchLower);
        }).toList();
      }
    });
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
        SnackHelper.error(context, 'File is larger than 10MB.');
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
      SnackHelper.error(context, 'User not authenticated.');
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

      _extractionListener?.cancel();
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

      SnackHelper.error(context, 'Error uploading CV: $e');
    }
  }

  void _goToNextStep() {
    if (_currentStep == 0) {
      if (!_extractionComplete) {
        SnackHelper.error(context, 'Please wait for extraction to complete.');
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
      SnackHelper.error(context, 'Please select a job.');
      return;
    }

    if (_jobSelectionType == 'other' &&
        _jobTitleController.text.trim().isEmpty) {
      SnackHelper.error(context, 'Please enter a job title.');
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
      _navigatedSuccessfully = true;

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

      SnackHelper.error(context, 'Error: $e');
    }
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => const JadeerDialog<void>(
        title: 'Job Selection',
        primaryLabel: 'Got it',
        primaryResult: null,
        content: Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'If you select a specific job you want to apply for, we will help you enhance your CV and highlight your strengths to increase your chances of getting the job.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    // Allow free navigation if nothing started yet
    if (_currentStep == 0 && _selectedFile == null && !_isUploading) {
      return true;
    }

    // Prevent back during upload/extraction
    if (_isUploading || _isExtracting || _isSaving) {
      return false;
    }

    // Show warning if file selected or in job selection
    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (context) => const JadeerDialog<bool>(
        title: 'Leave CV Enhancement?',
        content: Text(
          'Your progress will be lost. Are you sure you want to leave?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
          ),
        ),
        secondaryLabel: 'Cancel',
        secondaryResult: false,
        primaryLabel: 'Leave',
        primaryResult: true,
      ),
    );

    if (shouldPop == true && _cvHistoryId != null) {
      await FirebaseFirestore.instance
          .collection('CVHistory')
          .doc(_cvHistoryId)
          .delete();
    }

    return shouldPop ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: ThemedScaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.primaryPurple,
          foregroundColor: Colors.white,
          title: const Text('CV Enhancement',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              )),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
          actions: _currentStep == 1
              ? [
                  IconButton(
                    onPressed: _showInfoDialog,
                    icon: const Icon(Icons.help_outline, color: Colors.white),
                  ),
                ]
              : null,
        ),
        body: _currentStep == 0 ? _buildUploadStep() : _buildJobSelectionStep(),
      ),
    );
  }

  Widget _buildUploadStep() {
    final scheme = Theme.of(context).colorScheme;
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
          const SizedBox(height: 10),
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: (_isUploading || _isExtracting) ? null : _pickFile,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _selectedFile == null
                      ? const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Iconsax.document_upload,
                                size: 60, color: Color(0xFFFF7B7B)),
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
                                size: 60, color: Color(0xFFFF7B7B)),
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
          if (_isUploading) ...[
            const SizedBox(height: 16),
            const Text('Uploading CV...',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _uploadProgress),
            const SizedBox(height: 8),
            Text('${(_uploadProgress * 100).toStringAsFixed(0)}%'),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: (_isUploading || _isExtracting || !_extractionComplete)
                  ? null
                  : _goToNextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryPurple,
                foregroundColor: scheme.onPrimary,
                disabledBackgroundColor: scheme.onSurface.withOpacity(0.22),
                disabledForegroundColor: scheme.onSurface.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
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
    final scheme = Theme.of(context).colorScheme;

    final baseJobs = _showAllJobs ? _allJobs : _wishlistJobs;
    final jobsToShow =
        _searchController.text.isEmpty ? baseJobs : _filteredJobs;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Are you interested in applying for a specific job?',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryPurple),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: scheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        title: const Text('Select a job from Jadeer'),
                        value: 'jadeer',
                        groupValue: _jobSelectionType,
                        activeColor: const Color(0xFFFF7B7B),
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
                        activeColor: const Color(0xFFFF7B7B),
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
                        activeColor: const Color(0xFFFF7B7B),
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
                      Text(
                          _showAllJobs
                              ? 'All Jadeer Jobs'
                              : 'Your Favorite Jobs',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _showAllJobs = !_showAllJobs;
                            _selectedJobId = null;
                            _searchController.clear();
                            _filterJobs('');
                          });
                        },
                        icon: Icon(
                            _showAllJobs ? Icons.favorite : Icons.grid_view,
                            color: const Color(0xFFFF7B7B)),
                        label: Text(
                            _showAllJobs ? 'Show Favorite' : 'Show All Jobs',
                            style: const TextStyle(color: Color(0xFFFF7B7B))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // خانة البحث
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search,
                          color: Colors.grey[500],
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: _filterJobs,
                            style: const TextStyle(fontSize: 15),
                            decoration: InputDecoration(
                              hintText: 'Search jobs, companies...',
                              hintStyle: TextStyle(
                                fontSize: 15,
                                color: Colors.grey[500],
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        if (_searchController.text.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              _filterJobs('');
                            },
                            child: Icon(
                              Icons.clear,
                              color: Colors.grey[400],
                              size: 20,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_loadingJobs)
                    const Center(child: CircularProgressIndicator())
                  else if (jobsToShow.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: scheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12)),
                      child: Center(
                        child: Text(
                          _searchController.text.isNotEmpty
                              ? 'No jobs found'
                              : (_showAllJobs
                                  ? 'No jobs available'
                                  : 'No jobs in favorite'),
                          style: TextStyle(
                              color: scheme.onSurface.withOpacity(0.6)),
                        ),
                      ),
                    )
                  else
                    Column(
                      children: jobsToShow.map((job) {
                        final isClosed =
                            job['status']?.toString().toLowerCase() == 'closed';
                        final isSelected = _selectedJobId == job['id'];
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedJobId = job['id']),
                          child: Card(
                            elevation: 0.5,
                            margin: const EdgeInsets.only(bottom: 12),
                            color: scheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: isSelected
                                    ? AppTheme.primaryPurple
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Radio<String>(
                                    value: job['id'],
                                    groupValue: _selectedJobId,
                                    activeColor: const Color(0xFFFF7B7B),
                                    onChanged: (value) =>
                                        setState(() => _selectedJobId = value),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Company name with logo
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: AppTheme.primaryPurple,
                                                  width: 2,
                                                ),
                                              ),
                                              child: CircleAvatar(
                                                radius: 16,
                                                backgroundImage:
                                                    job['companyLogo']
                                                                ?.toString()
                                                                .isNotEmpty ==
                                                            true
                                                        ? NetworkImage(
                                                            job['companyLogo'])
                                                        : null,
                                                child: job['companyLogo']
                                                            ?.toString()
                                                            .isEmpty !=
                                                        false
                                                    ? const Icon(Icons.business,
                                                        size: 16)
                                                    : null,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                job['companyName'] ?? 'Company',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.primaryPurple,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        // Job title
                                        Text(
                                          job['title'],
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: scheme.onSurface,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        // Posted date
                                        Text(
                                          'Posted: 2025/11/21',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        // Position tag
                                        if (job['position']
                                                ?.toString()
                                                .isNotEmpty ==
                                            true)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryPurple
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              job['position'],
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppTheme.primaryPurple,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        if (isClosed)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 6),
                                            child: Text(
                                              '(Closed)',
                                              style: TextStyle(
                                                color: scheme.error,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                ],
                if (_jobSelectionType == 'other') ...[
                  const Text('Enter Job Title and Job Description',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(
                    children: const [
                      Text(
                        'Job Title',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(width: 4),
                      Text(
                        '*',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _jobTitleController,
                      style:
                          TextStyle(color: scheme.onSurface.withOpacity(0.8)),
                      decoration: InputDecoration(
                        hintText: 'Enter the job title',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: scheme.surface,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: const [
                      Text(
                        'Job Description',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(width: 4),
                      Text(
                        '*',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _jobDescriptionController,
                      maxLines: 5,
                      style:
                          TextStyle(color: scheme.onSurface.withOpacity(0.8)),
                      decoration: InputDecoration(
                        hintText: 'Enter the job description',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: scheme.surface,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Fixed button at the bottom
        Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _goToNextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryPurple,
                foregroundColor: scheme.onPrimary,
                disabledBackgroundColor: scheme.onSurface.withOpacity(0.22),
                disabledForegroundColor: scheme.onSurface.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: _isSaving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Next',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }
}
