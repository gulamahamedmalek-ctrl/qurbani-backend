import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/database_service.dart';
import '../services/receipt_generator.dart';
import '../models/form_settings.dart';

class BookingDetailsScreen extends StatefulWidget {
  final int bookingId;
  const BookingDetailsScreen({super.key, required this.bookingId});

  @override
  State<BookingDetailsScreen> createState() => _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends State<BookingDetailsScreen> {
  static const Color _brand = Color(0xFF0D5C46);
  
  Map<String, dynamic>? _booking;
  List<Map<String, dynamic>> _hissahEntries = [];
  FormSettings _settings = FormSettings();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    final result = await DatabaseService.getBookingDetails(widget.bookingId);
    final settings = await DatabaseService.loadFormSettings();

    if (result['success'] == true) {
      setState(() {
        _booking = result['data']['booking'];
        _hissahEntries = List<Map<String, dynamic>>.from(result['data']['hissah_entries'] ?? []);
        _settings = settings;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${result['message']}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(backgroundColor: _brand, title: const Text('Loading Details...')),
        body: const Center(child: CircularProgressIndicator(color: _brand)),
      );
    }

    if (_booking == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: _brand, title: const Text('Error')),
        body: const Center(child: Text('Booking not found.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text('Receipt ${_booking!['receipt_no']}'),
        backgroundColor: _brand,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _reprintReceipt,
            tooltip: 'Share Receipt',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderCard(),
            const SizedBox(height: 16),
            _buildCustomerCard(),
            const SizedBox(height: 16),
            _buildHissahCard(),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _reprintReceipt,
              icon: const Icon(Icons.print),
              label: const Text('RE-PRINT RECEIPT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final date = DateTime.tryParse(_booking!['booking_date'] ?? '')?.toLocal();
    final dateStr = date != null ? '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}' : 'N/A';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _brand,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: _brand.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Text(_booking!['receipt_no'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Transaction Date: $dateStr', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Divider(color: Colors.white24, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Paid', style: TextStyle(color: Colors.white70, fontSize: 14)),
              Text('${_settings.currencySymbol}${_booking!['total_amount']}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard() {
    final customData = _booking!['custom_fields_data'] is Map ? _booking!['custom_fields_data'] as Map<String, dynamic> : {};
    
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.person, color: _brand, size: 20),
                SizedBox(width: 8),
                Text('Customer Profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            _buildDetailRow('Name', _booking!['customer_name']),
            _buildDetailRow('Mobile', _booking!['customer_mobile']),
            if (_booking!['representative_name'] != null && _booking!['representative_name'].toString().isNotEmpty)
              _buildDetailRow('Representative', _booking!['representative_name']),
            _buildDetailRow('Address', _booking!['address']),
            _buildDetailRow('Purpose', _booking!['purpose']),
            _buildDetailRow('Reference', _booking!['booking_reference']),
            
            if (customData.isNotEmpty) ...[
              const Padding(padding: EdgeInsets.only(top: 12, bottom: 8), child: Text('Other Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey))),
              ...customData.entries.map((e) => _buildDetailRow(e.key, e.value.toString())),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHissahCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.pets, color: _brand, size: 20),
                SizedBox(width: 8),
                Text('Animal Assignments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            if (_hissahEntries.isEmpty)
              const Text('No animals assigned yet.', style: TextStyle(color: Colors.grey)),
            ..._hissahEntries.map((e) {
              final isDone = e['qurbani_done'] == true;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e['category_title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text('Token #${e['token_no']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDone ? Colors.green.shade50 : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isDone ? 'COMPLETED' : 'PENDING',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDone ? Colors.green : Colors.orange),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 13))),
          Expanded(child: Text(value ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }

  Future<void> _reprintReceipt() async {
    if (_booking == null) return;
    
    // Prepare data for generator
    final List<String> ownerNames = List<String>.from(jsonDecode(jsonEncode(_hissahEntries)).map((e) => _booking!['customer_name'])); 
    // Note: In history, we usually want to re-print the whole booking receipt.
    // The generator needs the specific list of owner names for that booking.
    
    // Actually, we can just pass the booking data map if we adapt the generator, 
    // but for now we'll match the existing interface.
    
    // We need to group owner names correctly if one booking has multiple hissah.
    // Let's just use the customer name for all since they are the one who booked.
    
    await ReceiptGenerator.generateAndShow(
      context: context,
      settings: _settings,
      customerName: _booking!['customer_name'] ?? '',
      receiptNo: _booking!['receipt_no'] ?? '',
      categoryTitle: _booking!['category_title'] ?? '',
      amountPerHissah: (_booking!['amount_per_hissah'] ?? 0).toDouble(),
      totalAmount: (_booking!['total_amount'] ?? 0).toDouble(),
      hissahCount: _booking!['hissah_count'] ?? 1,
      purpose: _booking!['purpose'] ?? '',
      representativeName: _booking!['representative_name'] ?? '',
      ownerNames: ownerNames,
      bookingDate: DateTime.parse(_booking!['booking_date']),
      customFieldsData: _booking!['custom_fields_data'] is Map ? _booking!['custom_fields_data'] as Map<String, dynamic> : {},
    );
  }
}
