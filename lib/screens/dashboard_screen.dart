import 'package:flutter/material.dart';
import 'admin_dashboard_screen.dart';
import 'hissa_configuration_screen.dart';
import 'qurbani_status_screen.dart';
import 'booking_history_screen.dart';
import 'dart:convert';
import '../services/database_service.dart';
import '../models/form_settings.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _orgName = 'Qurbani Management';
  String _logoBase64 = '';

  @override
  void initState() {
    super.initState();
    _loadBranding();
  }

  Future<void> _loadBranding() async {
    final settings = await DatabaseService.loadFormSettings();
    setState(() {
      _orgName = settings.organizationName;
      _logoBase64 = settings.logoBase64;
    });
  }

  void _navigateToAdmin() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen())).then((_) => _loadBranding());
  }


  Widget _buildDashboardCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))
          ],
          border: Border.all(color: color.withOpacity(0.15), width: 1.0),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.2)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade300, size: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                   if (_logoBase64.isNotEmpty) 
                     Container(
                       padding: const EdgeInsets.all(8),
                       decoration: BoxDecoration(
                         color: Colors.white,
                         borderRadius: BorderRadius.circular(12),
                         boxShadow: [
                           BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))
                         ],
                       ),
                       child: ClipRRect(
                         borderRadius: BorderRadius.circular(8),
                         child: Image.memory(
                           const Base64Decoder().convert(_logoBase64.contains(',') ? _logoBase64.split(',').last : _logoBase64),
                           width: 42,
                           height: 42,
                           fit: BoxFit.contain,
                         ),
                       ),
                     )
                   else
                     Container(
                       padding: const EdgeInsets.all(10),
                       decoration: BoxDecoration(
                         color: theme.colorScheme.primary.withOpacity(0.1),
                         borderRadius: BorderRadius.circular(12),
                       ),
                       child: Icon(Icons.mosque, color: theme.colorScheme.primary, size: 28),
                     ),
                  
                  const SizedBox(width: 16),
                  
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _orgName,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -0.5, height: 1.1),
                        ),
                        const SizedBox(height: 4),
                        Text('Select a module below to proceed.', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              _buildDashboardCard(
                context,
                title: 'Master Module',
                subtitle: 'Admin panel to configure everything.',
                icon: Icons.admin_panel_settings,
                color: Colors.blueGrey.shade700,
                onTap: _navigateToAdmin,
              ),

              const SizedBox(height: 12),

              _buildDashboardCard(
                context,
                title: 'New Booking',
                subtitle: 'Register customer for Qurbani Hissah.',
                icon: Icons.app_registration,
                color: theme.colorScheme.primary,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const HissaConfigurationScreen()));
                },
              ),

              const SizedBox(height: 12),

              _buildDashboardCard(
                context,
                title: 'Live Tracking Board',
                subtitle: 'Monitor tokens and confirm executed Qurbanis.',
                icon: Icons.fact_check_rounded,
                color: Colors.teal.shade800,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const QurbaniStatusScreen()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
