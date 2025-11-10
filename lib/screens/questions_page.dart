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
  static const int kMaxQuestionLength = 180;
  static const int kEditQuotaInit = 3;

  bool _locked = false;
  bool _regenUsed = false;
  int _quotaLeft = kEditQuotaInit;
  static const String _projectId = 'jadeer-b4953';

  Uri _fnUrl() {
    return Uri.parse(
      'https://us-central1-jadeer-b4953.cloudfunctions.net/generateInterviewQuestions',
    );
  }

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

  Future<bool> _isDuplicateQuestion(String text) async {
    final snap = await FirebaseFirestore.instance
        .collection('Jobs')
        .doc(_jobId)
        .collection('Questions')
        .where('Text', isEqualTo: text.trim())
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<void> _consumeQuota() async {
    // Decrease the per-job edit/add/delete quota by 1
    final jobRef = FirebaseFirestore.instance.collection('Jobs').doc(_jobId);
    await jobRef.update({
      'QuestionsEditQuotaLeft': FieldValue.increment(-1),
    });
    _quotaLeft -= 1;
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
    String difficulty = 'medium';
    String category = 'General';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Question'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLength: kMaxQuestionLength,
                decoration: const InputDecoration(labelText: 'Question text'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(
                      value: 'technical', child: Text('Technical')),
                  DropdownMenuItem(
                      value: 'behavioral', child: Text('Behavioral')),
                ],
                onChanged: (v) => type = v ?? 'technical',
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: difficulty,
                decoration: const InputDecoration(labelText: 'Difficulty'),
                items: const [
                  DropdownMenuItem(value: 'easy', child: Text('Easy')),
                  DropdownMenuItem(value: 'medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'hard', child: Text('Hard')),
                ],
                onChanged: (v) => difficulty = v ?? 'medium',
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                onChanged: (v) =>
                    category = v.trim().isEmpty ? 'General' : v.trim(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
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
      // Compute next Order
      final qCol = FirebaseFirestore.instance
          .collection('Jobs')
          .doc(_jobId)
          .collection('Questions');
      final last = await qCol.orderBy('Order', descending: true).limit(1).get();
      int order = 0;
      if (last.docs.isNotEmpty)
        order = (last.docs.first['Order'] as int? ?? 0) + 1;

      await qCol.add({
        'Text': text,
        'Type': type,
        'Category': category,
        'Difficulty': difficulty,
        'Source': 'Manual',
        'Order': order,
        'CreatedAt': FieldValue.serverTimestamp(),
      });

      await _consumeQuota();
      _snack('Added.');
    } catch (e) {
      _snack('Could not add: $e', error: true);
    }
  }

  Future<void> _editQuestion(DocumentSnapshot d) async {
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
        TextEditingController(text: (d['Text'] ?? '').toString());
    String type = (d['Type'] ?? 'technical').toString();
    String difficulty = (d['Difficulty'] ?? 'medium').toString();
    String category = (d['Category'] ?? 'General').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Question'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLength: kMaxQuestionLength,
                decoration: const InputDecoration(labelText: 'Question text'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(
                      value: 'technical', child: Text('Technical')),
                  DropdownMenuItem(
                      value: 'behavioral', child: Text('Behavioral')),
                ],
                onChanged: (v) => type = v ?? 'technical',
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: difficulty,
                decoration: const InputDecoration(labelText: 'Difficulty'),
                items: const [
                  DropdownMenuItem(value: 'easy', child: Text('Easy')),
                  DropdownMenuItem(value: 'medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'hard', child: Text('Hard')),
                ],
                onChanged: (v) => difficulty = v ?? 'medium',
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                onChanged: (v) =>
                    category = v.trim().isEmpty ? 'General' : v.trim(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );

    if (ok != true) return;

    final text = controller.text.trim();
    if (text.isEmpty) return _snack('Question cannot be empty.', error: true);
    if (text.length > kMaxQuestionLength) {
      return _snack('Character limit reached.', error: true);
    }

    // If text changed, ensure it doesn’t duplicate another question
    if (text != (d['Text'] ?? '')) {
      if (await _isDuplicateQuestion(text)) {
        return _snack('Duplicate question.', error: true);
      }
    }

    try {
      await d.reference.update({
        'Text': text,
        'Type': type,
        'Category': category,
        'Difficulty': difficulty,
      });
      await _consumeQuota();
      _snack('Saved.');
    } catch (e) {
      _snack('Could not edit: $e', error: true);
    }
  }

  Future<void> _deleteQuestion(DocumentSnapshot d) async {
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
        title: const Text('Delete Question'),
        content: const Text(
            'Are you sure you want to delete this question? This will consume your quota.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await d.reference.delete();
      await _consumeQuota();
      _snack('Deleted.');
    } catch (e) {
      _snack('Could not delete: $e', error: true);
    }
  }

  Future<void> _loadJobMeta() async {
    if (_jobId == null) {
      setState(() => _loadingJob = false);
      return;
    }
    try {
      final doc =
          await FirebaseFirestore.instance.collection('Jobs').doc(_jobId).get();
      if (doc.exists) {
        _jobData = doc.data();
        _locked = (_jobData?['QuestionsLocked'] == true);
        _regenUsed = (_jobData?['QuestionsRegenerated'] == true);

        // Initialize quota if missing
        final q = _jobData?['QuestionsEditQuotaLeft'];
        if (q is! int) {
          await FirebaseFirestore.instance
              .collection('Jobs')
              .doc(_jobId)
              .update({'QuestionsEditQuotaLeft': kEditQuotaInit});
          _quotaLeft = kEditQuotaInit;
        } else {
          _quotaLeft = q;
        }
      }
    } catch (_) {}
    setState(() => _loadingJob = false);
    await _autoGenerateIfEmpty();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          textAlign: TextAlign.center,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: error
            ? const Color(0xFFFF7B7B).withOpacity(0.8)
            : const Color(0xFF4CAF50).withOpacity(0.8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _generate({required bool overwrite}) async {
    if (_jobId == null || _jobData == null) return;

    // ✅ Block if locked
    if (_locked) {
      _snack('Questions are locked. You can no longer generate or modify.',
          error: true);
      return;
    }

    // ✅ Regenerate once only
    if (overwrite && _regenUsed) {
      _snack('You can only regenerate questions once.', error: true);
      return;
    }

    setState(() => _busy = true);

    try {
      // Confirm regenerate
      if (overwrite) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Regenerate questions?'),
            content: const Text(
                'This will delete existing questions and generate new ones. Continue?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Regenerate'),
              ),
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

      final payload = {
        'jobId': _jobId,
        'title': title,
        if (position.isNotEmpty) 'position': position,
        if (specialty.isNotEmpty) 'specialty': specialty,
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

      final qCol = FirebaseFirestore.instance
          .collection('Jobs')
          .doc(_jobId)
          .collection('Questions');

      // If regenerate → remove all first
      if (overwrite) {
        final existing = await qCol.get();
        for (final d in existing.docs) {
          await d.reference.delete();
        }
      }

      int order = 0;
      final batch = FirebaseFirestore.instance.batch();
      for (final q in out) {
        final ref = qCol.doc();
        batch.set(ref, {
          'Text': (q['text'] ?? '').toString().trim(),
          'Type': (q['type'] ?? '').toString(),
          'Category': (q['category'] ?? '').toString(),
          'Difficulty': (q['difficulty'] ?? '').toString(),
          'Source': 'AI',
          'Order': order++,
          'CreatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
// Mark regenerate as used if this was a regenerate
      if (overwrite) {
        await FirebaseFirestore.instance
            .collection('Jobs')
            .doc(_jobId)
            .update({'QuestionsRegenerated': true});
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
      Navigator.pushNamedAndRemoveUntil(context, '/company-home', (r) => false);
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
                borderRadius: BorderRadius.circular(20),
              ),
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
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Lock & Finish'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await FirebaseFirestore.instance.collection('Jobs').doc(_jobId).update({
        'QuestionsLocked': true,
        'QuestionsLockedAt': FieldValue.serverTimestamp(),
      });
      _locked = true;
      _snack('Questions locked for this job.');
    } catch (e) {
      _snack('Failed to lock: $e', error: true);
      return;
    }

    Navigator.pushNamedAndRemoveUntil(
        context, '/company-home', (route) => false);
  }

  bool _autoTriggered = false;

  Future<void> _autoGenerateIfEmpty() async {
    if (_jobId == null || _autoTriggered) return;
    _autoTriggered = true;

    final snap = await FirebaseFirestore.instance
        .collection('Jobs')
        .doc(_jobId)
        .collection('Questions')
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      await _generate(overwrite: false);
    }
  }

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
          backgroundColor: const Color(0xFF4A5FBC),
          foregroundColor: Colors.white,
          title: const Text(
            'Job Questions',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _navigateBackToJobPosting,
          ),
          actions: [
            if (!_loadingJob && _jobId != null && !_locked && !_regenUsed) ...[
              IconButton(
                tooltip: 'Regenerate',
                onPressed: _busy ? null : () => _generate(overwrite: true),
                icon: const Icon(Icons.restart_alt),
              ),
            ],
          ],
        ),
        body: _loadingJob
            ? const Center(child: CircularProgressIndicator())
            : (_jobId == null)
                ? const _CenteredInfo(text: 'Missing Job ID')
                : Column(
                    children: [
                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('Jobs')
                              .doc(_jobId)
                              .collection('Questions')
                              .orderBy('Order')
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            if (!snapshot.hasData ||
                                snapshot.data!.docs.isEmpty) {
                              return _EmptyState(
                                onGenerate: _busy
                                    ? null
                                    : () => _generate(overwrite: false),
                              );
                            }
                            final docs = snapshot.data!.docs;
                            return ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              itemCount: docs.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final d = docs[i];
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
                                              (d['Type'] ?? '')
                                                      .toString()
                                                      .isEmpty
                                                  ? 'Question'
                                                  : (d['Type'] as String)
                                                      .toUpperCase(),
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600),
                                            ),
                                            const Spacer(),
                                            IconButton(
                                              tooltip: 'Edit',
                                              onPressed:
                                                  (_locked || _quotaLeft <= 0)
                                                      ? null
                                                      : () => _editQuestion(d),
                                              icon: const Icon(Icons.edit),
                                            ),
                                            IconButton(
                                              tooltip: 'Delete',
                                              onPressed: (_locked ||
                                                      _quotaLeft <= 0)
                                                  ? null
                                                  : () => _deleteQuestion(d),
                                              icon: const Icon(
                                                  Icons.delete_outline),
                                            ),
                                            const SizedBox(width: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                  (d['Difficulty'] ?? 'medium')
                                                      .toString()),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          (d['Text'] ?? '').toString(),
                                          style: const TextStyle(
                                              fontSize: 15, height: 1.4),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          (d['Category'] ?? '').toString(),
                                          style: TextStyle(
                                              color: Colors.grey[700]),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      if (!_locked)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed:
                                  (_quotaLeft > 0) ? _addQuestionDialog : null,
                              icon: const Icon(Icons.add),
                              label: Text('Add question (${_quotaLeft} left)'),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _done,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4A5FBC),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30)),
                            ),
                            child: const Text('Done',
                                style: TextStyle(fontSize: 16)),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

/* =========== صغار UI =========== */

class _CenteredInfo extends StatelessWidget {
  final String text;
  const _CenteredInfo({required this.text});
  @override
  Widget build(BuildContext context) {
    return Center(child: Text(text, style: TextStyle(color: Colors.grey[600])));
  }
}

class _JobHeader extends StatelessWidget {
  final Map<String, dynamic> jobData;
  const _JobHeader({required this.jobData});
  @override
  Widget build(BuildContext context) {
    final title = (jobData['JobTitle'] ?? '').toString();
    final pos = (jobData['Position'] ?? '').toString();
    final spec = (jobData['Specialty'] ?? '').toString();
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.work_outline, size: 28, color: Color(0xFF4A5FBC)),
          const SizedBox(width: 12),
          Expanded(
            child: Text('$title — $pos\n$spec',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, height: 1.3)),
          ),
        ],
      ),
    );
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
