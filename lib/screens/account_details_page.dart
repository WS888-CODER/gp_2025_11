// lib/screens/account_details_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gp_2025_11/l10n/app_localizations.dart'; 

class AccountDetailsPage extends StatelessWidget {
  final String userId;
  final String userType;

  const AccountDetailsPage({
    super.key,
    required this.userId,
    required this.userType,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isJobSeeker = userType == 'JobSeeker';
    final brandColor = const Color(0xFF4A5FBC);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Details'), 
        backgroundColor: brandColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            tooltip: 'Edit Profile',
            onPressed: () {
              final profileRoute = isJobSeeker ? '/profile/jobseeker' : '/profile/company';
              Navigator.pushNamed(context, profileRoute);
            },
          ),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance.collection('Users').doc(userId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Failed to load user data.'));
          }

          final userData = snapshot.data!.data()!;
          
          final registeredFullName = userData['Name'] ?? 'N/A';
          final registeredEmail = userData['Email'] ?? 'N/A';
          final companyName = userData['CompanyName'] ?? 'N/A';

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 1. الاسم الكامل (Full Name) - مطلوب للجميع
              _DetailCard(
                icon: Icons.person,
                label: l10n.fullNameLabel,
                value: registeredFullName,
              ),

              // 2. اسم الشركة (للشركات فقط)
              if (!isJobSeeker) 
                _DetailCard(
                  icon: Icons.business,
                  label: l10n.companyNameLabel, 
                  value: companyName,
                ),
                
              // 3. البريد الإلكتروني (Registered Email) - مطلوب للجميع
              _DetailCard(
                icon: Icons.email,
                label: l10n.registeredEmailLabel,
                value: registeredEmail,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ويدجت لعرض التفاصيل بشكل منظم
class _DetailCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  
  const _DetailCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.only(bottom: 15),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF4A5FBC)),
        title: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        subtitle: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}