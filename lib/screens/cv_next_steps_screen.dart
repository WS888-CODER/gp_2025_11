import 'package:flutter/material.dart';
import '../config/theme.dart';

class CVNextStepsScreen extends StatefulWidget {
  final String? cvHistoryId;
  final String? jobTitle;
  final bool hasJobSelection;

  const CVNextStepsScreen({
    super.key,
    this.cvHistoryId,
    this.jobTitle,
    this.hasJobSelection = false,
  });

  @override
  State<CVNextStepsScreen> createState() => _CVNextStepsScreenState();
}

class _CVNextStepsScreenState extends State<CVNextStepsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryPurple,
        foregroundColor: Colors.white,
        title: const Text('Next Steps'),
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 100,
                color: AppTheme.primaryPurple,
              ),
              const SizedBox(height: 20),
              const Text(
                'CV Uploaded Successfully!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryPurple,
                ),
              ),
              const SizedBox(height: 10),
              if (widget.hasJobSelection && widget.jobTitle != null)
                Text(
                  'Selected Job: ${widget.jobTitle}',
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 30),
              // هنا بتضيفين الخطوات التالية لاحقاً
              const Text(
                'What would you like to do next?',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
