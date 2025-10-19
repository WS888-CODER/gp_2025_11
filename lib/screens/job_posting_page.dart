import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class JobPostingPage extends StatefulWidget {
  const JobPostingPage({super.key});

  @override
  State<JobPostingPage> createState() => _JobPostingPageState();
}

class _JobPostingPageState extends State<JobPostingPage> {
  final _formKey = GlobalKey<FormState>();

  final _jobTitleController = TextEditingController();
  final _jobDescriptionController = TextEditingController();
  final _positionController = TextEditingController();
  final _specialityController = TextEditingController();
  final _requirementController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  final List<String> _requirements = [];

  // ---- وضع تعديل أم إنشاء؟
  bool _isEdit = false;
  String? _jobId; // لو تعديل راح نستعمله

  // AI Credits tracking
  int _aiCreditsRemaining = 2;
  bool _loadingCredits = true;

  @override
  void initState() {
    super.initState();
    // نقرأ الarguments بعد بناء الصفحة
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Security check: Verify user is a verified company
      await _verifyUserAccess();

      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        _isEdit = true;
        _jobId = args['jobId'] as String?;

        // Read with correct Firestore field names
        _jobTitleController.text = (args['JobTitle'] ?? args['title'] ?? '') as String;
        _positionController.text = (args['Position'] ?? args['position'] ?? '') as String;
        _specialityController.text = (args['Specialty'] ?? args['specialty'] ?? args['speciality'] ?? '') as String;
        _jobDescriptionController.text = (args['JobDescription'] ?? args['description'] ?? '') as String;

        // requirements يمكن تجي List<String> أو List<dynamic>
        final req = args['Requirements'] ?? args['requirements'];
        if (req is List) {
          _requirements
            ..clear()
            ..addAll(req.map((e) => e.toString()));
        }

        // التواريخ (timeStamp/date/string)
        DateTime? _asDate(v) {
          if (v == null) return null;
          if (v is Timestamp) return v.toDate();
          if (v is DateTime) return v;
          if (v is String && v.isNotEmpty) {
            return DateTime.tryParse(v);
          }
          return null;
        }

        _startDate = _asDate(args['StartDate'] ?? args['startDate']);
        _endDate = _asDate(args['EndDate'] ?? args['endDate']);

        setState(() {});
      }

