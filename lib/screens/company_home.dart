// lib/screens/company_home.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gp_2025_11/config/theme.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
import 'dart:async';

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
  static const Color _brand = Color(0xFF4A5FBC);
  int _tab = 1; // 0: Reports, 1: Home
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

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
                      onSurface: Colors.white, // السنوات والأرقام
                      surface: const Color(0xFF4A5FBC).withOpacity(0.95),
                    ),
                    textTheme: theme.textTheme.copyWith(
                      // نص السنوات
                      bodyLarge: const TextStyle(color: Colors.white),
                      // نص الأرقام في الكاليندر
                      bodyMedium: const TextStyle(color: Colors.white),
                      // نص التاريخ المختار
                      headlineMedium: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                      // نص السنة في الـ header
                      titleLarge: const TextStyle(color: Colors.white),
                    ),
                    inputDecorationTheme: InputDecorationTheme(
                      // للـ Input mode (لما تضغطين القلم)
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
                        foregroundColor:
                            const Color(0xFFFC686A), // أزرار OK و Cancel
                      ),
                    ),
                    datePickerTheme: DatePickerThemeData(
                      backgroundColor:
                          const Color(0xFF4A5FBC).withOpacity(0.95),
                      headerForegroundColor: Colors.white,
                      weekdayStyle: const TextStyle(color: Colors.white),
                      yearStyle: const TextStyle(color: Colors.white),
                      dayStyle: const TextStyle(
                          color: Colors.white), // الأيام في الشبكة
                      yearForegroundColor:
                          MaterialStateColor.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Colors.white; // السنة المختارة
                        }
                        return Colors.white; // باقي السنوات
                      }),
                      yearBackgroundColor:
                          MaterialStateColor.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return const Color(
                              0xFFFC686A); // خلفية السنة المختارة
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
                      onSurface: Colors.white, // السنوات والأرقام
                      surface: const Color(0xFF4A5FBC).withOpacity(0.95),
                    ),
                    textTheme: theme.textTheme.copyWith(
                      // نص السنوات
                      bodyLarge: const TextStyle(color: Colors.white),
                      // نص الأرقام في الكاليندر
                      bodyMedium: const TextStyle(color: Colors.white),
                      // نص التاريخ المختار
                      headlineMedium: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                      // نص السنة في الـ header
                      titleLarge: const TextStyle(color: Colors.white),
                    ),
                    inputDecorationTheme: InputDecorationTheme(
                      // للـ Input mode (لما تضغطين القلم)
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
                        foregroundColor:
                            const Color(0xFFFC686A), // أزرار OK و Cancel
                      ),
                    ),
                    datePickerTheme: DatePickerThemeData(
                      backgroundColor:
                          const Color(0xFF4A5FBC).withOpacity(0.95),
                      headerForegroundColor: Colors.white,
                      weekdayStyle: const TextStyle(color: Colors.white),
                      yearStyle: const TextStyle(color: Colors.white),
                      dayStyle: const TextStyle(
                          color: Colors.white), // الأيام في الشبكة
                      yearForegroundColor:
                          MaterialStateColor.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Colors.white; // السنة المختارة
                        }
                        return Colors.white; // باقي السنوات
                      }),
                      yearBackgroundColor:
                          MaterialStateColor.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return const Color(
                              0xFFFC686A); // خلفية السنة المختارة
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
            backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.95),
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
        await FirebaseFirestore.instance.collection('Jobs').doc(jobId).update({
          'StartDate': result['startDate'],
          'EndDate': result['endDate'],
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
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.95),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Job Expired',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            content: Text(
              'This job expired on ${endDate.day}/${endDate.month}/${endDate.year}.\n\nTo reopen it, please select a new end date.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.9),
                  foregroundColor: const Color(0xFF4A5FBC),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Cancel',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFFD6C67),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Select New Date',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            actionsAlignment: MainAxisAlignment.center,
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
                  surface: const Color(0xFF4A5FBC).withOpacity(0.95),
                ),
                textTheme: theme.textTheme.copyWith(
                  // نص السنوات
                  bodyLarge: const TextStyle(color: Colors.white),
                  // نص الأرقام في الكاليندر
                  bodyMedium: const TextStyle(color: Colors.white),
                  // نص التاريخ المختار
                  headlineMedium: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                  // نص السنة في الـ header
                  titleLarge: const TextStyle(color: Colors.white),
                ),
                inputDecorationTheme: InputDecorationTheme(
                  // للـ Input mode (لما تضغطين القلم)
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
                    foregroundColor:
                        const Color(0xFFFC686A), // أزرار OK و Cancel
                  ),
                ),
                datePickerTheme: DatePickerThemeData(
                  backgroundColor: const Color(0xFF4A5FBC).withOpacity(0.95),
                  headerForegroundColor: Colors.white,
                  weekdayStyle: const TextStyle(color: Colors.white),
                  yearStyle: const TextStyle(color: Colors.white),
                  dayStyle:
                      const TextStyle(color: Colors.white), // الأيام في الشبكة
                  yearForegroundColor: MaterialStateColor.resolveWith((states) {
                    if (states.contains(MaterialState.selected)) {
                      return Colors.white; // السنة المختارة
                    }
                    return Colors.white; // باقي السنوات
                  }),
                  yearBackgroundColor: MaterialStateColor.resolveWith((states) {
                    if (states.contains(MaterialState.selected)) {
                      return const Color(0xFFFC686A); // خلفية السنة المختارة
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

        // Update both JobStatus and EndDate
        await FirebaseFirestore.instance.collection('Jobs').doc(jobId).update({
          'JobStatus': 'Open',
          'EndDate': newEndDate,
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

  Widget _buildAnimatedNavBar() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        // الـ Bottom Bar مع القطع (notch)
        ClipPath(
          clipper: _BottomBarClipper(
            circlePosition: _getCirclePosition() + 30,
            circleRadius: 45,
          ),
          child: Container(
            height: 70,
            decoration: const BoxDecoration(
              color: Colors.white,
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

        // الدائرة المتحركة البارزة
        AnimatedPositioned(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
          left: _getCirclePosition(),
          bottom: 35,
          child: Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFFC686A),
            ),
            child: Icon(
              _getSelectedIcon(),
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
      ],
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

  Widget _buildNavIcon(IconData icon, int index) {
    final isSelected = _tab == index;
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
          color: isSelected ? Colors.transparent : Colors.grey[400],
        ),
      ),
    );
  }

  Stream<String> _companyNameStream(String companyId) {
    if (companyId.isEmpty) return Stream.value(widget.fallbackCompanyName);

    return FirebaseFirestore.instance
        .collection('Users')
        .doc(companyId)
        .snapshots()
        .map((snap) {
      final data = snap.data() ?? {};
      final name =
          (data['CompanyName'] ?? data['companyName'] ?? '').toString().trim();
      return name.isEmpty ? widget.fallbackCompanyName : name;
    });
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
      print("Error in _jobsStream: $e");
      return Stream.error(e);
    }
  }

  PreferredSizeWidget _buildCustomAppBar(String companyId) {
    // For Reports tab, use standard AppBar
    if (_tab != 1) {
      return AppBar(
        backgroundColor: _brand,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false, // ← نشيل السهم الخلفي
        leadingWidth: 70, // ← نعطيه مساحة أكبر
        leading: Padding(
          // ← نحطه في Padding
          padding: const EdgeInsets.only(left: 16), // ← نبعده عن الحافة
          child: _ProfileButton(userId: companyId),
        ),
        title: const Text(
          'Reports',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none, color: Colors.white),
            onPressed: () => SnackHelper.error(
                context, 'Notifications will be available soon'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                Navigator.pushNamed(
                  context,
                  '/settings',
                  arguments: {'userType': 'Company', 'userId': uid},
                );
              }
            },
          ),
        ],
      );
    }

    // For home tab, use custom purple gradient header
    return PreferredSize(
      preferredSize: const Size.fromHeight(200),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4A5FBC), Color(0xFF4A5FBC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row with profile, notification, and settings
                Row(
                  children: [
                    // Profile button
                    _ProfileButton(userId: companyId),
                    const Spacer(),
                    // Notification button
                    GestureDetector(
                      onTap: () {
                        SnackHelper.error(context, 'Notifications coming soon');
                      },
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.notifications_outlined,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Settings button
                    GestureDetector(
                      onTap: () {
                        final uid = FirebaseAuth.instance.currentUser?.uid;
                        if (uid != null) {
                          Navigator.pushNamed(
                            context,
                            '/settings',
                            arguments: {'userType': 'Company', 'userId': uid},
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
                // Welcome text
                _WelcomeTitle(companyId: companyId),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final companyId = _effectiveCompanyId;

    final homeBody = Container(
      color: const Color(0xFF4A5FBC),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: ListView(
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
                        return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.work_outline,
                                size: 40,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.4),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No job posts yet',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tap "Create Job Post" to add your first opening.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.7),
                                    ),
                              ),
                            ],
                          ),
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
                          final endDateField = data['EndDate'];
                          DateTime? endDate;
                          if (endDateField is Timestamp) {
                            endDate = endDateField.toDate();
                          }
                          final now = DateTime.now();

                          final jobStatus =
                              (data['JobStatus'] ?? 'Open').toString();
                          final isClosed = jobStatus == 'Closed' ||
                              (endDate != null && endDate.isBefore(now));

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
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
                                                    color: isClosed
                                                        ? Colors.black54
                                                        : Colors.black87,
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
                                                    color: isClosed
                                                        ? Colors.black38
                                                        : Colors.black54,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (isClosed)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 6),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFFE5E5),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: const Text(
                                                'Closed',
                                                style: TextStyle(
                                                  color: Color(0xFFFF5252),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          // Edit button
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
                                                  child: const Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                        Icons.edit_outlined,
                                                        color:
                                                            Color(0xFF4A5FBC),
                                                        size: 20,
                                                      ),
                                                      SizedBox(width: 6),
                                                      Text(
                                                        'Edit',
                                                        style: TextStyle(
                                                          color:
                                                              Color(0xFF4A5FBC),
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
                                          // View button
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
                                                  child: const Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .visibility_outlined,
                                                        color:
                                                            Color(0xFF4A5FBC),
                                                        size: 20,
                                                      ),
                                                      SizedBox(width: 6),
                                                      Text(
                                                        'View',
                                                        style: TextStyle(
                                                          color:
                                                              Color(0xFF4A5FBC),
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
                                          // More menu
                                          Container(
                                            width: 42,
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                onTap: () {
                                                  final safeCtx = _scaffoldKey
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
                                                                  0.95),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(20),
                                                      ),
                                                      contentPadding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                              vertical: 10),
                                                      content: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          ListTile(
                                                            leading: Icon(
                                                              isClosed
                                                                  ? Icons
                                                                      .lock_open_outlined
                                                                  : Icons
                                                                      .lock_outline,
                                                              color:
                                                                  Colors.white,
                                                              size: 22,
                                                            ),
                                                            title: Text(
                                                              isClosed
                                                                  ? 'Reopen Job'
                                                                  : 'Close Job',
                                                              style:
                                                                  const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                            onTap: () {
                                                              Navigator.pop(
                                                                  dialogContext);
                                                              _closeJob(
                                                                  doc.id,
                                                                  isClosed,
                                                                  safeCtx,
                                                                  endDate);
                                                            },
                                                          ),
                                                          const Divider(
                                                            color:
                                                                Colors.white24,
                                                            height: 1,
                                                          ),
                                                          ListTile(
                                                            leading: const Icon(
                                                              Icons
                                                                  .delete_outline,
                                                              color: Color(
                                                                  0xFFFF7B7B),
                                                              size: 22,
                                                            ),
                                                            title: const Text(
                                                              'Delete Job',
                                                              style: TextStyle(
                                                                color: Color(
                                                                    0xFFFF7B7B),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                            onTap: () {
                                                              Navigator.pop(
                                                                  dialogContext);
                                                              _deleteJob(
                                                                  doc.id,
                                                                  title,
                                                                  safeCtx);
                                                            },
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: const Icon(
                                                  Icons.more_vert,
                                                  color: Colors.black54,
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

    return ThemedScaffold(
      floatingActionButton: _tab == 1
          ? Padding(
              padding: const EdgeInsets.only(bottom: 30, right: 0),
              child: FloatingActionButton.extended(
                backgroundColor: _brand,
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
                  final canProceed = await _checkProfileComplete();
                  if (canProceed && mounted) {
                    await Navigator.pushNamed(context, '/job-posting');
                    if (mounted) setState(() {});
                  }
                },
              ),
            )
          : null,
      key: _scaffoldKey,
      appBar: _buildCustomAppBar(companyId),
      body: IndexedStack(
        index: _tab,
        children: [
          // Reports tab - Coming Soon
          Container(
            color: const Color(0xFF4A5FBC),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(30),
                        topRight: Radius.circular(30),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Icon with coral gradient
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFD6C67), Color(0xFFFF8A87)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFFFD6C67).withOpacity(0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.assessment_rounded,
                              size: 40,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Title
                          const Text(
                            'Reports',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                              letterSpacing: -0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),

                          // Coming Soon badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4A5FBC).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: const Color(0xFF4A5FBC).withOpacity(0.3),
                                width: 2,
                              ),
                            ),
                            child: const Text(
                              'Coming Soon',
                              style: TextStyle(
                                color: Color(0xFF4A5FBC),
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Description
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              'Comprehensive AI-powered evaluation reports for every candidate interview.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black.withOpacity(0.6),
                                height: 1.5,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Feature list - compact
                          _CompactReportFeature(
                            icon: Icons.description_outlined,
                            title: 'CV Evaluation',
                          ),
                          const SizedBox(height: 12),
                          _CompactReportFeature(
                            icon: Icons.psychology_outlined,
                            title: 'Psychometric Analysis',
                          ),
                          const SizedBox(height: 12),
                          _CompactReportFeature(
                            icon: Icons.mic_outlined,
                            title: 'Voice Tone Analysis',
                          ),

                          const SizedBox(height: 20),

                          // Footer
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF4A5FBC).withOpacity(0.05),
                                  const Color(0xFFFD6C67).withOpacity(0.05),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 16,
                                  color:
                                      const Color(0xFF4A5FBC).withOpacity(0.7),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Plus much more!',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: const Color(0xFF4A5FBC)
                                        .withOpacity(0.8),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          homeBody,
        ],
      ),
      bottomNavigationBar: _buildAnimatedNavBar(),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.black.withOpacity(0.06),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF4A5FBC).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: const Color(0xFF4A5FBC),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
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
