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
  String? _jobId;
  Map<String, dynamic>? _jobData;
  bool _loadingJob = true;
  bool _busy = false;

  static const int kMaxQuestionLength = 180; // character limit
  static const int kEditQuotaInit = 3; // add/edit/delete total = 3

  bool _locked = false; // lock after Done
  bool _regenUsed = false; // regenerate only once
  int _quotaLeft = kEditQuotaInit;

  Uri _fnUrl() => Uri.parse(
        'https://us-central1-jadeer-b4953.cloudfunctions.net/generateInterviewQuestions',
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      _jobId = args?['jobId'] as String?;
      setState(() {});
      _loadJobMeta();
    });
  }

  // ===== Firestore helpers =====
  DocumentReference<Map<String, dynamic>> get _jobRef =>
      FirebaseFirestore.instance.collection('Jobs').doc(_jobId);

  Stream<DocumentSnapshot<Map<String, dynamic>>> _jobStream() =>
      _jobRef.snapshots();

  List<Map<String, dynamic>> _readQuestionsFromJob(Map<String, dynamic>? job) {
    final List raw = (job?['Questions'] as List?) ?? const [];
    // ensure well-shaped list of maps
    return raw
        .map((e) => (e is Map<String, dynamic>) ? e : <String, dynamic>{})
        .toList();
  }

  Future<void> _loadJobMeta() async {
    if (_jobId == null) {
      setState(() => _loadingJob = false);
      return;
    }
    try {
      final doc = await _jobRef.get();
      if (doc.exists) {
        _jobData = doc.data();
        _locked = (_jobData?['QuestionsLocked'] == true);
        _regenUsed = (_jobData?['QuestionsRegenerated'] == true);

        _quotaLeft =
            (_jobData?['QuestionsEditQuotaLeft'] as int?) ?? kEditQuotaInit;
      }
    } catch (_) {}
    setState(() => _loadingJob = false);
    await _autoGenerateIfEmpty();
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

  // ===== Validation helpers (array-based) =====
  Future<bool> _isDuplicateQuestion(String text) async {
    final doc = await _jobRef.get();
    final job = doc.data();
    final questions = _readQuestionsFromJob(job);
    final t = text.trim();
    return questions.any((q) => (q['Text'] ?? '').toString().trim() == t);
  }

  Future<void> _consumeQuota() async {
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(_jobRef);
        final data = snap.data() as Map<String, dynamic>?;

        final current = (data?['QuestionsEditQuotaLeft'] is int)
            ? data!['QuestionsEditQuotaLeft'] as int
            : kEditQuotaInit;

        if (current <= 0) {
          throw StateError('quota_exhausted');
        }

        tx.update(_jobRef, {'QuestionsEditQuotaLeft': current - 1});
      });

      setState(() => _quotaLeft = (_quotaLeft > 0) ? _quotaLeft - 1 : 0);
    } on StateError catch (e) {
      if (e.message == 'quota_exhausted') {
        _snack('You have no remaining edits for this job.', error: true);
      } else {
        _snack('Quota logic error.', error: true);
      }
    } on FirebaseException catch (e) {
      _snack('Quota update denied: ${e.code}', error: true);
    } catch (e) {
      _snack('Quota update error: $e', error: true);
    }
  }

  Future<void> _addQuestionDialog() async {
    if (_locked) {
      _snack('Questions are locked.', error: true);
      return;
    }
    if (_quotaLeft <= 0) {
      _snack('You reached the limit: only 3 add/edit/delete actions allowed.',
          error: true);
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
                style: TextStyle(color: Colors.white),
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
                      value: 'behavioral',
                      child: Text('Behavioral',
                          style: TextStyle(color: Colors.white))),
                ],
                onChanged: (v) => type = v ?? 'technical',
                style: TextStyle(color: Colors.white),
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
    if (await _isDuplicateQuestion(text)) {
      return _snack('Duplicate question.', error: true);
    }

    try {
      final doc = await _jobRef.get();
      final job = doc.data();
      final questions = _readQuestionsFromJob(job);

      questions.add({
        'Text': text,
        'Type': type,
      });

      await _jobRef.update({'Questions': questions});
      await _consumeQuota();
      _snack('Added.');
    } catch (e) {
      _snack('Could not add: $e', error: true);
    }
  }

  Future<void> _editQuestionAt(int index, Map<String, dynamic> q) async {
    if (_locked) {
      _snack('Questions are locked.', error: true);
      return;
    }
    if (_quotaLeft <= 0) {
      _snack('You reached the limit: only 3 add/edit/delete actions allowed.',
          error: true);
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
                style: TextStyle(color: Colors.white),
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
                      value: 'behavioral',
                      child: Text('Behavioral',
                          style: TextStyle(color: Colors.white))),
                ],
                onChanged: (v) => type = v ?? 'technical',
                style: TextStyle(color: Colors.white),
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

    if (newText != (q['Text'] ?? '').toString()) {
      if (await _isDuplicateQuestion(newText)) {
        return _snack('Duplicate question.', error: true);
      }
    }

    try {
      final doc = await _jobRef.get();
      final job = doc.data();
      final questions = _readQuestionsFromJob(job);

      if (index < 0 || index >= questions.length) {
        return _snack('Invalid question.', error: true);
      }

      questions[index] = {
        'Text': newText,
        'Type': type,
      };

      await _jobRef.update({'Questions': questions});
      await _consumeQuota();
      _snack('Saved.');
    } catch (e) {
      _snack('Could not edit: $e', error: true);
    }
  }

  Future<void> _deleteQuestionAt(int index) async {
    if (_locked) {
      _snack('Questions are locked.', error: true);
      return;
    }
    if (_quotaLeft <= 0) {
      _snack('You reached the limit: only 3 add/edit/delete actions allowed.',
          error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        title: const Text(
          'Delete Question',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to delete this question? This will consume your quota.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white),
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
          ElevatedButton(
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
              child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final doc = await _jobRef.get();
      final job = doc.data();
      final questions = _readQuestionsFromJob(job);

      if (index < 0 || index >= questions.length) {
        return _snack('Invalid question.', error: true);
      }

      questions.removeAt(index);
      await _jobRef.update({'Questions': questions});
      await _consumeQuota();
      _snack('Deleted.');
    } catch (e) {
      _snack('Could not delete: $e', error: true);
    }
  }

  // ===== Generation (array-based) =====
  Future<void> _generate({required bool overwrite}) async {
    if (_jobId == null || _jobData == null) return;

    if (_locked) {
      _snack('Questions are locked. You can no longer generate or modify.',
          error: true);
      return;
    }
    if (overwrite && _regenUsed) {
      _snack('You can only regenerate questions once.', error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      if (overwrite) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.7),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            title: const Text(
              'Regenerate questions?',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'This will delete existing questions and generate new ones. Continue?',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.9),
                    foregroundColor: const Color(0xFF4A5FBC),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFFC686A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text('Regenerate')),
            ],
          ),
        );
        if (ok != true) {
          setState(() => _busy = false);
          return;
        }
      }

      final title = (_jobData?['JobTitle'] ?? '').toString();
      final position = (_jobData?['Position'] ?? '').toString();
      final specialty =
          (_jobData?['Specialty'] ?? '').toString(); // REQUIRED now
      final requirements =
          (_jobData?['Requirements'] as List?)?.cast<String>() ??
              const <String>[];
      final description = (_jobData?['JobDescription'] ?? '').toString();

      if (title.isEmpty) {
        _snack('Missing job title.', error: true);
        setState(() => _busy = false);
        return;
      }
      // specialty is required in your flow
      if (specialty.isEmpty) {
        _snack('Missing specialty.', error: true);
        setState(() => _busy = false);
        return;
      }

      final payload = {
        'jobId': _jobId,
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

      // Convert to array of maps for the job document
      final generated = out.map((q) {
        return {
          'Text': (q['text'] ?? '').toString().trim(),
          'Type': (q['type'] ?? '').toString(),
        };
      }).toList();

      // Write to job doc as array
      final doc = await _jobRef.get();
      final job = doc.data();
      List<Map<String, dynamic>> current = _readQuestionsFromJob(job);

      if (overwrite) {
        current = generated;
      } else {
        current.addAll(generated);
      }

      await _jobRef.update({'Questions': current});

      if (overwrite) {
        await _jobRef.update({'QuestionsRegenerated': true});
        setState(() => _regenUsed = true);
      }

      _snack(overwrite
          ? 'Questions regenerated successfully!'
          : 'Questions generated successfully!');
    } catch (e) {
      _snack('Error: $e', error: true);
    } finally {
      setState(() => _busy = false);
    }
  }

  // ===== Auto-generate if empty (array-based) =====
  bool _autoTriggered = false;
  Future<void> _autoGenerateIfEmpty() async {
    if (_jobId == null || _autoTriggered) return;
    _autoTriggered = true;

    final doc = await _jobRef.get();
    final job = doc.data();
    final questions = _readQuestionsFromJob(job);

    if (questions.isEmpty) {
      await _generate(overwrite: false);
    }
  }

  // ===== Navigation =====
  void _navigateBackToJobPosting() {
    if (_jobId != null) {
      Navigator.pushReplacementNamed(
        context,
        '/job_posting',
        arguments: {'jobId': _jobId, 'fromQuestionsPage': true},
      );
    } else {
      Navigator.pop(context);
    }
  }

  void _done() async {
    if (_locked) {
      if (!mounted) return;
      final companyId = _jobData?['UserID'] as String?;
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/company-home',
        (route) => false,
        arguments: companyId != null ? {'companyId': companyId} : null,
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        title: const Text(
          'Confirm Lock',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'After finishing, this job’s questions will be locked.\n'
          'You will not be able to add, edit, delete, or regenerate later.\n\n'
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
            child: const Text('Lock & Finish'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _jobRef.update({
        'QuestionsLocked': true,
      });
      _locked = true;
      _snack('Questions locked for this job.');
    } catch (e) {
      _snack('Failed to lock: $e', error: true);
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
        _navigateBackToJobPosting();
        return false;
      },
      child: ThemedScaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: const Text('Job Questions',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _navigateBackToJobPosting),
          actions: [
            if (!_loadingJob && _jobId != null && !_locked && !_regenUsed)
              IconButton(
                tooltip: 'Regenerate',
                onPressed: _busy ? null : () => _generate(overwrite: true),
                icon: const Icon(Icons.restart_alt),
              ),
          ],
        ),
        body: _loadingJob
            ? const Center(child: CircularProgressIndicator())
            : (_jobId == null)
                ? const _CenteredInfo(text: 'Missing Job ID')
                : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _jobStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || !snapshot.data!.exists) {
                        return _EmptyState(
                            onGenerate: _busy
                                ? null
                                : () => _generate(overwrite: false));
                      }

                      final job = snapshot.data!.data();
                      final questions = _readQuestionsFromJob(job);

                      if (questions.isEmpty) {
                        return _EmptyState(
                            onGenerate: _busy
                                ? null
                                : () => _generate(overwrite: false));
                      }

                      // keep local flags updated from the live doc
                      _locked = (job?['QuestionsLocked'] == true);
                      _regenUsed = (job?['QuestionsRegenerated'] == true);
                      _quotaLeft = (job?['QuestionsEditQuotaLeft'] as int?) ??
                          _quotaLeft;

                      return Column(
                        children: [
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              itemCount: questions.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final q = questions[i];
                                return Card(
                                  elevation: 1.5,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
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
                                                  fontWeight: FontWeight.w600),
                                            ),
                                            const Spacer(),
                                            IconButton(
                                              tooltip: 'Edit',
                                              onPressed: (_locked ||
                                                      _quotaLeft <= 0)
                                                  ? null
                                                  : () => _editQuestionAt(i, q),
                                              icon: const Icon(Icons.edit),
                                            ),
                                            IconButton(
                                              tooltip: 'Delete',
                                              onPressed: (_locked ||
                                                      _quotaLeft <= 0)
                                                  ? null
                                                  : () => _deleteQuestionAt(i),
                                              icon: const Icon(
                                                  Icons.delete_outline),
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
                              },
                            ),
                          ),
                          if (!_locked)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: (_quotaLeft > 0)
                                      ? _addQuestionDialog
                                      : null,
                                  icon: const Icon(Icons.add),
                                  label: Text(
                                    'Add question ($_quotaLeft left)',
                                    style: const TextStyle(
                                        color: Color(0xFF4A5FBC)),
                                  ),
                                  style: ButtonStyle(
                                    side: MaterialStateProperty.resolveWith<
                                        BorderSide?>((states) {
                                      final color = states
                                              .contains(MaterialState.disabled)
                                          ? Colors.white54
                                          : const Color(0xFF4A5FBC);
                                      return BorderSide(color: color, width: 3);
                                    }),
                                    foregroundColor: MaterialStateProperty
                                        .resolveWith<Color?>((states) {
                                      return states
                                              .contains(MaterialState.disabled)
                                          ? Colors.white54
                                          : const Color(0xFF4A5FBC);
                                    }),
                                    shape: MaterialStateProperty.all(
                                      RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(30)),
                                    ),
                                    padding: MaterialStateProperty.all(
                                      const EdgeInsets.symmetric(vertical: 16),
                                    ),
                                  ),
                                ),
                              ),
                            ),
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
                                      borderRadius: BorderRadius.circular(30)),
                                ),
                                child: const Text('Done',
                                    style: TextStyle(fontSize: 16)),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
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
