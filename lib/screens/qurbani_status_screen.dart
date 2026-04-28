import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/form_settings.dart';
import '../services/receipt_generator.dart';
import '../services/report_generator.dart';
import '../services/slaughter_list_generator.dart';
import 'customer_details_screen.dart';
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
  Set<int> _selectedEntryIds = {};
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
    // 1. Try to load from CACHE first for instant feedback
    if (_allTokens.isEmpty) {
      final cached = await DatabaseService.loadTokens(useCache: true);
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _allTokens = cached;
          _isLoading = false;
        });
        _applyFilters();
      }
    }

    // 2. Fetch fresh data from network
    if (_allTokens.isEmpty) setState(() => _isLoading = true);
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
      // Preserve selection if possible, prune stale references
      _selectedTokenIds.retainWhere((id) => tokens.any((t) => t['id'] == id));
      final allEntryIds = <int>{};
      for (var t in tokens) {
        for (var e in List<Map<String, dynamic>>.from(t['entries'] ?? [])) {
          if (e['id'] != null) allEntryIds.add(e['id']);
        }
      }
      _selectedEntryIds.retainWhere((id) => allEntryIds.contains(id));
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
    setState(() {
      _selectedTokenIds.clear();
      _selectedEntryIds.clear();
    });
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
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BookingDetailSheet(bookingId: bookingId, settings: _settings),
    );
    // Automatically refresh token list when the bottom sheet closes (e.g., after cancel/edit)
    _loadTokens();
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
          title: _selectedEntryIds.isNotEmpty
              ? Text('${_selectedEntryIds.length} Selected', style: const TextStyle(fontSize: 18))
              : const Text('Advanced Execution Engine', style: TextStyle(fontSize: 18)),
          backgroundColor: _selectedEntryIds.isNotEmpty ? Colors.blue.shade800 : _brand,
          elevation: 0,
          leading: _selectedEntryIds.isNotEmpty
              ? IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection)
              : null,
          actions: [
            if (_selectedEntryIds.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.move_up),
                tooltip: 'Move Selected',
                onPressed: () {
                  final entriesToMove = <Map<String, dynamic>>[];
                  for (var t in _allTokens) {
                    final ents = List<Map<String, dynamic>>.from(t['entries'] ?? []);
                    for (var e in ents) {
                      if (_selectedEntryIds.contains(e['id'])) {
                        // Manually inject token_id to guarantee it exists even if backend schema is outdated
                        e['token_id'] = t['id'];
                        entriesToMove.add(e);
                      }
                    }
                  }
                  if (entriesToMove.isNotEmpty) {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => _MoveEntrySheet(entries: entriesToMove, allTokens: _allTokens, onRefresh: () {
                        _clearSelection();
                        _loadTokens();
                      }),
                    );
                  }
                },
              ),
          ],
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
              Expanded(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Column(
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
                  ),
                ),
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

  Future<void> _editEntryName(Map<String, dynamic> entry) async {
    final TextEditingController nameController = TextEditingController(text: entry['owner_name']);
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Edit Name', style: TextStyle(fontWeight: FontWeight.bold, color: _brand)),
            content: TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Owner Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: _brand, width: 2)),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _brand, foregroundColor: Colors.white),
                onPressed: isSaving ? null : () async {
                  if (nameController.text.trim().isEmpty) return;
                  setState(() => isSaving = true);
                  final res = await DatabaseService.editTokenEntryName(entry['id'], nameController.text.trim());
                  setState(() => isSaving = false);
                  if (res['success'] == true) {
                    Navigator.pop(ctx);
                    _loadTokens(); // Refresh list to show new name
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${res['message']}'), backgroundColor: Colors.red));
                  }
                },
                child: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Save'),
              )
            ],
          );
        }
      ),
    );
  }

  void _moveEntry(Map<String, dynamic> entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MoveEntrySheet(entries: [entry], allTokens: _allTokens, onRefresh: _loadTokens),
    );
  }

  Widget _buildExpandableTokenRow(Map<String, dynamic> token) {
    final bool isDone = token['qurbani_done'] == true;
    final int id = token['id'];
    final bool isSelected = _selectedTokenIds.contains(id);
    final int max = token['max_slots'] ?? 7;
    final int tokenNo = token['token_no'];
    List<dynamic> entries = List.from(token['entries'] ?? []);
    
    // Sort entries by serial_no to guarantee correct order on the frontend
    entries.sort((a, b) => (a['serial_no'] ?? 0).compareTo(b['serial_no'] ?? 0));

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
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...List.generate(max, (index) {
                  final e = index < entries.length ? entries[index] : null;
                  
                  // Extract info
                  final ownerName = e == null ? '—' : (e['owner_name'] ?? '');
                  final category = e == null ? '' : (e['booking_category'] ?? '');
                  final receipt = e == null ? '' : (e['receipt_no'] ?? '');
                  final repName = e == null ? '' : (e['representative_name'] ?? '');
                  
                  // Detect if this is a new booking boundary
                  bool isNewReceipt = false;
                  if (e != null) {
                    e['token_id'] = id; // Safety fallback injection
                    if (index == 0) {
                      isNewReceipt = true;
                    } else {
                      final prev = entries[index - 1];
                      if (prev['receipt_no'] != receipt) {
                        isNewReceipt = true;
                      }
                    }
                  }

                  Widget tile = InkWell(
                    onTap: e == null ? null : () => _showBookingDetails(e['booking_id']),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 1. Selection Checkbox
                          if (e != null && !isDone)
                            SizedBox(
                              width: 32,
                              child: Checkbox(
                                value: _selectedEntryIds.contains(e['id']),
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) _selectedEntryIds.add(e['id']);
                                    else _selectedEntryIds.remove(e['id']);
                                  });
                                },
                              ),
                            )
                          else
                            const SizedBox(width: 32),
                            
                          // 2. Avatar
                          CircleAvatar(
                            backgroundColor: _brand.withOpacity(0.1),
                            radius: 16,
                            child: Text('$tokenNo.${index + 1}', style: const TextStyle(fontSize: 11, color: _brand, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          
                          // 3. Name and Purpose (Expanded so it never squishes)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ownerName, style: TextStyle(color: e == null ? Colors.grey : Colors.black87, fontWeight: FontWeight.w600, fontSize: 14)),
                                if (e != null && category.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Text('$category • $receipt${(e['purpose'] != null && e['purpose'].toString().isNotEmpty) ? ' • ${e['purpose']}' : ''}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ),
                              ],
                            ),
                          ),
                          
                          // 4. Action Buttons
                          if (e != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.swap_horiz, size: 20, color: Colors.blue),
                                  onPressed: () => _moveEntry(e),
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(4),
                                  tooltip: 'Move to another token',
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18, color: _brand),
                                  onPressed: () => _editEntryName(e),
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(4),
                                  tooltip: 'Edit name',
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );

                  if (isNewReceipt) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (index > 0) const Divider(height: 16, color: Colors.black12),
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.receipt_long, size: 14, color: _brand),
                              const SizedBox(width: 6),
                              Expanded(child: Text(repName.isNotEmpty ? 'Receipt $receipt  •  $repName' : 'Receipt $receipt', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _brand), overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                        tile,
                      ],
                    );
                  }

                  return tile;
                }),
                if (!isDone)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0, bottom: 4.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final res = await DatabaseService.markQurbaniDone(id);
                          if (res['success'] == true) _loadTokens();
                        },
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text(
                          'MARK AS DONE', 
                          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5, fontSize: 13),
                          maxLines: 1,
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          backgroundColor: _brand,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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

  Future<void> _cancelBooking() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Booking', style: TextStyle(color: Colors.red)),
        content: const Text('Are you sure you want to cancel and delete this booking?\n\nThis will free up the associated Token slots for other customers. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go Back')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Booking'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    
    setState(() => _isLoading = true);
    final res = await DatabaseService.deleteBooking(widget.bookingId);
    if (res['success'] == true) {
      if (mounted) Navigator.pop(context); // Close sheet
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Cancelled successfully'), backgroundColor: _brand));
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${res['message']}'), backgroundColor: Colors.red));
    }
  }

  Future<void> _editBookingDetails() async {
    final saved = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomerDetailsScreen(
          qurbaniSize: _booking!['category_title'] ?? 'Large Animal',
          portionAmount: double.tryParse(_booking!['amount_per_hissah']?.toString() ?? '0') ?? 0.0,
          existingBooking: _booking,
          existingEntries: _hissahEntries,
        ),
      ),
    );

    if (saved == true) {
      _loadDetails();
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
    final date = DateTime.tryParse(_booking!['created_at'] ?? '')?.toLocal();
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
                  child: const Center(child: Icon(Icons.person, size: 20, color: _brand)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${e['owner_name']} (${_booking!['representative_name']})', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('Token #${e['token_no']}  •  ${e['category_title'] ?? 'Large Animal'}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _editBookingDetails,
                  icon: const Icon(Icons.edit, color: _brand),
                  label: const Text('EDIT', style: TextStyle(color: _brand, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _brand),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _cancelBooking,
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('CANCEL BOOKING', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
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
  List<Map<String, dynamic>> _allBookings = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  final TextEditingController _searchCtrl = TextEditingController();

  // Filters
  DateTimeRange? _dateRange;
  String _catFilter = 'All';
  String _refFilter = 'All';
  bool _showRefBreakdown = false;

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    if (_allBookings.isEmpty) {
      final cached = await DatabaseService.loadBookings(useCache: true);
      if (cached.isNotEmpty && mounted) {
        setState(() { _allBookings = cached; _isLoading = false; });
        _applyFilters();
      }
    }
    if (_allBookings.isEmpty) setState(() => _isLoading = true);
    final results = await DatabaseService.loadBookings();
    if (mounted) {
      setState(() { _allBookings = results; _isLoading = false; });
      _applyFilters();
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> result = List.from(_allBookings);

    // Search
    final q = _searchCtrl.text.toLowerCase();
    if (q.isNotEmpty) {
      result = result.where((b) {
        final name = (b['representative_name'] ?? '').toString().toLowerCase();
        final mobile = (b['mobile'] ?? '').toString().toLowerCase();
        final receipt = (b['receipt_no'] ?? '').toString().toLowerCase();
        return name.contains(q) || mobile.contains(q) || receipt.contains(q);
      }).toList();
    }

    // Date Range
    if (_dateRange != null) {
      result = result.where((b) {
        final d = DateTime.tryParse(b['created_at'] ?? '');
        if (d == null) return false;
        return !d.isBefore(_dateRange!.start) && d.isBefore(_dateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }

    // Category
    if (_catFilter != 'All') {
      result = result.where((b) => b['category_title'] == _catFilter).toList();
    }

    // Reference
    if (_refFilter != 'All') {
      result = result.where((b) => (b['reference'] ?? '') == _refFilter).toList();
    }

    setState(() => _filtered = result);
  }

  List<String> get _categories {
    final cats = _allBookings.map((b) => (b['category_title'] ?? '').toString()).toSet().toList();
    cats.sort();
    return ['All', ...cats];
  }

  List<String> get _references {
    final refs = _allBookings.map((b) => (b['reference'] ?? '').toString()).where((r) => r.isNotEmpty).toSet().toList();
    refs.sort();
    return ['All', ...refs];
  }

  Map<String, _RefBreakdown> get _refBreakdownMap {
    final map = <String, _RefBreakdown>{};
    for (var b in _filtered) {
      final ref = (b['reference'] ?? 'N/A').toString();
      map.putIfAbsent(ref, () => _RefBreakdown());
      map[ref]!.count++;
      map[ref]!.hissahs += (b['hissah_count'] ?? 0) as int;
      map[ref]!.amount += (b['total_amount'] ?? 0).toDouble();
    }
    return map;
  }

  String get _dateRangeStr {
    if (_dateRange == null) return '';
    final s = _dateRange!.start;
    final e = _dateRange!.end;
    return '${s.day}/${s.month}/${s.year} — ${e.day}/${e.month}/${e.year}';
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dateRange,
      builder: (ctx, child) => Theme(data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: _brand)), child: child!),
    );
    if (picked != null) {
      _dateRange = picked;
      _applyFilters();
    }
  }

  void _exportPdf() {
    final cur = widget.settings.currencySymbol;
    ReportGenerator.generateReport(
      bookings: _filtered,
      title: 'Booking Report',
      currencySymbol: cur,
      organizationName: widget.settings.organizationName,
      dateRange: _dateRangeStr.isNotEmpty ? _dateRangeStr : null,
      categoryFilter: _catFilter,
      referenceFilter: _refFilter,
    );
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating PDF report...'), backgroundColor: _brand));
  }

  void _exportSlaughterList() {
    SlaughterListGenerator.generate(
      organizationName: widget.settings.organizationName,
      currencySymbol: widget.settings.currencySymbol,
      category: _catFilter != 'All' ? _catFilter : null,
    );
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating Slaughter List...'), backgroundColor: _brand));
  }

  @override
  Widget build(BuildContext context) {
    double totalAmount = 0;
    int totalHissah = 0;
    for (var b in _filtered) {
      totalAmount += (b['total_amount'] ?? 0).toDouble();
      totalHissah += (b['hissah_count'] ?? 0) as int;
    }

    final hasActiveFilter = _dateRange != null || _catFilter != 'All' || _refFilter != 'All';

    return Column(
      children: [
        // Search + Export Row
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => _applyFilters(),
                  decoration: InputDecoration(
                    hintText: 'Search Name, Mobile, Receipt...',
                    prefixIcon: const Icon(Icons.search, color: _brand, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () { _searchCtrl.clear(); _applyFilters(); })
                        : null,
                    filled: true, fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.picture_as_pdf, color: _brand),
                tooltip: 'Export PDF',
                enabled: _filtered.isNotEmpty,
                onSelected: (v) {
                  if (v == 'report') _exportPdf();
                  if (v == 'slaughter') _exportSlaughterList();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'report', child: ListTile(leading: Icon(Icons.summarize, color: Color(0xFF0D5C46)), title: Text('Booking Report'), subtitle: Text('Summary, stats & breakdown', style: TextStyle(fontSize: 11)), dense: true, contentPadding: EdgeInsets.zero)),
                  const PopupMenuItem(value: 'slaughter', child: ListTile(leading: Icon(Icons.format_list_numbered, color: Color(0xFF0D5C46)), title: Text('Slaughter List'), subtitle: Text('Token-wise owner names for sacrifice', style: TextStyle(fontSize: 11)), dense: true, contentPadding: EdgeInsets.zero)),
                ],
              ),
            ],
          ),
        ),

        // Filter Chips Row
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Date Range Chip
                ActionChip(
                  avatar: const Icon(Icons.calendar_today, size: 14, color: _brand),
                  label: Text(_dateRange != null ? _dateRangeStr : 'Date Range', style: TextStyle(fontSize: 12, color: _dateRange != null ? _brand : Colors.grey.shade700)),
                  backgroundColor: _dateRange != null ? _brand.withOpacity(0.1) : Colors.grey.shade100,
                  side: BorderSide(color: _dateRange != null ? _brand : Colors.grey.shade300),
                  onPressed: _pickDateRange,
                ),
                const SizedBox(width: 8),
                // Category Chip
                _buildDropdownChip('Category', _catFilter, _categories, (v) { _catFilter = v ?? 'All'; _applyFilters(); }),
                const SizedBox(width: 8),
                // Reference Chip
                _buildDropdownChip('Reference', _refFilter, _references, (v) { _refFilter = v ?? 'All'; _applyFilters(); }),
                // Clear All
                if (hasActiveFilter) ...[
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.clear_all, size: 14, color: Colors.red),
                    label: const Text('Clear', style: TextStyle(fontSize: 12, color: Colors.red)),
                    backgroundColor: Colors.red.withOpacity(0.06),
                    side: const BorderSide(color: Colors.red),
                    onPressed: () { _dateRange = null; _catFilter = 'All'; _refFilter = 'All'; _applyFilters(); },
                  ),
                ],
              ],
            ),
          ),
        ),

        // Summary Stats Row
        if (!_isLoading && _filtered.isNotEmpty)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Row(
              children: [
                _buildStatChip(Icons.receipt_long, '${_filtered.length}', 'Bookings'),
                const SizedBox(width: 8),
                _buildStatChip(Icons.people, '$totalHissah', 'Hissahs'),
                const SizedBox(width: 8),
                _buildStatChip(Icons.account_balance_wallet, '${widget.settings.currencySymbol}${totalAmount.toStringAsFixed(0)}', 'Collected'),
              ],
            ),
          ),

        // Reference Breakdown Toggle
        if (!_isLoading && _filtered.isNotEmpty && widget.settings.referenceAsDropdown)
          Container(
            color: Colors.white,
            child: InkWell(
              onTap: () => setState(() => _showRefBreakdown = !_showRefBreakdown),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Icon(_showRefBreakdown ? Icons.expand_less : Icons.expand_more, color: _brand, size: 20),
                    const SizedBox(width: 6),
                    Text('Reference Breakdown', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _brand)),
                    const Spacer(),
                    Text('${_refBreakdownMap.length} sources', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ),
          ),

        // Reference Breakdown Details
        if (_showRefBreakdown && _filtered.isNotEmpty)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: _refBreakdownMap.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: _brand.withOpacity(0.04), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Icon(Icons.group, size: 16, color: _brand),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
                      Text('${e.value.count} bookings', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      const SizedBox(width: 12),
                      Text('${e.value.hissahs} hissah', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      const SizedBox(width: 12),
                      Text('${widget.settings.currencySymbol}${e.value.amount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _brand)),
                    ],
                  ),
                ),
              )).toList(),
            ),
          ),

        // Divider
        Container(height: 1, color: Colors.grey.shade200),

        // Booking List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: _brand))
              : _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text(hasActiveFilter ? 'No results for applied filters' : 'No bookings yet.', style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: _brand,
                      onRefresh: _loadBookings,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filtered.length,
                        itemBuilder: (ctx, i) {
                          final b = _filtered[i];
                          final date = DateTime.tryParse(b['created_at'] ?? '')?.toLocal();
                          final dateStr = date != null ? '${date.day}/${date.month}/${date.year}' : '';
                          final hissah = b['hissah_count'] ?? 0;
                          final amount = (b['total_amount'] ?? 0).toDouble();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white, borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade100),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                await showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
                                  builder: (ctx) => _BookingDetailSheet(bookingId: b['id'], settings: widget.settings));
                                _loadBookings();
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: _brand.withOpacity(0.1), radius: 24,
                                      child: Text(
                                        (b['representative_name'] ?? 'N').toString().isNotEmpty
                                            ? (b['representative_name'] ?? 'N').toString().substring(0, 1).toUpperCase() : 'N',
                                        style: const TextStyle(color: _brand, fontWeight: FontWeight.bold, fontSize: 18),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(b['representative_name'] ?? 'No Name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis, maxLines: 1),
                                          const SizedBox(height: 4),
                                          Row(children: [
                                            Icon(Icons.receipt, size: 13, color: Colors.grey.shade500),
                                            const SizedBox(width: 4),
                                            Flexible(child: Text('${b['receipt_no'] ?? ''}${dateStr.isNotEmpty ? '  •  $dateStr' : ''}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12), overflow: TextOverflow.ellipsis)),
                                          ]),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('${widget.settings.currencySymbol}${amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _brand)),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(color: _brand.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                                          child: Text('$hissah Hissah', style: const TextStyle(fontSize: 11, color: _brand, fontWeight: FontWeight.w600)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildDropdownChip(String label, String value, List<String> options, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: value != 'All' ? _brand.withOpacity(0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: value != 'All' ? _brand : Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down, size: 18, color: value != 'All' ? _brand : Colors.grey.shade600),
          style: TextStyle(fontSize: 12, color: value != 'All' ? _brand : Colors.grey.shade700),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o == 'All' ? label : o))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(color: _brand.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: _brand),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _brand), overflow: TextOverflow.ellipsis),
                  Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefBreakdown {
  int count = 0;
  int hissahs = 0;
  double amount = 0;
}


class _MoveEntrySheet extends StatefulWidget {
  final List<Map<String, dynamic>> entries;
  final List<Map<String, dynamic>> allTokens;
  final VoidCallback onRefresh;

  const _MoveEntrySheet({required this.entries, required this.allTokens, required this.onRefresh});

  @override
  State<_MoveEntrySheet> createState() => _MoveEntrySheetState();
}

class _MoveEntrySheetState extends State<_MoveEntrySheet> {
  static const Color _brand = Color(0xFF0D5C46);
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final bool isGroup = widget.entries.length > 1;
    final int requiredSlots = widget.entries.length;
    final List<int> sourceTokenIds = widget.entries.map((e) => e['token_id'] as int).toSet().toList();

    // 1. Available Tokens with ENOUGH free space
    final availableTokens = widget.allTokens.where((t) => 
      !sourceTokenIds.contains(t['id']) && 
      t['qurbani_done'] == false &&
      (t['max_slots'] - t['filled_slots']) >= requiredSlots
    ).toList();

    // 2. All other people to SWAP with (only relevant if isGroup == false)
    final List<Map<String, dynamic>> allOtherPeople = [];
    if (!isGroup) {
      for (var t in widget.allTokens) {
        if (t['qurbani_done'] == true) continue;
        final ents = List<dynamic>.from(t['entries'] ?? []);
        for (var e in ents) {
          if (e['id'] != widget.entries.first['id']) {
            allOtherPeople.add({
              ...e,
              'token_no': t['token_no'],
              'category_title': t['category_title'],
            });
          }
        }
      }
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header — always shown
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
            child: Row(
              children: [
                CircleAvatar(backgroundColor: _brand.withOpacity(0.1), child: const Icon(Icons.person, color: _brand)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Reassigning', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(isGroup ? '${widget.entries.length} People Selected' : widget.entries.first['owner_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          // Body — branch based on group vs single
          Expanded(
            child: _isSaving 
              ? const Center(child: CircularProgressIndicator())
              : isGroup
                ? _buildMoveList(availableTokens, requiredSlots)
                : DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        TabBar(
                          labelColor: _brand,
                          unselectedLabelColor: Colors.grey,
                          indicatorColor: _brand,
                          tabs: const [
                            Tab(text: 'Move to Slot'),
                            Tab(text: 'Swap Person'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildMoveList(availableTokens, requiredSlots),
                              // SWAP TAB
                              ListView(
                                padding: const EdgeInsets.all(16),
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 16),
                                    child: Text('Select someone to instantly swap places with:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                                  ),
                                  if (allOtherPeople.isEmpty)
                                    const Center(child: Text('No one else to swap with.', style: TextStyle(color: Colors.grey))),
                                  ...allOtherPeople.map((p) => Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: CircleAvatar(backgroundColor: Colors.orange.shade50, child: const Icon(Icons.swap_calls, color: Colors.orange)),
                                      title: Text(p['owner_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                      subtitle: Text('Currently in Token #${p['token_no']}'),
                                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                                      onTap: () async {
                                        setState(() => _isSaving = true);
                                        final res = await DatabaseService.swapTokenEntries(widget.entries.first['id'], p['id']);
                                        if (res['success'] == true) {
                                          Navigator.pop(context);
                                          widget.onRefresh();
                                        } else {
                                          setState(() => _isSaving = false);
                                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message']), backgroundColor: Colors.red));
                                        }
                                      },
                                    ),
                                  )),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoveList(List<Map<String, dynamic>> availableTokens, int requiredSlots) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: _brand, foregroundColor: Colors.white, padding: const EdgeInsets.all(16)),
          onPressed: () async {
            setState(() => _isSaving = true);
            final ids = widget.entries.map((e) => e['id'] as int).toList();
            final res = await DatabaseService.bulkMoveEntries(ids, null);
            if (res['success'] == true) {
              Navigator.pop(context);
              widget.onRefresh();
            } else {
              setState(() => _isSaving = false);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message']), backgroundColor: Colors.red));
            }
          },
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Extract into a Brand New Token', style: TextStyle(fontSize: 16)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('OR MOVE TO EXISTING TOKEN:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
        ),
        if (availableTokens.isEmpty)
          Center(child: Text('No other tokens have $requiredSlots empty slot(s).', style: const TextStyle(color: Colors.grey))),
        ...availableTokens.map((t) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: Colors.blue.shade50, child: Text('${t['token_no']}', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
            title: Text('Token #${t['token_no']} (${t['category_title']})', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${t['max_slots'] - t['filled_slots']} slots free'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () async {
              setState(() => _isSaving = true);
              final ids = widget.entries.map((e) => e['id'] as int).toList();
              final res = await DatabaseService.bulkMoveEntries(ids, t['id']);
              if (res['success'] == true) {
                Navigator.pop(context);
                widget.onRefresh();
              } else {
                setState(() => _isSaving = false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message']), backgroundColor: Colors.red));
              }
            },
          ),
        )),
      ],
    );
  }
}

