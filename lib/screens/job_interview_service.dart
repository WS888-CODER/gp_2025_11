import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/screens/jobseeker_home.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class JobInterviewService {
  static Future<bool> _requestCamMicPermissions(BuildContext context) async {
    try {
      final camStatus = await Permission.camera.status;
      final micStatus = await Permission.microphone.status;

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

    final existing = await FirebaseFirestore.instance
        .collection('Applications')
        .where('UserID', isEqualTo: user.uid)
        .where('JobID', isEqualTo: jobId)
        .limit(1)
        .get();
    if (!context.mounted) return;
    if (existing.docs.isNotEmpty) {
      SnackHelper.error(context, 'You have already applied for this job.');
      return;
    }

    final questions = await _loadJobQuestions(jobDocId);
    if (!context.mounted) return;

    if (questions.isEmpty) {
      SnackHelper.error(context, 'This job has no interview questions.');
      return;
    }

    final profileOk = await _ensureProfileComplete(context, uid: user.uid);
    if (!context.mounted) return;
    if (!profileOk) return;

    final cvFile = await _pickApplicationCv(context);
    if (!context.mounted) return;
    if (cvFile == null) return;

    final permOk = await _confirmPermissionsDialog(context);
    if (!context.mounted) return;
    if (!permOk) return;

    final granted = await _requestCamMicPermissions(context);
    if (!context.mounted) return;
    if (!granted) return;

    await _createAndStart(
      context: context,
      uid: user.uid,
      cvFile: cvFile,
      jobDocId: jobDocId,
      jobId: jobId,
      specialty: specialty,
      questionsCount: questions.length,
      questions: questions,
      jobTitle: jobTitle,
      companyName: companyName,
    );
  }

  static Future<bool> _ensureProfileComplete(
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
    if (cvUrl.isEmpty) missing.add('CV file');
    if (dob == null) missing.add('Date of birth');
    if (nationality.isEmpty) missing.add('Nationality');
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
      return false;
    }

    return true;
  }

  static Future<File?> _pickApplicationCv(BuildContext context) {
    return showDialog<File?>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => _ApplicationCvPicker(parentContext: context),
    );
  }

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
    required File cvFile,
    required String jobDocId,
    required String jobId,
    required String specialty,
    required int questionsCount,
    required List<String> questions,
    String jobTitle = '',
    String companyName = '',
  }) async {
    try {
      // Generate application ID here (after all confirmations passed)
      final appRef =
          FirebaseFirestore.instance.collection('Applications').doc();

      // Upload CV now — only after user confirmed and permissions granted
      final ext = cvFile.path.split('.').last.toLowerCase();
      final cvStoragePath =
          'applications/$uid/${appRef.id}/${DateTime.now().millisecondsSinceEpoch}_cv.$ext';
      final cvRef = FirebaseStorage.instance.ref(cvStoragePath);
      await cvRef.putFile(cvFile);
      final cvUrl = await cvRef.getDownloadURL();

      await appRef.set({
        'ApplicationsID': appRef.id,
        'UserID': uid,
        'JobID': jobId,
        'ApplicationCVURL': cvUrl,
        'ApplicationCVPath': cvStoragePath,
        'ApplicationStatus': 'InInterview',
        'Answers': List<String>.filled(questionsCount, ''),
        'AnswersRecordsURL': List<String>.filled(questionsCount, ''),
        'ReportURL': '',
        'Score': 0,
        'Date': FieldValue.serverTimestamp(),
        'RecordExpiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 120)),
        ),
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
    required this.applicationId,
    required this.jobDocId,
  });

  final String applicationId;
  final String jobDocId;

  @override
  State<JobInterviewSessionScreen> createState() =>
      _JobInterviewSessionScreenState();
}

class _JobInterviewSessionScreenState extends State<JobInterviewSessionScreen> {
  bool _isUploadingAnswer = false;
  double _uploadProgress = 0.0;
  StreamSubscription<TaskSnapshot>? _uploadSub;

  bool _isGeneratingReport = false;
  bool _isFinishing = false;

  CameraController? _camera;
  bool _initializing = true;
  String? _error;

  List<String> _questions = [];
  int _index = 0;

  String get _currentQuestion =>
      (_questions.isEmpty) ? '—' : _questions[_index];
  bool get _isLast => _questions.isNotEmpty && _index >= _questions.length - 1;

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;

  late List<String> _answerUrls;
  late List<String> _answers;

  bool get _canGoNext =>
      !_loadingQuestions &&
      _questions.isNotEmpty &&
      !_isRecording &&
      !_isUploadingAnswer &&
      _answerUrls[_index].trim().isNotEmpty;

  bool _loadingQuestions = true;

