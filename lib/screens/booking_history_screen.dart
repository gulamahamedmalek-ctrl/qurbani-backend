import 'package:flutter/material.dart';
import '../services/database_service.dart';
import 'booking_details_screen.dart';

class BookingHistoryScreen extends StatefulWidget {
  const BookingHistoryScreen({super.key});

  @override
  State<BookingHistoryScreen> createState() => _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends State<BookingHistoryScreen> {
  static const Color _brand = Color(0xFF0D5C46);
  
  List<Map<String, dynamic>> _bookings = [];
  bool _isLoading = true;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings({String? query}) async {
    setState(() => _isLoading = true);
    final results = await DatabaseService.loadBookings(query: query);
    setState(() {
      _bookings = results;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Booking History & Archive'),
        backgroundColor: _brand,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _brand))
                : _bookings.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _bookings.length,
                        itemBuilder: (ctx, i) => _buildBookingCard(_bookings[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: _brand,
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 20, top: 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => _loadBookings(query: v),
        decoration: InputDecoration(
          hintText: 'Search by Name, Mobile or Receipt...',
          fillColor: Colors.white,
          filled: true,
          prefixIcon: const Icon(Icons.search, color: _brand),
          suffixIcon: _searchCtrl.text.isNotEmpty 
            ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchCtrl.clear(); _loadBookings(); })
            : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_edu, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No bookings found', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> b) {
    final date = DateTime.tryParse(b['booking_date'] ?? '')?.toLocal();
    final dateStr = date != null ? '${date.day}/${date.month}/${date.year}' : 'Unknown Date';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (ctx) => BookingDetailsScreen(bookingId: b['id'])),
        ),
        leading: CircleAvatar(
          backgroundColor: _brand.withOpacity(0.1),
          child: const Icon(Icons.receipt_long, color: _brand, size: 20),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(b['representative_name'] ?? 'No Name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis)),
            Text(b['receipt_no'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _brand)),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Mobile: ${b['mobile'] ?? 'N/A'}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(dateStr, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                const Spacer(),
                Text('₹${b['total_amount']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }
}
