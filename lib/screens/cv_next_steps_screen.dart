import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../config/theme.dart';
import 'cv_ready_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _detectMissingSections();
  }

  Future<void> _detectMissingSections() async {
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
      }
    } catch (e) {
      setState(() {
        _isDetecting = false;
      });
      SnackHelper.error(context, 'Error detecting missing sections: $e');
    }
  }

  Future<void> _enhanceCV() async {
    setState(() {
      _isEnhancing = true;
    });

    try {
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

      setState(() {
        _isEnhancing = false;
      });

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

  void _skipAll() {
    _enhanceCV();
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
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: AppTheme.primaryPurple,
          foregroundColor: Colors.white,
          title: Text(
            _isEnhancing ? 'Enhancing CV' : 'Complete Your CV',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
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
            color: scheme.brightness == Brightness.dark
                ? scheme.surfaceVariant.withOpacity(0.6)
                : AppTheme.primaryPurple.withOpacity(0.04),
            border: Border(
              bottom: BorderSide(
                color: scheme.outline.withOpacity(0.3),
                width: 1,
              ),
            ),
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
                    const SizedBox.shrink(),
                  Text(
                    'Section ${_currentSectionIndex + 1} of ${_missingSections.length}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                  TextButton(
                    onPressed: _skipAll,
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant,
                    ),
                    child: const Text('Skip All'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: scheme.surface.withOpacity(0.5),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppTheme.primaryPurple,
                ),
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
                TextField(
                  controller: _fullNameController,
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    hintText: 'e.g., John Doe',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryPurple,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    hintText: 'e.g., john@example.com',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryPurple,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone',
                    hintText: 'e.g., +1 234 567 8900',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryPurple,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _locationController,
                  decoration: InputDecoration(
                    labelText: 'Location',
                    hintText: 'e.g., New York, USA',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryPurple,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _linksController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Links (LinkedIn, Portfolio, etc.)',
                    hintText:
                        'e.g., linkedin.com/in/johndoe, github.com/johndoe',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryPurple,
                        width: 2,
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
          decoration: BoxDecoration(
            color: scheme.surface,
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withOpacity(0.2),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onSkip,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(
                      color: AppTheme.primaryPurple,
                      width: 2,
                    ),
                  ),
                  child: const Text('Skip'),
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
                    backgroundColor: AppTheme.primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Next'),
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
                TextField(
                  controller: _controller,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText:
                        'e.g., Experienced software engineer with 5+ years...',
                    hintStyle: TextStyle(
                      color: scheme.onSurfaceVariant.withOpacity(0.7),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryPurple,
                        width: 2,
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
          decoration: BoxDecoration(
            color: scheme.surface,
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withOpacity(0.2),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onSkip,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(
                      color: AppTheme.primaryPurple,
                      width: 2,
                    ),
                  ),
                  child: const Text('Skip'),
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
                    backgroundColor: AppTheme.primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Next'),
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
                const Text(
                  'Work Experience',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryPurple,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add up to ${10 - _experiences.length} more experience(s)',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                if (_experiences.length < 10)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: OutlinedButton.icon(
                      onPressed: _addExperience,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Another Experience'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        side: const BorderSide(
                            color: AppTheme.primaryPurple, width: 1.5),
                        foregroundColor: AppTheme.primaryPurple,
                      ),
                    ),
                  ),
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
          decoration: BoxDecoration(
            color: scheme.surface,
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withOpacity(0.2),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onSkip,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(
                        color: AppTheme.primaryPurple, width: 2),
                  ),
                  child: const Text('Skip'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveExperiences,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExperienceEntry(
      int index, Map<String, TextEditingController> exp) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surface,
      margin: const EdgeInsets.only(bottom: 16),
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
            TextField(
              controller: exp['title'],
              decoration: const InputDecoration(
                labelText: 'Job Title',
                hintText: 'e.g., Software Engineer',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: exp['company'],
              decoration: const InputDecoration(
                labelText: 'Company',
                hintText: 'e.g., Google',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: exp['years'],
              decoration: const InputDecoration(
                labelText: 'Years',
                hintText: 'e.g., 2020-2023',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: exp['description'],
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Describe your responsibilities and achievements',
                border: OutlineInputBorder(),
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
                const Text(
                  'Education',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryPurple,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add up to ${10 - _education.length} more education entries',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                if (_education.length < 10)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: OutlinedButton.icon(
                      onPressed: _addEducation,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Another Education'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        side: const BorderSide(color: AppTheme.primaryPurple),
                        foregroundColor: AppTheme.primaryPurple,
                      ),
                    ),
                  ),
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
          decoration: BoxDecoration(
            color: scheme.surface,
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withOpacity(0.2),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onSkip,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: AppTheme.primaryPurple),
                  ),
                  child: const Text('Skip'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveEducation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEducationEntry(
      int index, Map<String, TextEditingController> edu) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surface,
      margin: const EdgeInsets.only(bottom: 16),
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
            TextField(
              controller: edu['degree'],
              decoration: const InputDecoration(
                labelText: 'Degree',
                hintText: 'e.g., Bachelor of Computer Science',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: edu['institution'],
              decoration: const InputDecoration(
                labelText: 'Institution',
                hintText: 'e.g., MIT',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: edu['years'],
              decoration: const InputDecoration(
                labelText: 'Years',
                hintText: 'e.g., 2016-2020',
                border: OutlineInputBorder(),
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

    return SingleChildScrollView(
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

          // Custom Skills Section (moved to top)
          Text(
            hasSuggestions ? 'Add Custom Skills:' : 'Your Skills:',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'e.g., JavaScript, Python',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppTheme.primaryPurple, width: 2),
                    ),
                  ),
                  onSubmitted: (_) => _addCustomSkill(),
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
                  backgroundColor: AppTheme.primaryPurple.withOpacity(0.1),
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
            const Divider(),
            const SizedBox(height: 16),
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
                final isSelected = _selectedSuggestedSkills.contains(skill);
                final canSelect = _totalSkills < 20 || isSelected;
                return FilterChip(
                  label: Text(skill),
                  selected: isSelected,
                  onSelected:
                      canSelect ? (_) => _toggleSuggestedSkill(skill) : null,
                  selectedColor: AppTheme.primaryPurple,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight:
                        isSelected ? FontWeight.w500 : FontWeight.normal,
                  ),
                  backgroundColor: AppTheme.primaryPurple.withOpacity(0.1),
                  disabledColor: AppTheme.primaryPurple.withOpacity(0.05),
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

          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onSkip,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: AppTheme.primaryPurple),
                  ),
                  child: const Text('Skip'),
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
                    backgroundColor: AppTheme.primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
        ],
      ),
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
                const Text(
                  'Certifications',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryPurple,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add up to ${10 - _certifications.length} more certifications',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                if (_certifications.length < 10)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: OutlinedButton.icon(
                      onPressed: _addCertification,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Another Certification'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        side: const BorderSide(color: AppTheme.primaryPurple),
                        foregroundColor: AppTheme.primaryPurple,
                      ),
                    ),
                  ),
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
          decoration: BoxDecoration(
            color: scheme.surface,
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withOpacity(0.2),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onSkip,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(
                        color: AppTheme.primaryPurple, width: 2),
                  ),
                  child: const Text('Skip'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveCertifications,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCertificationEntry(
      int index, Map<String, TextEditingController> cert) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surface,
      margin: const EdgeInsets.only(bottom: 16),
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
            TextField(
              controller: cert['name'],
              decoration: const InputDecoration(
                labelText: 'Certification Name',
                hintText: 'e.g., AWS Certified Solutions Architect',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cert['issuer'],
              decoration: const InputDecoration(
                labelText: 'Issuer',
                hintText: 'e.g., Amazon Web Services',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cert['year'],
              decoration: const InputDecoration(
                labelText: 'Year',
                hintText: 'e.g., 2023',
                border: OutlineInputBorder(),
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
  final List<Map<String, TextEditingController>> _languages = [];

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
          'language': TextEditingController(text: lang['language'] ?? ''),
          'proficiency': TextEditingController(text: lang['proficiency'] ?? ''),
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
          'language': TextEditingController(),
          'proficiency': TextEditingController(),
        });
      });
    }
  }

  void _removeLanguage(int index) {
    setState(() {
      _languages[index].forEach((key, controller) => controller.dispose());
      _languages.removeAt(index);
    });
  }

  @override
  void dispose() {
    for (var lang in _languages) {
      lang.forEach((key, controller) => controller.dispose());
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
                const Text(
                  'Languages',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryPurple,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add up to ${10 - _languages.length} more languages',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                if (_languages.length < 10)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: OutlinedButton.icon(
                      onPressed: _addLanguage,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Another Language'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        side: const BorderSide(
                            color: AppTheme.primaryPurple, width: 1.5),
                        foregroundColor: AppTheme.primaryPurple,
                      ),
                    ),
                  ),
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
          decoration: BoxDecoration(
            color: scheme.surface,
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withOpacity(0.2),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onSkip,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(
                        color: AppTheme.primaryPurple, width: 2),
                  ),
                  child: const Text('Skip'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveLanguages,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryPurple,
                    foregroundColor: Colors.white,
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

  Widget _buildLanguageEntry(
      int index, Map<String, TextEditingController> lang) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surface,
      margin: const EdgeInsets.only(bottom: 16),
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
            TextField(
              controller: lang['language'],
              decoration: const InputDecoration(
                labelText: 'Language',
                hintText: 'e.g., English, Arabic',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lang['proficiency'],
              decoration: const InputDecoration(
                labelText: 'Proficiency',
                hintText: 'e.g., Native, Fluent, Intermediate',
                border: OutlineInputBorder(),
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
        'language': lang['language']!.text.trim(),
        'proficiency': lang['proficiency']!.text.trim(),
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
