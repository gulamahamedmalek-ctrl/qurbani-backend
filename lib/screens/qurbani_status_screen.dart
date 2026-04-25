import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/form_settings.dart';
import '../services/receipt_generator.dart';
import 'dart:convert';

class QurbaniStatusScreen extends StatefulWidget {
  const QurbaniStatusScreen({super.key});

  @override
  State<QurbaniStatusScreen> createState() => _QurbaniStatusScreenState();
}

class _QurbaniStatusScreenState extends State<QurbaniStatusScreen> {
  static const Color _brand = Color(0xFF0D5C46);

  List<Map<String, dynamic>> _allTokens = [];
  List<Map<String, dynamic>> _filteredTokens = [];
  List<String> _categories = [];
  bool _isLoading = true;

  // Filter & Search State
  String _searchQuery = '';
  String _statusFilter = 'All'; // All, Pending, Done
  String _fillStatusFilter = 'All'; // All, Full, Partial, Empty
  String _selectedCategory = 'All';
  String _selectedReference = 'All';
  String _sortBy = 'Token Number (A-Z)';
  DateTime? _filterDate;
  FormSettings _settings = FormSettings();

  // Batch Selection
  Set<int> _selectedTokenIds = {};
  bool _isMarkingBulk = false;

  final List<String> _sortOptions = [
    'Token Number (A-Z)',
    'Token Number (Z-A)',
    'Most Filled First',
    'Least Filled First',
  ];

  @override
  void initState() {
    super.initState();
    _loadTokens();
  }

  Future<void> _loadTokens() async {
    setState(() => _isLoading = true);
    final tokens = await DatabaseService.loadTokens();
    final settings = await DatabaseService.loadFormSettings();
    final cats = tokens.map((t) => t['category_title'].toString()).toSet().toList();
    cats.sort();
    
    if (!mounted) return;
    setState(() {
      _allTokens = tokens;
      _categories = cats;
      _settings = settings;
      _isLoading = false;
      // Preserve selection if possible
      _selectedTokenIds.retainWhere((id) => tokens.any((t) => t['id'] == id));
    });
    _applyFilters();
  }

  void _applyFilters() {
    List<Map<String, dynamic>> result = List.from(_allTokens);

    // 1. Category Filter
    if (_selectedCategory != 'All') {
      result = result.where((t) => t['category_title'] == _selectedCategory).toList();
    }

    // 1.5 Reference Filter
    if (_settings.referenceAsDropdown && _selectedReference != 'All') {
      result = result.where((t) {
        final entries = List<Map<String, dynamic>>.from(t['entries'] ?? []);
        return entries.any((e) => e['booking_reference'] == _selectedReference);
      }).toList();
    }

    // 2. Execution Status Filter
    if (_statusFilter == 'Pending') {
      result = result.where((t) => t['qurbani_done'] != true).toList();
    } else if (_statusFilter == 'Done') {
      result = result.where((t) => t['qurbani_done'] == true).toList();
    }

    // 3. Fill Status Filter
    if (_fillStatusFilter == 'Full') {
      result = result.where((t) => (t['filled_slots'] ?? 0) >= (t['max_slots'] ?? 7)).toList();
    } else if (_fillStatusFilter == 'Partial') {
      result = result.where((t) {
        final f = t['filled_slots'] ?? 0;
        return f > 0 && f < (t['max_slots'] ?? 7);
      }).toList();
    } else if (_fillStatusFilter == 'Empty') {
      result = result.where((t) => (t['filled_slots'] ?? 0) == 0).toList();
    }

    // 4. Global Search (Deep search in names, refs and purposes)
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((t) {
        if (t['token_no'].toString().contains(q)) return true;
        if (t['category_title'].toString().toLowerCase().contains(q)) return true;
        
        // Deep search through assigned people
        final entries = List<Map<String, dynamic>>.from(t['entries'] ?? []);
        for (final e in entries) {
          if ((e['owner_name'] ?? '').toString().toLowerCase().contains(q)) return true;
          if ((e['purpose'] ?? '').toString().toLowerCase().contains(q)) return true;
          if ((e['booking_reference'] ?? '').toString().toLowerCase().contains(q)) return true;
        }
        return false;
      }).toList();
    }

    // 4.5 Date Filter
    if (_filterDate != null) {
      result = result.where((t) {
        final entries = List<Map<String, dynamic>>.from(t['entries'] ?? []);
        for (final e in entries) {
           final bDateStr = e['booking_date'];
           if (bDateStr != null) {
              try {
                final bDate = DateTime.parse(bDateStr).toLocal();
                if (bDate.year == _filterDate!.year && bDate.month == _filterDate!.month && bDate.day == _filterDate!.day) {
                   return true;
                }
              } catch (_) {}
           }
        }
        return false;
      }).toList();
    }

