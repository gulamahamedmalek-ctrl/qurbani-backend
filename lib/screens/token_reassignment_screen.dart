import 'package:flutter/material.dart';
import '../services/database_service.dart';

class TokenReassignmentScreen extends StatefulWidget {
  const TokenReassignmentScreen({super.key});
  @override
  State<TokenReassignmentScreen> createState() => _TokenReassignmentScreenState();
}

class _TokenReassignmentScreenState extends State<TokenReassignmentScreen> {
  static const Color _brand = Color(0xFF0D5C46);
  bool _isLoading = true;
  List<Map<String, dynamic>> _tokens = [];
  
  // Selection State
  List<int> _selectedEntryIds = [];
  
  @override
  void initState() {
    super.initState();
    _loadTokens();
  }

  Future<void> _loadTokens() async {
    setState(() => _isLoading = true);
    final data = await DatabaseService.loadTokens();
    if (mounted) {
      setState(() {
        _tokens = data.where((t) => t['qurbani_done'] != true).toList();
        _selectedEntryIds.clear();
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSwap(int entry1Id, int entry2Id) async {
    setState(() => _isLoading = true);
    final res = await DatabaseService.swapTokenEntries(entry1Id, entry2Id);
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Swapped successfully'), backgroundColor: _brand));
      await _loadTokens();
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${res['message']}'), backgroundColor: Colors.red));
    }
  }

  Future<void> _handleBulkMove(int? targetTokenId) async {
    setState(() => _isLoading = true);
    final res = await DatabaseService.bulkMoveEntries(_selectedEntryIds, targetTokenId);
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Moved successfully'), backgroundColor: _brand));
      await _loadTokens();
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${res['message']}'), backgroundColor: Colors.red));
    }
  }

  void _onEntryTapped(int entryId) {
    setState(() {
      if (_selectedEntryIds.contains(entryId)) {
        _selectedEntryIds.remove(entryId);
      } else {
        if (_selectedEntryIds.length == 1) {
          // If 1 is already selected, tapping another ONE could trigger a swap prompt
          _showSwapOrSelectDialog(entryId);
        } else {
          _selectedEntryIds.add(entryId);
        }
      }
    });
  }
  
  void _showSwapOrSelectDialog(int secondEntryId) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Action'),
      content: const Text('Do you want to SWAP these two people, or just select both of them to move as a group?'),
      actions: [
        TextButton(onPressed: () {
          Navigator.pop(ctx);
          setState(() => _selectedEntryIds.add(secondEntryId));
        }, child: const Text('Select Both', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _brand, foregroundColor: Colors.white),
          onPressed: () {
            Navigator.pop(ctx);
            _handleSwap(_selectedEntryIds.first, secondEntryId);
          }, 
          child: const Text('Swap Them')
        )
      ],
    ));
  }

  Widget _buildTokenCard(Map<String, dynamic> token) {
    final int max = token['max_slots'] ?? 7;
    final int filled = token['filled_slots'] ?? 0;
    final entries = List<dynamic>.from(token['entries'] ?? []);
    entries.sort((a, b) => (a['serial_no'] ?? 0).compareTo(b['serial_no'] ?? 0));

    return Container(
      width: 300,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _brand.withOpacity(0.05), borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Token #${token['token_no']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text('$filled/$max', style: TextStyle(fontWeight: FontWeight.bold, color: filled >= max ? Colors.red : _brand)),
              ],
            ),
          ),
          // Slots
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: max,
              itemBuilder: (context, i) {
                if (i < entries.length) {
                  final e = entries[i];
                  final isSelected = _selectedEntryIds.contains(e['id']);
                  return InkWell(
                    onTap: () => _onEntryTapped(e['id']),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue.shade50 : Colors.grey.shade50,
                        border: Border.all(color: isSelected ? Colors.blue : Colors.grey.shade200, width: isSelected ? 2 : 1),
                        borderRadius: BorderRadius.circular(8)
                      ),
                      child: Row(
                        children: [
                          Icon(isSelected ? Icons.check_circle : Icons.person, size: 16, color: isSelected ? Colors.blue : _brand),
                          const SizedBox(width: 8),
                          Expanded(child: Text(e['owner_name'], style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal))),
                        ],
                      ),
                    ),
                  );
                } else {
                  // Empty slot
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                      borderRadius: BorderRadius.circular(8)
                    ),
                    child: const Text('Empty Slot', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                  );
                }
              },
            ),
          ),
          // Move Here Button
          if (_selectedEntryIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brand, foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 40)
                ),
                onPressed: (max - filled) >= _selectedEntryIds.length ? () => _handleBulkMove(token['id']) : null,
                icon: const Icon(Icons.download),
                label: const Text('Move Here'),
              ),
            )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Visual Shuffling Board'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        actions: [
          if (_selectedEntryIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(child: Text('${_selectedEntryIds.length} Selected', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadTokens),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Tap names to select them. Then tap "Move Here" on any token.', style: TextStyle(color: Colors.grey.shade700)),
                ),
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _tokens.length + 1, // +1 for "Create New Token" card
                    itemBuilder: (context, index) {
                      if (index == _tokens.length) {
                        return _buildCreateNewTokenCard();
                      }
                      return _buildTokenCard(_tokens[index]);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCreateNewTokenCard() {
    return Container(
      width: 250,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: _brand.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _brand.withOpacity(0.3), style: BorderStyle.solid, width: 2),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_circle_outline, size: 48, color: _brand.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text('Brand New Token', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Extract selected people\ninto an empty token', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            if (_selectedEntryIds.isNotEmpty)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _brand, foregroundColor: Colors.white),
                onPressed: () => _handleBulkMove(null),
                icon: const Icon(Icons.output),
                label: const Text('Extract Here'),
              )
          ],
        ),
      ),
    );
  }
}
