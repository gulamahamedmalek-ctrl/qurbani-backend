import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  static const String _adminKey = 'admin_logged_in';
  String _orgName = 'Qurbani Management';
  String _logoBase64 = '';
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadBranding();
    _checkAdminSession();
  }

  Future<void> _checkAdminSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _isAdmin = prefs.getBool(_adminKey) ?? false);
    }
  }

  Future<void> _loadBranding() async {
    final cachedSettings = await DatabaseService.loadFormSettings(useCache: true);
    if (mounted) {
      setState(() {
        _orgName = cachedSettings.organizationName;
        _logoBase64 = cachedSettings.logoBase64;
      });
    }
    final settings = await DatabaseService.loadFormSettings();
    if (mounted) {
      setState(() {
        _orgName = settings.organizationName;
        _logoBase64 = settings.logoBase64;
      });
    }
  }

  /// Admin login dialog
  Future<void> _handleAdminLogin() async {
    // Already logged in → go straight to admin hub
    if (_isAdmin) {
      _openAdminHub();
      return;
    }

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
              // Persist admin session
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool(_adminKey, true);
              Navigator.pop(ctx, true);
            } else {
              setDialogState(() => isVerifying = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invalid email or password'), backgroundColor: Colors.red),
              );
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            title: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _brand.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.admin_panel_settings, color: _brand, size: 32),
                ),
                const SizedBox(height: 12),
                const Text('Admin Login', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                const SizedBox(height: 4),
                Text('Sign in to access admin features', style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.normal)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email_outlined, color: _brand),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passCtrl,
                  obscureText: obscurePass,
                  onSubmitted: (_) => doLogin(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline, color: _brand),
                    suffixIcon: IconButton(
                      icon: Icon(obscurePass ? Icons.visibility_off : Icons.visibility, size: 20, color: Colors.grey),
                      onPressed: () => setDialogState(() => obscurePass = !obscurePass),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isVerifying ? null : doLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brand,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isVerifying
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      setState(() => _isAdmin = true);
      _openAdminHub();
    }
  }

  void _openAdminHub() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AdminHubScreen(onLogout: _handleLogout)),
    ).then((_) => _loadBranding());
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_adminKey, false);
    if (mounted) {
      setState(() => _isAdmin = false);
    }
  }

  Widget _buildDashboardCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    Widget? trailing,
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
            if (trailing != null) trailing!,
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
                title: 'Admin Panel',
                subtitle: _isAdmin ? 'Logged in — Tap to manage.' : 'Login required to access admin features.',
                icon: _isAdmin ? Icons.admin_panel_settings : Icons.lock,
                color: _isAdmin ? Colors.teal.shade700 : Colors.blueGrey.shade600,
                onTap: _handleAdminLogin,
                trailing: _isAdmin
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Text('Active', style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Admin Hub — the screen admin sees after logging in
// Contains Master Module, Live Tracking, Logout
// ═══════════════════════════════════════════════════════════

class AdminHubScreen extends StatelessWidget {
  final VoidCallback onLogout;
  const AdminHubScreen({super.key, required this.onLogout});

  static const Color _brand = Color(0xFF0D5C46);

  Widget _buildCard(
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Admin Panel'),
        actions: [
          TextButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('Logout?'),
                  content: const Text('You will need to login again to access admin features.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    ElevatedButton(
                      onPressed: () {
                        onLogout();
                        Navigator.pop(ctx);    // Close dialog
                        Navigator.pop(context); // Go back to dashboard
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600),
                      child: const Text('Logout'),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.logout, color: Colors.white, size: 20),
            label: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),

            _buildCard(
              context,
              title: 'Master Module',
              subtitle: 'Configure categories, settings & branding.',
              icon: Icons.admin_panel_settings,
              color: Colors.blueGrey.shade700,
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen()));
              },
            ),

            const SizedBox(height: 12),

            _buildCard(
              context,
              title: 'Live Tracking Board',
              subtitle: 'Monitor tokens, history & export reports.',
              icon: Icons.fact_check_rounded,
              color: Colors.teal.shade800,
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const QurbaniStatusScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }
}
