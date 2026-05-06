import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import '../config/theme.dart';
import 'cv_ready.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CVNextStepsScreen extends StatefulWidget {
  final String? cvHistoryId;
  final String? jobTitle;
  final bool hasJobSelection;

  const CVNextStepsScreen({
    super.key,
    this.cvHistoryId,
    this.jobTitle,
    this.hasJobSelection = false,
  });

  @override
  State<CVNextStepsScreen> createState() => _CVNextStepsScreenState();
}

class _CVNextStepsScreenState extends State<CVNextStepsScreen> {
  bool _isDetecting = true;
  bool _isEnhancing = false;
  List<String> _missingSections = [];
  List<String>? _suggestedSkills;
  int _currentSectionIndex = 0;
  Map<String, dynamic> _filledSections = {};
  bool _completedSuccessfully = false;

  // AI Credits tracking
  int _cvEnhancementCredits = 0;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _fetchCredits();

      if (!mounted) return;
      _detectMissingSections();
    });
  }

  @override
  void dispose() {
    if (!_completedSuccessfully && widget.cvHistoryId != null) {
      FirebaseFirestore.instance
          .collection('CVHistory')
          .doc(widget.cvHistoryId)
          .delete();
    }
    super.dispose();
  }

  Future<void> _fetchCredits() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return;
      }

      final userDocRef =
          FirebaseFirestore.instance.collection('Users').doc(currentUser.uid);

      final userDoc = await userDocRef.get();

      if (userDoc.exists) {
        final data = userDoc.data();
        final aiUsage = data?['AiUsage'] as Map<String, dynamic>?;

        int credits = aiUsage?['CvEnhancement'] ?? 2;
        final lastReset = aiUsage?['LastReset'] as Timestamp?;

        // Check if we need to reset credits (new day)
        if (lastReset != null) {
          final lastResetDate = lastReset.toDate();
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final lastResetDay = DateTime(
              lastResetDate.year, lastResetDate.month, lastResetDate.day);

          // If LastReset is not today, reset credits to 2
          if (lastResetDay.isBefore(today)) {
            credits = 2;
            await userDocRef.update({
              'AiUsage.CvEnhancement': 2,
              'AiUsage.MockInterview': 2,
              'AiUsage.LastReset': FieldValue.serverTimestamp(),
            });
          }
        }

        setState(() {
          _cvEnhancementCredits = credits;
        });
      }
    } catch (e) {}
  }

  Future<void> _detectMissingSections() async {
    if (!widget.hasJobSelection) {
      setState(() {
        _isDetecting = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _enhanceCV();
      });

      return;
    }

    setState(() {
      _isDetecting = true;
    });

    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('detectMissingSections');
      final result = await callable.call({'cvHistoryId': widget.cvHistoryId});

      final missingSections =
          List<String>.from(result.data['missingSections'] ?? []);
      final suggestedSkills = result.data['suggestedSkills'] != null
          ? List<String>.from(result.data['suggestedSkills'])
          : null;

      setState(() {
        _missingSections = missingSections;
        _suggestedSkills = suggestedSkills;
        _isDetecting = false;
      });

      // If no missing sections, automatically enhance CV
      if (missingSections.isEmpty) {
        _enhanceCV();
      } else {
        // Show info dialog about missing sections
        _showMissingSectionsDialog();
      }
    } catch (e) {
      setState(() {
        _isDetecting = false;
      });
      SnackHelper.error(context, 'Error detecting missing sections: $e');
    }
  }

  void _showMissingSectionsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const JadeerDialog<void>(
        title: 'Complete Your CV',
        content: Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'We\'ve analyzed your CV and found some sections that could strengthen your application.\n\nPlease fill in the missing information to create a complete professional CV.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ),
        primaryLabel: 'Continue',
        primaryResult: null,
      ),
    );
  }

  Future<void> _enhanceCV() async {
    // Check if user has credits
    if (_cvEnhancementCredits <= 0) {
      SnackHelper.error(
        context,
        'You have reached your AI enhancement limit for today. Resets at midnight.',
      );
      return;
    }

    setState(() {
      _isEnhancing = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('enhanceCV');

      final data = <String, dynamic>{
        'cvHistoryId': widget.cvHistoryId,
      };

      // Add additional sections if any were filled
      if (_filledSections.isNotEmpty) {
        data['additionalSections'] = _filledSections;
      }

      await callable.call(data);

      // Decrement credits after successful enhancement
      final newCredits = _cvEnhancementCredits - 1;
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(currentUser.uid)
          .update({
        'AiUsage.CvEnhancement': newCredits,
      });

      setState(() {
        _cvEnhancementCredits = newCredits;
        _isEnhancing = false;
      });

      _completedSuccessfully = true;

      // Show success message
      if (mounted) {
        SnackHelper.success(
          context,
          'CV enhanced successfully! ($newCredits ${newCredits == 1 ? 'enhancement' : 'enhancements'} remaining)',
        );
      }

      // Navigate to CV Ready Screen to show results
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PublishScreen(cvUrl: widget.cvHistoryId!),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isEnhancing = false;
      });
      SnackHelper.error(context, 'Error enhancing CV: $e');
    }
  }

  void _skipSection() {
    if (_currentSectionIndex < _missingSections.length - 1) {
      setState(() {
        _currentSectionIndex++;
      });
    } else {
      // All sections processed, enhance CV
      _enhanceCV();
    }
  }

  Future<void> _skipAll() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => JadeerDialog<bool>(
        title: '⚠️ Skip All Sections?',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Completing these sections significantly improves your CV quality and makes it more attractive to employers.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Missing: ${_missingSections.join(", ")}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
          ],
        ),
        secondaryLabel: 'Go Back',
        secondaryResult: false,
        primaryLabel: 'Skip Anyway',
        primaryResult: true,
      ),
    );

    if (result == true) {
      _enhanceCV();
    }
  }

  void _goBack() {
    if (_currentSectionIndex > 0) {
      setState(() {
        _currentSectionIndex--;
      });
    }
  }

  void _saveAndNext(Map<String, dynamic> sectionData) {
    final sectionName = _missingSections[_currentSectionIndex];
    setState(() {
      _filledSections[sectionName] = sectionData;
    });

    if (_currentSectionIndex < _missingSections.length - 1) {
      setState(() {
        _currentSectionIndex++;
      });
    } else {
      // All sections processed, enhance CV
      _enhanceCV();
    }
  }

  Future<bool> _onWillPop() async {
    if (_isEnhancing || _isDetecting) {
      return false; // Don't allow back during processing
    }

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

    if (shouldPop == true && widget.cvHistoryId != null) {
      await FirebaseFirestore.instance
          .collection('CVHistory')
          .doc(widget.cvHistoryId)
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
        appBar: CustomHeader(
          title: _isEnhancing ? 'Enhancing CV' : 'Complete Your CV',
          leading: Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, bottom: 16),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () async {
                final shouldPop = await _onWillPop();
                if (shouldPop && mounted) {
                  Navigator.pop(context);
                }
              },
            ),
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isDetecting) {
      return _buildLoadingState('Analyzing your CV...');
    }

    if (_isEnhancing) {
      return _buildLoadingState(
          'Enhancing your CV...\nThis may take a moment.');
    }

    if (_missingSections.isEmpty) {
      return _buildLoadingState('No missing sections!\nEnhancing your CV...');
    }

    return _buildMissingSectionForm();
  }

  Widget _buildLoadingState(String message) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMissingSectionForm() {
    final scheme = Theme.of(context).colorScheme;

    final sectionName = _missingSections[_currentSectionIndex];
    final progress = (_currentSectionIndex + 1) / _missingSections.length;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentSectionIndex > 0)
                    TextButton.icon(
                      onPressed: _goBack,
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('Back'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryPurple,
                      ),
                    )
                  else
                    const SizedBox(width: 80),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Section ${_currentSectionIndex + 1} of ${_missingSections.length}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: TextButton(
                      onPressed: _skipAll,
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.accentCoral,
                      ),
                      child: const Text('Skip All',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: AppTheme.primaryPurple.withOpacity(0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppTheme.primaryPurple,
                ),
                minHeight: 6,
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildSectionForm(sectionName),
        ),
      ],
    );
  }

  Widget _buildSectionForm(String sectionName) {
    // Get previously saved data for this section if it exists
    final existingData = _filledSections[sectionName];

    switch (sectionName) {
      case 'PersonalInformation':
        return _PersonalInformationForm(
          onSave: _saveAndNext,
          onSkip: _skipSection,
          initialData: existingData,
        );
      case 'Summary':
        return _SummaryForm(
          onSave: _saveAndNext,
          onSkip: _skipSection,
          initialData: existingData,
        );
      case 'Experience':
        return _ExperienceForm(
          onSave: _saveAndNext,
          onSkip: _skipSection,
          initialData: existingData,
        );
      case 'Education':
        return _EducationForm(
          onSave: _saveAndNext,
          onSkip: _skipSection,
          initialData: existingData,
        );
      case 'Skills':
        return _SkillsForm(
          onSave: _saveAndNext,
          onSkip: _skipSection,
          suggestedSkills: _suggestedSkills,
          initialData: existingData,
        );
      case 'Certifications':
        return _CertificationsForm(
          onSave: _saveAndNext,
          onSkip: _skipSection,
          initialData: existingData,
        );
      case 'Languages':
        return _LanguagesForm(
          onSave: _saveAndNext,
          onSkip: _skipSection,
          initialData: existingData,
        );
      default:
        return Center(child: Text('Unknown section: $sectionName'));
    }
  }
}

