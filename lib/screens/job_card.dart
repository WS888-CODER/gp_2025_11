import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/screens/favorites.dart';
import 'package:gp_2025_11/screens/job_interview_service.dart';
import 'package:url_launcher/url_launcher.dart';

String effectiveStatusFromDates(DateTime? start, DateTime? end) {
  final now = DateTime.now();
  if (end != null && end.isBefore(now)) return 'Closed';
  if (start != null && start.isAfter(now)) return 'Soon';
  return 'Open';
}

/// Checks the Firestore JobStatus field first (e.g. manually closed by company),
/// then falls back to date-based logic.
String effectiveJobStatus(Job job) {
  final raw = job.status.trim().toLowerCase();
  if (raw == 'closed') return 'Closed';
  return effectiveStatusFromDates(job.startDate, job.endDate);
}

class JobFields {
  static const jobId = 'JobID';
  static const title = 'JobTitle';
  static const position = 'Position';
  static const keywords = 'JobKeywords';
  static const startDate = 'StartDate';
  static const endDate = 'EndDate';
  static const description = 'JobDescription';
  static const status = 'JobStatus';
  static const requirements = 'Requirements';
  static const specialty = 'Specialty';
  static const userId = 'UserID';
  static const company = 'Company';
  static const postedAt = 'PostedAt';
}

class CompanyInfo {
  final String name;
  final String logoUrl;
  final String location;
  final String description;
  final String contactEmail;
  final String phone;
  final String website;

  const CompanyInfo({
    this.name = 'Company',
    this.logoUrl = '',
    this.location = '',
    this.description = '',
    this.contactEmail = '',
    this.phone = '',
    this.website = '',
  });
}

class Job {
  final String id;
  final String jobId;
  final String title;
  final String position;
  final List<String> keywords;

  final DateTime postedAt;

  final DateTime? startDate;
  final DateTime? endDate;

  final String description;
  final String status;
  final List<String> requirements;
  final String specialty;
  final String userId;

  const Job({
    required this.id,
    required this.jobId,
    required this.title,
    required this.position,
    required this.keywords,
    required this.postedAt,
    this.startDate,
    this.endDate,
    required this.description,
    required this.status,
    required this.requirements,
    required this.specialty,
    required this.userId,
  });

  factory Job.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};

    DateTime? asDate(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    List<String> asStringList(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : <String>[];

    final startDate = asDate(d[JobFields.startDate]);
    final endDate = asDate(d[JobFields.endDate]);

    final postedAt =
        asDate(d[JobFields.postedAt]) ?? startDate ?? DateTime(2000);

    return Job(
      id: doc.id,
      jobId: (d[JobFields.jobId] ?? doc.id).toString(),
      title: (d[JobFields.title] ?? '').toString(),
      position: (d[JobFields.position] ?? '').toString(),
      keywords: asStringList(d[JobFields.keywords]),
      postedAt: postedAt,
      startDate: startDate,
      endDate: endDate,
      description: (d[JobFields.description] ?? '').toString(),
      status: (d[JobFields.status] ?? 'Open').toString(),
      requirements: asStringList(d[JobFields.requirements]),
      specialty: (d[JobFields.specialty] ?? '').toString(),
      userId: (d[JobFields.userId] ?? '').toString(),
    );
  }
}

/* ====================== Job Details Page ====================== */

class JobDetailsPage extends StatefulWidget {
  final Job job;
  final CompanyInfo? company;
  final bool isSaved;
  final bool isApplied;

  const JobDetailsPage({
    super.key,
    required this.job,
    this.company,
    this.isSaved = false,
    this.isApplied = false,
  });

  @override
  State<JobDetailsPage> createState() => _JobDetailsPageState();
}

Widget _infoRow(
  BuildContext ctx, {
  required IconData icon,
  required String label,
  required String value,
}) {
  if (value.trim().isEmpty) return const SizedBox.shrink();

  final scheme = Theme.of(ctx).colorScheme;

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: scheme.secondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    fontSize: 13.5,
                    height: 1.3,
                  ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ExpandableText extends StatefulWidget {
  final String text;
  final int maxLines;
  const _ExpandableText(this.text, {this.maxLines = 2});
  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    if (widget.text.trim().isEmpty) {
      return const Text('No description provided.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _expanded ? null : widget.maxLines,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size(40, 28),
          ),
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Text(_expanded ? 'Show less' : 'Show more'),
        ),
      ],
    );
  }
}

