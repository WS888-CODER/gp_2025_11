import 'package:flutter/material.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dropdown_button2/dropdown_button2.dart';

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
  final _customSpecialityController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  final List<String> _requirements = [];

  // Specialty dropdown
  static const List<String> _specialtyOptions = [
    'Software Development',
    'Frontend Development',
    'Backend Development',
    'Full Stack Development',
    'Mobile Development',
    'Data Science',
    'Machine Learning/AI',
    'Cybersecurity',
    'DevOps',
    'Cloud Computing',
    'UI/UX Design',
    'Graphic Design',
    'Product Management',
    'Project Management',
    'Quality Assurance/Testing',
    'Network Engineering',
    'Database Administration',
    'Business Analysis',
    'Digital Marketing',
    'Content Writing',
  ];
  String? _selectedSpecialty;

  // ---- وضع تعديل أم إنشاء؟
  bool _isEdit = false;
  String? _jobId; // لو تعديل راح نستعمله

  // AI Credits tracking
  int _aiCreditsRemaining = 2;
  bool _loadingCredits = true;

  // Track if user attempted to submit
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    // نقرأ الarguments بعد بناء الصفحة
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Security check: Verify user is a verified company
      await _verifyUserAccess();

      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        _isEdit = true;
        _jobId = args['jobId'] as String?;

        // Check if coming from questions page - need to fetch job data
        final fromQuestionsPage = args['fromQuestionsPage'] == true;

        if (fromQuestionsPage && _jobId != null) {
          // Fetch job data from Firestore
          try {
            final jobDoc = await FirebaseFirestore.instance
                .collection('Jobs')
                .doc(_jobId)
                .get();

            if (jobDoc.exists) {
              final jobData = jobDoc.data() as Map<String, dynamic>;

              _jobTitleController.text = jobData['JobTitle'] ?? '';
              _positionController.text = jobData['Position'] ?? '';
              _selectedSpecialty = jobData['Specialty'] ?? '';
              if (_selectedSpecialty != null && !_specialtyOptions.contains(_selectedSpecialty)) {
                _customSpecialityController.text = _selectedSpecialty!;
              }
              _jobDescriptionController.text = jobData['JobDescription'] ?? '';

              final req = jobData['Requirements'];
              if (req is List) {
                _requirements
                  ..clear()
                  ..addAll(req.map((e) => e.toString()));
              }

              // التواريخ
              DateTime? _asDate(v) {
                if (v == null) return null;
                if (v is Timestamp) return v.toDate();
                if (v is DateTime) return v;
                if (v is String && v.isNotEmpty) {
                  return DateTime.tryParse(v);
                }
                return null;
              }

              _startDate = _asDate(jobData['StartDate']);
              _endDate = _asDate(jobData['EndDate']);
            }
          } catch (e) {
            _showErrorSnackBar('Error loading job: $e');
          }
        } else {
          // Normal edit mode with all data in args
          _jobTitleController.text =
              (args['JobTitle'] ?? args['title'] ?? '') as String;
          _positionController.text =
              (args['Position'] ?? args['position'] ?? '') as String;

          // Handle specialty dropdown
          final specialty = (args['Specialty'] ??
              args['specialty'] ??
              args['speciality'] ??
              '') as String;
          if (specialty.isNotEmpty) {
            _selectedSpecialty = specialty;
            if (!_specialtyOptions.contains(specialty)) {
              _customSpecialityController.text = specialty;
            }
          }

          _jobDescriptionController.text =
              (args['JobDescription'] ?? args['description'] ?? '') as String;

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
        }

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
          _showErrorAndGoBack(
              'Your company account is pending approval. Please wait for admin verification.');
        } else if (accountStatus == 'Rejected') {
          _showErrorAndGoBack(
              'Your company account has been rejected. Please contact support.');
        } else {
          _showErrorAndGoBack(
              'Your company account is not verified. Please contact support.');
        }
        return;
      }

      // Check if profile is complete
      if (!isProfileComplete) {
        _showErrorAndGoBack(
            'Please complete your company profile before creating or editing job postings.');
        return;
      }
    } catch (e) {
      _showErrorAndGoBack('Error verifying access: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        backgroundColor: const Color(0xFF4CAF50).withOpacity(0.8), // Green
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        backgroundColor: const Color(0xFFFF7B7B).withOpacity(0.8), // Red
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showWarningSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        backgroundColor:
            const Color(0xFFFF7B7B).withOpacity(0.8), // Same red as team leader
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        backgroundColor:
            const Color(0xFF4A5FBC).withOpacity(0.8), // Brand purple
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showErrorAndGoBack(String message) {
    _showErrorSnackBar(message);
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
    _customSpecialityController.dispose();
    _requirementController.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day); // Strip time

    // Use existing date if it's today or future, otherwise use today
    final DateTime initialDate =
        (_startDate != null && !_startDate!.isBefore(today))
            ? _startDate!
            : today;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: const Color(
                      0xFF4A5FBC), // Selected date background (purple)
                  onPrimary: Colors.white, // Selected date text
                  onSurface: Colors.black, // Default text color
                ),
            datePickerTheme: DatePickerThemeData(
              todayBorder: BorderSide.none,
              todayBackgroundColor: MaterialStateColor.resolveWith((states) {
                if (states.contains(MaterialState.selected)) {
                  return const Color(
                      0xFF4A5FBC); // Selected today background (purple)
                }
                return Colors.grey.shade300; // Unselected today background
              }),
              todayForegroundColor: MaterialStateColor.resolveWith((states) {
                if (states.contains(MaterialState.selected)) {
                  return Colors.white; // Selected today text
                }
                return Colors.black; // Unselected today text
              }),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _selectEndDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day); // Strip time

    // First allowed date is the later of start date or today
    final DateTime firstAllowedDate =
        _startDate != null && !_startDate!.isBefore(today)
            ? _startDate!
            : today;

    // Initial date should be valid (between firstAllowedDate and lastDate)
    final DateTime initialDate =
        (_endDate != null && !_endDate!.isBefore(firstAllowedDate))
            ? _endDate!
            : firstAllowedDate;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstAllowedDate,
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: const Color(
                      0xFF4A5FBC), // Selected date background (purple)
                  onPrimary: Colors.white, // Selected date text
                  onSurface: Colors.black, // Default text color
                ),
            datePickerTheme: DatePickerThemeData(
              todayBorder: BorderSide.none,
              todayBackgroundColor: MaterialStateColor.resolveWith((states) {
                if (states.contains(MaterialState.selected)) {
                  return const Color(
                      0xFF4A5FBC); // Selected today background (purple)
                }
                return Colors.grey.shade300; // Unselected today background
              }),
              todayForegroundColor: MaterialStateColor.resolveWith((states) {
                if (states.contains(MaterialState.selected)) {
                  return Colors.white; // Selected today text
                }
                return Colors.black; // Unselected today text
              }),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  void _addRequirement() {
    if (_requirements.length >= 15) {
      _showWarningSnackBar('Maximum 15 requirements allowed');
      return;
    }
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
      // Common English stop words
      'the', 'a', 'an', 'and', 'or', 'but', 'if', 'then', 'else', 'when',
      'while',
      'for', 'of', 'at', 'by', 'with', 'about', 'against', 'between', 'into',
      'through', 'during', 'before', 'after', 'above', 'below', 'to', 'from',
      'up', 'down', 'in', 'out', 'on', 'off', 'over', 'under', 'again',
      'further',
      'once', 'here', 'there', 'all', 'any', 'both', 'each', 'few', 'more',
      'most',
      'other', 'some', 'such', 'no', 'nor', 'not', 'only', 'own', 'same', 'so',
      'than', 'too', 'very', 'can', 'will', 'just', 'should', 'now', 'this',
      'that', 'these', 'those', 'is', 'am', 'are', 'was', 'were', 'be', 'been',
      'being', 'have', 'has', 'had', 'having', 'do', 'does', 'did', 'doing',
      'as',
      'because', 'until', 'out', 'over', 'under', 'therefore', 'where', 'why',
      'how', 'whose', 'whom', 'which', 'what', 'who', 'he', 'him', 'his', 'she',
      'her', 'they', 'them', 'their', 'theirs', 'you', 'your', 'yours', 'me',
      'my', 'mine', 'we', 'our', 'ours', 'us', 'it', 'its', 'itself',
      'yourself',
      'yourselves', 'themselves', 'ourselves',

      // Frequent resume/job filler verbs
      'responsible', 'assisted', 'worked', 'helped', 'handled', 'provided',
      'created', 'made', 'developed', 'used', 'utilized', 'performed',
      'conducted',
      'ensured', 'participated', 'involved', 'supported', 'completed',
      'contributed',
      'experience', 'project', 'projects', 'team', 'teams', 'member', 'members',

      // Symbols and punctuation
      '.', ',', ';', ':', '-', '_', '–', '—', '!', '?', '(', ')', '[', ']', '{',
      '}', '\'', '"', '/', '\\', '|', '@', '#', '\$', '%', '^', '&', '*', '+',
      '=',
      '<', '>', '`', '~',

      // Common technical noise
      'http', 'https', 'www', 'com', 'net', 'org', 'email', 'address',
      'linkedin',
      'github', 'portfolio', 'resume', 'cv', 'document', 'pdf', 'file',

      // Numbers
      '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',

      // Time and date words
      'year', 'years', 'month', 'months', 'day', 'days', 'date', 'time',

      // Job listing boilerplate
      'apply', 'applicant', 'candidate', 'requirement', 'requirements',
      'qualification', 'qualifications', 'responsibilities', 'description',
      'skills', 'skill', 'position', 'role', 'roles', 'opportunity', 'vacancy',
      'employment', 'full-time', 'part-time', 'internship', 'intern', 'job',
      'jobs'
    };

    // Extract from title
    final titleWords = _jobTitleController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) =>
            word.isNotEmpty && !stopWords.contains(word.toLowerCase()))
        .map((word) => word.toLowerCase());
    keywords.addAll(titleWords);

    // Extract from position
    final positionWords = _positionController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) =>
            word.isNotEmpty && !stopWords.contains(word.toLowerCase()))
        .map((word) => word.toLowerCase());
    keywords.addAll(positionWords);

    // Extract from specialty
    final specialtyWords = _getSpecialtyValue()
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) =>
            word.isNotEmpty && !stopWords.contains(word.toLowerCase()))
        .map((word) => word.toLowerCase());
    keywords.addAll(specialtyWords);

    // Extract from job description
    final descriptionWords = _jobDescriptionController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) =>
            word.isNotEmpty && !stopWords.contains(word.toLowerCase()))
        .map((word) => word.toLowerCase());
    keywords.addAll(descriptionWords);

    // Extract from requirements
    for (final requirement in _requirements) {
      final reqWords = requirement
          .trim()
          .split(RegExp(r'\s+'))
          .where((word) =>
              word.isNotEmpty && !stopWords.contains(word.toLowerCase()))
          .map((word) => word.toLowerCase());
      keywords.addAll(reqWords);
    }

    return keywords.toList();
  }

  String _getSpecialtyValue() {
    return _selectedSpecialty ?? '';
  }

  Future<void> _generateJobPost() async {
    if (_jobTitleController.text.isEmpty) {
      _showWarningSnackBar('Please enter job title first');
      return;
    }

    if (_positionController.text.isEmpty) {
      _showWarningSnackBar('Please enter position first');
      return;
    }

    final specialtyValue = _getSpecialtyValue();
    if (specialtyValue.isEmpty) {
      _showWarningSnackBar('Please select or enter speciality first');
      return;
    }

    // Check if user is logged in
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showWarningSnackBar('You must be logged in to use AI generation');
      return;
    }

    try {
      // Check AI usage limit
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        _showErrorSnackBar('User data not found');
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
        _showInfoSnackBar('Daily AI usage limit has been reset!');
      } else {
        jobPostingCount = (aiUsage?['JobPosting'] ?? 0) as int;
      }

      if (jobPostingCount <= 0) {
        _showWarningSnackBar(
            'You have reached your AI generation limit for job postings. Resets tomorrow!');
        return;
      }

      // Call your Cloud Function from firebase RUNNING THIS REQUIRES WIFI
      final url = Uri.parse(
          'https://us-central1-jadeer-b4953.cloudfunctions.net/generateJobPost');

      _showInfoSnackBar('Generating job description...');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': _jobTitleController.text,
          'position': _positionController.text,
          'speciality': _getSpecialtyValue(),
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

        _showSuccessSnackBar(
            'AI job description generated! (${jobPostingCount - 1} uses remaining)');
      } else {
        _showErrorSnackBar('Failed: ${response.body}');
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Error: $e');
    }
  }

  Future<void> _submitForm() async {
    setState(() => _submitted = true);

    if (!_formKey.currentState!.validate()) return;

    // Check required fields
    if (_startDate == null || _endDate == null) {
      _showWarningSnackBar('Please select start and end dates');
      return;
    }

    // Get current user ID
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showWarningSnackBar('You must be logged in to post a job');
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
        _showSuccessSnackBar('Job dates updated successfully');
      } else {
        // CREATE MODE - Validate requirements first
        if (_requirements.isEmpty) {
          _showWarningSnackBar('Please add at least one requirement');
          return;
        }

        final keywords = _extractKeywords();

        final data = <String, dynamic>{
          'JobTitle': _jobTitleController.text.trim(),
          'JobDescription': _jobDescriptionController.text.trim(),
          'Position': _positionController.text.trim(),
          'Specialty': _getSpecialtyValue(),
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
        _showSuccessSnackBar('Job created successfully');

        // Navigate to questions page after creating job
        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context,
          '/questions',
          arguments: {'jobId': jobId},
        );
        return;
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Error: $e');
    }
  }

  Future<void> _continueToQuestions() async {
    // Validate dates are selected
    if (_startDate == null || _endDate == null) {
      _showWarningSnackBar('Please select start and end dates');
      return;
    }

    if (_jobId == null) return;

    try {
      // Update dates in Firestore
      await FirebaseFirestore.instance.collection('Jobs').doc(_jobId).update({
        'StartDate': _startDate,
        'EndDate': _endDate,
      });

      _showSuccessSnackBar('Job dates updated successfully');

      // Navigate to questions page
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/questions',
        arguments: {'jobId': _jobId},
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Error updating dates: $e');
    }
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Widget _buildLabel(String text, bool isInvalid, {bool isBold = false}) {
    if (!_submitted || !isInvalid) {
      return Text(
        text,
        style: isBold
            ? const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
            : null,
      );
    }
    return RichText(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.red,
          fontSize: 16,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        ),
        children: const [
          TextSpan(
            text: ' *',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildLabelWithInfo(String text, String tooltipMessage) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        const SizedBox(width: 4),
        InkWell(
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.95),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                content: Text(
                  tooltipMessage,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF4A5FBC),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                actionsAlignment: MainAxisAlignment.center,
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: Icon(
              Icons.info_outline,
              size: 18,
              color: Colors.grey[600],
            ),
          ),
        ),
      ],
    );
  }

  Future<bool> _onWillPop() async {
    // Show confirmation dialog
    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        title: const Text(
          'Abandon Changes?',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to go back? Any unsaved changes will be lost.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.9),
              foregroundColor: const Color(0xFF4A5FBC),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Cancel',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFFC686A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Leave',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return shouldPop ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: ThemedScaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: Color(0xFF4A5FBC),
          foregroundColor: Colors.white,
          title: Text(_isEdit ? 'Edit Job' : 'Create Job Posting'),
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Job Title
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: _buildLabel(
                        'Job Title', _jobTitleController.text.isEmpty),
                  ),
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
                    child: TextFormField(
                      controller: _jobTitleController,
                      enabled: !_isEdit,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: Colors.transparent,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide.none,
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide.none,
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide.none,
                        ),
                        errorStyle: TextStyle(height: 0, fontSize: 0),
                        errorMaxLines: 1,
                        counterText: '',
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? '' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Position
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: _buildLabelWithInfo(
                      'Position',
                      'Specify the job\'s level and role e.g., Junior Developer, Senior Designer, Team Lead. \nThis helps show the seniority, scope, and responsibilities of the position.',
                    ),
                  ),
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
                    child: TextFormField(
                      controller: _positionController,
                      enabled: !_isEdit,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: Colors.transparent,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide.none,
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide.none,
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide.none,
                        ),
                        errorStyle: TextStyle(height: 0, fontSize: 0),
                        errorMaxLines: 1,
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Speciality
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: _buildLabelWithInfo(
                      'Speciality',
                      'Indicate the job\'s main area of expertise e.g., Data Science, Frontend Development, Cybersecurity. \nThis shows the specific field or focus the role specializes in.',
                    ),
                  ),
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
                    child: Autocomplete<String>(
                      initialValue: _selectedSpecialty != null
                          ? TextEditingValue(text: _selectedSpecialty!)
                          : null,
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return _specialtyOptions;
                        }
                        return _specialtyOptions.where((String option) {
                          return option
                              .toLowerCase()
                              .contains(textEditingValue.text.toLowerCase());
                        });
                      },
                      onSelected: (String selection) {
                        setState(() {
                          _selectedSpecialty = selection;
                        });
                      },
                      fieldViewBuilder: (context, textEditingController,
                          focusNode, onFieldSubmitted) {
                        if (_selectedSpecialty != null &&
                            textEditingController.text.isEmpty) {
                          textEditingController.text = _selectedSpecialty!;
                        }
                        return TextFormField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          enabled: !_isEdit,
                          maxLength: 100,
                          decoration: const InputDecoration(
                            hintText: 'Type or select specialty',
                            hintStyle: TextStyle(
                              color: Colors.grey,
                            ),
                            filled: true,
                            fillColor: Colors.transparent,
                            border: const OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12)),
                              borderSide: BorderSide.none,
                            ),
                            errorBorder: const OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12)),
                              borderSide: BorderSide.none,
                            ),
                            focusedErrorBorder: const OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12)),
                              borderSide: BorderSide.none,
                            ),
                            errorStyle: const TextStyle(height: 0, fontSize: 0),
                            errorMaxLines: 1,
                            counterText: '',
                          ),
                          onChanged: (value) {
                            setState(() {
                              _selectedSpecialty = value;
                            });
                          },
                        );
                      },
                      optionsViewBuilder:
                          (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              constraints: const BoxConstraints(maxHeight: 200),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (context, index) {
                                  final option = options.elementAt(index);
                                  return InkWell(
                                    onTap: () => onSelected(option),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      child: Text(option),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
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
                  child: _aiCreditsRemaining > 0
                      ? Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF6B4CE6), // Vibrant purple
                                Color(0xFF4A5FBC), // Brand purple
                                Color(0xFF3B8FD9), // Blue accent
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6B4CE6).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: TextButton.icon(
                            onPressed: _generateJobPost,
                            icon: const Icon(Icons.auto_awesome,
                                size: 20, color: Colors.white),
                            label: const Text(
                              'Generate with AI',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                          ),
                        )
                      : TextButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.auto_awesome, size: 18),
                          label: const Text(
                            'Generate with AI',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.grey,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 12),
              ],

              // Job Description
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: _buildLabel('Job Description',
                        _jobDescriptionController.text.isEmpty),
                  ),
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
                    child: TextFormField(
                      controller: _jobDescriptionController,
                      enabled: !_isEdit,
                      maxLength: 2000,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.transparent,
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide.none,
                        ),
                        errorBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide.none,
                        ),
                        focusedErrorBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide.none,
                        ),
                        errorStyle: const TextStyle(height: 0, fontSize: 0),
                        errorMaxLines: 1,
                        counterText: '',
                        helperText: '${_jobDescriptionController.text.length}/2000',
                        helperStyle: const TextStyle(fontSize: 12),
                      ),
                      minLines: 6,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      validator: (v) => (v == null || v.isEmpty) ? '' : null,
                      onChanged: (value) => setState(() {}),
                    ),
                  ),
                ],
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildLabel('Requirements', _requirements.isEmpty,
                                isBold: true),
                            Text(
                              '${_requirements.length}/15',
                              style: TextStyle(
                                fontSize: 12,
                                color: _requirements.length >= 15
                                    ? Colors.red
                                    : Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
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
                                  controller: _requirementController,
                                  maxLength: 200,
                                  decoration: InputDecoration(
                                    hintText: 'Enter requirement',
                                    filled: true,
                                    fillColor: Colors.transparent,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    counterText: '',
                                  ),
                                  onSubmitted: (_) => _addRequirement(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _requirements.length >= 15
                                  ? null
                                  : _addRequirement,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4A5FBC),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              child: const Text('Add'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_requirements.isEmpty)
                          const Text('No requirements added yet',
                              style: TextStyle(color: Colors.grey))
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
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
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
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        if (_requirements.isEmpty)
                          const Text('No requirements',
                              style: TextStyle(color: Colors.grey))
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
                                    style:
                                        const TextStyle(color: Colors.black87),
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
                child: InkWell(
                  onTap: _selectStartDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      label: _buildLabel('Start Date', _startDate == null),
                      filled: true,
                      fillColor: Colors.transparent,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      _startDate != null
                          ? _fmtDate(_startDate!)
                          : 'Select date',
                      style: TextStyle(
                        color: _startDate != null ? Colors.black : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // End Date
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
                child: InkWell(
                  onTap: _selectEndDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      label: _buildLabel('End Date', _endDate == null),
                      filled: true,
                      fillColor: Colors.transparent,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
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
              ),
              const SizedBox(height: 24),

              // Submit Button or Continue to Questions
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isEdit ? _continueToQuestions : _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A5FBC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: Text(
                    _isEdit ? 'Continue to Questions' : 'Create Job Posting',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
