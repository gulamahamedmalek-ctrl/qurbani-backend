import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Beautiful animated success dialog with checkmark animation.
/// Shows receipt number, token info, and offers PDF download.
class SuccessDialog extends StatefulWidget {
  final String receiptNo;
  final String categoryTitle;
  final double totalAmount;
  final String currencySymbol;
  final int hissahCount;
  final List<Map<String, dynamic>> tokenAssignments;
  final VoidCallback? onDownloadReceipt;

  const SuccessDialog({
    super.key,
    required this.receiptNo,
    required this.categoryTitle,
    required this.totalAmount,
    this.currencySymbol = '₹',
    required this.hissahCount,
    this.tokenAssignments = const [],
    this.onDownloadReceipt,
  });

  @override
  State<SuccessDialog> createState() => _SuccessDialogState();
}

class _SuccessDialogState extends State<SuccessDialog>
    with TickerProviderStateMixin {
  late AnimationController _checkController;
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late AnimationController _confettiController;

  late Animation<double> _checkAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    _checkController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _checkAnimation = CurvedAnimation(
      parent: _checkController,
      curve: Curves.easeInOut,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    _confettiController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Sequence animations
    _scaleController.forward().then((_) {
      _checkController.forward().then((_) {
        _fadeController.forward();
        _confettiController.forward();
      });
    });
  }

  @override
  void dispose() {
    _checkController.dispose();
    _scaleController.dispose();
    _fadeController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  // Get unique token numbers from assignments
  String _getTokenNumbers() {
    if (widget.tokenAssignments.isEmpty) return '-';
    final tokenNos = widget.tokenAssignments.map((a) => a['token_no']).toSet();
    return tokenNos.map((n) => '#$n').join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SingleChildScrollView(
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            // Confetti
            AnimatedBuilder(
              animation: _confettiController,
              builder: (context, child) {
                return CustomPaint(
                  size: const Size(320, 480),
                  painter: _ConfettiPainter(_confettiController.value),
                );
              },
            ),

            // Main card
            Container(
              width: 320,
              margin: const EdgeInsets.only(top: 45),
              padding: const EdgeInsets.fromLTRB(24, 70, 24, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    const Text(
                      'Booking Successful!',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2D7D3E),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your hissah has been registered',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 20),

                    // Receipt info card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FAF3),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFD4EDDA)),
                      ),
                      child: Column(
                        children: [
                          _infoRow('Receipt No', widget.receiptNo, bold: true),
                          const SizedBox(height: 8),
                          _infoRow('Category', widget.categoryTitle),
                          const SizedBox(height: 8),
                          _infoRow('Hissah', '${widget.hissahCount}'),
                          const SizedBox(height: 8),
                          _infoRow('Token No', _getTokenNumbers(),
                              bold: true, valueColor: const Color(0xFF1565C0)),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          _infoRow(
                            'Total Amount',
                            '${widget.currencySymbol}${widget.totalAmount.toStringAsFixed(2)}',
                            bold: true,
                            valueColor: const Color(0xFF2D7D3E),
                          ),
                        ],
                      ),
                    ),

                    // Token assignment details
                    if (widget.tokenAssignments.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.token, size: 16, color: Colors.blue.shade700),
                                const SizedBox(width: 6),
                                Text('Token Assignments',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: Colors.blue.shade700)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...widget.tokenAssignments.map((a) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade700,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'T${a['token_no']}-${a['serial_no']}',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${a['owner_name']}',
                                          style: const TextStyle(fontSize: 13),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Download Receipt button
                    if (widget.onDownloadReceipt != null)
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF2D7D3E),
                            side: const BorderSide(color: Color(0xFF2D7D3E)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: widget.onDownloadReceipt,
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Download Receipt',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Done button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D7D3E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).pop();
                        },
                        child: const Text('Done',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Animated checkmark circle
            Positioned(
              top: 0,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF43A047), Color(0xFF2D7D3E)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF43A047).withOpacity(0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: AnimatedBuilder(
                    animation: _checkAnimation,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _CheckmarkPainter(_checkAnimation.value),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value,
      {bool bold = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: valueColor ?? Colors.black87,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════

class _CheckmarkPainter extends CustomPainter {
  final double progress;
  _CheckmarkPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final start = Offset(cx - 15, cy + 2);
    final mid = Offset(cx - 4, cy + 13);
    final end = Offset(cx + 17, cy - 10);

    final path = Path();
    if (progress <= 0.5) {
      final t = progress / 0.5;
      path.moveTo(start.dx, start.dy);
      path.lineTo(
          start.dx + (mid.dx - start.dx) * t, start.dy + (mid.dy - start.dy) * t);
    } else {
      final t = (progress - 0.5) / 0.5;
      path.moveTo(start.dx, start.dy);
      path.lineTo(mid.dx, mid.dy);
      path.lineTo(
          mid.dx + (end.dx - mid.dx) * t, mid.dy + (end.dy - mid.dy) * t);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckmarkPainter old) => old.progress != progress;
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  final List<_Particle> particles;
  _ConfettiPainter(this.progress) : particles = _generateParticles();

  static List<_Particle> _generateParticles() {
    final r = math.Random(42);
    return List.generate(20, (i) => _Particle(
          angle: r.nextDouble() * 2 * math.pi,
          speed: 80 + r.nextDouble() * 120,
          color: [
            const Color(0xFF43A047), const Color(0xFF66BB6A),
            const Color(0xFFFFA726), const Color(0xFF42A5F5),
            const Color(0xFFEF5350), const Color(0xFFAB47BC),
          ][i % 6],
          size: 4 + r.nextDouble() * 4,
        ));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;
    final cx = size.width / 2;
    const cy = 45.0;
    for (final p in particles) {
      final opacity = (1.0 - progress).clamp(0.0, 1.0);
      final paint = Paint()..color = p.color.withOpacity(opacity);
      final dist = p.speed * progress;
      final x = cx + math.cos(p.angle) * dist;
      final y = cy + math.sin(p.angle) * dist + (progress * progress * 80);
      canvas.drawCircle(Offset(x, y), p.size * (1 - progress * 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

class _Particle {
  final double angle, speed, size;
  final Color color;
  _Particle({required this.angle, required this.speed, required this.color, required this.size});
}

// ═══════════════════════════════════════════════════
// HELPER — Show the dialog
// ═══════════════════════════════════════════════════

Future<void> showBookingSuccessDialog(
  BuildContext context, {
  required String receiptNo,
  required String categoryTitle,
  required double totalAmount,
  required int hissahCount,
  String currencySymbol = '₹',
  List<Map<String, dynamic>> tokenAssignments = const [],
  VoidCallback? onDownloadReceipt,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Success',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (context, anim1, anim2) {
      return SuccessDialog(
        receiptNo: receiptNo,
        categoryTitle: categoryTitle,
        totalAmount: totalAmount,
        hissahCount: hissahCount,
        currencySymbol: currencySymbol,
        tokenAssignments: tokenAssignments,
        onDownloadReceipt: onDownloadReceipt,
      );
    },
    transitionBuilder: (context, anim1, anim2, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
        child: FadeTransition(opacity: anim1, child: child),
      );
    },
  );
}
