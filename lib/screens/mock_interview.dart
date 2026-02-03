import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class MockInterviewSpecialtyScreen extends StatefulWidget {
  const MockInterviewSpecialtyScreen({super.key});

  @override
  State<MockInterviewSpecialtyScreen> createState() =>
      _MockInterviewSpecialtyScreenState();
}

class _MockInterviewSpecialtyScreenState
    extends State<MockInterviewSpecialtyScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _selected;

  final Map<String, String> _specialties = const {
    // Technical
    'Computer & Information Technology':
        'General tech roles, software, IT, and digital systems.',
    'Cybersecurity':
        'Security, threats, incident response, and risk awareness.',
    'Data & Artificial Intelligence':
        'Data analysis, AI concepts, and problem solving with data.',

    // Engineering
    'Engineering':
        'Engineering fundamentals, projects, and technical teamwork.',

    // Business
    'Business Administration':
        'Operations, management, teamwork, and decision making.',
    'Marketing': 'Campaigns, content, customer focus, and basic analytics.',
    'Finance & Accounting':
        'Numbers, budgeting, reporting, and financial reasoning.',
    'Human Resources':
        'People operations, communication, and workplace scenarios.',

    // Health
    'Healthcare & Medical':
        'Healthcare roles, patient care basics, and professionalism.',

    'Law': 'Legal roles, regulations, ethics, and professional responsibility.',

    'Education': 'Teaching mindset, communication, and planning lessons.',
    'Media & Communication':
        'Communication skills, storytelling, and public-facing roles.',
  };

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final entries = _specialties.entries.toList();

    final filtered = entries.where((e) {
      final q = _query.toLowerCase().trim();
      return e.key.toLowerCase().contains(q);
    }).toList();
    final shadowColor =
        isDark ? Colors.black.withOpacity(0.6) : Colors.black.withOpacity(0.07);
    return ThemedScaffold(
      appBar: const CustomHeader(
        title: 'Choose your specialty',
        showBack: true,
      ),

      body: Container(
        color: isDark ? scheme.background : const Color(0xFFF5F5F5),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Search

              Container(
                decoration: BoxDecoration(
                  color: isDark ? scheme.surface : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: shadowColor,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (v) => setState(() => _query = v),
                        style: TextStyle(
                          fontSize: 15,
                          color: isDark ? scheme.onSurface : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'Search specialty, e.g. Marketing…',
                          hintStyle: TextStyle(
                            fontSize: 15,
                            color: isDark ? Colors.grey[400] : Colors.grey[500],
                          ),
                        ),
                      ),
                    ),
                    if (_query.trim().isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        child: Icon(
                          Icons.close,
                          size: 20,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // List
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.manage_search,
                        title: 'No specialties found',
                        subtitle: 'Try a different keyword.',
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final title = filtered[i].key;
                          final subtitle = filtered[i].value;
                          final selected = _selected == title;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: isDark ? scheme.surface : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => setState(() => _selected = title),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: selected
                                          ? scheme.primary
                                          : Colors.transparent,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: selected
                                              ? scheme.primary
                                              : scheme.primary.withOpacity(
                                                  isDark ? 0.25 : 0.12,
                                                ),
                                        ),
                                        child: Icon(
                                          Icons.school_outlined,
                                          color: selected
                                              ? Colors.white
                                              : scheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: isDark
                                                    ? scheme.onSurface
                                                    : Colors.black87,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              subtitle,
                                              style: TextStyle(
                                                fontSize: 13,
                                                height: 1.25,
                                                color: isDark
                                                    ? scheme.onSurface
                                                        .withOpacity(0.7)
                                                    : Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (selected)
                                        Icon(Icons.check_circle,
                                            color: scheme.primary),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      // Continue button
      bottomNavigationBar: SafeArea(
        minimum:
            const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 16),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton(
            onPressed: _selected == null
                ? null
                : () => _confirmPermissionsThenStart(_selected!),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4A5FBC),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            child: const Text(
              'Continue',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmPermissionsThenStart(String specialty) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const JadeerDialog<bool>(
          title: 'Before we start',
          content: Text(
            'Mock Interview needs access to your camera and microphone to record your answers.\n\n'
            'Please make sure you allow permissions when prompted.',
          ),
          primaryLabel: 'Continue',
          primaryResult: true,
          secondaryLabel: 'Cancel',
          secondaryResult: false,
        );
      },
    );

    if (ok != true) return;

    await _startMockInterviewFlow(specialty);
  }

  Future<void> _startMockInterviewFlow(String specialty) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      if (!mounted) return;
      SnackHelper.error(context, 'Please login again.');
      return;
    }

    try {
      final docRef =
          FirebaseFirestore.instance.collection('MockInterviews').doc();

      await docRef.set({
        'MockInterviewsID': docRef.id,
        'UserID': uid,
        'Specialty': specialty,
        'Date': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2) generate questions (for now: static generator)
      final questions = _generateQuestionsForSpecialty(specialty);

      // 3) save questions into existing field from screenshot
      await docRef.set({
        'Questions': questions,
      }, SetOptions(merge: true));

      if (!mounted) return;

      // 4) go to start screen (or directly to session later)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MockInterviewSessionScreen(
            mockInterviewId: docRef.id,
            questions: questions,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      SnackHelper.error(context, 'Failed to start mock interview: $e');
    }
  }

  List<String> _generateQuestionsForSpecialty(String specialty) {
    final base = <String>[
      'Tell me about yourself.',
      'Why are you interested in this field?',
      'Describe a challenge you faced and how you handled it.',
      'What are your strengths and weaknesses?',
      'Where do you see yourself in 2 years?',
    ];

    switch (specialty) {
      case 'Cybersecurity':
        return [
          ...base,
          'How do you handle suspicious emails or phishing attempts?',
        ];
      case 'Finance & Accounting':
        return [
          ...base,
          'How do you ensure accuracy when working with numbers?',
        ];
      case 'Marketing':
        return [
          ...base,
          'How would you measure the success of a marketing campaign?',
        ];
      case 'Healthcare & Medical':
        return [
          ...base,
          'How do you handle pressure in a fast-paced environment?',
        ];
      case 'Engineering':
        return [
          ...base,
          'Tell me about a project you worked on and your role in it.',
        ];
      default:
        return base;
    }
  }
}

class MockInterviewSessionScreen extends StatefulWidget {
  const MockInterviewSessionScreen({
    super.key,
    required this.mockInterviewId,
    required this.questions,
  });

  final String mockInterviewId;
  final List<String> questions;

  @override
  State<MockInterviewSessionScreen> createState() =>
      _MockInterviewSessionScreenState();
}

class _MockInterviewSessionScreenState
    extends State<MockInterviewSessionScreen> {
  CameraController? _camera;
  bool _initializing = true;
  String? _error;

  int _index = 0;

  String get _currentQuestion =>
      (widget.questions.isEmpty) ? '—' : widget.questions[_index];

  bool get _isLast => _index >= widget.questions.length - 1;
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;

  late List<String> _answerUrls;

  @override
  void initState() {
    super.initState();
    _initPermissionsAndCamera();
    _answerUrls = List<String>.filled(widget.questions.length, '');
  }

  Future<void> _initPermissionsAndCamera() async {
    try {
      if (!mounted) return;
      setState(() {
        _initializing = true;
        _error = null;
      });

      final cam = await Permission.camera.request();
      final mic = await Permission.microphone.request();

      if (!mounted) return;

      if (!cam.isGranted || !mic.isGranted) {
        setState(() {
          _error = 'Camera/Microphone permission is required to continue.';
          _initializing = false;
        });
        return;
      }

      final cams = await availableCameras();

      if (!mounted) return;

      if (cams.isEmpty) {
        setState(() {
          _error = 'No camera found on this device.';
          _initializing = false;
        });
        return;
      }

      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: true,
      );

      await controller.initialize();

      if (!mounted) return;

      setState(() {
        _camera = controller;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to initialize camera: $e';
        _initializing = false;
      });
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_isRecording) {
      SnackHelper.error(context, 'Stop recording first.');
      return;
    }

    final hasAnswer = _answerUrls[_index].trim().isNotEmpty;
    if (!hasAnswer) {
      SnackHelper.error(context, 'Please record your answer first.');
      return;
    }

    if (_isLast) {
      await _finish();
      return;
    }

    setState(() {
      _index++;
      _recordDuration = Duration.zero;
    });
  }

  void _startTimer() {
    _recordTimer?.cancel();
    _recordDuration = Duration.zero;
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recordDuration += const Duration(seconds: 1));
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _toggleRecording() async {
    try {
      if (_isRecording) {
        // Stop
        final path = await _recorder.stop();
        _recordTimer?.cancel();

        if (!mounted) return;
        setState(() => _isRecording = false);

        if (path == null || path.isEmpty) {
          SnackHelper.error(context, 'Recording failed. Try again.');
          return;
        }

        // Upload to Firebase Storage
        final url = await _uploadAudioAndGetUrl(File(path));

        // Save URL in local list + Firestore AnswersRecordsURL[index]
        _answerUrls[_index] = url;

        await FirebaseFirestore.instance
            .collection('MockInterviews')
            .doc(widget.mockInterviewId)
            .set({
          'AnswersRecordsURL': _answerUrls,
        }, SetOptions(merge: true));

        if (!mounted) return;
        SnackHelper.success(context, 'Answer recorded ✅');
        return;
      }
      if (_answerUrls[_index].trim().isNotEmpty) {
        final overwrite = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const JadeerDialog<bool>(
            title: 'Replace recording?',
            content: Text(
                'You already recorded an answer for this question. Replace it?'),
            primaryLabel: 'Replace',
            primaryResult: true,
            secondaryLabel: 'Cancel',
            secondaryResult: false,
          ),
        );

        if (overwrite != true) return;

        _answerUrls[_index] = '';
        if (!mounted) return;
        setState(() {});
      }

      // Start
      final hasMic = await _recorder.hasPermission();
      if (!hasMic) {
        if (!mounted) return;
        SnackHelper.error(context, 'Microphone permission is required.');
        return;
      }

      final dir = await getTemporaryDirectory();
      final fileName =
          'mock_${widget.mockInterviewId}_q${_index + 1}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final path = '${dir.path}/$fileName';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _startTimer();

      if (!mounted) return;
      setState(() => _isRecording = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
      });
      SnackHelper.error(context, 'Recording error: $e');
    }
  }

  Future<String> _uploadAudioAndGetUrl(File file) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final storagePath =
        'mock_interviews/$uid/${widget.mockInterviewId}/q${_index + 1}.m4a';

    final ref = FirebaseStorage.instance.ref().child(storagePath);

    await ref.putFile(
      file,
      SettableMetadata(contentType: 'audio/mp4'),
    );

    return await ref.getDownloadURL();
  }

  Future<void> _finish() async {
    final reportText =
        'Mock interview completed. Answers recorded: ${_answerUrls.where((e) => e.trim().isNotEmpty).length}/${widget.questions.length}.';

    try {
      await FirebaseFirestore.instance
          .collection('MockInterviews')
          .doc(widget.mockInterviewId)
          .set({'Report': reportText}, SetOptions(merge: true));
    } catch (_) {}

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => JadeerDialog<void>(
        title: 'Finished',
        content: Text(reportText),
        primaryLabel: 'Done',
        primaryResult: null,
      ),
    );

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ThemedScaffold(
      appBar: const CustomHeader(
        title: 'Mock Interview',
        showBack: true,
      ),
      body: Container(
        color: isDark ? scheme.background : const Color(0xFFF5F5F5),
        child: _initializing
            ? const Center(child: CircularProgressIndicator())
            : (_error != null)
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.error),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _initPermissionsAndCamera,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // Camera preview
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: AspectRatio(
                            aspectRatio: _camera!.value.aspectRatio,
                            child: CameraPreview(_camera!),
                          ),
                        ),
                      ),

                      // Question card
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? scheme.surface : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withOpacity(isDark ? 0.6 : 0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Question ${_index + 1}/${widget.questions.length}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? scheme.onSurface.withOpacity(0.7)
                                      : Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _currentQuestion,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Answer by voice, then press Next.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? scheme.onSurface.withOpacity(0.7)
                                      : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isDark ? scheme.surface : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withOpacity(isDark ? 0.6 : 0.08),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _isRecording ? Icons.mic : Icons.mic_none,
                                      color: _isRecording
                                          ? const Color(0xFFFC686A)
                                          : scheme.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _isRecording
                                            ? 'Recording… ${_fmt(_recordDuration)}'
                                            : (_answerUrls[_index].isNotEmpty
                                                ? 'Answer recorded ✅'
                                                : 'Tap to record your answer'),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? scheme.onSurface
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    SizedBox(
                                      height: 42,
                                      child: FilledButton(
                                        onPressed: _toggleRecording,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: _isRecording
                                              ? const Color(0xFFFC686A)
                                              : const Color(0xFF4A5FBC),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                        ),
                                        child: Text(
                                            _isRecording ? 'Stop' : 'Record'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      // Next / Finish
                      SafeArea(
                        minimum: const EdgeInsets.symmetric(horizontal: 16)
                            .copyWith(bottom: 16),
                        child: SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: FilledButton(
                            onPressed: _next,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF4A5FBC),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: Text(_isLast ? 'Finish' : 'Next'),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
