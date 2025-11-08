import 'package:flutter/material.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';

class QuestionsPage extends StatefulWidget {
  const QuestionsPage({super.key});

  @override
  State<QuestionsPage> createState() => _QuestionsPageState();
}

class _QuestionsPageState extends State<QuestionsPage> {
  String? _jobId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        _jobId = args['jobId'] as String?;
        setState(() {});
      }
    });
  }

  void _navigateBackToJobPosting() {
    if (_jobId != null) {
      Navigator.pushReplacementNamed(
        context,
        '/job_posting',
        arguments: {
          'jobId': _jobId,
          'fromQuestionsPage': true,
        },
      );
    } else {
      Navigator.pop(context);
    }
  }

  void _done() {
    // Close the questions page and go back to company home
    Navigator.popUntil(context, (route) => route.isFirst);
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
          title: const Text('Job Questions'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _navigateBackToJobPosting,
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        // Done button at the bottom
                        ElevatedButton(
                          onPressed: _done,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4A5FBC),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: const Text(
                            'Done',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
