import 'package:flutter/material.dart';
import 'admin_dashboard_screen.dart';
import 'hissa_configuration_screen.dart';
import 'qurbani_status_screen.dart';

import 'dart:convert';
import '../services/database_service.dart';
import '../models/form_settings.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const Color _brand = Color(0xFF0D5C46);
  String _orgName = 'Qurbani Management';
  String _logoBase64 = '';

  @override
  void initState() {
    super.initState();
    _loadBranding();
  }

  Future<void> _loadBranding() async {
    // 1. Load from cache for instant logo/name
    final cachedSettings = await DatabaseService.loadFormSettings(useCache: true);
    if (mounted) {
      setState(() {
        _orgName = cachedSettings.organizationName;
        _logoBase64 = cachedSettings.logoBase64;
      });
    }

    // 2. Fetch fresh from network
    final settings = await DatabaseService.loadFormSettings();
    if (mounted) {
      setState(() {
        _orgName = settings.organizationName;
        _logoBase64 = settings.logoBase64;
      });
    }
  }

  /// Show admin login dialog. Returns true if verified.
  Future<bool> _verifyAdmin() async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool isVerifying = false;
    bool obscurePass = true;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> doLogin() async {
            if (emailCtrl.text.isEmpty || passCtrl.text.isEmpty) return;
            setDialogState(() => isVerifying = true);
            final ok = await DatabaseService.verifyAdmin(emailCtrl.text.trim(), passCtrl.text);
            if (ok) {
              Navigator.pop(ctx, true);
            } else {
              setDialogState(() => isVerifying = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invalid credentials'), backgroundColor: Colors.red),
              );
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: _brand.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.admin_panel_settings, color: _brand, size: 24),
                ),
                const SizedBox(width: 12),
                const Text('Admin Login', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email_outlined, color: _brand),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  obscureText: obscurePass,
                  onSubmitted: (_) => doLogin(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline, color: _brand),
                    suffixIcon: IconButton(
                      icon: Icon(obscurePass ? Icons.visibility_off : Icons.visibility, size: 20),
                      onPressed: () => setDialogState(() => obscurePass = !obscurePass),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: isVerifying ? null : doLogin,
                style: ElevatedButton.styleFrom(backgroundColor: _brand, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: isVerifying
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Login'),
              ),
            ],
          );
        },
      ),
    );
    return result == true;
  }

  void _navigateToAdmin() async {
    if (await _verifyAdmin()) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen())).then((_) => _loadBranding());
    }
  }

  void _navigateToTracking() async {
    if (await _verifyAdmin()) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const QurbaniStatusScreen()));
    }
  }

  Widget _buildDashboardCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isLocked = false,
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
            if (isLocked)
              Icon(Icons.lock, color: Colors.grey.shade400, size: 18),
            const SizedBox(width: 4),
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
                        Text('Qurbani Hissah Management', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // PUBLIC — Everyone can access
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('BOOKING', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 1.2)),
              ),

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

              const SizedBox(height: 24),

              // ADMIN ONLY — Requires PIN
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('ADMIN ONLY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 1.2)),
              ),

              _buildDashboardCard(
                context,
                title: 'Master Module',
                subtitle: 'Configure categories, settings & branding.',
                icon: Icons.admin_panel_settings,
                color: Colors.blueGrey.shade700,
                onTap: _navigateToAdmin,
                isLocked: true,
              ),

              const SizedBox(height: 12),

              _buildDashboardCard(
                context,
                title: 'Live Tracking Board',
                subtitle: 'Monitor tokens, history & export reports.',
                icon: Icons.fact_check_rounded,
                color: Colors.teal.shade800,
                onTap: _navigateToTracking,
                isLocked: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