// Personal Information Form
class _PersonalInformationForm extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  final VoidCallback onSkip;
  final Map<String, dynamic>? initialData;

  const _PersonalInformationForm({
    required this.onSave,
    required this.onSkip,
    this.initialData,
  });

  @override
  State<_PersonalInformationForm> createState() =>
      _PersonalInformationFormState();
}

class _PersonalInformationFormState extends State<_PersonalInformationForm> {
  late final TextEditingController _fullNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _locationController;
  late final TextEditingController _linksController;

  @override
  void initState() {
    super.initState();
    final existingContent =
        widget.initialData?['content'] as Map<String, dynamic>?;
    _fullNameController =
        TextEditingController(text: existingContent?['full_name'] ?? '');
    _emailController =
        TextEditingController(text: existingContent?['email'] ?? '');
    _phoneController =
        TextEditingController(text: existingContent?['phone'] ?? '');
    _locationController =
        TextEditingController(text: existingContent?['location'] ?? '');
    final links = (existingContent?['links'] as List?)?.join(', ') ?? '';
    _linksController = TextEditingController(text: links);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    _linksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Personal Information',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryPurple,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Fill in your personal details.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(
                          Theme.of(context).brightness == Brightness.dark
                              ? 0.12
                              : 0.05,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _fullNameController,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                      floatingLabelStyle:
                          const TextStyle(color: Color(0xFF4A5FBC)),
                      hintText: 'e.g., John Doe',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.transparent,
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(
                          Theme.of(context).brightness == Brightness.dark
                              ? 0.12
                              : 0.05,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                      floatingLabelStyle:
                          const TextStyle(color: Color(0xFF4A5FBC)),
                      hintText: 'e.g., john@example.com',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.transparent,
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(
                          Theme.of(context).brightness == Brightness.dark
                              ? 0.12
                              : 0.05,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone',
                      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                      floatingLabelStyle:
                          const TextStyle(color: Color(0xFF4A5FBC)),
                      hintText: 'e.g., +1 234 567 8900',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.transparent,
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(
                          Theme.of(context).brightness == Brightness.dark
                              ? 0.12
                              : 0.05,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _locationController,
                    decoration: InputDecoration(
                      labelText: 'Location',
                      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                      floatingLabelStyle:
                          const TextStyle(color: Color(0xFF4A5FBC)),
                      hintText: 'e.g., New York, USA',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.transparent,
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(
                          Theme.of(context).brightness == Brightness.dark
                              ? 0.12
                              : 0.05,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _linksController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Links (LinkedIn, Portfolio, etc.)',
                      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                      floatingLabelStyle:
                          const TextStyle(color: Color(0xFF4A5FBC)),
                      hintText:
                          'e.g., linkedin.com/in/johndoe, github.com/johndoe',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.transparent,
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.onSkip,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentCoral,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text(
                    'Skip',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    if (_fullNameController.text.trim().isEmpty &&
                        _emailController.text.trim().isEmpty &&
                        _phoneController.text.trim().isEmpty &&
                        _locationController.text.trim().isEmpty &&
                        _linksController.text.trim().isEmpty) {
                      SnackHelper.error(
                        context,
                        'Please fill at least one field or skip',
                      );
                      return;
                    }

                    final linksText = _linksController.text.trim();
                    final links = linksText.isEmpty
                        ? <String>[]
                        : linksText
                            .split(RegExp(r'[,\n]'))
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList();

                    widget.onSave({
                      'content': {
                        'full_name': _fullNameController.text.trim(),
                        'email': _emailController.text.trim(),
                        'phone': _phoneController.text.trim(),
                        'location': _locationController.text.trim(),
                        'links': links,
                      }
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text(
                    'Next',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Summary Form
class _SummaryForm extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  final VoidCallback onSkip;
  final Map<String, dynamic>? initialData;

  const _SummaryForm({
    required this.onSave,
    required this.onSkip,
    this.initialData,
  });

  @override
  State<_SummaryForm> createState() => _SummaryFormState();
}

class _SummaryFormState extends State<_SummaryForm> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // Pre-fill with existing data if available
    final existingContent = widget.initialData?['content'] as String?;
    _controller = TextEditingController(text: existingContent ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Summary',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryPurple,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Write a brief summary about yourself and your career goals.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(
                          Theme.of(context).brightness == Brightness.dark
                              ? 0.12
                              : 0.05,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _controller,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText:
                          'e.g., Experienced software engineer with 5+ years...',
                      hintStyle: TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.transparent,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.onSkip,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentCoral,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text('Skip',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    if (_controller.text.trim().isEmpty) {
                      SnackHelper.error(
                        context,
                        'Please enter a summary or skip',
                      );
                      return;
                    }
                    widget.onSave({'content': _controller.text.trim()});
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text('Next',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Experience Form
class _ExperienceForm extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  final VoidCallback onSkip;
  final Map<String, dynamic>? initialData;

  const _ExperienceForm({
    required this.onSave,
    required this.onSkip,
    this.initialData,
  });

  @override
  State<_ExperienceForm> createState() => _ExperienceFormState();
}

class _ExperienceFormState extends State<_ExperienceForm> {
  final List<Map<String, TextEditingController>> _experiences = [];

  @override
  void initState() {
    super.initState();
    // Restore previously saved experiences
    if (widget.initialData != null) {
      final existingExps = (widget.initialData!['content'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      for (final exp in existingExps) {
        _experiences.add({
          'title': TextEditingController(text: exp['title'] ?? ''),
          'company': TextEditingController(text: exp['company'] ?? ''),
          'years': TextEditingController(text: exp['years'] ?? ''),
          'description': TextEditingController(text: exp['description'] ?? ''),
        });
      }
    }
    // Add at least one entry if empty
    if (_experiences.isEmpty) {
      _addExperience();
    }
  }

  void _addExperience() {
    if (_experiences.length < 10) {
      setState(() {
        _experiences.add({
          'title': TextEditingController(),
          'company': TextEditingController(),
          'years': TextEditingController(),
          'description': TextEditingController(),
        });
      });
    }
  }

  void _removeExperience(int index) {
    setState(() {
      _experiences[index].forEach((key, controller) => controller.dispose());
      _experiences.removeAt(index);
    });
  }

  @override
  void dispose() {
    for (var exp in _experiences) {
      exp.forEach((key, controller) => controller.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Work Experience',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryPurple,
                      ),
                    ),
                    if (_experiences.length < 10)
                      IconButton(
                        onPressed: _addExperience,
                        icon: const Icon(Icons.add_circle, size: 32),
                        color: AppTheme.primaryPurple,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Add up to ${10 - _experiences.length} more experience(s)',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                ..._experiences.asMap().entries.map((entry) {
                  final index = entry.key;
                  final exp = entry.value;
                  return _buildExperienceEntry(index, exp);
                }).toList(),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.onSkip,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentCoral,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text('Skip',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveExperiences,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text('Next',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExperienceEntry(
    int index,
    Map<String, TextEditingController> exp,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              isDark ? 0.12 : 0.05,
            ),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Experience ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (_experiences.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _removeExperience(index),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.transparent : scheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: exp['title'],
                decoration: InputDecoration(
                  labelText: 'Job Title',
                  labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                  floatingLabelStyle: const TextStyle(color: Color(0xFF4A5FBC)),
                  hintText: 'e.g., Software Engineer',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: isDark
                      ? scheme.surface.withOpacity(0.4)
                      : Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    borderSide: isDark
                        ? const BorderSide(color: Color(0xFF4A5FBC), width: 1.4)
                        : BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.transparent : scheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: exp['company'],
                decoration: InputDecoration(
                  labelText: 'Company',
                  labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                  floatingLabelStyle: const TextStyle(color: Color(0xFF4A5FBC)),
                  hintText: 'e.g., Google',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: isDark
                      ? scheme.surface.withOpacity(0.4)
                      : Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    borderSide: isDark
                        ? const BorderSide(color: Color(0xFF4A5FBC), width: 1.4)
                        : BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.transparent : scheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: exp['years'],
                decoration: InputDecoration(
                  labelText: 'Years',
                  labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                  floatingLabelStyle: const TextStyle(color: Color(0xFF4A5FBC)),
                  hintText: 'e.g., 2020-2023',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: isDark
                      ? scheme.surface.withOpacity(0.4)
                      : Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    borderSide: isDark
                        ? const BorderSide(color: Color(0xFF4A5FBC), width: 1.4)
                        : BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.transparent : scheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: exp['description'],
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Description',
                  labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                  floatingLabelStyle: const TextStyle(color: Color(0xFF4A5FBC)),
                  hintText: 'Describe your responsibilities and achievements',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    borderSide: isDark
                        ? const BorderSide(color: Color(0xFF4A5FBC), width: 1.4)
                        : BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveExperiences() {
    final experiences = _experiences.map((exp) {
      return {
        'title': exp['title']!.text.trim(),
        'company': exp['company']!.text.trim(),
        'years': exp['years']!.text.trim(),
        'description': exp['description']!.text.trim(),
      };
    }).where((exp) {
      // Only include non-empty experiences
      return exp['title']!.isNotEmpty || exp['company']!.isNotEmpty;
    }).toList();

    if (experiences.isEmpty) {
      SnackHelper.error(context, 'Please add at least one experience or skip');
      return;
    }

    widget.onSave({'content': experiences});
  }
}

// Education Form
class _EducationForm extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  final VoidCallback onSkip;
  final Map<String, dynamic>? initialData;

  const _EducationForm({
    required this.onSave,
    required this.onSkip,
    this.initialData,
  });

  @override
  State<_EducationForm> createState() => _EducationFormState();
}

class _EducationFormState extends State<_EducationForm> {
  final List<Map<String, TextEditingController>> _education = [];

  @override
  void initState() {
    super.initState();
    // Restore previously saved education
    if (widget.initialData != null) {
      final existingEdu = (widget.initialData!['content'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      for (final edu in existingEdu) {
        _education.add({
          'degree': TextEditingController(text: edu['degree'] ?? ''),
          'institution': TextEditingController(text: edu['institution'] ?? ''),
          'years': TextEditingController(text: edu['years'] ?? ''),
        });
      }
    }
    // Add at least one entry if empty
    if (_education.isEmpty) {
      _addEducation();
    }
  }

  void _addEducation() {
    if (_education.length < 10) {
      setState(() {
        _education.add({
          'degree': TextEditingController(),
          'institution': TextEditingController(),
          'years': TextEditingController(),
        });
      });
    }
  }

  void _removeEducation(int index) {
    setState(() {
      _education[index].forEach((key, controller) => controller.dispose());
      _education.removeAt(index);
    });
  }

  @override
  void dispose() {
    for (var edu in _education) {
      edu.forEach((key, controller) => controller.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Education',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryPurple,
                      ),
                    ),
                    if (_education.length < 10)
                      IconButton(
                        onPressed: _addEducation,
                        icon: const Icon(Icons.add_circle, size: 32),
                        color: AppTheme.primaryPurple,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Add up to ${10 - _education.length} more education entries',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                ..._education.asMap().entries.map((entry) {
                  final index = entry.key;
                  final edu = entry.value;
                  return _buildEducationEntry(index, edu);
                }).toList(),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.onSkip,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentCoral,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text('Skip',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveEducation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text('Next',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEducationEntry(
    int index,
    Map<String, TextEditingController> edu,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              isDark ? 0.12 : 0.05,
            ),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Education ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (_education.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _removeEducation(index),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.transparent : scheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: edu['degree'],
                decoration: InputDecoration(
                  labelText: 'Degree',
                  labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                  floatingLabelStyle: const TextStyle(color: Color(0xFF4A5FBC)),
                  hintText: 'e.g., Bachelor of Computer Science',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: isDark
                      ? scheme.surface.withOpacity(0.4)
                      : Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    borderSide: isDark
                        ? const BorderSide(
                            color: Color(0xFF4A5FBC),
                            width: 1.4,
                          )
                        : BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.transparent : scheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: edu['institution'],
                decoration: InputDecoration(
                  labelText: 'Institution',
                  labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                  floatingLabelStyle: const TextStyle(color: Color(0xFF4A5FBC)),
                  hintText: 'e.g., MIT',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: isDark
                      ? scheme.surface.withOpacity(0.4)
                      : Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    borderSide: isDark
                        ? const BorderSide(
                            color: Color(0xFF4A5FBC),
                            width: 1.4,
                          )
                        : BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.transparent : scheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: edu['years'],
                decoration: InputDecoration(
                  labelText: 'Years',
                  labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                  floatingLabelStyle: const TextStyle(color: Color(0xFF4A5FBC)),
                  hintText: 'e.g., 2016-2020',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: isDark
                      ? scheme.surface.withOpacity(0.4)
                      : Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    borderSide: isDark
                        ? const BorderSide(
                            color: Color(0xFF4A5FBC),
                            width: 1.4,
                          )
                        : BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveEducation() {
    final education = _education.map((edu) {
      return {
        'degree': edu['degree']!.text.trim(),
        'institution': edu['institution']!.text.trim(),
        'years': edu['years']!.text.trim(),
      };
    }).where((edu) {
      return edu['degree']!.isNotEmpty || edu['institution']!.isNotEmpty;
    }).toList();

    if (education.isEmpty) {
      SnackHelper.error(context, 'Please add at least one education or skip');
      return;
    }

    widget.onSave({'content': education});
  }
}

// Skills Form
class _SkillsForm extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  final VoidCallback onSkip;
  final List<String>? suggestedSkills;
  final Map<String, dynamic>? initialData;

  const _SkillsForm({
    required this.onSave,
    required this.onSkip,
    this.suggestedSkills,
    this.initialData,
  });

  @override
  State<_SkillsForm> createState() => _SkillsFormState();
}

class _SkillsFormState extends State<_SkillsForm> {
  final _controller = TextEditingController();
  final Set<String> _selectedSuggestedSkills = {};
  final List<String> _customSkills = [];

  @override
  void initState() {
    super.initState();
    // Restore previously saved skills
    if (widget.initialData != null) {
      final existingSkills =
          (widget.initialData!['content'] as List?)?.cast<String>() ?? [];
      final suggested = widget.suggestedSkills?.toSet() ?? {};

      for (final skill in existingSkills) {
        if (suggested.contains(skill)) {
          _selectedSuggestedSkills.add(skill);
        } else {
          _customSkills.add(skill);
        }
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _totalSkills =>
      _selectedSuggestedSkills.length + _customSkills.length;

  void _addCustomSkill() {
    final skill = _controller.text.trim();
    if (skill.isNotEmpty &&
        _totalSkills < 20 &&
        !_customSkills.contains(skill)) {
      setState(() {
        _customSkills.add(skill);
        _controller.clear();
      });
    }
  }

  void _removeCustomSkill(int index) {
    setState(() {
      _customSkills.removeAt(index);
    });
  }

  void _toggleSuggestedSkill(String skill) {
    setState(() {
      if (_selectedSuggestedSkills.contains(skill)) {
        _selectedSuggestedSkills.remove(skill);
      } else {
        if (_totalSkills < 20) {
          _selectedSuggestedSkills.add(skill);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final hasSuggestions =
        widget.suggestedSkills != null && widget.suggestedSkills!.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Skills',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryPurple,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hasSuggestions
                      ? 'Add custom skills or select from suggestions below (max 20)'
                      : 'Add your skills (max 20)',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),

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
                          controller: _controller,
                          decoration: const InputDecoration(
                            hintText: 'e.g., JavaScript, Python',
                            hintStyle: TextStyle(color: Colors.grey),
                            filled: true,
                            fillColor: Colors.transparent,
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12)),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12)),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12)),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) => _addCustomSkill(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _totalSkills < 20 ? _addCustomSkill : null,
                      icon: const Icon(Icons.add_circle, size: 40),
                      color: AppTheme.primaryPurple,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '${_totalSkills}/20 skills selected',
                  style: TextStyle(
                    color: _totalSkills >= 20 ? Colors.red : Colors.grey,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                if (_customSkills.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _customSkills.asMap().entries.map((entry) {
                      final index = entry.key;
                      final skill = entry.value;
                      return Chip(
                        label: Text(skill),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () => _removeCustomSkill(index),
                        backgroundColor: scheme.brightness == Brightness.dark
                            ? scheme.surfaceContainerHighest
                            : Colors.white,
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      );
                    }).toList(),
                  ),

                // Suggested Skills Section (moved to bottom)
                if (hasSuggestions) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Or select from suggested skills:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.suggestedSkills!.map((skill) {
                      final isSelected =
                          _selectedSuggestedSkills.contains(skill);
                      final canSelect = _totalSkills < 20 || isSelected;
                      return FilterChip(
                        label: Text(skill),
                        selected: isSelected,
                        onSelected: canSelect
                            ? (_) => _toggleSuggestedSkill(skill)
                            : null,
                        selectedColor: AppTheme.primaryPurple,
                        checkmarkColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : scheme.onSurface,
                          fontWeight:
                              isSelected ? FontWeight.w500 : FontWeight.normal,
                        ),
                        backgroundColor: scheme.brightness == Brightness.dark
                            ? scheme.surfaceContainerHighest
                            : Colors.white,
                        disabledColor: scheme.brightness == Brightness.dark
                            ? scheme.surfaceContainer
                            : Colors.grey[200],
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 0,
                        pressElevation: 0,
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.onSkip,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentCoral,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text('Skip',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    if (_totalSkills == 0) {
                      SnackHelper.error(context,
                          'Please select or add at least one skill or skip');
                      return;
                    }
                    // Combine selected suggested skills and custom skills
                    final allSkills = [
                      ..._selectedSuggestedSkills,
                      ..._customSkills
                    ];
                    widget.onSave({'content': allSkills});
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text('Next',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Certifications Form
class _CertificationsForm extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  final VoidCallback onSkip;
  final Map<String, dynamic>? initialData;

  const _CertificationsForm({
    required this.onSave,
    required this.onSkip,
    this.initialData,
  });

  @override
  State<_CertificationsForm> createState() => _CertificationsFormState();
}

class _CertificationsFormState extends State<_CertificationsForm> {
  final List<Map<String, TextEditingController>> _certifications = [];

  @override
  void initState() {
    super.initState();
    // Restore previously saved certifications
    if (widget.initialData != null) {
      final existingCerts = (widget.initialData!['content'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      for (final cert in existingCerts) {
        _certifications.add({
          'name': TextEditingController(text: cert['name'] ?? ''),
          'issuer': TextEditingController(text: cert['issuer'] ?? ''),
          'year': TextEditingController(text: cert['year'] ?? ''),
        });
      }
    }
    // Add at least one entry if empty
    if (_certifications.isEmpty) {
      _addCertification();
    }
  }

  void _addCertification() {
    if (_certifications.length < 10) {
      setState(() {
        _certifications.add({
          'name': TextEditingController(),
          'issuer': TextEditingController(),
          'year': TextEditingController(),
        });
      });
    }
  }

  void _removeCertification(int index) {
    setState(() {
      _certifications[index].forEach((key, controller) => controller.dispose());
      _certifications.removeAt(index);
    });
  }

  @override
  void dispose() {
    for (var cert in _certifications) {
      cert.forEach((key, controller) => controller.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Certifications',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryPurple,
                      ),
                    ),
                    if (_certifications.length < 10)
                      IconButton(
                        onPressed: _addCertification,
                        icon: const Icon(Icons.add_circle, size: 32),
                        color: AppTheme.primaryPurple,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Add up to ${10 - _certifications.length} more certifications',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                ..._certifications.asMap().entries.map((entry) {
                  final index = entry.key;
                  final cert = entry.value;
                  return _buildCertificationEntry(index, cert);
                }).toList(),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.onSkip,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentCoral,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text('Skip',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveCertifications,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text('Next',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCertificationEntry(
    int index,
    Map<String, TextEditingController> cert,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              isDark ? 0.12 : 0.05,
            ),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Certification ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (_certifications.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _removeCertification(index),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.transparent : scheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: cert['name'],
                decoration: InputDecoration(
                  labelText: 'Certification Name',
                  labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                  floatingLabelStyle: const TextStyle(color: Color(0xFF4A5FBC)),
                  hintText: 'e.g., AWS Certified Solutions Architect',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: isDark
                      ? scheme.surface.withOpacity(0.4)
                      : Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    borderSide: isDark
                        ? const BorderSide(
                            color: Color(0xFF4A5FBC),
                            width: 1.4,
                          )
                        : BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.transparent : scheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: cert['issuer'],
                decoration: InputDecoration(
                  labelText: 'Issuer',
                  labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                  floatingLabelStyle: const TextStyle(color: Color(0xFF4A5FBC)),
                  hintText: 'e.g., Amazon Web Services',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: isDark
                      ? scheme.surface.withOpacity(0.4)
                      : Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    borderSide: isDark
                        ? const BorderSide(
                            color: Color(0xFF4A5FBC),
                            width: 1.4,
                          )
                        : BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.transparent : scheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: cert['year'],
                decoration: InputDecoration(
                  labelText: 'Year',
                  labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                  floatingLabelStyle: const TextStyle(color: Color(0xFF4A5FBC)),
                  hintText: 'e.g., 2023',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: isDark
                      ? scheme.surface.withOpacity(0.4)
                      : Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    borderSide: isDark
                        ? const BorderSide(
                            color: Color(0xFF4A5FBC),
                            width: 1.4,
                          )
                        : BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveCertifications() {
    final certifications = _certifications.map((cert) {
      return {
        'name': cert['name']!.text.trim(),
        'issuer': cert['issuer']!.text.trim(),
        'year': cert['year']!.text.trim(),
      };
    }).where((cert) {
      return cert['name']!.isNotEmpty || cert['issuer']!.isNotEmpty;
    }).toList();

    if (certifications.isEmpty) {
      SnackHelper.error(
          context, 'Please add at least one certification or skip');
      return;
    }

    widget.onSave({'content': certifications});
  }
}

// Languages Form
class _LanguagesForm extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  final VoidCallback onSkip;
  final Map<String, dynamic>? initialData;

  const _LanguagesForm({
    required this.onSave,
    required this.onSkip,
    this.initialData,
  });

  @override
  State<_LanguagesForm> createState() => _LanguagesFormState();
}

class _LanguagesFormState extends State<_LanguagesForm> {
  static const List<String> _proficiencyLevels = [
    'Native',
    'Fluent',
    'Advanced',
    'Intermediate',
    'Basic',
  ];

  static const List<String> _worldLanguages = [
    'Afrikaans',
    'Albanian',
    'Amharic',
    'Arabic',
    'Armenian',
    'Azerbaijani',
    'Basque',
    'Belarusian',
    'Bengali',
    'Bosnian',
    'Bulgarian',
    'Burmese',
    'Catalan',
    'Cebuano',
    'Chinese (Simplified)',
    'Chinese (Traditional)',
    'Corsican',
    'Croatian',
    'Czech',
    'Danish',
    'Dutch',
    'English',
    'Esperanto',
    'Estonian',
    'Finnish',
    'French',
    'Frisian',
    'Galician',
    'Georgian',
    'German',
    'Greek',
    'Gujarati',
    'Haitian Creole',
    'Hausa',
    'Hawaiian',
    'Hebrew',
    'Hindi',
    'Hmong',
    'Hungarian',
    'Icelandic',
    'Igbo',
    'Indonesian',
    'Irish',
    'Italian',
    'Japanese',
    'Javanese',
    'Kannada',
    'Kazakh',
    'Khmer',
    'Kinyarwanda',
    'Korean',
    'Kurdish',
    'Kyrgyz',
    'Lao',
    'Latin',
    'Latvian',
    'Lithuanian',
    'Luxembourgish',
    'Macedonian',
    'Malagasy',
    'Malay',
    'Malayalam',
    'Maltese',
    'Maori',
    'Marathi',
    'Mongolian',
    'Nepali',
    'Norwegian',
    'Odia',
    'Pashto',
    'Persian',
    'Polish',
    'Portuguese',
    'Punjabi',
    'Romanian',
    'Russian',
    'Samoan',
    'Scots Gaelic',
    'Serbian',
    'Sesotho',
    'Shona',
    'Sindhi',
    'Sinhala',
    'Slovak',
    'Slovenian',
    'Somali',
    'Spanish',
    'Sundanese',
    'Swahili',
    'Swedish',
    'Tagalog',
    'Tajik',
    'Tamil',
    'Tatar',
    'Telugu',
    'Thai',
    'Turkish',
    'Turkmen',
    'Ukrainian',
    'Urdu',
    'Uyghur',
    'Uzbek',
    'Vietnamese',
    'Welsh',
    'Xhosa',
    'Yiddish',
    'Yoruba',
    'Zulu',
  ];

  final List<Map<String, String?>> _languages = [];

  @override
  void initState() {
    super.initState();
    // Restore previously saved languages
    if (widget.initialData != null) {
      final existingLangs = (widget.initialData!['content'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      for (final lang in existingLangs) {
        _languages.add({
          'language': lang['language'] as String?,
          'proficiency': lang['proficiency'] as String?,
        });
      }
    }
    // Add at least one entry if empty
    if (_languages.isEmpty) {
      _addLanguage();
    }
  }

  void _addLanguage() {
    if (_languages.length < 10) {
      setState(() {
        _languages.add({
          'language': null,
          'proficiency': null,
        });
      });
    }
  }

  void _removeLanguage(int index) {
    setState(() {
      _languages.removeAt(index);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Languages',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryPurple,
                      ),
                    ),
                    if (_languages.length < 10)
                      IconButton(
                        onPressed: _addLanguage,
                        icon: const Icon(Icons.add_circle, size: 32),
                        color: AppTheme.primaryPurple,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Add up to ${10 - _languages.length} more languages',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                ..._languages.asMap().entries.map((entry) {
                  final index = entry.key;
                  final lang = entry.value;
                  return _buildLanguageEntry(index, lang);
                }).toList(),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.onSkip,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentCoral,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text('Skip',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveLanguages,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Finish'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageEntry(int index, Map<String, String?> lang) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              isDark ? 0.12 : 0.05,
            ),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Language ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (_languages.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _removeLanguage(index),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.transparent : scheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: DropdownButtonFormField2<String>(
                value: lang['language'],
                decoration: InputDecoration(
                  labelText: 'Language',
                  labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                  floatingLabelStyle: const TextStyle(color: Color(0xFF4A5FBC)),
                  hintText: 'Select a language',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: isDark
                      ? scheme.surface.withOpacity(0.4)
                      : Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    borderSide: isDark
                        ? const BorderSide(
                            color: Color(0xFF4A5FBC),
                            width: 1.4,
                          )
                        : BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                ),
                items: _worldLanguages.map((language) {
                  return DropdownMenuItem<String>(
                    value: language,
                    child: Text(language),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    lang['language'] = value;
                  });
                },
                buttonStyleData: const ButtonStyleData(
                  padding: EdgeInsets.only(right: 8),
                ),
                iconStyleData: const IconStyleData(
                  icon: Icon(Icons.arrow_drop_down),
                  iconSize: 24,
                ),
                dropdownStyleData: DropdownStyleData(
                  maxHeight: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                menuItemStyleData: const MenuItemStyleData(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.transparent : scheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: DropdownButtonFormField2<String>(
                value: lang['proficiency'],
                decoration: InputDecoration(
                  labelText: 'Proficiency',
                  labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                  floatingLabelStyle: const TextStyle(color: Color(0xFF4A5FBC)),
                  hintText: 'Select proficiency level',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: isDark
                      ? scheme.surface.withOpacity(0.4)
                      : Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    borderSide: isDark
                        ? const BorderSide(
                            color: Color(0xFF4A5FBC),
                            width: 1.4,
                          )
                        : BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                ),
                items: _proficiencyLevels.map((level) {
                  return DropdownMenuItem<String>(
                    value: level,
                    child: Text(level),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    lang['proficiency'] = value;
                  });
                },
                buttonStyleData: const ButtonStyleData(
                  padding: EdgeInsets.only(right: 8),
                ),
                iconStyleData: const IconStyleData(
                  icon: Icon(Icons.arrow_drop_down),
                  iconSize: 24,
                ),
                dropdownStyleData: DropdownStyleData(
                  maxHeight: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                menuItemStyleData: const MenuItemStyleData(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveLanguages() {
    final languages = _languages.map((lang) {
      return {
        'language': lang['language'] ?? '',
        'proficiency': lang['proficiency'] ?? '',
      };
    }).where((lang) {
      return lang['language']!.isNotEmpty;
    }).toList();

    if (languages.isEmpty) {
      SnackHelper.error(context, 'Please add at least one language or skip');
      return;
    }

    widget.onSave({'content': languages});
  }
}
