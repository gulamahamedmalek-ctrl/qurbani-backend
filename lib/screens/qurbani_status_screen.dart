import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/form_settings.dart';

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
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      floatingActionButton: _buildFloatingActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      appBar: AppBar(
        title: const Text('Advanced Execution Engine'),
        backgroundColor: _brand,
        actions: const [],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
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

  // ════════════════════════════════════════════════════════
  // ADVANCED DASHBOARD WIDGETS
  // ════════════════════════════════════════════════════════

  Widget _buildAdvancedFilterDashboard() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Row 1: Stats & Global Search
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
                  controller: TextEditingController.fromValue(TextEditingValue(text: _searchQuery, selection: TextSelection.collapsed(offset: _searchQuery.length))),
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
          
          // Row 2: Advanced Filter Dropdowns
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
                // Date Picker Button
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4, left: 2),
                      child: Text('Booking Date', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                    ),
                    InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _filterDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                          builder: (context, child) => Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: const ColorScheme.light(primary: _brand),
                            ),
                            child: child!,
                          ),
                        );
                        if (d != null) {
                          setState(() => _filterDate = d);
                          _applyFilters();
                        }
                      },
                      child: Container(
                        height: 38, // adjusted to match dropdowns
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: _filterDate != null ? _brand : Colors.grey.shade300, width: _filterDate != null ? 1.5 : 1),
                          borderRadius: BorderRadius.circular(8),
                          color: _filterDate != null ? _brand.withOpacity(0.05) : Colors.transparent,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.calendar_month, size: 16, color: _filterDate != null ? _brand : Colors.grey.shade700),
                            const SizedBox(width: 6),
                            Text(
                              _filterDate != null ? '${_filterDate!.day}/${_filterDate!.month}/${_filterDate!.year}' : 'All Dates',
                              style: TextStyle(fontSize: 13, color: _filterDate != null ? _brand : Colors.grey.shade800, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(padding: EdgeInsets.only(bottom: 4), child: Text('', style: TextStyle(fontSize: 11))),
                    TextButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reset'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Row 3: Batch Actions Bar
          if (_filteredTokens.any((t) => t['qurbani_done'] != true)) ...[
            const Divider(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text('${_filteredTokens.length} viewable results', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                TextButton(onPressed: _selectAllPending, child: const Text('Select All Pending')),
                if (_selectedTokenIds.isNotEmpty) 
                  TextButton(onPressed: _clearSelection, child: const Text('Clear Selection', style: TextStyle(color: Colors.red))),
              ],
            )
          ]
        ],
      ),
    );
  }

  Widget _buildDropdownFilter(String label, List<String> options, String currentValue, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4, left: 2),
          child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
        ),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentValue,
              icon: const Icon(Icons.arrow_drop_down, size: 16),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
              items: options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════
  // INLINE EXPANDABLE DATA ROW
  // ════════════════════════════════════════════════════════

  Widget _buildExpandableTokenRow(Map<String, dynamic> token) {
    final bool isDone = token['qurbani_done'] == true;
    final int id = token['id'];
    final bool isSelected = _selectedTokenIds.contains(id);
    final entries = List<Map<String, dynamic>>.from(token['entries'] ?? []);
    final int max = token['max_slots'] ?? 7;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isSelected ? _brand : Colors.grey.shade200, width: isSelected ? 1.5 : 1),
        boxShadow: [ BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)) ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.only(left: 8, right: 16),
          leading: Checkbox(
            value: isSelected,
            activeColor: _brand,
            onChanged: (v) {
              setState(() {
                if (v == true) _selectedTokenIds.add(id);
                else _selectedTokenIds.remove(id);
              });
            },
          ),
          title: Row(
            children: [
              Container(
                width: 44,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(color: _brand.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Text('#${token['token_no']}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: _brand, fontSize: 13)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(token['category_title'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('${token['filled_slots']}/$max Hissah', style: TextStyle(fontSize: 11, color: Colors.grey.shade600), maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
                        if (isDone)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4)),
                            child: const Text('Done', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.green)),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4)),
                            child: const Text('Pending', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.orange)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          children: [
            // Expanded content (The Inner Details Table)
            Container(
              color: Colors.grey.shade50,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isDone && token['qurbani_done_at'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('Completed on: ${_formatDate(token['qurbani_done_at'].toString())}', style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
                    ),

                  // Inner table header
                  Row(
                    children: [
                      SizedBox(width: 30, child: Text('No.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.bold))),
                      Expanded(child: Text('Janaab / Owner Name', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.bold))),
                      SizedBox(width: 80, child: Text('Purpose', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.bold))),
                    ],
                  ),
                  const Divider(),

                  // Inner table rows
                  ...List.generate(max, (index) {
                    final e = index < entries.length ? entries[index] : null;
                    final bool isEmpty = e == null;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30, 
                            child: Text('${index + 1}', style: TextStyle(fontSize: 12, color: isEmpty ? Colors.grey.shade400 : Colors.grey.shade700, fontWeight: FontWeight.bold))
                          ),
                          Expanded(
                            child: Text(
                              isEmpty ? '—' : (e['owner_name'] ?? ''),
                              style: TextStyle(fontSize: 13, color: isEmpty ? Colors.grey.shade400 : Colors.black87),
                            )
                          ),
                          SizedBox(
                            width: 80, 
                            child: Text(
                              isEmpty ? '' : (e['purpose'] ?? ''), 
                              textAlign: TextAlign.right, 
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)
                            )
                          ),
                        ],
                      ),
                    );
                  }),

                  if (!isDone) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle, size: 18),
                        label: const Text('Mark this Qurbani as Done', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: _brand, foregroundColor: Colors.white),
                        onPressed: () async {
                          setState(() => _isMarkingBulk = true); // reuse loading state
                          final res = await DatabaseService.markQurbaniDone(id);
                          setState(() => _isMarkingBulk = false);
                          if (res['success'] == true) {
                            _selectedTokenIds.remove(id);
                            await _loadTokens();
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Token #$id marked Done!'), backgroundColor: Colors.green));
                          }
                        },
                      ),
                    ),
                  ]
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
