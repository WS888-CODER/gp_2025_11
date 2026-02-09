import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/screens/mock_interview_report.dart';
import 'package:just_audio/just_audio.dart';
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
  Future<bool> consumeMockInterviewCredit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final userDocRef =
        FirebaseFirestore.instance.collection('Users').doc(user.uid);

    return FirebaseFirestore.instance.runTransaction<bool>((tx) async {
      final snap = await tx.get(userDocRef);
      final data = snap.data() ?? {};
      final aiUsage = (data['AiUsage'] as Map<String, dynamic>?) ?? {};

      int credits = (aiUsage['MockInterview'] ?? 2) as int;

      if (credits <= 0) return false;

      tx.update(userDocRef, {
        'AiUsage.MockInterview': credits - 1,
      });

      return true;
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  int _mockInterviewCredits = 0;
  bool _loadingCredits = true;
  @override
  void initState() {
    super.initState();
    _loadCredits();
  }

  Future<void> _loadCredits() async {
    setState(() => _loadingCredits = true);
    final usage = await fetchAndResetAiUsageIfNeeded();
    if (!mounted) return;
    setState(() {
      _mockInterviewCredits = usage['MockInterview'] ?? 0;
      _loadingCredits = false;
    });
  }

  Widget _buildMockCreditsInfo() {
    if (_loadingCredits) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF4A5FBC).withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF4A5FBC).withOpacity(0.25),
            width: 1,
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Loading credits...'),
          ],
        ),
      );
    }

    final hasCredits = _mockInterviewCredits > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: hasCredits
            ? const Color(0xFF4A5FBC).withOpacity(0.10)
            : Colors.red.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasCredits
              ? const Color(0xFF4A5FBC).withOpacity(0.25)
              : Colors.red.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasCredits ? Icons.auto_awesome : Icons.warning_rounded,
            color: hasCredits ? const Color(0xFF4A5FBC) : Colors.red,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasCredits
                      ? 'Mock Interview Credits'
                      : 'No Credits Remaining',
                  style: TextStyle(
                    color: hasCredits ? const Color(0xFF4A5FBC) : Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasCredits
                      ? '$_mockInterviewCredits ${_mockInterviewCredits == 1 ? 'credit' : 'credits'} remaining today'
                      : 'Credits reset daily at midnight',
                  style: TextStyle(
                    color: hasCredits
                        ? const Color(0xFF4A5FBC).withOpacity(0.75)
                        : Colors.red.withOpacity(0.75),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
    final canContinue =
        _selected != null && !_loadingCredits && _mockInterviewCredits > 0;

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
              _buildMockCreditsInfo(),
              const SizedBox(height: 12),
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
        minimum: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          bottom: 16,
        ),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton(
            onPressed: canContinue
                ? () => _confirmPermissionsThenStart(_selected!)
                : null,
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
      // 1) reset if needed
      final usage = await fetchAndResetAiUsageIfNeeded();
      if (!mounted) return;
      setState(() {
        _mockInterviewCredits = usage['MockInterview'] ?? _mockInterviewCredits;
      });

      // 2) consume credit
      final ok = await consumeMockInterviewCredit();
      if (!ok) {
        if (!mounted) return;
        SnackHelper.error(
          context,
          'You have no Mock Interview credits remaining today. Credits reset at midnight.',
        );
        return;
      }

      if (!mounted) return;
      setState(() =>
          _mockInterviewCredits = (_mockInterviewCredits - 1).clamp(0, 999));

      // 3) create interview doc
      final docRef =
          FirebaseFirestore.instance.collection('MockInterviews').doc();

      await docRef.set({
        'MockInterviewsID': docRef.id,
        'UserID': uid,
        'Specialty': specialty,
        'Date': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final questions = _generateQuestionsForSpecialty(specialty);

      await docRef.set({'Questions': questions}, SetOptions(merge: true));

      if (!mounted) return;

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
      await refundMockInterviewCredit();
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
  final AudioPlayer _player = AudioPlayer();
  bool _isGeneratingReport = false;

  bool _isUploadingAnswer = false;
  double _uploadProgress = 0.0;
  StreamSubscription<TaskSnapshot>? _uploadSub;
  bool _isFinishing = false;

  String? _currentPlaybackUrl;
  bool _isPlaying = false;
  bool get _canGoNext =>
      !_isRecording &&
      !_isUploadingAnswer &&
      _answerUrls[_index].trim().isNotEmpty;

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
  late final FlutterTts _tts;
  bool _ttsReady = false;
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _answerUrls = List<String>.filled(widget.questions.length, '');
    _tts = FlutterTts();

    _initTts().then((_) {
      if (!mounted) return;
      _initPermissionsAndCamera();
    });

    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        setState(() => _isPlaying = false);
      }
    });
  }

  Future<void> _cancelInterviewAndCleanup() async {
    try {
      // أوقفي أي شيء شغال
      _recordTimer?.cancel();
      if (_isRecording) {
        await _recorder.stop();
        _isRecording = false;
      }
      await _player.stop();
      await _tts.stop();

      final docRef = FirebaseFirestore.instance
          .collection('MockInterviews')
          .doc(widget.mockInterviewId);

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        final folderRef = FirebaseStorage.instance
            .ref()
            .child('mock_interviews/$uid/${widget.mockInterviewId}');

        final list = await folderRef.listAll();
        for (final item in list.items) {
          try {
            await item.delete();
          } catch (_) {}
        }
      }

      await docRef.delete();
    } catch (e) {
      if (mounted) {
        SnackHelper.error(context, 'Cleanup failed: $e');
      }
    }
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);

      _tts.setStartHandler(() {
        if (!mounted) return;
        setState(() => _isSpeaking = true);
      });

      _tts.setCompletionHandler(() {
        if (!mounted) return;
        setState(() => _isSpeaking = false);
      });

      _tts.setErrorHandler((_) {
        if (!mounted) return;
        setState(() => _isSpeaking = false);
      });
      if (!mounted) return;
      setState(() => _ttsReady = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _ttsReady = false);
    }
  }

  Future<void> _speakCurrentQuestion() async {
    if (!_ttsReady) return;
    if (_isRecording) return;
    await _tts.stop();
    await _tts.speak(_currentQuestion);
  }

  Future<void> _toggleSpeak() async {
    if (!_ttsReady) return;

    if (_isSpeaking) {
      await _tts.stop();
      return;
    }
    await _speakCurrentQuestion();
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
        enableAudio: false,
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

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    await _speakCurrentQuestion();
  }

  @override
  void dispose() {
    _tts.stop();
    _recordTimer?.cancel();
    _recorder.dispose();
    _camera?.dispose();
    _uploadSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final url = _answerUrls[_index].trim();
    if (url.isEmpty) return;

    try {
      if (_isPlaying) {
        await _player.pause();
        if (!mounted) return;
        setState(() => _isPlaying = false);
        return;
      }

      if (_currentPlaybackUrl != url) {
        await _player.setUrl(url);
        _currentPlaybackUrl = url;
      }

      await _player.play();
      if (!mounted) return;
      setState(() => _isPlaying = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPlaying = false);
      SnackHelper.error(context, 'Playback error: $e');
    }
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

    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await _speakCurrentQuestion();
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

  Future<String> _uploadAudioAndGetUrlWithProgress(File file) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final storagePath =
        'mock_interviews/$uid/${widget.mockInterviewId}/q${_index + 1}.m4a';

    final ref = FirebaseStorage.instance.ref().child(storagePath);
    final task = ref.putFile(file, SettableMetadata(contentType: 'audio/m4a'));

    _uploadSub?.cancel();
    _uploadSub = task.snapshotEvents.listen((s) {
      final total = s.totalBytes;
      if (total == 0) return;
      final p = s.bytesTransferred / total;
      if (!mounted) return;
      setState(() => _uploadProgress = p);
    });

    await task;
    return await ref.getDownloadURL();
  }

  Future<void> _toggleRecording() async {
    try {
      if (_isRecording) {
        final path = await _recorder.stop();
        _recordTimer?.cancel();

        if (!mounted) return;
        setState(() => _isRecording = false);

        if (path == null || path.isEmpty) {
          SnackHelper.error(context, 'Recording failed. Try again.');
          return;
        }

        // ✅ Show uploading state
        setState(() {
          _isUploadingAnswer = true;
          _uploadProgress = 0.0;
        });

        try {
          final url = await _uploadAudioAndGetUrlWithProgress(File(path));
          _answerUrls[_index] = url;

          await FirebaseFirestore.instance
              .collection('MockInterviews')
              .doc(widget.mockInterviewId)
              .set({'AnswersRecordsURL': _answerUrls}, SetOptions(merge: true));

          if (!mounted) return;
          setState(() => _isUploadingAnswer = false);

          SnackHelper.success(context, 'Your answer has been uploaded.');
        } catch (e) {
          if (!mounted) return;
          setState(() => _isUploadingAnswer = false);
          SnackHelper.error(context, 'Upload failed: $e');
        }

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
      await Permission.microphone.request();

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
      await _tts.stop();

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

  Future<void> _finish() async {
    if (_isFinishing) return;
    _isFinishing = true;

    if (!mounted) return;
    setState(() => _isGeneratingReport = true);

    try {
      await FirebaseFirestore.instance
          .collection('MockInterviews')
          .doc(widget.mockInterviewId)
          .set({
        'Finished': true,
        'FinishedAt': FieldValue.serverTimestamp(),
        'AnsweredCount': _answerUrls.where((e) => e.trim().isNotEmpty).length,
        'TotalQuestions': widget.questions.length,
        'Report': null, // ✅ مهم عشان صفحة التقرير تعتبره "لسه يتولد"
      }, SetOptions(merge: true));

      final functions = FirebaseFunctions.instance;
      await functions.httpsCallable('generateMockInterviewReport').call({
        'mockInterviewID': widget.mockInterviewId,
      });

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MockInterviewReportScreen(
            mockInterviewID: widget.mockInterviewId,
            fromHistory: false,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGeneratingReport = false);
      _isFinishing = false;
      SnackHelper.error(context, 'Failed to generate report: $e');
    }
  }

  Widget _buildGeneratingReportUI(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              color: AppTheme.primaryPurple,
            ),
            const SizedBox(height: 24),
            Text(
              'Generating your report...',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'AI is analyzing your interview answers\nThis may take up to 30 seconds',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        final shouldExit = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const JadeerDialog<bool>(
            title: 'Exit Interview?',
            content: Text(
              'Exiting now will count this attempt, and you won’t be able to continue the interview.\n\n'
              'Are you sure you want to exit?',
            ),
            primaryLabel: 'Exit',
            primaryResult: true,
            secondaryLabel: 'Continue',
            secondaryResult: false,
          ),
        );

        if (shouldExit == true && context.mounted) {
          await _cancelInterviewAndCleanup();

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
                builder: (_) => const MockInterviewSpecialtyScreen()),
          );
        }
      },
      child: ThemedScaffold(
        appBar: CustomHeader(
          title: 'Mock Interview',
          showBack: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFFFFFFFF)),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: Container(
          color: isDark ? scheme.background : const Color(0xFFF5F5F5),
          child: _isGeneratingReport
              ? _buildGeneratingReportUI(context)
              : _initializing
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
                      : SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight:
                                  MediaQuery.of(context).size.height - 100,
                            ),
                            child: IntrinsicHeight(
                              child: Column(
                                children: [
                                  // Camera preview
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(22),
                                      child: SizedBox(
                                        height: 320,
                                        width: double.infinity,
                                        child: CameraPreview(_camera!),
                                      ),
                                    ),
                                  ),

                                  // Question card
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? scheme.surface
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(18),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                                isDark ? 0.6 : 0.08),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Question ${_index + 1}/${widget.questions.length}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: isDark
                                                  ? scheme.onSurface
                                                      .withOpacity(0.7)
                                                  : Colors.black54,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  _currentQuestion,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w800,
                                                    height: 1.3,
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: _toggleSpeak,
                                                icon: Icon(
                                                  size: 30,
                                                  _isSpeaking
                                                      ? Icons.stop_circle
                                                      : Icons.volume_up_rounded,
                                                  color: _isSpeaking
                                                      ? const Color(0xFFFD6C67)
                                                      : const Color(0xFF4A5FBC),
                                                ),
                                                tooltip: _isSpeaking
                                                    ? 'Stop'
                                                    : 'Listen',
                                              ),
                                            ],
                                          ),
                                          Text(
                                            'Answer by voice, then press Next.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? scheme.onSurface
                                                      .withOpacity(0.7)
                                                  : Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  Center(
                                    child: GestureDetector(
                                      onTap: (_isUploadingAnswer)
                                          ? null
                                          : _toggleRecording,
                                      child: Container(
                                        width: 84,
                                        height: 84,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _isRecording
                                              ? const Color(0xFFFD6C67)
                                              : const Color(0xFF4A5FBC),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                  isDark ? 0.6 : 0.12),
                                              blurRadius: 14,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          _isRecording
                                              ? Icons.stop_rounded
                                              : Icons.mic_rounded,
                                          size: 40,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 10),

                                  Text(
                                    _isRecording
                                        ? 'Recording… ${_fmt(_recordDuration)}'
                                        : _isUploadingAnswer
                                            ? 'Uploading… ${(_uploadProgress * 100).toStringAsFixed(0)}%'
                                            : (_answerUrls[_index].isNotEmpty
                                                ? 'Answer uploaded'
                                                : 'Tap the mic to record'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? scheme.onSurface.withOpacity(0.8)
                                          : Colors.black87,
                                    ),
                                  ),

                                  if (!_isRecording &&
                                      !_isUploadingAnswer &&
                                      _answerUrls[_index].isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        FilledButton.tonalIcon(
                                          onPressed: _togglePlayback,
                                          icon: Icon(
                                            _isPlaying
                                                ? Icons.pause
                                                : Icons.play_arrow,
                                            color: Colors.white,
                                          ),
                                          label: Text(
                                            _isPlaying ? 'Pause' : 'Listen',
                                            style: const TextStyle(
                                                color: Colors.white),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(
                                              width: 2,
                                              color: Color(0xFF4A5FBC),
                                            ),
                                          ),
                                          onPressed: () async {
                                            final ok = await showDialog<bool>(
                                              context: context,
                                              barrierDismissible: false,
                                              builder: (_) =>
                                                  const JadeerDialog<bool>(
                                                title: 'Replace recording?',
                                                content: Text(
                                                    'This will overwrite your current answer. Continue?'),
                                                primaryLabel: 'Replace',
                                                primaryResult: true,
                                                secondaryLabel: 'Cancel',
                                                secondaryResult: false,
                                              ),
                                            );

                                            if (ok != true) return;

                                            await _player.stop();
                                            if (!mounted) return;
                                            setState(() {
                                              _isPlaying = false;
                                              _currentPlaybackUrl = null;
                                              _answerUrls[_index] = '';
                                            });

                                            await Future.delayed(const Duration(
                                                milliseconds: 200));
                                            if (!mounted) return;
                                            await _toggleRecording();
                                          },
                                          icon: const Icon(Icons.refresh),
                                          label: const Text('Re-record'),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (_isUploadingAnswer) ...[
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24),
                                      child: LinearProgressIndicator(
                                          value: _uploadProgress),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
        ),

        // Next / Finish
        bottomNavigationBar: _isGeneratingReport
            ? const SizedBox.shrink()
            : SafeArea(
                minimum: const EdgeInsets.symmetric(horizontal: 16)
                    .copyWith(bottom: 16, top: 4),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: _canGoNext ? _next : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFF4A5FBC),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: Text(_isLast ? 'Finish' : 'Next'),
                  ),
                ),
              ),
      ),
    );
  }
}

