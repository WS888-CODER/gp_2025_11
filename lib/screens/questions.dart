import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class QuestionsPage extends StatefulWidget {
  const QuestionsPage({super.key});

  @override
  State<QuestionsPage> createState() => _QuestionsPageState();
}

class _QuestionsPageState extends State<QuestionsPage> {
  String _computeJobStatus({
    required DateTime? start,
    required DateTime? end,
  }) {
    final now = DateTime.now();

    final endOfDay = end != null ? DateTime(end.year, end.month, end.day, 23, 59, 59) : null;
    if (endOfDay != null && endOfDay.isBefore(now)) return 'Closed';
    if (start != null && start.isAfter(now)) return 'Soon';
    return 'Open';
  }

  DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is Timestamp) return v.toDate();
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  Map<String, dynamic>? _jobData;
  String? _jobId;
  static const int kMaxQuestionLength = 500;
  static const int kMinQuestionChars = 20;
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
      builder: (ctx) => JadeerDialog<bool>(
        title: 'Add Question',
        primaryLabel: 'Add',
        primaryResult: true,
        secondaryLabel: 'Cancel',
        secondaryResult: false,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatefulBuilder(
              builder: (context, setSB) {
                final currentLen = controller.text.trim().length;
                final isBelowMin = currentLen < kMinQuestionChars;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      maxLength: kMaxQuestionLength,
                      onChanged: (_) => setSB(() {}),
                      decoration: InputDecoration(
                        labelText: 'Question text',
                        labelStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
                        counterText:
                            '${controller.text.length}/$kMaxQuestionLength',
                      ),
                      style: const TextStyle(color: Colors.white),
                      maxLines: null,
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 20,
                      child: isBelowMin
                          ? const Text(
                              'Minimum is $kMinQuestionChars characters',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: type,
              decoration: const InputDecoration(
                labelText: 'Type',
                labelStyle: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white, width: 2),
                ),
              ),
              dropdownColor: const Color(0xFF4A5FBC),
              items: [
                DropdownMenuItem(
                  value: 'technical',
                  child: Text(
                    'Technical',
                    style: TextStyle(
                      color: scheme.surface,
                    ),
                  ),
                ),
                DropdownMenuItem(
                  value: 'psychometric',
                  child: Text(
                    'Psychometric',
                    style: TextStyle(
                      color: scheme.surface,
                    ),
                  ),
                ),
              ],
              onChanged: (v) => type = v ?? 'technical',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
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
    if (text.length < kMinQuestionChars) {
      return SnackHelper.error(
        context,
        'Question must be at least $kMinQuestionChars characters.',
      );
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
      builder: (ctx) => JadeerDialog<bool>(
        title: 'Edit Question',
        primaryLabel: 'Save',
        primaryResult: true,
        secondaryLabel: 'Cancel',
        secondaryResult: false,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatefulBuilder(
              builder: (context, setSB) {
                final currentLen = controller.text.trim().length;
                final isBelowMin = currentLen < kMinQuestionChars;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      maxLength: kMaxQuestionLength,
                      onChanged: (_) => setSB(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Question text',
                        labelStyle: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      maxLines: null,
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 20,
                      child: isBelowMin
                          ? const Text(
                              'Minimum is $kMinQuestionChars characters',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final newText = controller.text.trim();
    if (newText.isEmpty) {
      return SnackHelper.error(context, 'Question cannot be empty.');
    }
    if (newText.length < kMinQuestionChars) {
      return SnackHelper.error(
        context,
        'Question must be at least $kMinQuestionChars characters.',
      );
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
      builder: (ctx) => const JadeerDialog<bool>(
        title: 'Delete Question?',
        primaryLabel: 'Delete',
        primaryResult: true,
        secondaryLabel: 'Cancel',
        secondaryResult: false,
        content: Text(
          'Are you sure you want to delete this question?',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white),
        ),
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
      if (generated.isEmpty) {
        SnackHelper.error(
          context,
          'AI generation did not return any questions. Please try again or add questions manually.',
        );
        setState(() => _busy = false);
        return;
      }
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
      builder: (ctx) => const JadeerDialog<bool>(
        title: 'Leave Questions?',
        primaryLabel: 'Go back',
        primaryResult: true,
        secondaryLabel: 'Stay',
        secondaryResult: false,
        content: Text(
          'If you go back, your job posting data will stay, but any unsaved changes to questions will be lost.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white),
        ),
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => const JadeerDialog<bool>(
        title: 'Confirm Post',
        primaryLabel: 'Post & Lock',
        primaryResult: true,
        secondaryLabel: 'Cancel',
        secondaryResult: false,
        content: Text(
          'After finishing, this job and its questions will be posted.\n'
          'You will not be able to add or edit questions later.\n\n'
          'Do you want to proceed?',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white),
        ),
      ),
    );

    if (ok != true) return;

    try {
      final jobs = FirebaseFirestore.instance.collection('Jobs');
      final newJobDoc = jobs.doc();
      final jobId = newJobDoc.id;

      final start = _asDate(_jobData?['StartDate']);
      final end = _asDate(_jobData?['EndDate']);

      final jobDataToSave = {
        ..._jobData!,
        'JobID': jobId,
        'JobStatus': _computeJobStatus(start: start, end: end),
        'Questions': _questions,
        'QuestionsLocked': true,
        'QuestionsUserAddedCount': _userAddedCount,
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

  void _showInstructions() {
    showDialog(
      context: context,
      builder: (ctx) => JadeerDialog<void>(
        title: 'How this page works',
        primaryLabel: 'Got it',
        primaryResult: null,
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_locked)
                const Text(
                  '• Questions are locked for this job.\n'
                  '• You can review questions only.\n'
                  '• Editing, adding, or deleting is disabled.',
                  style: TextStyle(color: Colors.white, height: 1.4),
                )
              else
                const Text(
                  '• You can edit any AI-generated question.\n'
                  '• You can add up to 3 custom questions.\n'
                  '• You can delete only questions you added yourself.\n'
                  '• All questions will be locked after posting the job.',
                  style: TextStyle(color: Colors.white, height: 1.4),
                ),
            ],
          ),
        ),
      ),
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
        appBar: CustomHeader(
          title: 'Job Questions',
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: Colors.white,
            ),
            onPressed: () {
              if (_locked) {
                Navigator.pop(context);
              } else {
                _confirmBackToJobPosting();
              }
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.white),
              tooltip: 'Instructions',
              onPressed: _showInstructions,
            ),
          ],
        ),
        body: (_jobData == null)
            ? const _CenteredInfo(text: 'Missing job data')
            : _questions.isEmpty && _busy
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: _JobHeaderCard(
                          jobData: _jobData!,
                          jobId: _jobId,
                          onTap: _jobId != null && _jobId!.isNotEmpty
                              ? () {
                                  Navigator.pushNamed(
                                    context,
                                    '/job-details-view',
                                    arguments: {'jobId': _jobId},
                                  );
                                }
                              : null,
                        ),
                      ),
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

                                  return Container(
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(context).colorScheme.surface,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(
                                            Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? 0.12
                                                : 0.05,
                                          ),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
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
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _done,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4A5FBC),
                                foregroundColor: Colors.white,
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.help_outline,
            size: 64,
            color: scheme.primary,
          ),
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

class _JobHeaderCard extends StatelessWidget {
  final Map<String, dynamic> jobData;
  final String? jobId;
  final VoidCallback? onTap;

  const _JobHeaderCard({
    required this.jobData,
    this.jobId,
    this.onTap,
  });

  DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is Timestamp) return v.toDate();
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  String _computeStatus(DateTime? start, DateTime? end) {
    final now = DateTime.now();
    final endOfDay = end != null ? DateTime(end.year, end.month, end.day, 23, 59, 59) : null;
    if (endOfDay != null && endOfDay.isBefore(now)) return 'Closed';
    if (start != null && start.isAfter(now)) return 'Soon';
    return 'Open';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final title = (jobData['JobTitle'] ?? '').toString();
    final position = (jobData['Position'] ?? '').toString();
    final specialty = (jobData['Specialty'] ?? '').toString();

    final start = _asDate(jobData['StartDate']);
    final end = _asDate(jobData['EndDate']);

    String? dateRange;
    if (start != null && end != null) {
      dateRange = '${_fmtDate(start)}  →  ${_fmtDate(end)}';
    } else if (start != null) {
      dateRange = 'Starts: ${_fmtDate(start)}';
    } else if (end != null) {
      dateRange = 'Ends: ${_fmtDate(end)}';
    }

    final status = _computeStatus(start, end);

    Color statusColor;
    switch (status) {
      case 'Open':
        statusColor = Colors.green;
        break;
      case 'Soon':
        statusColor = const Color(0xFFB8860B);
        break;
      case 'Closed':
        statusColor = Colors.redAccent;
        break;
      default:
        statusColor = scheme.primary;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.06,
              ),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: const Color(0xFF4A5FBC).withOpacity(0.1),
          ),
        ),
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title.isEmpty ? 'Job title not set' : title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4A5FBC),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (position.isNotEmpty)
                  Row(
                    children: [
                      const Icon(
                        Icons.badge_outlined,
                        size: 18,
                        color: Color(0xFF4A5FBC),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        position,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                if (position.isNotEmpty) const SizedBox(height: 4),
                if (specialty.isNotEmpty)
                  Row(
                    children: [
                      const Icon(
                        Icons.stars_rounded,
                        size: 18,
                        color: Color(0xFFFD6C67),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          specialty,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                if ((specialty.isNotEmpty) && dateRange != null)
                  const SizedBox(height: 4),
                if (dateRange != null)
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          dateRange,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurface.withOpacity(0.65),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (onTap != null)
              Positioned(
                bottom: -8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFD6C67),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
