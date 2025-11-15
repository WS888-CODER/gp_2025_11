import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:gp_2025_11/config/theme.dart';
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

  final Set<Map<String, dynamic>> _userAddedQuestions =
      <Map<String, dynamic>>{};

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
        SnackHelper.error(context, 'Missing job data.');
      } else {
        _autoGenerateIfEmpty();
      }
      setState(() {});
    });
  }

  // ===== UX helpers =====

  Future<void> _loadExistingJob(String jobId) async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection('Jobs').doc(jobId).get();

      if (!doc.exists) {
        SnackHelper.error(context, 'Job not found.');
        return;
      }
      final data = doc.data() as Map<String, dynamic>;
      _jobData = Map<String, dynamic>.from(data);
      final List qsRaw = (data['Questions'] as List?) ?? const [];
      _questions
        ..clear()
        ..addAll(qsRaw.map((q) {
          final m = Map<String, dynamic>.from(q as Map);
          return {
            'Text': (m['Text'] ?? '').toString(),
            'Type': (m['Type'] ?? 'technical').toString(),
          };
        }));

      _userAddedQuestions.clear();
      _userAddedCount = (data['QuestionsUserAddedCount'] ?? 0) as int;
      _locked = data['QuestionsLocked'] == true;

      setState(() {});
    } catch (e) {
      SnackHelper.error(context, 'Failed to load questions: $e');
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
      SnackHelper.error(context, 'Questions are locked.');
      return;
    }

    if (_userAddedCount >= kMaxUserAdds) {
      SnackHelper.error(
        context,
        'You can only add up to $kMaxUserAdds custom questions for this job.',
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
    if (text.isEmpty) {
      return SnackHelper.error(context, 'Question cannot be empty.');
    }
    if (text.length > kMaxQuestionLength) {
      return SnackHelper.error(context, 'Character limit reached.');
    }
    if (_isDuplicateQuestionLocal(text)) {
      return SnackHelper.error(context, 'Duplicate question.');
    }

    setState(() {
      final m = <String, dynamic>{
        'Text': text,
        'Type': type,
      };
      _questions.add(m);
      _userAddedQuestions.add(m);
      _userAddedCount += 1;
    });

    SnackHelper.success(context, 'Added.');
  }

  // ===== Edit Question (no limit) =====
  Future<void> _editQuestionAt(int index, Map<String, dynamic> q) async {
    if (_locked) {
      SnackHelper.error(context, 'Questions are locked.');
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
      return SnackHelper.error(context, 'Question cannot be empty.');
    }
    if (newText.length > kMaxQuestionLength) {
      return SnackHelper.error(context, 'Character limit reached.');
    }

    if (newText != (q['Text'] ?? '').toString() &&
        _isDuplicateQuestionLocal(newText)) {
      return SnackHelper.error(context, 'Duplicate question.');
    }

    if (index < 0 || index >= _questions.length) {
      return SnackHelper.error(context, 'Invalid question.');
    }

    setState(() {
      q['Text'] = newText;
      q['Type'] = type;
    });

    SnackHelper.success(context, 'Saved.');
  }

  // ===== Delete Question (only user-added in this session) =====
  Future<void> _deleteQuestionAt(int index) async {
    if (_locked) {
      SnackHelper.error(context, 'Questions are locked.');
      return;
    }
    if (index < 0 || index >= _questions.length) {
      SnackHelper.error(context, 'Invalid question.');
      return;
    }

    final q = _questions[index];
    final isUserAdded = _userAddedQuestions.contains(q);

    if (!isUserAdded) {
      SnackHelper.error(
        context,
        'You can only delete questions you added in this session.',
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        title: const Text(
          'Delete Question?',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to delete this question?',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() {
      _userAddedQuestions.remove(q);
      _questions.removeAt(index);
      if (_userAddedCount > 0) _userAddedCount -= 1;
    });

    SnackHelper.success(context, 'Question deleted.');
  }

  // ===== Generate via Cloud Function =====
  Future<void> _generate() async {
    if (_jobData == null) return;

    if (_locked) {
      SnackHelper.error(
        context,
        'Questions are locked. You can no longer generate or modify.',
      );
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
        SnackHelper.error(context, 'Missing job title.');
        setState(() => _busy = false);
        return;
      }
      if (specialty.isEmpty) {
        SnackHelper.error(context, 'Missing specialty.');
        setState(() => _busy = false);
        return;
      }

      final tempJobId = 'temp-${DateTime.now().millisecondsSinceEpoch}';

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
        SnackHelper.error(context, 'AI generation failed: ${resp.body}');
        setState(() => _busy = false);
        return;
      }

      final data = jsonDecode(resp.body);
      final List out = (data['questions'] as List?) ?? const [];

      final generated = out
          .map((q) {
            final text = (q['text'] ?? '').toString().trim();
            final type = (q['type'] ?? '').toString();
            if (text.isEmpty) return null;
            return <String, dynamic>{
              'Text': text,
              'Type': type,
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();

      setState(() {
        _questions
          ..clear()
          ..addAll(generated);
        _userAddedQuestions.clear();
        _userAddedCount = 0;
      });

      SnackHelper.success(context, 'Questions generated successfully!');
    } catch (e) {
      SnackHelper.error(context, 'Error: $e');
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

  Future<void> _done() async {
    if (_locked) return;

    if (_jobData == null) {
      SnackHelper.error(context, 'Missing job data.');
      return;
    }

    if (_questions.length < kMinQuestions) {
      SnackHelper.error(context,
          'Please add at least $kMinQuestions questions before finishing.');
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
      };

      await newJobDoc.set(jobDataToSave);

      _locked = true;
      SnackHelper.success(context, 'Job posted successfully.');
    } catch (e) {
      SnackHelper.error(context, 'Failed to post job: $e');
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
    final canAddMore = _userAddedCount < kMaxUserAdds;
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
                                  final typeRaw =
                                      (q['Type'] ?? '').toString().trim();
                                  final typeLabel = typeRaw.isEmpty
                                      ? 'Question'
                                      : typeRaw.toUpperCase();

                                  final isUserAdded =
                                      _userAddedQuestions.contains(q);

                                  return Card(
                                    elevation: 1.5,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                      Icons.question_mark,
                                                      color: Color(0xFF4A5FBC)),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    typeLabel,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600),
                                                  ),
                                                ],
                                              ),
                                              if (!_locked)
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      tooltip: 'Edit',
                                                      onPressed: () =>
                                                          _editQuestionAt(i, q),
                                                      icon: const Icon(
                                                          Icons.edit),
                                                    ),
                                                    if (isUserAdded)
                                                      IconButton(
                                                        tooltip: 'Delete',
                                                        onPressed: () =>
                                                            _deleteQuestionAt(
                                                                i),
                                                        icon: const Icon(
                                                            Icons.delete,
                                                            color: Colors.red),
                                                      ),
                                                  ],
                                                ),
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
                                }),
                      ),
                      if (!_locked)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: ButtonStyle(
                                side: MaterialStateProperty.resolveWith<
                                    BorderSide>(
                                  (states) {
                                    if (states
                                        .contains(MaterialState.disabled)) {
                                      return const BorderSide(
                                          color: Colors.grey, width: 2);
                                    }
                                    return const BorderSide(
                                        color: Color(0xFF4A5FBC), width: 2);
                                  },
                                ),
                                foregroundColor:
                                    MaterialStateProperty.resolveWith<Color>(
                                  (states) {
                                    if (states
                                        .contains(MaterialState.disabled)) {
                                      return Colors.grey;
                                    }
                                    return const Color(0xFF4A5FBC);
                                  },
                                ),
                              ),
                              onPressed: canAddMore ? _addQuestionDialog : null,
                              icon: const Icon(Icons.add),
                              label: Text(
                                canAddMore
                                    ? 'Add question (${kMaxUserAdds - _userAddedCount} left)'
                                    : 'Max custom questions reached',
                              ),
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
