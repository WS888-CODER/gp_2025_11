import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/screens/jobseeker_home.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class JobInterviewService {
  static Future<bool> _requestCamMicPermissions(BuildContext context) async {
    try {
      // 1) check current
      final camStatus = await Permission.camera.status;
      final micStatus = await Permission.microphone.status;

      // If permanently denied/restricted -> open settings
      final blocked = camStatus.isPermanentlyDenied ||
          camStatus.isRestricted ||
          micStatus.isPermanentlyDenied ||
          micStatus.isRestricted;

      if (blocked) {
        if (!context.mounted) return false;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dCtx) => AlertDialog(
            title: const Text('Permissions needed'),
            content: const Text(
              'Camera/Microphone permissions are blocked.\n\n'
              'Please enable them from Settings to continue.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dCtx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.of(dCtx).pop();
                  await openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
        return false;
      }

      // 2) request
      final cam = await Permission.camera.request();
      final mic = await Permission.microphone.request();

      if (!context.mounted) return false;

      if (!cam.isGranted || !mic.isGranted) {
        SnackHelper.error(
          context,
          'Camera/Microphone permission is required to continue.',
        );
        return false;
      }

      return true;
    } catch (e) {
      if (context.mounted) {
        SnackHelper.error(context, 'Permission error: $e');
      }
      return false;
    }
  }

  static Future<bool> _confirmPermissionsDialog(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const JadeerDialog<bool>(
        title: 'Camera & Microphone Access',
        content: Text(
            'Jadeer needs access to your camera and microphone to record your interview answers.\n\n'
            'Your recordings are used only to generate your interview report.'),
        primaryLabel: 'Continue',
        primaryResult: true,
        secondaryLabel: 'Cancel',
        secondaryResult: false,
      ),
    );

    return ok == true;
  }

  static Future<void> start(
    BuildContext context, {
    required String jobDocId,
    required String jobId,
    required String specialty,
    String jobTitle = '',
    String companyName = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      SnackHelper.error(context, 'Please login again.');
      return;
    }

    // 1) Load questions
    final questions = await _loadJobQuestions(jobDocId);
    if (!context.mounted) return;

    if (questions.isEmpty) {
      SnackHelper.error(context, 'This job has no interview questions.');
      return;
    }

    // 2) Check profile completion + get CV
    final cvUrl = await _ensureProfileCompleteAndGetCvUrl(
      context,
      uid: user.uid,
    );
    if (!context.mounted) return;
    if (cvUrl == null) return;

    // ✅ 3) Show permissions dialog (like Mock Interview)
    final permOk = await _confirmPermissionsDialog(context);

    if (!context.mounted) return;
    if (!permOk) return;

    final granted = await _requestCamMicPermissions(context);
    if (!context.mounted) return;
    if (!granted) return;

    // 5) Create Applications doc then navigate
    await _createAndStart(
      context: context,
      uid: user.uid,
      jobDocId: jobDocId,
      jobId: jobId,
      specialty: specialty,
      cvUrl: cvUrl,
      questionsCount: questions.length,
      questions: questions,
      jobTitle: jobTitle,
      companyName: companyName,
    );
  }

  static Future<String?> _ensureProfileCompleteAndGetCvUrl(
    BuildContext context, {
    required String uid,
  }) async {
    final doc =
        await FirebaseFirestore.instance.collection('Users').doc(uid).get();
    final data = doc.data() ?? {};

    final photoUrl = (data['PhotoURL'] ?? '').toString().trim();
    final cvUrl = (data['CVURL'] ?? '').toString().trim();
    final nationality = (data['Nationality'] ?? '').toString().trim();
    final phone = (data['Phone'] ?? '').toString().trim();
    final contactEmail = (data['ContactEmail'] ?? '').toString().trim();

    DateTime? dob;
    final dobRaw = data['DoB'];
    if (dobRaw is Timestamp) dob = dobRaw.toDate();

    final emailValid = contactEmail.isNotEmpty &&
        RegExp(
          r"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$",
          caseSensitive: false,
        ).hasMatch(contactEmail);

    final hasAnyContact = emailValid || phone.isNotEmpty;

    final missing = <String>[];
    if (photoUrl.isEmpty) missing.add('Profile photo');
    if (dob == null) missing.add('Date of birth');
    if (nationality.isEmpty) missing.add('Nationality');
    if (cvUrl.isEmpty) missing.add('CV file');
    if (!hasAnyContact) missing.add('Contact (email or phone)');

    final flagComplete = data['IsProfileComplete'] == true;
    final computedComplete = missing.isEmpty;

    if (!(flagComplete || computedComplete)) {
      await showDialog<void>(
        context: context,
        builder: (_) => JadeerDialog<void>(
          title: 'Complete your profile',
          primaryLabel: 'Ok',
          primaryResult: null,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your profile is incomplete. Please complete the missing information before applying.',
                style: TextStyle(color: Colors.white, height: 1.35),
              ),
              const SizedBox(height: 12),
              Text(
                missing.map((m) => '• $m').join('\n'),
                style: const TextStyle(color: Colors.white, height: 1.4),
              ),
            ],
          ),
        ),
      );
      return null;
    }

    final lower = cvUrl.toLowerCase();
    final looksOk = lower.contains('.pdf') ||
        lower.contains('.doc') ||
        lower.contains('.docx') ||
        lower.contains('firebase');
    if (!looksOk) {
      SnackHelper.error(
        context,
        'Please upload a valid CV (PDF/DOCX) in your profile before applying.',
      );
      return null;
    }

    return cvUrl;
  }

  // ✅ Supports: Questions = ["..."] OR Questions = [{Text: "..."}]
  static Future<List<String>> _loadJobQuestions(String jobDocId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Jobs')
          .doc(jobDocId)
          .get();

      final data = doc.data() ?? {};
      final raw = data['Questions'];

      if (raw is List) {
        return raw
            .map((e) {
              if (e is Map) {
                final v = e['Text'] ?? e['text'] ?? '';
                return v.toString().trim();
              }
              return e.toString().trim();
            })
            .where((s) => s.isNotEmpty)
            .toList();
      }
      return <String>[];
    } catch (_) {
      return <String>[];
    }
  }

  static Future<void> _createAndStart({
    required BuildContext context,
    required String uid,
    required String jobDocId,
    required String jobId,
    required String specialty,
    required String cvUrl,
    required int questionsCount,
    required List<String> questions,
    String jobTitle = '',
    String companyName = '',
  }) async {
    try {
      // ✅ IMPORTANT: Collection name is Applications (like your DB)
      final appRef =
          FirebaseFirestore.instance.collection('Applications').doc();

      await appRef.set({
        // ✅ same field names as your screenshot
        'ApplicationsID': appRef.id,
        'UserID': uid,
        'JobID': jobId,
        'ApplicationCVURL': cvUrl,
        'ApplicationStatus': 'InInterview',

        // ✅ arrays like screenshot (and same length as questions)
        'Answers': List<String>.filled(questionsCount, ''),
        'AnswersRecordsURL': List<String>.filled(questionsCount, ''),

        'ReportURL': '',
        'Score': 0,
        'Date': FieldValue.serverTimestamp(),
        'RecordExpiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 120)),
        ),

        // ✅ NEW: Save job info so history can display it (per story #38)
        'JobTitle': jobTitle,
        'CompanyName': companyName,
      }, SetOptions(merge: true));

      if (!context.mounted) return;

      Navigator.of(context, rootNavigator: true).pushReplacement(
        MaterialPageRoute(
          builder: (_) => JobInterviewSessionScreen(
            applicationId: appRef.id,
            jobDocId: jobDocId,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      SnackHelper.error(context, 'Failed to start interview: $e');
    }
  }
}

class JobInterviewSessionScreen extends StatefulWidget {
  const JobInterviewSessionScreen({
    super.key,
    required this.applicationId, // Applications doc id
    required this.jobDocId, // Jobs doc id
  });

  final String applicationId;
  final String jobDocId;

  @override
  State<JobInterviewSessionScreen> createState() =>
      _JobInterviewSessionScreenState();
}

class _JobInterviewSessionScreenState extends State<JobInterviewSessionScreen> {
  // ====== Audio playback ======
  final AudioPlayer _player = AudioPlayer();
  String? _currentPlaybackUrl;
  bool _isPlaying = false;

  // ====== Upload ======
  bool _isUploadingAnswer = false;
  double _uploadProgress = 0.0;
  StreamSubscription<TaskSnapshot>? _uploadSub;

  // ====== Finish ======
  bool _isGeneratingReport = false;
  bool _isFinishing = false;

  // ====== Camera ======
  CameraController? _camera;
  bool _initializing = true;
  String? _error;

  // ====== Questions (loaded from Jobs) ======
  bool _loadingQuestions = true;
  List<String> _questions = [];
  int _index = 0;

  String get _currentQuestion =>
      (_questions.isEmpty) ? '—' : _questions[_index];
  bool get _isLast => _questions.isNotEmpty && _index >= _questions.length - 1;

  // ====== Recording ======
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;

  // Stored in Applications
  late List<String> _answerUrls; // AnswersRecordsURL
  late List<String> _answers; // Answers (optional)

  bool get _canGoNext =>
      !_loadingQuestions &&
      _questions.isNotEmpty &&
      !_isRecording &&
      !_isUploadingAnswer &&
      _answerUrls[_index].trim().isNotEmpty;

  // ====== TTS ======
  late final FlutterTts _tts;
  bool _ttsReady = false;
  bool _isSpeaking = false;

  // ====== Face detection ======
  late final FaceDetector _faceDetector;
  bool _faceDetected = false;
  bool _processingFrame = false;

  @override
  void initState() {
    super.initState();

    _tts = FlutterTts();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableClassification: true,
        enableTracking: false,
        minFaceSize: 0.05,
        performanceMode: FaceDetectorMode.fast,
      ),
    );

    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        setState(() => _isPlaying = false);
      }
    });

    _boot();
  }

  Future<void> _boot() async {
    // 1) Load questions first (Jobs -> Questions)
    await _loadQuestionsFromJobs();
    if (!mounted) return;

    if (_questions.isEmpty) {
      setState(() {
        _loadingQuestions = false;
        _initializing = false;
        _error = 'This job has no interview questions.';
      });
      return;
    }

    // 2) init arrays that depend on questions length
    _answerUrls = List<String>.filled(_questions.length, '');
    _answers = List<String>.filled(_questions.length, '');

    // 3) init TTS
    await _initTts();
    if (!mounted) return;

    // 4) init camera & face detection
    await _initPermissionsAndCamera();
  }

  Future<void> _loadQuestionsFromJobs() async {
    try {
      setState(() => _loadingQuestions = true);

      final doc = await FirebaseFirestore.instance
          .collection('Jobs')
          .doc(widget.jobDocId)
          .get();

      final data = doc.data() ?? {};
      final raw = data['Questions'];

      List<String> q = [];
      if (raw is List) {
        q = raw
            .map((e) {
              if (e is Map) {
                final v = e['Text'] ?? e['text'] ?? e['question'] ?? '';
                return v.toString().trim();
              }
              return e.toString().trim();
            })
            .where((s) => s.isNotEmpty)
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _questions = q;
        _index = 0;
        _loadingQuestions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _questions = [];
        _loadingQuestions = false;
        _error = 'Failed to load questions: $e';
      });
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

      final cam = await Permission.camera.status;
      final mic = await Permission.microphone.status;

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

      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      _processCameraImage();
      await _speakCurrentQuestion();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to initialize camera: $e';
        _initializing = false;
      });
    }
  }

  Future<void> _processCameraImage() async {
    if (_processingFrame || _camera == null || !_camera!.value.isInitialized) {
      return;
    }

    _processingFrame = true;

    try {
      final image = await _camera!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted) return;

      bool hasValidFace = false;

      if (faces.isNotEmpty) {
        final face = faces.first;
        final box = face.boundingBox;

        final faceWidth = box.width;
        final faceHeight = box.height;
        final isLargeEnough = faceWidth > 50 && faceHeight > 60;

        if (isLargeEnough) {
          final headAngleY = face.headEulerAngleY ?? 0;
          final headAngleZ = face.headEulerAngleZ ?? 0;
          final isFacingForward =
              headAngleY.abs() < 30 && headAngleZ.abs() < 30;

          if (isFacingForward) {
            final leftEye = face.leftEyeOpenProbability ?? -1;
            final rightEye = face.rightEyeOpenProbability ?? -1;
            final bothEyesVisible = leftEye > 0.15 && rightEye > 0.15;

            final aspectRatio = faceHeight / faceWidth;
            final hasNormalProportions = aspectRatio >= 1.0;

            if (bothEyesVisible && hasNormalProportions) {
              hasValidFace = true;
            }
          }
        }
      }

      setState(() => _faceDetected = hasValidFace);
    } catch (_) {
      if (mounted) setState(() => _faceDetected = false);
    } finally {
      _processingFrame = false;
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _processCameraImage();
        });
      }
    }
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
        'applications/$uid/${widget.applicationId}/q${_index + 1}.m4a';

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

  Future<void> _toggleRecording() async {
    if (!_faceDetected && !_isRecording) {
      SnackHelper.error(
          context, 'Please position your face in front of the camera.');
      return;
    }

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

        setState(() {
          _isUploadingAnswer = true;
          _uploadProgress = 0.0;
        });

        try {
          final url = await _uploadAudioAndGetUrlWithProgress(File(path));

          if (!mounted) return;
          setState(() {
            _answerUrls[_index] = url;
            _answers[_index] = ''; // optional
          });

          await FirebaseFirestore.instance
              .collection('Applications')
              .doc(widget.applicationId)
              .set({
            'AnswersRecordsURL': _answerUrls,
            'Answers': _answers,
          }, SetOptions(merge: true));

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

      // replace existing answer
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

        if (!mounted) return;
        setState(() {
          _answerUrls[_index] = '';
          _answers[_index] = '';
          _isPlaying = false;
          _currentPlaybackUrl = null;
        });

        await FirebaseFirestore.instance
            .collection('Applications')
            .doc(widget.applicationId)
            .set({
          'AnswersRecordsURL': _answerUrls,
          'Answers': _answers,
        }, SetOptions(merge: true));
      }

      final mic = await Permission.microphone.status;
      final hasMic = mic.isGranted && await _recorder.hasPermission();
      if (!hasMic) {
        if (!mounted) return;
        SnackHelper.error(context, 'Microphone permission is required.');
        return;
      }

      final dir = await getTemporaryDirectory();
      final fileName =
          'app_${widget.applicationId}_q${_index + 1}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final path = '${dir.path}/$fileName';

      await _tts.stop();

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );

      _startTimer();

      if (!mounted) return;
      setState(() => _isRecording = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRecording = false);
      SnackHelper.error(context, 'Recording error: $e');
    }
  }

  Future<void> _next() async {
    if (_isRecording) {
      SnackHelper.error(context, 'Stop recording first.');
      return;
    }

    if (!_faceDetected) {
      SnackHelper.error(context, 'Please show your face to continue.');
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
      _currentPlaybackUrl = null;
      _isPlaying = false;
    });

    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await _speakCurrentQuestion();
  }

  Future<void> _finish() async {
    if (_isFinishing) return;
    _isFinishing = true;

    if (!mounted) return;
    setState(() => _isGeneratingReport = true);

    try {
      await FirebaseFirestore.instance
          .collection('Applications')
          .doc(widget.applicationId)
          .set({
        'ApplicationStatus': 'Pending',
        'SubmittedAt': FieldValue.serverTimestamp(),
        'ReportURL': '',
      }, SetOptions(merge: true));

      // optional cloud function
      try {
        await FirebaseFunctions.instance
            .httpsCallable(
          'generateJobInterviewReport',
          options: HttpsCallableOptions(
            timeout: const Duration(minutes: 30),
          ),
        )
            .call({'applicationsID': widget.applicationId});
      } catch (_) {}

      if (!mounted) return;

      SnackHelper.success(context, 'Interview submitted successfully.');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const JobSeekerHome()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGeneratingReport = false);
      _isFinishing = false;
      SnackHelper.error(context, 'Failed to submit interview: $e');
    }
  }

  Future<void> _cancelInterviewAndCleanup() async {
    try {
      _recordTimer?.cancel();
      if (_isRecording) {
        await _recorder.stop();
        _isRecording = false;
      }
      await _player.stop();
      await _tts.stop();

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        final folderRef = FirebaseStorage.instance
            .ref()
            .child('applications/$uid/${widget.applicationId}');

        final list = await folderRef.listAll();
        for (final item in list.items) {
          try {
            await item.delete();
          } catch (_) {}
        }
      }

      await FirebaseFirestore.instance
          .collection('Applications')
          .doc(widget.applicationId)
          .set({
        'ApplicationStatus': 'InterviewCancelled',
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) SnackHelper.error(context, 'Cleanup failed: $e');
    }
  }

  Widget _buildGeneratingReportUI(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppTheme.primaryPurple),
            const SizedBox(height: 24),
            Text(
              'Submitting your interview...',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Please wait a moment…',
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
  void dispose() {
    _tts.stop();
    _recordTimer?.cancel();
    _recorder.dispose();
    _camera?.dispose();
    _uploadSub?.cancel();
    _player.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Loading questions screen
    if (_loadingQuestions) {
      return ThemedScaffold(
        appBar: const CustomHeader(title: 'Job Interview', showBack: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

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
              'Exiting now will cancel this interview attempt.\n\n'
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
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const JobSeekerHome()),
            (route) => false,
          );
        }
      },
      child: ThemedScaffold(
        appBar: CustomHeader(
          title: 'Job Interview',
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
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(22),
                                          child: SizedBox(
                                            height: 320,
                                            width: double.infinity,
                                            child: CameraPreview(_camera!),
                                          ),
                                        ),
                                        Positioned(
                                          top: 16,
                                          right: 16,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _faceDetected
                                                  ? Colors.green
                                                      .withOpacity(0.9)
                                                  : Colors.red.withOpacity(0.9),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  _faceDetected
                                                      ? Icons.check_circle
                                                      : Icons.warning,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  _faceDetected
                                                      ? 'Face detected'
                                                      : 'No face detected',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
                                              isDark ? 0.6 : 0.08,
                                            ),
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
                                            'Question ${_index + 1}/${_questions.length}',
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
                                              color: Colors.white,
                                            ),
                                          ),
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
                                        value: _uploadProgress,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                ],
                              ),
                            ),
                          ),
                        ),
        ),
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