Future<Map<String, int>> fetchAndResetAiUsageIfNeeded() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return {'CvEnhancement': 0, 'MockInterview': 0};

  final userDocRef =
      FirebaseFirestore.instance.collection('Users').doc(user.uid);

  final snap = await userDocRef.get();
  final data = snap.data() ?? {};
  final aiUsage = (data['AiUsage'] as Map<String, dynamic>?) ?? {};

  int cv = (aiUsage['CvEnhancement'] ?? 2) as int;
  int mock = (aiUsage['MockInterview'] ?? 2) as int;
  final lastReset = aiUsage['LastReset'] as Timestamp?;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  bool shouldReset;
  if (lastReset == null) {
    shouldReset = true;
  } else {
    final last = lastReset.toDate();
    final lastDay = DateTime(last.year, last.month, last.day);
    shouldReset = lastDay.isBefore(today);
  }

  if (shouldReset) {
    cv = 2;
    mock = 2;
    await userDocRef.update({
      'AiUsage.CvEnhancement': 2,
      'AiUsage.MockInterview': 2,
      'AiUsage.LastReset': FieldValue.serverTimestamp(),
    });
  }

  return {'CvEnhancement': cv, 'MockInterview': mock};
}

Future<void> refundMockInterviewCredit() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final userDocRef =
      FirebaseFirestore.instance.collection('Users').doc(user.uid);

  await FirebaseFirestore.instance.runTransaction((tx) async {
    final snap = await tx.get(userDocRef);
    final data = snap.data() ?? {};
    final aiUsage = (data['AiUsage'] as Map<String, dynamic>?) ?? {};
    final credits = (aiUsage['MockInterview'] ?? 0) as int;

    tx.update(userDocRef, {'AiUsage.MockInterview': credits + 1});
  });
}
