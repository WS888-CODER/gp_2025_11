import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'dart:async';
import 'package:gp_2025_11/screens/company_reports_page.dart';

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is Timestamp) return v.toDate();
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

String effectiveStatusFromDates({
  required DateTime? start,
  required DateTime? end,
  required String? storedStatus,
}) {
  final now = DateTime.now();

  // If company manually closed it
  if ((storedStatus ?? '').toLowerCase() == 'closed') return 'Closed';

  final endOfDay = end != null
      ? DateTime(end.year, end.month, end.day, 23, 59, 59)
      : null;
  if (endOfDay != null && endOfDay.isBefore(now)) return 'Closed';
  if (start != null && start.isAfter(now)) return 'Soon';
  return 'Open';
}

class CompanyHome extends StatefulWidget {
  const CompanyHome({
    super.key,
    this.companyId,
    this.fallbackCompanyName = 'Company',
  });

  final String? companyId;

  final String fallbackCompanyName;

  @override
  State<CompanyHome> createState() => _CompanyHomeState();
}

class _CompanyHomeState extends State<CompanyHome> {
  int _tab = 1; // 0: Reports, 1: Home
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _jobsScrollController = ScrollController();
  String get _effectiveCompanyId {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final fromArgs = (args?['companyId'] ?? '').toString();
    return fromArgs.isNotEmpty ? fromArgs : (widget.companyId ?? '');
  }

