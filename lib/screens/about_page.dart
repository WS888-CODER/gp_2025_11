// lib/screens/about_page.dart
import 'package:flutter/material.dart';
import 'package:gp_2025_11/config/themed_scaffold.dart';
import 'package:url_launcher/url_launcher.dart'; // for email launch

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const Color _brand = Color(0xFF4A5FBC);
  static const String _contactEmail = 'jadeergp2025@gmail.com';

  Future<void> _launchEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: _contactEmail,
      queryParameters: {
        'subject': 'Contact from Jadeer App',
      },
    );
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return ThemedScaffold(
      appBar: AppBar(
        title: const Text(
          'About',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          // Gradient header section
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF4A5FBC),
                    Color(0xFF6B7EF3),
                  ],
                ),
              ),
              child: Column(
                children: [
                  // ✅ Logo badge with subtle elevation + glow
                  Container(
                    width: 95,
                    height: 95,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(.15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Colors.white.withOpacity(0.15),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                      image: const DecorationImage(
                        image: AssetImage('assets/images/logo.jpg'),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    'Jadeer',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                  ),
                  const SizedBox(height: 4),

                  Text(
                    'Smart Recruitment Platform',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withOpacity(.85),
                          fontSize: 15,
                        ),
                  ),

                  const SizedBox(height: 12),

                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.15),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(.15),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Text(
                      'Version 1.0.0',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Body content
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            sliver: SliverList.list(
              children: [
                _InfoCard(
                  icon: Icons.lightbulb_outline,
                  iconTint: Colors.amber,
                  title: 'About Jadeer',
                  child: Text(
                    'Jadeer is a smart recruitment platform designed to seamlessly connect companies with qualified job seekers. '
                    'It aims to simplify the hiring process and empower individuals to find opportunities that match their skills and ambitions.',
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  icon: Icons.groups_2_outlined,
                  iconTint: Colors.teal,
                  title: 'Developed by',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'King Saud University – IT Students (Class of 2026)',
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Under the supervision of the College of Computer and Information Sciences.',
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Contact section
                _InfoCard(
                  icon: Icons.email_outlined,
                  iconTint: Colors.indigo,
                  title: 'Contact Us',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'For inquiries or feedback, reach out to us at:',
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _launchEmail,
                        child: Text(
                          _contactEmail,
                          style: text.bodyMedium?.copyWith(
                            color: _brand,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* -------------------- reusable widget -------------------- */

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconTint;
  final String title;
  final Widget child;

  const _InfoCard({
    required this.icon,
    required this.iconTint,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconTint.withOpacity(.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconTint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
