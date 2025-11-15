import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class QuestionsPage extends StatefulWidget {
  const QuestionsPage({super.key});

  @override
  State<QuestionsPage> createState() => _QuestionsPageState();
}

class _QuestionsPageState extends State<QuestionsPage> {
  Map<String, dynamic>? _jobData;
  String? _jobId;
  static const int kMaxQuestionLength = 180;
  static const int kMinQuestions = 10;
  static const int kMaxUserAdds = 3;

  bool _busy = false;
  bool _locked = false;
  bool _autoTriggered = false;

  int _userAddedCount = 0;
  final List<Map<String, dynamic>> _questions = [];

  Uri _fnUrl() => Uri.parse(
        'https://us-central1-jadeer-b4953.cloudfunctions.net/generateInterviewQuestions',
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

      final jobIdArg = args?['jobId'] as String?;
      if (jobIdArg != null && jobIdArg.isNotEmpty) {
        _jobId = jobIdArg;
        _loadExistingJob(jobIdArg);
        return;
      }

      _jobData = args?['jobData'] as Map<String, dynamic>?;

      if (_jobData == null) {
        _snack('Missing job data.', error: true);
      } else {
        _autoGenerateIfEmpty();
      }
      setState(() {});
    });
  }

  // ===== UX helpers =====
  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        backgroundColor: error
            ? const Color(0xFFFF7B7B).withOpacity(0.8)
            : const Color(0xFF4CAF50).withOpacity(0.8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _loadExistingJob(String jobId) async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection('Jobs').doc(jobId).get();

      if (!doc.exists) {
        _snack('Job not found.', error: true);
        return;
      }
      final data = doc.data() as Map<String, dynamic>;
      _jobData = Map<String, dynamic>.from(data);
      final List qsRaw = (data['Questions'] as List?) ?? const [];
      _questions
        ..clear()
        ..addAll(qsRaw.map((q) {
          final m = q as Map<String, dynamic>;
          return {
            'Text': (m['Text'] ?? '').toString(),
            'Type': (m['Type'] ?? 'technical').toString(),
          };
        }));

      _userAddedCount = (data['QuestionsUserAddedCount'] ?? 0) as int;

      // لو كانت مقفلة في الداتابيس نقفلها في الـ UI
      _locked = data['QuestionsLocked'] == true;

      setState(() {});
    } catch (e) {
      _snack('Failed to load questions: $e', error: true);
    }
  }

  // ===== Validation helpers (local only) =====
  bool _isDuplicateQuestionLocal(String text) {
    final t = text.trim();
    return _questions.any((q) => (q['Text'] ?? '').toString().trim() == t);
  }

  // ===== Add Question (3 max) =====
  Future<void> _addQuestionDialog() async {
    if (_locked) {
      _snack('Questions are locked.', error: true);
      return;
    }

    if (_userAddedCount >= kMaxUserAdds) {
      _snack(
        'You can only add up to $kMaxUserAdds custom questions for this job.',
        error: true,
      );
      return;
    }

    final controller = TextEditingController();
    String type = 'technical';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        title: const Text(
          'Add Question',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLength: kMaxQuestionLength,
                decoration: const InputDecoration(
                  labelText: 'Question text',
                  labelStyle: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white, width: 2),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  labelStyle: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white, width: 2),
                  ),
                ),
                dropdownColor: Colors.black,
                items: const [
                  DropdownMenuItem(
                      value: 'technical',
                      child: Text('Technical',
                          style: TextStyle(color: Colors.white))),
                  DropdownMenuItem(
                      value: 'psychometric',
                      child: Text('Psychometric',
                          style: TextStyle(color: Colors.white))),
                ],
                onChanged: (v) => type = v ?? 'technical',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.9),
                foregroundColor: const Color(0xFF4A5FBC),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFFC686A),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('Add')),
        ],
      ),
    );

    if (ok != true) return;

    final text = controller.text.trim();
    if (text.isEmpty) return _snack('Question cannot be empty.', error: true);
    if (text.length > kMaxQuestionLength) {
      return _snack('Character limit reached.', error: true);
    }
    if (_isDuplicateQuestionLocal(text)) {
      return _snack('Duplicate question.', error: true);
    }

    setState(() {
      _questions.add({
        'Text': text,
        'Type': type,
      });
      _userAddedCount += 1;
    });

    _snack('Added.');
  }

  // ===== Edit Question (no limit) =====
  Future<void> _editQuestionAt(int index, Map<String, dynamic> q) async {
    if (_locked) {
      _snack('Questions are locked.', error: true);
      return;
    }

    final controller =
        TextEditingController(text: (q['Text'] ?? '').toString());
    String type = (q['Type'] ?? 'technical').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        title: const Text(
          'Edit Question',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLength: kMaxQuestionLength,
                decoration: const InputDecoration(
                  labelText: 'Question text',
                  labelStyle: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white, width: 2),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  labelStyle: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white, width: 2),
                  ),
                ),
                dropdownColor: Colors.black,
                items: const [
                  DropdownMenuItem(
                      value: 'technical',
                      child: Text('Technical',
                          style: TextStyle(color: Colors.white))),
                  DropdownMenuItem(
                      value: 'psychometric',
                      child: Text('Psychometric',
                          style: TextStyle(color: Colors.white))),
                ],
                onChanged: (v) => type = v ?? 'technical',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFFC686A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Save',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final newText = controller.text.trim();
    if (newText.isEmpty) {
      return _snack('Question cannot be empty.', error: true);
    }
    if (newText.length > kMaxQuestionLength) {
      return _snack('Character limit reached.', error: true);
    }

    if (newText != (q['Text'] ?? '').toString() &&
        _isDuplicateQuestionLocal(newText)) {
      return _snack('Duplicate question.', error: true);
    }

    if (index < 0 || index >= _questions.length) {
      return _snack('Invalid question.', error: true);
    }

    setState(() {
      _questions[index] = {
        'Text': newText,
        'Type': type,
      };
    });

    _snack('Saved.');
  }

  // ===== Generate via Cloud Function =====
  Future<void> _generate() async {
    if (_jobData == null) return;

    if (_locked) {
      _snack('Questions are locked. You can no longer generate or modify.',
          error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final title = (_jobData?['JobTitle'] ?? '').toString();
      final position = (_jobData?['Position'] ?? '').toString();
      final specialty = (_jobData?['Specialty'] ?? '').toString();
      final requirements =
          (_jobData?['Requirements'] as List?)?.cast<String>() ??
              const <String>[];
      final description = (_jobData?['JobDescription'] ?? '').toString();

      if (title.isEmpty) {
        _snack('Missing job title.', error: true);
        setState(() => _busy = false);
        return;
      }
      if (specialty.isEmpty) {
        _snack('Missing specialty.', error: true);
        setState(() => _busy = false);
        return;
      }

      final tempJobId =
          'temp-${DateTime.now().millisecondsSinceEpoch}'; // لعيون الفنكشن

      final payload = {
        'jobId': tempJobId,
        'title': title,
        'specialty': specialty,
        if (position.isNotEmpty) 'position': position,
        if (requirements.isNotEmpty) 'requirements': requirements,
        if (description.isNotEmpty) 'description': description,
      };

      final resp = await http.post(
        _fnUrl(),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (resp.statusCode != 200) {
        _snack('AI generation failed: ${resp.body}', error: true);
        setState(() => _busy = false);
        return;
      }

      final data = jsonDecode(resp.body);
      final List out = (data['questions'] as List?) ?? const [];

      final generated = out
          .map((q) {
            return {
              'Text': (q['text'] ?? '').toString().trim(),
              'Type': (q['type'] ?? '').toString(),
            };
          })
          .where((m) => (m['Text'] as String).isNotEmpty)
          .toList();

      setState(() {
        _questions
          ..clear()
          ..addAll(generated);
      });

      _snack('Questions generated successfully!');
    } catch (e) {
      _snack('Error: $e', error: true);
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _autoGenerateIfEmpty() async {
    if (_autoTriggered) return;
    _autoTriggered = true;
    if (_questions.isEmpty) {
      await _generate();
    }
  }

  // ===== Navigation =====
  void _navigateBackToJobPosting() {
    if (_jobId != null && _jobId!.isNotEmpty) {
      Navigator.pushReplacementNamed(
        context,
        '/job_posting',
        arguments: {
          'jobId': _jobId,
          'fromQuestionsPage': true,
        },
      );
      return;
    }

    if (_jobData == null) {
      Navigator.pop(context);
      return;
    }

    Navigator.pushReplacementNamed(
      context,
      '/job_posting',
      arguments: {
        'draftJobData': _jobData,
      },
    );
  }

  Future<void> _confirmBackToJobPosting() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        title: const Text(
          'Leave Questions?',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'If you go back, your job posting data will stay, but any unsaved changes to questions will be lost.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.9),
              foregroundColor: const Color(0xFF4A5FBC),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Stay'),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFFC686A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Go back'),
          ),
        ],
      ),
    );

    if (ok == true) {
      _navigateBackToJobPosting();
    }
  }

  // ===== Done: هنا ننشئ البوست فعليًا =====
  Future<void> _done() async {
    if (_locked) return;

    if (_jobData == null) {
      _snack('Missing job data.', error: true);
      return;
    }

    if (_questions.length < kMinQuestions) {
      _snack(
        'Please add at least $kMinQuestions questions before finishing.',
        error: true,
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        title: const Text(
          'Confirm Post',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'After finishing, this job and its questions will be posted.\n'
          'You will not be able to add or edit questions later.\n\n'
          'Do you want to proceed?',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.9),
              foregroundColor: const Color(0xFF4A5FBC),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFFC686A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Post & Lock'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final jobs = FirebaseFirestore.instance.collection('Jobs');
      final newJobDoc = jobs.doc();
      final jobId = newJobDoc.id;

      final jobDataToSave = {
        ..._jobData!,
        'JobID': jobId,
        'JobStatus': 'Open',
        'Questions': _questions,
        'QuestionsLocked': true,
        'QuestionsLockedAt': FieldValue.serverTimestamp(),
        'QuestionsUserAddedCount': _userAddedCount,
      };

      await newJobDoc.set(jobDataToSave);

      _locked = true;
      _snack('Job posted successfully.');
    } catch (e) {
      _snack('Failed to post job: $e', error: true);
      return;
    }

    if (!mounted) return;
    final companyId = _jobData?['UserID'] as String?;
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/company-home',
      (route) => false,
      arguments: companyId != null ? {'companyId': companyId} : null,
    );
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_locked) {
          return true;
        } else {
          await _confirmBackToJobPosting();
          return false;
        }
      },
      child: ThemedScaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: const Text('Job Questions',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_locked) {
                Navigator.pop(context);
              } else {
                _confirmBackToJobPosting();
              }
            },
          ),
        ),
        body: (_jobData == null)
            ? const _CenteredInfo(text: 'Missing job data')
            : _questions.isEmpty && _busy
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Expanded(
                        child: _questions.isEmpty
                            ? _EmptyState(onGenerate: _busy ? null : _generate)
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                itemCount: _questions.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, i) {
                                  final q = _questions[i];
                                  return Card(
                                    elevation: 1.5,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.question_mark,
                                                  color: Color(0xFF4A5FBC)),
                                              const SizedBox(width: 6),
                                              Text(
                                                (q['Type'] ?? '')
                                                        .toString()
                                                        .isEmpty
                                                    ? 'Question'
                                                    : (q['Type'] as String)
                                                        .toUpperCase(),
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600),
                                              ),
                                              const Spacer(),
                                              IconButton(
                                                tooltip: 'Edit',
                                                onPressed: _locked
                                                    ? null
                                                    : () =>
                                                        _editQuestionAt(i, q),
                                                icon: const Icon(Icons.edit),
                                              ),
                                              // لا يوجد Delete
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            (q['Text'] ?? '').toString(),
                                            style: const TextStyle(
                                                fontSize: 15, height: 1.4),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      if (!_locked)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: (_userAddedCount >= kMaxUserAdds)
                                  ? null
                                  : _addQuestionDialog,
                              icon: const Icon(Icons.add),
                              label: Text(
                                _userAddedCount < kMaxUserAdds
                                    ? 'Add question (${kMaxUserAdds - _userAddedCount} left)'
                                    : 'Add question',
                                style:
                                    const TextStyle(color: Color(0xFF4A5FBC)),
                              ),
                              // ...
                            ),
                          ),
                        ),
                      if (!_locked)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _done,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4A5FBC),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              child: const Text(
                                'Done',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}

/* =========== small UI =========== */

class _CenteredInfo extends StatelessWidget {
  final String text;
  const _CenteredInfo({required this.text});
  @override
  Widget build(BuildContext context) {
    return Center(child: Text(text, style: TextStyle(color: Colors.grey[600])));
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback? onGenerate;
  const _EmptyState({this.onGenerate});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.help_outline, size: 64, color: Color(0xFF4A5FBC)),
          const SizedBox(height: 12),
          const Text('No questions yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Generate interview questions with AI.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onGenerate,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate with AI'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A5FBC),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
          ),
        ],
      ),
    );
  }
}