    // 5. Sorting
    result.sort((a, b) {
      if (_sortBy == 'Token Number (A-Z)') return a['token_no'].compareTo(b['token_no']);
      if (_sortBy == 'Token Number (Z-A)') return b['token_no'].compareTo(a['token_no']);
      if (_sortBy == 'Most Filled First') {
        int r = (b['filled_slots'] ?? 0).compareTo(a['filled_slots'] ?? 0);
        return r != 0 ? r : a['token_no'].compareTo(b['token_no']);
      }
      if (_sortBy == 'Least Filled First') {
        int r = (a['filled_slots'] ?? 0).compareTo(b['filled_slots'] ?? 0);
        return r != 0 ? r : a['token_no'].compareTo(b['token_no']);
      }
      return 0;
    });

    setState(() => _filteredTokens = result);
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _statusFilter = 'All';
      _fillStatusFilter = 'All';
      _selectedCategory = 'All';
      _selectedReference = 'All';
      _sortBy = 'Token Number (A-Z)';
      _filterDate = null;
    });
    _applyFilters();
  }

  void _selectAllPending() {
    setState(() {
      final pendingIds = _filteredTokens
          .where((t) => t['qurbani_done'] != true)
          .map((t) => t['id'] as int);
      _selectedTokenIds.addAll(pendingIds);
    });
  }

  void _clearSelection() {
    setState(() => _selectedTokenIds.clear());
  }

  Future<void> _markSelectedAsDone() async {
    if (_selectedTokenIds.isEmpty) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Batch Qurbani'),
        content: Text('Are you sure you want to mark ${_selectedTokenIds.length} tokens as Qurbani Done?\n\nThis cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _brand),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Mark All Done'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isMarkingBulk = true);
    final result = await DatabaseService.markBulkQurbaniDone(_selectedTokenIds.toList());
    setState(() => _isMarkingBulk = false);

    if (result['success'] == true) {
      _clearSelection();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Batch processing successful!'), backgroundColor: _brand));
      await _loadTokens();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${result['message']}'), backgroundColor: Colors.red));
    }
  }

  Future<void> _showBookingDetails(int bookingId) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BookingDetailSheet(bookingId: bookingId, settings: _settings),
    );
  }

  // ── Stats ──
  int get _total => _allTokens.length;
  int get _done => _allTokens.where((t) => t['qurbani_done'] == true).length;
  int get _pending => _total - _done;

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final am = dt.hour >= 12 ? 'PM' : 'AM';
      return '${dt.day}/${dt.month}/${dt.year} $h:$m $am';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          title: const Text('Advanced Execution Engine'),
          backgroundColor: _brand,
          elevation: 0,
          bottom: TabBar(
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withOpacity(0.7),
            tabs: const [
              Tab(icon: Icon(Icons.dashboard_customize), text: 'LIVE BOARD'),
              Tab(icon: Icon(Icons.history_edu), text: 'ARCHIVE & SEARCH'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // TAB 1: LIVE BOARD
            _isLoading
                ? const Center(child: CircularProgressIndicator(color: _brand))
                : Column(
                    children: [
                      _buildAdvancedFilterDashboard(),
                      Expanded(
                        child: _filteredTokens.isEmpty
                            ? const Center(child: Text('No tokens found matching filters.', style: TextStyle(color: Colors.grey, fontSize: 16)))
                            : ListView.builder(
                                padding: const EdgeInsets.only(bottom: 100),
                                itemCount: _filteredTokens.length,
                                itemBuilder: (ctx, i) => _buildExpandableTokenRow(_filteredTokens[i]),
                              ),
                      ),
                    ],
                  ),
            _HistoryTab(settings: _settings),
          ],
        ),
        floatingActionButton: _buildFloatingActionButton(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  Widget? _buildFloatingActionButton() {
    if (_selectedTokenIds.isEmpty) return null;

    return FloatingActionButton.extended(
      onPressed: _isMarkingBulk ? null : _markSelectedAsDone,
      backgroundColor: _brand,
      icon: _isMarkingBulk 
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Icon(Icons.playlist_add_check, color: Colors.white),
      label: Text(
        'Mark ${_selectedTokenIds.length} Done', 
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
      ),
    );
  }

  Widget _buildAdvancedFilterDashboard() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 4,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Deep Search (Name, Token, Ref, Purpose)...',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                    prefixIcon: const Icon(Icons.search, color: _brand),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { setState(() => _searchQuery = ''); _applyFilters(); })
                        : null,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) { _searchQuery = v; _applyFilters(); },
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$_total Total Tokens', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      Text('$_pending Pending', style: TextStyle(fontSize: 13, color: Colors.orange.shade700, fontWeight: FontWeight.bold)),
                      const Text(' / '),
                      Text('$_done Done', style: TextStyle(fontSize: 13, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDropdownFilter('Status', ['All', 'Pending', 'Done'], _statusFilter, (v) { setState(() => _statusFilter = v!); _applyFilters(); }),
                const SizedBox(width: 10),
                _buildDropdownFilter('Fill Status', ['All', 'Full', 'Partial', 'Empty'], _fillStatusFilter, (v) { setState(() => _fillStatusFilter = v!); _applyFilters(); }),
                const SizedBox(width: 10),
                if (_categories.isNotEmpty) ...[
                  _buildDropdownFilter('Category', ['All', ..._categories], _selectedCategory, (v) { setState(() => _selectedCategory = v!); _applyFilters(); }),
                  const SizedBox(width: 10),
                ],
                if (_settings.referenceAsDropdown && _settings.referenceOptions.isNotEmpty) ...[
                  _buildDropdownFilter('Reference', ['All', ..._settings.referenceOptions], _selectedReference, (v) { setState(() => _selectedReference = v!); _applyFilters(); }),
                  const SizedBox(width: 10),
                ],
                _buildDropdownFilter('Sort', _sortOptions, _sortBy, (v) { setState(() => _sortBy = v!); _applyFilters(); }),
                const SizedBox(width: 10),
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _filterDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) {
                      setState(() => _filterDate = d);
                      _applyFilters();
                    }
                  },
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month, size: 16, color: Colors.grey.shade700),
                        const SizedBox(width: 6),
                        Text(_filterDate != null ? '${_filterDate!.day}/${_filterDate!.month}/${_filterDate!.year}' : 'Date', style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(onPressed: _clearFilters, child: const Text('Reset')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownFilter(String label, List<String> options, String currentValue, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
        ),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentValue,
              items: options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
              onChanged: onChanged,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpandableTokenRow(Map<String, dynamic> token) {
    final bool isDone = token['qurbani_done'] == true;
    final int id = token['id'];
    final bool isSelected = _selectedTokenIds.contains(id);
    final entries = List<Map<String, dynamic>>.from(token['entries'] ?? []);
    final int max = token['max_slots'] ?? 7;
    final int tokenNo = token['token_no'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isSelected ? _brand : Colors.grey.shade200, width: isSelected ? 1.5 : 1),
      ),
      child: ExpansionTile(
        key: PageStorageKey<String>('token_$id'),
        leading: Checkbox(
          value: isSelected,
          onChanged: (v) {
            setState(() {
              if (v == true) _selectedTokenIds.add(id);
              else _selectedTokenIds.remove(id);
            });
          },
        ),
        title: Text('Token #$tokenNo', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text('${token['filled_slots']}/$max Hissah - ${isDone ? "Done" : "Pending"}'),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade50,
            child: Column(
              children: [
                ...List.generate(max, (index) {
                  final e = index < entries.length ? entries[index] : null;
                  
                  // Extract info
                  final ownerName = e == null ? '—' : (e['owner_name'] ?? '');
                  final category = e == null ? '' : (e['booking_category'] ?? '');
                  final receipt = e == null ? '' : (e['receipt_no'] ?? '');
                  
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    leading: CircleAvatar(
                      backgroundColor: _brand.withOpacity(0.1),
                      radius: 16,
                      child: Text('$tokenNo.${index + 1}', style: const TextStyle(fontSize: 11, color: _brand, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(ownerName, style: TextStyle(color: e == null ? Colors.grey : Colors.black87, fontWeight: FontWeight.w600)),
                    subtitle: e != null && category.isNotEmpty ? Text('$category • $receipt', style: const TextStyle(fontSize: 12)) : null,
                    onTap: e == null ? null : () => _showBookingDetails(e['booking_id']),
                    trailing: Text(e == null ? '' : (e['purpose'] ?? ''), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  );
                }),
                if (!isDone)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final res = await DatabaseService.markQurbaniDone(id);
                          if (res['success'] == true) _loadTokens();
                        },
                        icon: const Icon(Icons.check_circle_outline, size: 20),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('MARK QURBANI AS DONE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: _brand,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _BookingDetailSheet extends StatefulWidget {
  final int bookingId;
  final FormSettings settings;
  const _BookingDetailSheet({required this.bookingId, required this.settings});

  @override
  State<_BookingDetailSheet> createState() => _BookingDetailSheetState();
}

class _BookingDetailSheetState extends State<_BookingDetailSheet> {
  static const Color _brand = Color(0xFF0D5C46);
  Map<String, dynamic>? _booking;
  List<Map<String, dynamic>> _hissahEntries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final result = await DatabaseService.getBookingDetails(widget.bookingId);
    if (mounted) {
      setState(() {
        if (result['success'] == true) {
          _booking = result['data']['booking'];
          _hissahEntries = List<Map<String, dynamic>>.from(result['data']['hissah_entries'] ?? []);
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _booking == null 
              ? const Center(child: Text('Error'))
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final date = DateTime.tryParse(_booking!['booking_date'] ?? '')?.toLocal();
    final dateStr = date != null ? '${date.day}/${date.month}/${date.year}' : 'N/A';
    
    Map<String, dynamic> customData = {};
    try {
      if (_booking!['custom_fields_data'] != null) {
        if (_booking!['custom_fields_data'] is String) {
          customData = jsonDecode(_booking!['custom_fields_data']);
        } else {
          customData = Map<String, dynamic>.from(_booking!['custom_fields_data']);
        }
      }
    } catch (_) {}

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_booking!['representative_name'] ?? 'No Name', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    Text('Receipt: ${_booking!['receipt_no']}', style: const TextStyle(color: _brand, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _brand.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: IconButton(icon: const Icon(Icons.print, color: _brand), onPressed: _reprintReceipt),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildInfoSection('Customer Profile', [
            _buildDetailRow(Icons.phone, 'Mobile Number', _booking!['mobile']),
            _buildDetailRow(Icons.location_on, 'Address', _booking!['address']),
            _buildDetailRow(Icons.calendar_today, 'Booking Date', dateStr),
          ]),
          const SizedBox(height: 20),
          _buildInfoSection('Booking Specifics', [
            _buildDetailRow(Icons.info_outline, 'Purpose', _booking!['purpose']),
            _buildDetailRow(Icons.campaign, 'Reference', _booking!['reference']),
          ]),
          if (customData.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildInfoSection('Additional Details', 
              customData.entries.map((e) => _buildDetailRow(Icons.label_important_outline, e.key, e.value.toString())).toList()
            ),
          ],
          const SizedBox(height: 20),
          const Text('Animal Assignments', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
          const SizedBox(height: 12),
          ..._hissahEntries.map((e) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: _brand.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Center(child: Icon(Icons.pets, size: 20, color: _brand)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Token #${e['token_no']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(e['category_title'] ?? 'Large Animal', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: e['qurbani_done'] == true ? Colors.green.shade50 : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    e['qurbani_done'] == true ? 'DONE' : 'PENDING',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: e['qurbani_done'] == true ? Colors.green : Colors.orange),
                  ),
                ),
              ],
            ),
          )),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _reprintReceipt,
              icon: const Icon(Icons.print),
              label: const Text('RE-PRINT & SHARE RECEIPT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade500, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade100)),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontWeight: FontWeight.bold)),
                Text(value ?? '—', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reprintReceipt() async {
    final rawDate = _booking!['booking_date'] ?? DateTime.now().toIso8601String();
    final dateStr = rawDate.contains('T') ? rawDate.split('T').first : rawDate;
    
    await ReceiptGenerator.generateAndPrint(
      receiptNo: _booking!['receipt_no'] ?? '',
      date: dateStr,
      categoryTitle: _booking!['category_title'] ?? '',
      representativeName: _booking!['representative_name'] ?? '',
      referenceName: _booking!['reference'] ?? '',
      ownerNames: List<String>.from(_hissahEntries.map((e) => e['owner_name'] ?? 'Owner')),
      address: _booking!['address'] ?? '',
      mobile: _booking!['mobile'] ?? '',
      purpose: _booking!['purpose'] ?? '',
      amountPerHissah: (_booking!['amount_per_hissah'] ?? 0).toDouble(),
      hissahCount: _booking!['hissah_count'] ?? 1,
      totalAmount: (_booking!['total_amount'] ?? 0).toDouble(),
      currencySymbol: widget.settings.currencySymbol,
      organizationName: widget.settings.organizationName,
      logoBase64: widget.settings.logoBase64,
      tokenAssignments: _hissahEntries,
    );
  }
}

class _HistoryTab extends StatefulWidget {
  final FormSettings settings;
  const _HistoryTab({required this.settings});

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
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
    if (mounted) {
      setState(() {
        _bookings = results;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => _loadBookings(query: v),
            decoration: InputDecoration(
              hintText: 'Search by Name, Mobile or Receipt...',
              prefixIcon: const Icon(Icons.search, color: _brand),
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: _brand))
              : _bookings.isEmpty
                  ? Center(child: Text('No history found.', style: TextStyle(color: Colors.grey.shade400)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _bookings.length,
                      itemBuilder: (ctx, i) {
                        final b = _bookings[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade100),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            onTap: () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (ctx) => _BookingDetailSheet(bookingId: b['id'], settings: widget.settings),
                            ),
                            leading: CircleAvatar(backgroundColor: _brand.withOpacity(0.1), child: const Icon(Icons.person, color: _brand)),
                            title: Text(b['representative_name'] ?? 'No Name', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Receipt: ${b['receipt_no']}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