  final AudioPlayer _ttsPlayer = AudioPlayer();
  bool _isSpeaking = false;
  bool _ttsLoading = false;

  late final FaceDetector _faceDetector;
  bool _faceDetected = false;
  bool _processingFrame = false;

  @override
  void initState() {
    super.initState();

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableClassification: true,
        enableTracking: false,
        minFaceSize: 0.05,
        performanceMode: FaceDetectorMode.fast,
      ),
    );

    _ttsPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        setState(() => _isSpeaking = false);
      }
    });

    _boot();
  }

  Future<void> _boot() async {
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

    _answerUrls = List<String>.filled(_questions.length, '');
    _answers = List<String>.filled(_questions.length, '');

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

  Future<void> _speakCurrentQuestion() async {
    if (_isRecording) return;
    await _googleSpeak(_currentQuestion);
  }

  Future<void> _stopTts() async {
    await _ttsPlayer.stop();
    if (!mounted) return;
    setState(() => _isSpeaking = false);
  }

  Future<void> _googleSpeak(String text) async {
    try {
      if (!mounted) return;
      setState(() {
        _isSpeaking = true;
        _ttsLoading = true;
      });

      final response = await http.post(
        Uri.parse(
            'https://us-central1-jadeer-b4953.cloudfunctions.net/synthesizeSpeech'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );

      if (!mounted) return;
      setState(() => _ttsLoading = false);

      final data = jsonDecode(response.body);
      final audioContent = data['audioContent'] as String?;

      if (audioContent == null || audioContent.isEmpty) {
        setState(() => _isSpeaking = false);
        return;
      }

      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
      await file.writeAsBytes(base64Decode(audioContent));

      await _ttsPlayer.setFilePath(file.path);
      await _ttsPlayer.play();

      if (!mounted) return;
      setState(() => _isSpeaking = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSpeaking = false;
        _ttsLoading = false;
      });
    }
  }

  Future<void> _toggleSpeak() async {
    if (_isSpeaking) {
      await _stopTts();
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

      bool hasValidFace = true;

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
            _answers[_index] = '';
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

      if (_answerUrls[_index].trim().isNotEmpty) {
        SnackHelper.error(context, 'You have already recorded your answer.');
        return;
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

      await _stopTts();

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
        'ReportURL': '',
      }, SetOptions(merge: true));

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
      await _ttsPlayer.stop();

      final uid = FirebaseAuth.instance.currentUser?.uid;

      String? cvPath;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('Applications')
            .doc(widget.applicationId)
            .get();
        cvPath = doc.data()?['ApplicationCVPath']?.toString();
      } catch (_) {}

      if (uid != null && uid.isNotEmpty) {
        try {
          final folderRef = FirebaseStorage.instance
              .ref()
              .child('applications/$uid/${widget.applicationId}');
          final list = await folderRef.listAll();
          for (final item in list.items) {
            try {
              await item.delete();
            } catch (_) {}
          }
        } catch (_) {}

        if (cvPath != null && cvPath.isNotEmpty) {
          try {
            await FirebaseStorage.instance.ref(cvPath).delete();
          } catch (_) {}
        }
      }

      await FirebaseFirestore.instance
          .collection('Applications')
          .doc(widget.applicationId)
          .set({
        'ApplicationStatus': 'InterviewCancelled',
        'Answers': FieldValue.delete(),
        'AnswersRecordsURL': FieldValue.delete(),
        'ApplicationCVURL': FieldValue.delete(),
        'ApplicationCVPath': FieldValue.delete(),
        'ReportURL': FieldValue.delete(),
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
    _recordTimer?.cancel();
    _recorder.dispose();
    _camera?.dispose();
    _uploadSub?.cancel();
    _ttsPlayer.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loadingQuestions) {
      return ThemedScaffold(
        appBar: CustomHeader(
          title: 'Job Interview',
          showBack: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFFFFFFFF)),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          transparent: false,
          rounded: true,
        ),
        extendBodyBehindAppBar: true,
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
              'If you leave now, your application will be marked as cancelled and your recorded answers will be deleted.\n\n'
              'You will NOT be able to reapply for this job.',
              style: TextStyle(color: Colors.white, height: 1.4),
            ),
            primaryLabel: 'Exit',
            primaryResult: true,
            secondaryLabel: 'Stay',
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
          transparent: false,
          rounded: true,
        ),
        extendBodyBehindAppBar: true,
        body: _isGeneratingReport
            ? _buildGeneratingReportUI(context)
            : _initializing
                ? const Center(child: CircularProgressIndicator())
                : (_error != null)
                    ? Center(
                        child: Padding(
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
                        ),
                      )
                    : Stack(
                        children: [
                          Positioned.fill(
                            child: CameraPreview(_camera!),
                          ),
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.25),
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.75),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // ── FIXED: Moved the badge layout stack index below the top padding buffer boundary ──
                          Positioned(
                            top: 128,
                            left: 16,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _faceDetected
                                    ? Colors.green.withOpacity(0.85)
                                    : Colors.red.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _faceDetected
                                        ? Icons.check_circle
                                        : Icons.warning_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _faceDetected
                                        ? 'Face detected'
                                        : 'No face detected',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 60,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isRecording ||
                                    _isUploadingAnswer ||
                                    _answerUrls[_index].isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      _isRecording
                                          ? 'Recording… ${_fmt(_recordDuration)}'
                                          : _isUploadingAnswer
                                              ? 'Uploading… ${(_uploadProgress * 100).toStringAsFixed(0)}%'
                                              : '✓ Answer recorded',
                                      style: TextStyle(
                                        color: _answerUrls[_index].isNotEmpty &&
                                                !_isRecording &&
                                                !_isUploadingAnswer
                                            ? Colors.green.shade300
                                            : Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                if (_isUploadingAnswer)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        bottom: 10, left: 32, right: 32),
                                    child: LinearProgressIndicator(
                                      value: _uploadProgress,
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.15),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      GestureDetector(
                                        onTap: _isUploadingAnswer
                                            ? null
                                            : _toggleRecording,
                                        child: Container(
                                          width: 56,
                                          height: 56,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _isRecording
                                                ? const Color(0xFFFD6C67)
                                                : const Color(0xFF4A5FBC),
                                            boxShadow: [
                                              BoxShadow(
                                                color: (_isRecording
                                                        ? const Color(
                                                            0xFFFD6C67)
                                                        : const Color(
                                                            0xFF4A5FBC))
                                                    .withOpacity(0.4),
                                                blurRadius: 12,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Icon(
                                            _isRecording
                                                ? Icons.stop_rounded
                                                : Icons.mic_rounded,
                                            size: 28,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Question ${_index + 1}/${_questions.length}',
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withOpacity(0.5),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                  maxHeight: 110),
                                              child: SingleChildScrollView(
                                                child: Text(
                                                  _currentQuestion,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                    height: 1.3,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: _toggleSpeak,
                                        child: Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: _isSpeaking
                                                ? const Color(0xFFFD6C67)
                                                    .withOpacity(0.3)
                                                : Colors.white.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                          child: Icon(
                                            _isSpeaking
                                                ? Icons.stop_circle
                                                : Icons.volume_up_rounded,
                                            color: _isSpeaking
                                                ? const Color(0xFFFD6C67)
                                                : Colors.white,
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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

class _ApplicationCvPicker extends StatefulWidget {
  final BuildContext parentContext;
  const _ApplicationCvPicker({required this.parentContext});

  @override
  State<_ApplicationCvPicker> createState() => _ApplicationCvPickerState();
}

class _ApplicationCvPickerState extends State<_ApplicationCvPicker> {
  static const _brandColor = Color(0xFF4A5FBC);
  static const _dangerColor = Color(0xFFFC686A);

  File? _file;
  String _fileName = '';

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx'],
    );
    if (res == null || res.files.single.path == null) return;
    final path = res.files.single.path!;
    final name = res.files.single.name;
    final file = File(path);
    if (file.lengthSync() > 10 * 1024 * 1024) {
      if (mounted) {
        SnackHelper.error(widget.parentContext, 'File too large (max 10 MB)');
      }
      return;
    }
    setState(() {
      _file = file;
      _fileName = name;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = _file != null;

    return AlertDialog(
      backgroundColor: _brandColor.withOpacity(0.92),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30),
      ),
      title: const Text(
        'Upload Your CV',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      actionsAlignment: MainAxisAlignment.center,
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Upload the CV you want to submit with this application (PDF or DOCX, max 10 MB).',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              InkWell(
                onTap: _pick,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: hasFile
                          ? Colors.white
                          : Colors.white.withOpacity(0.3),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withOpacity(hasFile ? 0.12 : 0.06),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        hasFile
                            ? Icons.description_rounded
                            : Icons.upload_file_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          hasFile ? _fileName : 'Tap to select a CV file',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                hasFile ? FontWeight.w600 : FontWeight.normal,
                            color: hasFile
                                ? Colors.white
                                : Colors.white.withOpacity(0.6),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasFile)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          style: TextButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.9),
            foregroundColor: _brandColor,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: hasFile ? () => Navigator.of(context).pop(_file) : null,
          style: TextButton.styleFrom(
            backgroundColor: hasFile ? _dangerColor : Colors.white24,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: const Text(
            'Continue',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