      // Fetch AI credits for create mode
      if (!_isEdit) {
        await _fetchAICredits();
      }
    });
  }

  Future<void> _fetchAICredits() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      setState(() => _loadingCredits = false);
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        setState(() => _loadingCredits = false);
        return;
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

      int jobPostingCount;

      if (needsReset) {
        // Reset JobPosting count for the new day
        await FirebaseFirestore.instance
            .collection('Users')
            .doc(currentUser.uid)
            .update({
          'AiUsage.LastReset': FieldValue.serverTimestamp(),
          'AiUsage.JobPosting': 2,
        });
        jobPostingCount = 2;
      } else {
        jobPostingCount = (aiUsage?['JobPosting'] ?? 2) as int;
      }

      setState(() {
        _aiCreditsRemaining = jobPostingCount;
        _loadingCredits = false;
      });
    } catch (e) {
      setState(() => _loadingCredits = false);
    }
  }

  Future<void> _verifyUserAccess() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      _showErrorAndGoBack('You must be logged in to access this page');
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        _showErrorAndGoBack('User data not found');
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final userType = userData['UserType'] ?? '';
      final accountStatus = userData['AccountStatus'] ?? '';
      final isProfileComplete = userData['IsProfileComplete'] ?? false;

      // Check if user is a Company
      if (userType != 'Company') {
        _showErrorAndGoBack('Only companies can create job postings');
        return;
      }

      // Check if company account is Verified
      if (accountStatus != 'Verified') {
        if (accountStatus == 'Pending') {
          _showErrorAndGoBack('Your company account is pending approval. Please wait for admin verification.');
        } else if (accountStatus == 'Rejected') {
          _showErrorAndGoBack('Your company account has been rejected. Please contact support.');
        } else {
          _showErrorAndGoBack('Your company account is not verified. Please contact support.');
        }
        return;
      }

      // Check if profile is complete
      if (!isProfileComplete) {
        _showErrorAndGoBack('Please complete your company profile before creating or editing job postings.');
        return;
      }
    } catch (e) {
      _showErrorAndGoBack('Error verifying access: $e');
    }
  }

  void _showErrorAndGoBack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _jobTitleController.dispose();
    _jobDescriptionController.dispose();
    _positionController.dispose();
    _specialityController.dispose();
    _requirementController.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day); // Strip time

    // Use existing date if it's today or future, otherwise use today
    final DateTime initialDate = (_startDate != null && !_startDate!.isBefore(today))
        ? _startDate!
        : today;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _selectEndDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day); // Strip time

    // First allowed date is the later of start date or today
    final DateTime firstAllowedDate = _startDate != null && !_startDate!.isBefore(today)
        ? _startDate!
        : today;

    // Initial date should be valid (between firstAllowedDate and lastDate)
    final DateTime initialDate = (_endDate != null && !_endDate!.isBefore(firstAllowedDate))
        ? _endDate!
        : firstAllowedDate;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstAllowedDate,
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  void _addRequirement() {
    if (_requirementController.text.trim().isNotEmpty) {
      setState(() {
        _requirements.add(_requirementController.text.trim());
        _requirementController.clear();
      });
    }
  }

  void _removeRequirement(int index) {
    setState(() => _requirements.removeAt(index));
  }

  List<String> _extractKeywords() {
    final Set<String> keywords = {};

    // Common filler words to exclude
    final stopWords = {
      'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
      'of', 'with', 'by', 'from', 'as', 'is', 'was', 'are', 'be', 'been',
      'this', 'that', 'these', 'those', 'will', 'can', 'could', 'should',
      'would', 'may', 'must', 'have', 'has', 'had', 'do', 'does', 'did',
      'if', 'you', 'we', 'our', 'your', 'their', 'them', 'they', 'he', 'she',
      'it', 'us', 'not', 'no', 'yes', 'all', 'some', 'any', 'many', 'much',
      'few', 'more', 'most', 'less', 'about', 'into', 'than', 'over', 'under',
      'between', 'through', 'during', 'when', 'where', 'why', 'how', 'what',
      'which', 'who', 'whom', 'whose', 'just', 'only', 'also', 'too', 'very',
      'quite', 'get', 'got', 'make', 'made', 'such', 'each', 'other', 'both',
      'either', 'neither', 'whether', 'while', 'until', 'since', 'after',
      'before', 'above', 'below', 'out', 'up', 'down', 'off', 'here', 'there',
    };

    // Extract from title
    final titleWords = _jobTitleController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty && !stopWords.contains(word.toLowerCase()))
        .map((word) => word.toLowerCase());
    keywords.addAll(titleWords);

    // Extract from position
    final positionWords = _positionController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty && !stopWords.contains(word.toLowerCase()))
        .map((word) => word.toLowerCase());
    keywords.addAll(positionWords);

    // Extract from specialty
    final specialtyWords = _specialityController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty && !stopWords.contains(word.toLowerCase()))
        .map((word) => word.toLowerCase());
    keywords.addAll(specialtyWords);

    // Extract from job description
    final descriptionWords = _jobDescriptionController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty && !stopWords.contains(word.toLowerCase()))
        .map((word) => word.toLowerCase());
    keywords.addAll(descriptionWords);

    // Extract from requirements
    for (final requirement in _requirements) {
      final reqWords = requirement
          .trim()
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty && !stopWords.contains(word.toLowerCase()))
          .map((word) => word.toLowerCase());
      keywords.addAll(reqWords);
    }

    return keywords.toList();
  }

  Future<void> _generateJobPost() async {
    if (_jobTitleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter job title first')),
      );
      return;
    }

    if (_positionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter position first')),
      );
      return;
    }

    if (_specialityController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter speciality first')),
      );
      return;
    }

    // Check if user is logged in
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to use AI generation')),
      );
      return;
    }

    try {
      // Check AI usage limit
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User data not found')),
        );
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final aiUsage = userData['AiUsage'] as Map<String, dynamic>?;

      // Check if we need to reset daily usage
      final lastReset = aiUsage?['LastReset'] as Timestamp?;
      final now = DateTime.now();
      bool needsReset = false;

      if (lastReset != null) {
        final lastResetDate = lastReset.toDate();
        // Check if last reset was on a different day
        needsReset = lastResetDate.year != now.year ||
                     lastResetDate.month != now.month ||
                     lastResetDate.day != now.day;
      } else {
        needsReset = true;
      }

      int jobPostingCount;

      if (needsReset) {
        // Reset JobPosting count for the new day (companies only)
        await FirebaseFirestore.instance
            .collection('Users')
            .doc(currentUser.uid)
            .update({
          'AiUsage.LastReset': FieldValue.serverTimestamp(),
          'AiUsage.JobPosting': 2,
        });
        jobPostingCount = 2;

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Daily AI usage limit has been reset!'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        jobPostingCount = (aiUsage?['JobPosting'] ?? 0) as int;
      }

      if (jobPostingCount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You have reached your AI generation limit for job postings. Resets tomorrow!'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Call your Cloud Function from firebase RUNNING THIS REQUIRES WIFI
      final url = Uri.parse('https://us-central1-jadeer-b4953.cloudfunctions.net/generateJobPost');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generating job description...')),
      );

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': _jobTitleController.text,
          'position': _positionController.text,
          'speciality': _specialityController.text,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final generatedText = data['job_post'] ?? '';

        final cleanedText = generatedText
            .toString()
            .replaceAll(RegExp(r'\*\*'), '')
            .replaceAll(RegExp(r'\*'), '')
            .replaceAll(RegExp(r'#+'), '')
            .replaceAll(RegExp(r'- '), '• ')
            .trim();

        setState(() => _jobDescriptionController.text = cleanedText);

        // Decrement AI usage count
        await FirebaseFirestore.instance
            .collection('Users')
            .doc(currentUser.uid)
            .update({
          'AiUsage.JobPosting': jobPostingCount - 1,
        });

        // Update local credits state
        setState(() {
          _aiCreditsRemaining = jobPostingCount - 1;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI job description generated! (${jobPostingCount - 1} uses remaining)'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${response.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    // Get current user ID
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to post a job')),
      );
      return;
    }

    final userId = currentUser.uid;

    try {
      final jobs = FirebaseFirestore.instance.collection('Jobs');

      if (_isEdit && _jobId != null && _jobId!.isNotEmpty) {
        // EDIT MODE - Only update StartDate and EndDate
        await jobs.doc(_jobId).update({
          'StartDate': _startDate,
          'EndDate': _endDate,
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job dates updated successfully')),
        );
      } else {
        // CREATE MODE - Validate requirements first
        if (_requirements.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please add at least one requirement')),
          );
          return;
        }

        final keywords = _extractKeywords();

        final data = <String, dynamic>{
          'JobTitle': _jobTitleController.text.trim(),
          'JobDescription': _jobDescriptionController.text.trim(),
          'Position': _positionController.text.trim(),
          'Specialty': _specialityController.text.trim(),
          'Requirements': _requirements,
          'StartDate': _startDate,
          'EndDate': _endDate,
          'JobKeywords': keywords,
          'UserID': userId,
        };

        // CREATE - generate new JobID and use it as document ID
        final newJobDoc = jobs.doc(); // Generate document ID
        final jobId = newJobDoc.id;

        await newJobDoc.set({
          ...data,
          'JobID': jobId,
          'JobStatus': 'Open',
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job created successfully')),
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';

  Future<bool> _onWillPop() async {
    // Show confirmation dialog
    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abandon Changes?'),
        content: const Text(
          'Are you sure you want to go back? Any unsaved changes will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return shouldPop ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? 'Edit Job' : 'Create Job Posting'),
        ),
        body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // Job Title
            TextFormField(
              controller: _jobTitleController,
              enabled: !_isEdit,
              decoration: InputDecoration(
                labelText: 'Job Title *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'This field is required' : null,
            ),
            const SizedBox(height: 16),

            // Position
            TextFormField(
              controller: _positionController,
              enabled: !_isEdit,
              decoration: InputDecoration(
                labelText: 'Position *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'This field is required' : null,
            ),
            const SizedBox(height: 16),

            // Speciality
            TextFormField(
              controller: _specialityController,
              enabled: !_isEdit,
              decoration: InputDecoration(
                labelText: 'Speciality *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'This field is required' : null,
            ),
            const SizedBox(height: 16),

            // AI Generate Button (only show in create mode)
            if (!_isEdit) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_loadingCredits)
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Text(
                        'Loading credits...',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        '$_aiCreditsRemaining credits remaining (resets daily)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _aiCreditsRemaining > 0 ? _generateJobPost : null,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text(
                    'Generate with AI',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: _aiCreditsRemaining > 0 ? const Color(0xFF49469F) : Colors.grey,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Job Description
            TextFormField(
              controller: _jobDescriptionController,
              enabled: !_isEdit,
              decoration: InputDecoration(
                labelText: 'Job Description *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                alignLabelWithHint: true,
              ),
              minLines: 6,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              validator: (v) => (v == null || v.isEmpty) ? 'This field is required' : null,
            ),
            const SizedBox(height: 16),

            // Requirements (only show in create mode, display read-only in edit mode)
            if (!_isEdit)
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Requirements *',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _requirementController,
                              decoration: InputDecoration(
                                hintText: 'Enter requirement',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onSubmitted: (_) => _addRequirement(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _addRequirement,
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_requirements.isEmpty)
                        const Text('No requirements added yet', style: TextStyle(color: Colors.grey))
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _requirements.length,
                          itemBuilder: (context, index) {
                            return Card(
                              child: ListTile(
                                title: Text(_requirements[index]),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _removeRequirement(index),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              )
            else
              // Read-only requirements display in edit mode
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Requirements',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      if (_requirements.isEmpty)
                        const Text('No requirements', style: TextStyle(color: Colors.grey))
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _requirements.length,
                          itemBuilder: (context, index) {
                            return Card(
                              color: Colors.grey[100],
                              child: ListTile(
                                title: Text(
                                  _requirements[index],
                                  style: const TextStyle(color: Colors.black87),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Start Date
            InkWell(
              onTap: _selectStartDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Start Date *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                child: Text(
                  _startDate != null ? _fmtDate(_startDate!) : 'Select date',
                  style: TextStyle(
                    color: _startDate != null ? Colors.black : Colors.grey,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // End Date
            InkWell(
              onTap: _selectEndDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'End Date *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                child: Text(
                  _endDate != null ? _fmtDate(_endDate!) : 'Select date',
                  style: TextStyle(
                    color: _endDate != null ? Colors.black : Colors.grey,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Submit Button
            ElevatedButton(
              onPressed: _submitForm,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _isEdit ? 'Save changes' : 'Create Job Posting',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