class _JobDetailsPageState extends State<JobDetailsPage> {
  bool _companyExpanded = false;
  bool _saved = false;
  bool _isApplying = false;
  bool _hasApplied = false;

  String _fmtDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _saved = widget.isSaved;
    _hasApplied = widget.isApplied;
    _checkAlreadyApplied();
  }

  Future<void> _checkAlreadyApplied() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('Applications')
        .where('UserID', isEqualTo: uid)
        .where('JobID', isEqualTo: widget.job.jobId)
        .limit(1)
        .get();
    if (!mounted) return;
    if (snap.docs.isNotEmpty) setState(() => _hasApplied = true);
  }

  Future<void> _apply() async {
    final rootCtx = Navigator.of(context, rootNavigator: true).context;
    final job = widget.job;
    final status = effectiveJobStatus(job);

    if (status == 'Closed') {
      SnackHelper.error(context, 'This job is closed.');
      return;
    }
    if (status == 'Soon') {
      SnackHelper.error(context, 'Applications are not open yet.');
      return;
    }
    if (_isApplying || _hasApplied) return;
    setState(() => _isApplying = true);

    try {
      await JobInterviewService.start(
        rootCtx,
        jobDocId: job.id,
        jobId: job.jobId,
        specialty: job.specialty,
        jobTitle: job.title,
        companyName: widget.company?.name ?? '',
      );
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  Future<void> _openWebsite(String raw) async {
    final t = raw.trim();
    if (t.isEmpty) return;
    final url = t.startsWith(RegExp(r'https?://', caseSensitive: false))
        ? t
        : 'https://$t';
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await _safeLaunch(uri);
  }

  Future<void> _safeLaunch(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        SnackHelper.error(context, 'Could not open link.');
      }
    } catch (_) {
      if (mounted) {
        SnackHelper.error(context, 'Could not open link.');
      }
    }
  }

  Future<void> _toggleFavorite() async {
    final newValue = !_saved;

    setState(() {
      _saved = newValue;
    });

    try {
      await FavoritesService.toggleFavorite(widget.job.jobId, newValue);
      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saved = !newValue;
      });
      SnackHelper.error(context, 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final primary = scheme.primary;

    final job = widget.job;
    final company = widget.company;
    final status = effectiveJobStatus(job);
    final isClosed = status == 'Closed';
    final isSoon = status == 'Soon';
    final disabled = isClosed || isSoon;

    return ThemedScaffold(
      appBar: CustomHeader(
        title: 'Job Details',
        actions: [
          IconButton(
            onPressed: _toggleFavorite,
            icon: Icon(
              _saved ? Icons.favorite : Icons.favorite_border,
              color: (_saved ? Colors.red : Colors.white),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                Theme.of(context).brightness == Brightness.dark ? 0.12 : 0.05,
              ),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: FilledButton(
          onPressed: disabled || _isApplying || _hasApplied ? null : _apply,
          style: FilledButton.styleFrom(
            backgroundColor: _hasApplied
                ? Color.fromARGB(185, 253, 108, 103)
                : disabled
                    ? onSurface.withOpacity(0.6)
                    : scheme.primary,
            disabledBackgroundColor: _hasApplied
                ? Color.fromARGB(185, 253, 108, 103)
                : onSurface.withOpacity(0.6),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          child: Text(
            _hasApplied
                ? 'Already Applied'
                : _isApplying
                    ? 'Starting…'
                    : 'Apply',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Company details
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(
                    Theme.of(context).brightness == Brightness.dark
                        ? 0.12
                        : 0.05,
                  ),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.primary,
                        width: 3,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundImage: (company?.logoUrl ?? '').isNotEmpty
                          ? NetworkImage(company!.logoUrl)
                          : null,
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                              ? scheme.surface
                              : const Color(0xFFE8E8FF),
                      child: (company?.logoUrl ?? '').isEmpty
                          ? Icon(Icons.business,
                              size: 28, color: scheme.primary)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                (company?.name ?? 'Company'),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: isClosed
                                      ? onSurface.withOpacity(0.6)
                                      : primary,
                                ),
                              ),
                            ),
                            if (isClosed || isSoon)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isClosed
                                      ? Colors.grey.shade600
                                      : scheme.primary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  isClosed ? 'Closed' : 'Soon',
                                  style: TextStyle(
                                    color: isClosed
                                        ? Colors.white
                                        : scheme.primary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if ((company?.location ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: onSurface.withOpacity(0.6),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  company!.location,
                                  style: TextStyle(
                                    color: onSurface.withOpacity(0.75),
                                    fontSize: 13,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if ((company?.description ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          AnimatedCrossFade(
                            firstChild: Text(
                              company!.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: onSurface.withOpacity(0.85),
                                height: 1.35,
                              ),
                            ),
                            secondChild: Text(
                              company.description,
                              style: TextStyle(
                                fontSize: 13,
                                color: onSurface.withOpacity(0.85),
                                height: 1.35,
                              ),
                            ),
                            crossFadeState: _companyExpanded
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 200),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(40, 24),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => setState(
                                () => _companyExpanded = !_companyExpanded),
                            child: Text(
                              _companyExpanded ? 'Show less' : 'Show more',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Column(
                          spacing: 6,
                          children: [
                            if ((company?.contactEmail ?? '').isNotEmpty)
                              InkWell(
                                onTap: () {
                                  final uri = Uri(
                                    scheme: 'mailto',
                                    path: company!.contactEmail,
                                  );
                                  _safeLaunch(uri);
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    Icon(Icons.email,
                                        size: 16, color: scheme.secondary),
                                    const SizedBox(width: 4),
                                    Text(
                                      company!.contactEmail,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if ((company?.phone ?? '').isNotEmpty)
                              InkWell(
                                onTap: () {
                                  final uri = Uri(
                                    scheme: 'tel',
                                    path: company!.phone,
                                  );
                                  _safeLaunch(uri);
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    Icon(Icons.phone,
                                        size: 16, color: scheme.secondary),
                                    const SizedBox(width: 4),
                                    Text(
                                      company!.phone,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if ((company?.website ?? '').isNotEmpty)
                              InkWell(
                                onTap: () => _openWebsite(company!.website),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    Icon(Icons.link,
                                        size: 16, color: scheme.secondary),
                                    const SizedBox(width: 4),
                                    ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 180),
                                      child: Text(
                                        company!.website,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Job Summary
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(
                    Theme.of(context).brightness == Brightness.dark
                        ? 0.12
                        : 0.05,
                  ),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title.isEmpty ? 'Untitled Job' : job.title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: isClosed ? onSurface.withOpacity(0.7) : primary,
                      height: 1.2,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _infoRow(
                    context,
                    icon: Icons.stars_rounded,
                    label: 'Specialty',
                    value: job.specialty.isEmpty ? '—' : job.specialty,
                  ),
                  _infoRow(
                    context,
                    icon: Icons.badge_outlined,
                    label: 'Position',
                    value: job.position.isEmpty ? '—' : job.position,
                  ),
                  _infoRow(
                    context,
                    icon: Icons.schedule,
                    label: 'Posted',
                    value: _fmtDate(job.postedAt),
                  ),
                  _infoRow(
                    context,
                    icon: Icons.calendar_today,
                    label: 'Starts',
                    value: _fmtDate(job.startDate!),
                  ),
                  _infoRow(
                    context,
                    icon: Icons.event_available,
                    label: 'Ends',
                    value: _fmtDate(job.endDate!),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Description
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(
                    Theme.of(context).brightness == Brightness.dark
                        ? 0.12
                        : 0.05,
                  ),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Job Description',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ExpandableText(
                    job.description.isEmpty
                        ? 'No description provided.'
                        : job.description,
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Requirements
          if (job.requirements.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(
                      Theme.of(context).brightness == Brightness.dark
                          ? 0.12
                          : 0.05,
                    ),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Requirements',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: job.requirements.map((r) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 18,
                                color: scheme.secondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(r)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/* ====================== Job Card Widget ====================== */

class JobCard extends StatefulWidget {
  final Job job;
  final CompanyInfo company;
  final bool isSaved;
  final bool isApplied;
  final ValueChanged<bool>? onSavedChanged;

  const JobCard({
    super.key,
    required this.job,
    required this.company,
    this.isSaved = false,
    this.isApplied = false,
    this.onSavedChanged,
  });

  @override
  State<JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<JobCard> {
  bool _saved = false;
  bool _isApplying = false;

  bool get _isApplied => widget.isApplied;

  Future<void> _apply() async {
    final rootCtx = Navigator.of(context, rootNavigator: true).context;
    final job = widget.job;
    final status = effectiveJobStatus(job);

    if (status == 'Closed') {
      SnackHelper.error(context, 'This job is closed.');
      return;
    }
    if (status == 'Soon') {
      SnackHelper.error(context, 'Applications are not open yet.');
      return;
    }
    if (_isApplied || _isApplying) return;
    setState(() => _isApplying = true);

    try {
      await JobInterviewService.start(
        rootCtx,
        jobDocId: job.id,
        jobId: job.jobId,
        specialty: job.specialty,
        jobTitle: job.title,
        companyName: widget.company.name,
      );
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _saved = widget.isSaved;
  }

  @override
  void didUpdateWidget(covariant JobCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSaved != widget.isSaved) {
      _saved = widget.isSaved;
    }
  }

  void _toggleFavorite() {
    final newValue = !_saved;
    setState(() => _saved = newValue);
    widget.onSavedChanged?.call(newValue);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final primary = scheme.primary;

    final job = widget.job;
    final company = widget.company;
    final status = effectiveJobStatus(job);
    final isClosed = status == 'Closed';
    final isSoon = status == 'Soon';
    final disabled = isClosed || isSoon;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.12 : 0.05,
            ),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => JobDetailsPage(
                job: job,
                company: company,
                isSaved: _saved,
                isApplied: _isApplied,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.primary,
                        width: 2.5,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundImage: company.logoUrl.isNotEmpty
                          ? NetworkImage(company.logoUrl)
                          : null,
                      child: company.logoUrl.isEmpty
                          ? Icon(Icons.business,
                              size: 20, color: scheme.primary)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      company.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isClosed ? onSurface.withOpacity(0.6) : primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: _toggleFavorite,
                    icon: Icon(
                      _saved ? Icons.favorite : Icons.favorite_border,
                      color: _saved ? Colors.red : onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Job title
              Text(
                job.title.isEmpty ? 'Untitled Job' : job.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isClosed ? onSurface.withOpacity(0.6) : onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 6),

              // Posted date
              Text(
                'Posted: ${_fmtDate(job.postedAt)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isClosed ? onSurface.withOpacity(0.6) : onSurface,
                    ),
              ),

              const SizedBox(height: 12),

              // Bottom row
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (job.specialty.isNotEmpty && !isClosed && !isSoon)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: scheme.primary.withOpacity(0.10),
                      ),
                      child: Text(
                        job.specialty,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (isClosed || isSoon)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isClosed
                            ? Colors.grey.shade600
                            : scheme.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isClosed ? 'Closed' : 'Soon',
                        style: TextStyle(
                          color: isClosed ? Colors.white : scheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: FilledButton(
                      onPressed:
                          disabled || _isApplying || _isApplied ? null : _apply,
                      style: FilledButton.styleFrom(
                        backgroundColor: _isApplied
                            ? Color.fromARGB(185, 253, 108, 103)
                            : disabled
                                ? onSurface.withOpacity(0.6)
                                : scheme.primary,
                        disabledBackgroundColor: _isApplied
                            ? Color.fromARGB(185, 253, 108, 103)
                            : onSurface.withOpacity(0.6),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      child: Text(
                        _isApplied
                            ? 'Applied'
                            : _isApplying
                                ? 'Starting…'
                                : 'Apply',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