  /// Check if profile is complete before allowing job operations
  Future<bool> _checkProfileComplete() async {
    final companyId = _effectiveCompanyId;
    if (companyId.isEmpty) return false;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(companyId)
          .get();

      if (!userDoc.exists) return false;

      final userData = userDoc.data() as Map<String, dynamic>;
      final isProfileComplete = userData['IsProfileComplete'] ?? false;

      if (!isProfileComplete) {
        if (!mounted) return false;
        showDialog<void>(
          context: context,
          builder: (context) => const JadeerDialog<void>(
            title: 'Profile Incomplete',
            primaryLabel: 'OK',
            primaryResult: null,
            content: Text(
              'Please complete your company profile before creating or editing job postings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
        );

        return false;
      }

      return true;
    } catch (e) {
      if (!mounted) return false;
      showDialog<void>(
        context: context,
        builder: (context) => JadeerDialog<void>(
          title: 'Error',
          primaryLabel: 'OK',
          primaryResult: null,
          content: Text(
            'Failed to verify profile: $e',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );

      return false;
    }
  }

  /// Show dialog to edit job dates
  Future<void> _showEditDatesDialog(
    String jobId,
    String jobTitle,
    dynamic startDateData,
    dynamic endDateData,
    BuildContext ctx,
  ) async {
    DateTime? _asDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is Timestamp) return v.toDate();
      if (v is String && v.isNotEmpty) {
        return DateTime.tryParse(v);
      }
      return null;
    }

    String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

    DateTime? startDate = _asDate(startDateData);
    DateTime? endDate = _asDate(endDateData);

    final result = await showDialog<Map<String, DateTime?>>(
      context: ctx,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> selectStartDate() async {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final initialDate = startDate != null && !startDate!.isBefore(today)
                ? startDate!
                : today;

            final picked = await showDatePicker(
              context: context,
              initialDate: initialDate,
              firstDate: today,
              lastDate: DateTime(2100),
              builder: (context, child) {
                final theme = Theme.of(context);
                final scheme = theme.colorScheme;

                return Theme(
                  data: theme.copyWith(
                    colorScheme: scheme.copyWith(
                      primary: const Color(0xFFFC686A),
                      onPrimary: Colors.white,
                      onSurface: Colors.white,
                      surface: const Color(0xFF4A5FBC).withOpacity(0.7),
                    ),
                    textTheme: theme.textTheme.copyWith(
                      bodyLarge: const TextStyle(color: Colors.white),
                      bodyMedium: const TextStyle(color: Colors.white),
                      headlineMedium: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                      titleLarge: const TextStyle(color: Colors.white),
                    ),
                    inputDecorationTheme: InputDecorationTheme(
                      labelStyle: const TextStyle(color: Colors.white),
                      hintStyle:
                          TextStyle(color: Colors.white.withOpacity(0.7)),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: Color(0xFFFC686A), width: 2),
                      ),
                    ),
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFC686A),
                      ),
                    ),
                    datePickerTheme: DatePickerThemeData(
                      backgroundColor:
                          const Color(0xFF4A5FBC).withOpacity(0.7),
                      headerForegroundColor: Colors.white,
                      weekdayStyle: const TextStyle(color: Colors.white),
                      yearStyle: const TextStyle(color: Colors.white),
                      dayStyle: const TextStyle(color: Colors.white),
                      yearForegroundColor:
                          MaterialStateColor.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Colors.white;
                        }
                        return Colors.white;
                      }),
                      yearBackgroundColor:
                          MaterialStateColor.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return const Color(0xFFFC686A);
                        }
                        return Colors.transparent;
                      }),
                      dayForegroundColor:
                          MaterialStateColor.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Colors.white;
                        }
                        if (states.contains(MaterialState.disabled)) {
                          return Colors.white.withOpacity(0.3);
                        }
                        return Colors.white;
                      }),
                      todayBorder: BorderSide.none,
                      todayBackgroundColor:
                          MaterialStateColor.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return const Color(0xFFFC686A);
                        }
                        return const Color(0xFFFC686A).withOpacity(0.15);
                      }),
                      todayForegroundColor:
                          MaterialStateColor.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Colors.white;
                        }
                        return Colors.white;
                      }),
                    ),
                  ),
                  child: child!,
                );
              },
            );

            if (picked != null) {
              setDialogState(() => startDate = picked);
            }
          }

          Future<void> selectEndDate() async {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final firstAllowedDate =
                (startDate != null && !startDate!.isBefore(today))
                    ? startDate!
                    : today;
            final initialDate =
                (endDate != null && !endDate!.isBefore(firstAllowedDate))
                    ? endDate!
                    : firstAllowedDate;

            final picked = await showDatePicker(
              context: context,
              initialDate: initialDate,
              firstDate: firstAllowedDate,
              lastDate: DateTime(2100),
              builder: (context, child) {
                final theme = Theme.of(context);
                final scheme = theme.colorScheme;

                return Theme(
                  data: theme.copyWith(
                    colorScheme: scheme.copyWith(
                      primary: const Color(0xFFFC686A),
                      onPrimary: Colors.white,
                      onSurface: Colors.white,
                      surface: const Color(0xFF4A5FBC).withOpacity(0.7),
                    ),
                    textTheme: theme.textTheme.copyWith(
                      bodyLarge: const TextStyle(color: Colors.white),
                      bodyMedium: const TextStyle(color: Colors.white),
                      headlineMedium: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                      titleLarge: const TextStyle(color: Colors.white),
                    ),
                    inputDecorationTheme: InputDecorationTheme(
                      labelStyle: const TextStyle(color: Colors.white),
                      hintStyle:
                          TextStyle(color: Colors.white.withOpacity(0.7)),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: Color(0xFFFC686A), width: 2),
                      ),
                    ),
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFC686A),
                      ),
                    ),
                    datePickerTheme: DatePickerThemeData(
                      backgroundColor:
                          const Color(0xFF4A5FBC).withOpacity(0.7),
                      headerForegroundColor: Colors.white,
                      weekdayStyle: const TextStyle(color: Colors.white),
                      yearStyle: const TextStyle(color: Colors.white),
                      dayStyle: const TextStyle(color: Colors.white),
                      yearForegroundColor:
                          MaterialStateColor.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Colors.white;
                        }
                        return Colors.white;
                      }),
                      yearBackgroundColor:
                          MaterialStateColor.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return const Color(0xFFFC686A);
                        }
                        return Colors.transparent;
                      }),
                      dayForegroundColor:
                          MaterialStateColor.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Colors.white;
                        }
                        if (states.contains(MaterialState.disabled)) {
                          return Colors.white.withOpacity(0.3);
                        }
                        return Colors.white;
                      }),
                      todayBorder: BorderSide.none,
                      todayBackgroundColor:
                          MaterialStateColor.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return const Color(0xFFFC686A);
                        }
                        return const Color(0xFFFC686A).withOpacity(0.15);
                      }),
                      todayForegroundColor:
                          MaterialStateColor.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Colors.white;
                        }
                        return Colors.white;
                      }),
                    ),
                  ),
                  child: child!,
                );
              },
            );

            if (picked != null) {
              setDialogState(() => endDate = picked);
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Edit Dates - $jobTitle',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Start Date
                InkWell(
                  onTap: selectStartDate,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Start Date',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          startDate != null ? _fmtDate(startDate!) : 'Not set',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // End Date
                InkWell(
                  onTap: selectEndDate,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'End Date',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          endDate != null ? _fmtDate(endDate!) : 'Not set',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: 120,
                child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF4A5FBC),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, {
                      'startDate': startDate,
                      'endDate': endDate,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF7B7B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
            actionsAlignment: MainAxisAlignment.center,
            actionsPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          );
        },
      ),
    );

    if (result != null) {
      try {
        final now = DateTime.now();
        final newStart = result['startDate'];
        final newEnd = result['endDate'];

        String newStatus;
        final newEndOfDay = newEnd != null
            ? DateTime(newEnd.year, newEnd.month, newEnd.day, 23, 59, 59)
            : null;
        if (newEndOfDay != null && newEndOfDay.isBefore(now)) {
          newStatus = 'Closed';
        } else {
          newStatus = 'Open';
        }

        final savedEnd = newEnd != null
            ? DateTime(newEnd.year, newEnd.month, newEnd.day, 23, 59, 59)
            : null;

        await FirebaseFirestore.instance.collection('Jobs').doc(jobId).update({
          'StartDate': newStart,
          'EndDate': savedEnd,
        });

        await FirebaseFirestore.instance.collection('Jobs').doc(jobId).update({
          'JobStatus': newStatus,
        });

        if (!mounted) return;
        SnackHelper.success(ctx, 'Job dates updated successfully');
      } catch (e) {
        if (!mounted) return;
        SnackHelper.error(ctx, 'Error updating dates: $e');
      }
    }
  }

  /// Close or reopen a job
  Future<void> _closeJob(
      String jobId, bool isClosed, BuildContext ctx, DateTime? endDate) async {
    try {
      // If reopening and endDate has passed, prompt for new date
      if (isClosed && endDate != null && endDate.isBefore(DateTime.now())) {
        if (!mounted) return;

        // Show dialog explaining the job is expired
        final shouldExtend = await showDialog<bool>(
          context: ctx,
          builder: (context) => JadeerDialog<bool>(
            title: 'Job Expired',
            primaryLabel: 'Select New Date',
            primaryResult: true,
            secondaryLabel: 'Cancel',
            secondaryResult: false,
            content: Text(
              'This job expired on ${endDate.day}/${endDate.month}/${endDate.year}.\n\nTo reopen it, please select a new end date.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, height: 1.5),
            ),
          ),
        );

        if (shouldExtend != true || !mounted) return;

        // Show date picker for new end date
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        final newEndDate = await showDatePicker(
          context: ctx,
          initialDate: today,
          firstDate: today,
          lastDate: DateTime(2100),
          builder: (context, child) {
            final theme = Theme.of(context);
            final scheme = theme.colorScheme;

            return Theme(
              data: theme.copyWith(
                colorScheme: scheme.copyWith(
                  primary: const Color(0xFFFC686A),
                  onPrimary: Colors.white,
                  onSurface: Colors.white, // السنوات والأرقام
                  surface: const Color(0xFF4A5FBC).withOpacity(0.7),
                ),
                textTheme: theme.textTheme.copyWith(
                  bodyLarge: const TextStyle(color: Colors.white),
                  bodyMedium: const TextStyle(color: Colors.white),
                  headlineMedium: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                  titleLarge: const TextStyle(color: Colors.white),
                ),
                inputDecorationTheme: InputDecorationTheme(
                  labelStyle: const TextStyle(color: Colors.white),
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFFC686A), width: 2),
                  ),
                ),
                textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFC686A),
                  ),
                ),
                datePickerTheme: DatePickerThemeData(
                  backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.7),
                  headerForegroundColor: Colors.white,
                  weekdayStyle: const TextStyle(color: Colors.white),
                  yearStyle: const TextStyle(color: Colors.white),
                  dayStyle: const TextStyle(color: Colors.white),
                  yearForegroundColor: MaterialStateColor.resolveWith((states) {
                    if (states.contains(MaterialState.selected)) {
                      return Colors.white;
                    }
                    return Colors.white;
                  }),
                  yearBackgroundColor: MaterialStateColor.resolveWith((states) {
                    if (states.contains(MaterialState.selected)) {
                      return const Color(0xFFFC686A);
                    }
                    return Colors.transparent;
                  }),
                  dayForegroundColor: MaterialStateColor.resolveWith((states) {
                    if (states.contains(MaterialState.selected)) {
                      return Colors.white;
                    }
                    if (states.contains(MaterialState.disabled)) {
                      return Colors.white.withOpacity(0.3);
                    }
                    return Colors.white;
                  }),
                  todayBorder: BorderSide.none,
                  todayBackgroundColor:
                      MaterialStateColor.resolveWith((states) {
                    if (states.contains(MaterialState.selected)) {
                      return const Color(0xFFFC686A);
                    }
                    return const Color(0xFFFC686A).withOpacity(0.15);
                  }),
                  todayForegroundColor:
                      MaterialStateColor.resolveWith((states) {
                    if (states.contains(MaterialState.selected)) {
                      return Colors.white;
                    }
                    return Colors.white;
                  }),
                ),
              ),
              child: child!,
            );
          },
        );

        if (newEndDate == null || !mounted) return;

        // Save end of day so Cloud Function doesn't immediately close it
        final endOfPickedDay = DateTime(
          newEndDate.year,
          newEndDate.month,
          newEndDate.day,
          23,
          59,
          59,
        );

        // Update EndDate first, then JobStatus (Firestore rules require separate updates)
        await FirebaseFirestore.instance.collection('Jobs').doc(jobId).update({
          'EndDate': endOfPickedDay,
        });

        await FirebaseFirestore.instance.collection('Jobs').doc(jobId).update({
          'JobStatus': 'Open',
        });

        if (!mounted) return;

        SnackHelper.success(
          ctx,
          'Job reopened with new end date: ${newEndDate.day}/${newEndDate.month}/${newEndDate.year}',
        );
      } else {
        // Normal close/reopen without date change
        await FirebaseFirestore.instance.collection('Jobs').doc(jobId).update({
          'JobStatus': isClosed ? 'Open' : 'Closed',
        });

        if (!mounted) return;

        SnackHelper.success(
          ctx,
          isClosed ? 'Job reopened successfully' : 'Job closed successfully',
        );
      }
    } catch (e) {
      if (!mounted) return;

      SnackHelper.error(ctx, 'Error: $e');
    }
  }

  /// Delete a job with confirmation
  Future<void> _deleteJob(
      String jobId, String jobTitle, BuildContext ctx) async {
    if (!mounted) return;

    final shouldDelete = await showDialog<bool>(
      context: ctx,
      builder: (context) => JadeerDialog<bool>(
        title: 'Delete Job?',
        primaryLabel: 'Delete',
        primaryResult: true,
        secondaryLabel: 'Cancel',
        secondaryResult: false,
        content: Text(
          'Are you sure you want to permanently delete "$jobTitle"? This action cannot be undone.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );

    if (!mounted) return;

    if (shouldDelete == true) {
      try {
        await FirebaseFirestore.instance.collection('Jobs').doc(jobId).delete();

        if (!mounted) return;

        SnackHelper.success(ctx, 'Job deleted successfully');
      } catch (e) {
        if (!mounted) return;

        SnackHelper.error(ctx, 'Error: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      }
    });
  }

  @override
  void dispose() {
    _jobsScrollController.dispose();
    super.dispose();
  }

  Widget _buildAnimatedNavBar() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final barColor = isDark ? scheme.surface : Colors.white;
    final circleColor = isDark ? scheme.secondary : const Color(0xFFFC686A);
    final circleIconColor = isDark ? scheme.onSecondary : Colors.white;
    final shadowColor =
        isDark ? Colors.black.withOpacity(0.6) : Colors.black.withOpacity(0.08);

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        ClipPath(
          clipper: _BottomBarClipper(
            circlePosition: _getCirclePosition() + 30,
            circleRadius: 45,
          ),
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              color: barColor,
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavIcon(Icons.analytics_outlined, 0),
                  _buildNavIcon(Icons.home_outlined, 1),
                ],
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
          left: _getCirclePosition(),
          bottom: 35,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: circleColor,
              boxShadow: [
                BoxShadow(
                  color: circleColor.withOpacity(0.4),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              _getSelectedIcon(),
              color: circleIconColor,
              size: 30,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavIcon(IconData icon, int index) {
    final isSelected = _tab == index;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final Color baseColor =
        isDark ? scheme.onSurface.withOpacity(0.5) : Colors.grey[400]!;

    return GestureDetector(
      onTap: () {
        setState(() {
          _tab = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 60,
        height: 60,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 26,
          color: isSelected ? Colors.transparent : baseColor,
        ),
      ),
    );
  }

  double _getCirclePosition() {
    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth = screenWidth / 2;
    return (_tab * itemWidth) + (itemWidth / 2) - 30;
  }

  IconData _getSelectedIcon() {
    switch (_tab) {
      case 0:
        return Icons.analytics;
      case 1:
        return Icons.home;
      default:
        return Icons.home;
    }
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _jobsStream(
      String companyId) {
    try {
      Query<Map<String, dynamic>> q =
          FirebaseFirestore.instance.collection('Jobs');
      if (companyId.isNotEmpty) {
        q = q.where('UserID', isEqualTo: companyId);
      }
      return q.snapshots().map((snap) {
        final docs = snap.docs.toList();

        docs.sort((a, b) {
          final sa = a.data()['StartDate'];
          final sb = b.data()['StartDate'];
          final da = sa is Timestamp
              ? sa.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          final db = sb is Timestamp
              ? sb.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });

        return docs;
      });
    } catch (e) {
      return Stream.error(e);
    }
  }

  PreferredSizeWidget _buildCustomAppBar(String companyId) {
    // For Reports tab, use standard AppBar
    if (_tab != 1) {
      return const CustomHeader(title: 'Reports', showBack: false);
    }

    // For home tab, use custom purple gradient header
    return PreferredSize(
      preferredSize: const Size.fromHeight(200),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          final isDark = theme.brightness == Brightness.dark;

          final bubbleColor = Colors.white.withOpacity(isDark ? 0.03 : 0.06);
          final shadowColor = scheme.primary.withOpacity(isDark ? 0.6 : 0.4);

          return Container(
            height: 280,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(40),
                bottomRight: Radius.circular(40),
              ),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -60,
                  right: -40,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: bubbleColor,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 40,
                  left: -30,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: bubbleColor,
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _ProfileButton(userId: companyId),
                            const Spacer(),
                            GestureDetector(
                              onTap: () {
                                final uid =
                                    FirebaseAuth.instance.currentUser?.uid ??
                                        '';
                                if (uid.isEmpty) return;

                                Navigator.pushNamed(
                                  context,
                                  '/notifications',
                                  arguments: {'userId': uid},
                                );
                              },
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: StreamBuilder<
                                    QuerySnapshot<Map<String, dynamic>>>(
                                  stream: FirebaseFirestore.instance
                                      .collection('Notification')
                                      .where('UserID', isEqualTo: companyId)
                                      .where('Read', isEqualTo: false)
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    final unreadCount =
                                        snapshot.data?.docs.length ?? 0;

                                    return Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        const Center(
                                          child: Icon(
                                            Icons.notifications_outlined,
                                            color: Colors.white,
                                            size: 26,
                                          ),
                                        ),
                                        if (unreadCount > 0)
                                          Positioned(
                                            right: 8,
                                            top: 8,
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: const BoxDecoration(
                                                color: Colors.red,
                                                shape: BoxShape.circle,
                                              ),
                                              constraints: const BoxConstraints(
                                                minWidth: 18,
                                                minHeight: 18,
                                              ),
                                              child: Text(
                                                unreadCount > 99
                                                    ? '99+'
                                                    : unreadCount.toString(),
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () {
                                final uid =
                                    FirebaseAuth.instance.currentUser?.uid;
                                if (uid != null) {
                                  Navigator.pushNamed(
                                    context,
                                    '/settings',
                                    arguments: {
                                      'userType': 'Company',
                                      'userId': uid
                                    },
                                  );
                                }
                              },
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.settings_outlined,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _WelcomeTitle(companyId: companyId),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final companyId = _effectiveCompanyId;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final Color iconColor = isDark ? Colors.black87 : Colors.white;
    final homeBody = Container(
      color: isDark ? scheme.background : const Color(0xFFF5F5F5),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? scheme.background : const Color(0xFFF5F5F5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: ListView(
                key: const PageStorageKey('company_jobs_list'),
                controller: _jobsScrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 8),
                  const _SectionTitle(),
                  const SizedBox(height: 12),
                  StreamBuilder<
                      List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                    stream: _jobsStream(companyId),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snap.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Error: ${snap.error}'),
                        );
                      }

                      final jobs = snap.data ?? const [];
                      if (jobs.isEmpty) {
                        return const EmptyState(
                          icon: Icons.work_outline,
                          title: 'No job posts yet',
                          subtitle: 'Tap "Create Job Post" to add your first opening.',
                        );
                      }

                      return Column(
                        children: jobs.map((doc) {
                          final data = doc.data();

                          final title =
                              (data['JobTitle'] ?? 'Untitled').toString();
                          final position = (data['Position'] ?? '').toString();
                          final specialty =
                              (data['Specialty'] ?? '').toString();

                          DateTime? asDate(dynamic v) {
                            if (v == null) return null;
                            if (v is DateTime) return v;
                            if (v is Timestamp) return v.toDate();
                            if (v is String && v.isNotEmpty)
                              return DateTime.tryParse(v);
                            return null;
                          }

                          String effectiveStatusFromDates({
                            required DateTime? start,
                            required DateTime? end,
                            required String? storedStatus,
                          }) {
                            final now = DateTime.now();

                            // manual close
                            if ((storedStatus ?? '').toLowerCase() == 'closed')
                              return 'Closed';

                            final endOfDay = end != null ? DateTime(end.year, end.month, end.day, 23, 59, 59) : null;
                            if (endOfDay != null && endOfDay.isBefore(now))
                              return 'Closed';
                            if (start != null && start.isAfter(now))
                              return 'Soon';
                            return 'Open';
                          }

                          final startDate = asDate(data['StartDate']);
                          final endDate = asDate(data['EndDate']);
                          final storedStatus =
                              (data['JobStatus'] ?? 'Open').toString();

                          final status = effectiveStatusFromDates(
                            start: startDate,
                            end: endDate,
                            storedStatus: storedStatus,
                          );

                          final isClosed = status == 'Closed';
                          final isSoon = status == 'Soon';

                          final theme = Theme.of(context);
                          final scheme = theme.colorScheme;
                          final primary = scheme.primary;
                          final onSurface = scheme.onSurface;
                          final isDark = theme.brightness == Brightness.dark;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 20,
                                  offset: const Offset(0, 4),
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  Navigator.pushNamed(
                                    context,
                                    '/questions',
                                    arguments: {
                                      'jobId': doc.id,
                                      'locked': true,
                                    },
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  title,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 18,
                                                    color: (isClosed || isSoon)
                                                        ? onSurface
                                                            .withOpacity(0.6)
                                                        : onSurface,
                                                    letterSpacing: -0.5,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  [position, specialty]
                                                      .where(
                                                          (e) => e.isNotEmpty)
                                                      .join(' / '),
                                                  style: TextStyle(
                                                    color: (isClosed || isSoon)
                                                        ? onSurface
                                                            .withOpacity(0.5)
                                                        : onSurface
                                                            .withOpacity(0.7),
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Badge: Closed / Soon
                                          if (isClosed || isSoon)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: isClosed
                                                    ? Colors.grey.shade600
                                                    : Colors.amber
                                                        .withOpacity(0.18),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                isClosed ? 'Closed' : 'Soon',
                                                style: TextStyle(
                                                  color: isClosed
                                                      ? Colors.white
                                                      : const Color(0xFFB8860B),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Container(
                                              height: 42,
                                              decoration: BoxDecoration(
                                                color: primary.withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  onTap: () async {
                                                    final canProceed =
                                                        await _checkProfileComplete();
                                                    if (!canProceed || !mounted)
                                                      return;

                                                    final start =
                                                        data['StartDate'];
                                                    final end = data['EndDate'];

                                                    await _showEditDatesDialog(
                                                      doc.id,
                                                      title,
                                                      start,
                                                      end,
                                                      context,
                                                    );
                                                  },
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(Icons.edit_outlined,
                                                          color: primary,
                                                          size: 20),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        'Edit',
                                                        style: TextStyle(
                                                          color: primary,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Container(
                                              height: 42,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF4A5FBC)
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  onTap: () {
                                                    Navigator.pushNamed(
                                                      context,
                                                      '/questions',
                                                      arguments: {
                                                        'jobId': doc.id,
                                                        'locked': true,
                                                      },
                                                    );
                                                  },
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                          Icons
                                                              .visibility_outlined,
                                                          color: primary,
                                                          size: 20),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        'View',
                                                        style: TextStyle(
                                                          color: primary,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Container(
                                            width: 42,
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? scheme.surface
                                                      .withOpacity(0.9)
                                                  : Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                onTap: () {
                                                  final safeCtx =
                                                      _scaffoldKey
                                                          .currentContext;
                                                  if (safeCtx == null) return;

                                                  showDialog(
                                                    context: safeCtx,
                                                    builder: (dialogContext) =>
                                                        AlertDialog(
                                                      backgroundColor:
                                                          const Color(
                                                                  0xFF4A5FBC)
                                                              .withOpacity(
                                                                  0.7),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(30),
                                                      ),
                                                      contentPadding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                              vertical: 10),
                                                      content: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          InkWell(
                                                            onTap: () {
                                                              Navigator.pop(
                                                                  dialogContext);
                                                              _closeJob(
                                                                doc.id,
                                                                isClosed,
                                                                safeCtx,
                                                                endDate,
                                                              );
                                                            },
                                                            child: Padding(
                                                              padding: const EdgeInsets
                                                                  .symmetric(
                                                                  vertical: 14),
                                                              child: Row(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .center,
                                                                children: [
                                                                  Icon(
                                                                    isClosed
                                                                        ? Icons
                                                                            .lock_open_outlined
                                                                        : Icons
                                                                            .lock_outline,
                                                                    color: Colors
                                                                        .white,
                                                                    size: 26,
                                                                  ),
                                                                  const SizedBox(
                                                                      width:
                                                                          10),
                                                                  Text(
                                                                    isClosed
                                                                        ? 'Reopen Job'
                                                                        : 'Close Job',
                                                                    style: const TextStyle(
                                                                        color: Colors
                                                                            .white,
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                        fontSize:
                                                                            16),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                          const Divider(
                                                              color: Colors
                                                                  .white24,
                                                              height: 1),
                                                          InkWell(
                                                            onTap: () {
                                                              Navigator.pop(
                                                                  dialogContext);
                                                              _deleteJob(
                                                                doc.id,
                                                                title,
                                                                safeCtx,
                                                              );
                                                            },
                                                            child: Padding(
                                                              padding: const EdgeInsets
                                                                  .symmetric(
                                                                  vertical: 14),
                                                              child: Row(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .center,
                                                                children: const [
                                                                  Icon(
                                                                      Icons
                                                                          .delete_outline,
                                                                      color: Color(
                                                                          0xFFFF7B7B),
                                                                      size: 26),
                                                                  SizedBox(
                                                                      width:
                                                                          10),
                                                                  Text(
                                                                    'Delete Job',
                                                                    style: TextStyle(
                                                                        color: Color(
                                                                            0xFFFF7B7B),
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                        fontSize:
                                                                            16),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: Icon(
                                                  Icons.more_vert,
                                                  color: scheme.onSurface
                                                      .withOpacity(0.6),
                                                  size: 22,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            ThemedScaffold(
              key: _scaffoldKey,
              appBar: _buildCustomAppBar(companyId),
              body: IndexedStack(
                index: _tab,
                children: [
                  CompanyReportsPage(companyId: companyId),
                  homeBody,
                ],
              ),
              bottomNavigationBar: _buildAnimatedNavBar(),
            ),
            if (_tab == 1)
              _MovableFab(
                onPressed: () async {
                  final canProceed = await _checkProfileComplete();
                  if (canProceed && mounted) {
                    await Navigator.pushNamed(context, '/job-posting');
                    if (mounted) {
                      setState(() {});
                    }
                  }
                },
              ),
          ],
        );
      },
    );
  }
}

class _WelcomeTitle extends StatelessWidget {
  const _WelcomeTitle({required this.companyId});
  final String companyId;

  Stream<String> _companyNameStream() {
    if (companyId.isEmpty) return Stream.value('Company');

    return FirebaseFirestore.instance
        .collection('Users')
        .doc(companyId)
        .snapshots()
        .map((snap) {
      final data = snap.data() ?? {};
      final name =
          (data['CompanyName'] ?? data['companyName'] ?? '').toString().trim();
      return name.isEmpty ? 'Company' : name;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: _companyNameStream(),
      builder: (context, snap) {
        final name = (snap.data ?? 'Company').trim();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome back,',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text('Job Posts',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Spacer(),
        ],
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.userId});
  final String userId;

  Stream<Map<String, dynamic>> _userMiniStream() {
    if (userId.isEmpty) {
      return Stream.value({
        'name': 'Company',
        'photo': null,
        'complete': false,
      });
    }
    return FirebaseFirestore.instance
        .collection('Users')
        .doc(userId)
        .snapshots()
        .map((snap) {
      final d = snap.data() ?? {};
      return {
        'name': (d['CompanyName'] ?? '').toString().trim(),
        'photo': (d['PhotoURL'] ?? '').toString().trim(),
        'complete': d['IsProfileComplete'] == true,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: _userMiniStream(),
      builder: (context, snap) {
        final photo = (snap.data?['photo'] ?? '').toString();
        final complete = (snap.data?['complete'] == true);
        final name = (snap.data?['name'] ?? '').toString();

        String initials = '';
        if (name.isNotEmpty) {
          final parts = name.split(' ').where((s) => s.isNotEmpty).toList();
          if (parts.length >= 2) {
            initials = (parts[0][0] + parts[1][0]).toUpperCase();
          } else if (parts.isNotEmpty) {
            initials = name.substring(0, name.length > 1 ? 2 : 1).toUpperCase();
          }
        }

        final avatar = Hero(
          tag: 'profileAvatar',
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: CircleAvatar(
                  radius: 22,
                  backgroundImage:
                      photo.isNotEmpty ? NetworkImage(photo) : null,
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  child: photo.isEmpty && initials.isNotEmpty
                      ? Text(
                          initials,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        )
                      : (photo.isEmpty
                          ? const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 28,
                            )
                          : null),
                ),
              ),
            ],
          ),
        );

        return Tooltip(
          message: complete ? 'Profile complete' : 'Profile incomplete',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              Navigator.pushNamed(context, '/profile/company');
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: avatar,
            ),
          ),
        );
      },
    );
  }
}

class _CompactReportFeature extends StatelessWidget {
  final IconData icon;
  final String title;

  const _CompactReportFeature({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBarClipper extends CustomClipper<Path> {
  final double circlePosition;
  final double circleRadius;

  _BottomBarClipper({
    required this.circlePosition,
    required this.circleRadius,
  });

  @override
  Path getClip(Size size) {
    final path = Path();
    path.addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    path.addOval(
      Rect.fromCircle(
        center: Offset(circlePosition, 0),
        radius: circleRadius,
      ),
    );
    path.fillType = PathFillType.evenOdd;
    return path;
  }

  @override
  bool shouldReclip(_BottomBarClipper oldClipper) {
    return oldClipper.circlePosition != circlePosition;
  }
}

class _MovableFab extends StatefulWidget {
  final Future<void> Function() onPressed;

  const _MovableFab({required this.onPressed});

  @override
  State<_MovableFab> createState() => _MovableFabState();
}

class _MovableFabState extends State<_MovableFab> {
  double _fabX = 0;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    if (_fabX == 0) {
      _fabX = screenWidth - 180;
    }

    const double minX = 16;
    final double maxX = screenWidth - 180;

    if (_fabX < minX) _fabX = minX;
    if (_fabX > maxX) _fabX = maxX;

    return Positioned(
      bottom: 110,
      left: _fabX,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          setState(() {
            _fabX += details.delta.dx;
            if (_fabX < minX) _fabX = minX;
            if (_fabX > maxX) _fabX = maxX;
          });
        },
        child: FloatingActionButton.extended(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          icon: const Icon(Icons.add),
          label: const Text(
            'Create Job Post',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          onPressed: () async {
            await widget.onPressed();
          },
        ),
      ),
    );
  }
}
