import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../services/platform_helper.dart';
import '../models/qurbani_category.dart';
import '../models/form_settings.dart';
import '../services/database_service.dart';
import '../widgets/validated_dropdown.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<QurbaniCategory> _categories = [];
  FormSettings _settings = FormSettings();
  FormSettings _originalSettings = FormSettings(); // Snapshot to detect changes
  bool _isLoading = true;
  bool _hasUnsavedChanges = false;

  // Controllers for Receipt Settings
  final _orgCtrl = TextEditingController();
  final _prefixCtrl = TextEditingController();
  final _startNumCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() => setState(() {})); // Rebuild UI on every tab switch
    _loadAll();
  }

  @override
  void dispose() {
    _orgCtrl.dispose();
    _prefixCtrl.dispose();
    _startNumCtrl.dispose();
    _currencyCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final cats = await DatabaseService.loadCategories();
    final settings = await DatabaseService.loadFormSettings();
    
    // Defensive: Clean the logo data if it contains a Data URL prefix
    if (settings.logoBase64.contains(',')) {
      settings.logoBase64 = settings.logoBase64.split(',').last;
    }

    setState(() {
      _categories = cats;
      _settings = settings;
      _originalSettings = FormSettings.fromJson(settings.toJson()); // Deep copy snapshot
      _hasUnsavedChanges = false;
      _isLoading = false;
      _orgCtrl.text = _settings.organizationName;
      _prefixCtrl.text = _settings.receiptPrefix;
      _startNumCtrl.text = _settings.startingReceiptNumber.toString();
      _currencyCtrl.text = _settings.currencySymbol;
    });
  }

  Future<void> _saveCategories() async {
    await DatabaseService.saveCategories(_categories);
    _loadAll();
  }

  void _markDirty() {
    if (!_hasUnsavedChanges) setState(() => _hasUnsavedChanges = true);
  }

  Future<void> _saveSettings() async {
    await DatabaseService.saveFormSettings(_settings);
    _originalSettings = FormSettings.fromJson(_settings.toJson()); // Update snapshot
    setState(() => _hasUnsavedChanges = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved!'), duration: Duration(seconds: 1)),
    );
  }

  /// Show unsaved changes dialog. Returns true if user wants to leave.
  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 40),
        title: const Text('Unsaved Changes', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('You have unsaved changes. What would you like to do?'),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D5C46),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Save & Exit'),
          ),
        ],
      ),
    );

    if (result == 'save') {
      await _saveSettings();
      return true;
    } else if (result == 'discard') {
      // Revert to original
      _settings = FormSettings.fromJson(_originalSettings.toJson());
      return true;
    }
    return false; // Dialog dismissed
  }

  // ═══════════════════════════════════════════════════════════
  // TAB 1 — Categories & Pricing
  // ═══════════════════════════════════════════════════════════
  Widget _buildCategoriesTab() {
    if (_categories.isEmpty) {
      return const Center(child: Text('No categories. Tap + to add.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final cat = _categories[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: ListTile(
            title: Text(cat.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${cat.subtitle}\nAmount: ${_settings.currencySymbol}${cat.amount.toStringAsFixed(2)} | ${cat.hissahPerToken} per token'),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showCategoryForm(cat, index)),
                IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteCategory(index)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCategoryForm([QurbaniCategory? existing, int? index]) {
    final isEditing = existing != null;
    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController(text: isEditing ? existing.title : '');
    final subtitleCtrl = TextEditingController(text: isEditing ? existing.subtitle : '');
    final amountCtrl = TextEditingController(text: isEditing ? existing.amount.toString() : '');
    final hissahPerTokenCtrl = TextEditingController(text: isEditing ? existing.hissahPerToken.toString() : '7');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 24, right: 24, top: 24),
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(isEditing ? 'Edit Category' : 'Add Category', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title (e.g. Heavy Qurbani) *'),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Title is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: subtitleCtrl,
                  decoration: const InputDecoration(labelText: 'Subtitle (e.g. Premium)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount *', prefixIcon: Icon(Icons.currency_rupee)),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Amount is required';
                    final amount = double.tryParse(val.trim());
                    if (amount == null || amount <= 0) return 'Enter a valid amount greater than 0';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: hissahPerTokenCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Hissah Per Token (e.g. Large Animal=7, Goat=1) *', prefixIcon: Icon(Icons.token)),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Hissah Per Token is required';
                    final num = int.tryParse(val.trim());
                    if (num == null || num < 1) return 'Must be at least 1';
                    if (num > 20) return 'Maximum is 20';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    final cat = QurbaniCategory(
                      id: isEditing ? existing.id : DateTime.now().millisecondsSinceEpoch.toString(),
                      title: titleCtrl.text.trim(),
                      subtitle: subtitleCtrl.text.trim(),
                      amount: double.tryParse(amountCtrl.text.trim()) ?? 0.0,
                      hissahPerToken: int.tryParse(hissahPerTokenCtrl.text.trim()) ?? 7,
                    );
                    if (isEditing && index != null) {
                      _categories[index] = cat;
                    } else {
                      _categories.add(cat);
                    }
                    _saveCategories();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _deleteCategory(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () { _categories.removeAt(index); _saveCategories(); Navigator.pop(ctx); },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TAB 2 — Form Builder
  // ═══════════════════════════════════════════════════════════
  Widget _buildFormBuilderTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Standard Field Toggles ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Standard Fields Visibility', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  SwitchListTile(title: const Text('Representative Name'), value: _settings.showRepresentativeName, onChanged: (v) { setState(() => _settings.showRepresentativeName = v); _markDirty(); }),
                  SwitchListTile(title: const Text('Address'), value: _settings.showAddress, onChanged: (v) { setState(() => _settings.showAddress = v); _markDirty(); }),
                  SwitchListTile(title: const Text('Mobile Number'), value: _settings.showMobileNumber, onChanged: (v) { setState(() => _settings.showMobileNumber = v); _markDirty(); }),
                  SwitchListTile(title: const Text('Reference'), value: _settings.showReference, onChanged: (v) { setState(() => _settings.showReference = v); _markDirty(); }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Custom Fields ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Custom Fields', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  if (_settings.customFields.isEmpty)
                    const Padding(padding: EdgeInsets.all(8), child: Text('No custom fields added yet.', style: TextStyle(color: Colors.grey))),
                  ..._settings.customFields.asMap().entries.map((entry) {
                    final i = entry.key;
                    final f = entry.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f.label, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                Text('Type: ${f.fieldType} • ${f.isRequired ? "Required" : "Optional"}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18, color: Colors.blue), 
                            onPressed: () => _showCustomFieldForm(f, i), 
                            padding: EdgeInsets.zero, 
                            constraints: const BoxConstraints()
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 18, color: Colors.red), 
                            onPressed: () { setState(() => _settings.customFields.removeAt(i)); _markDirty(); }, 
                            padding: EdgeInsets.zero, 
                            constraints: const BoxConstraints()
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          ElevatedButton(onPressed: _saveSettings, child: const Text('Save Form Settings')),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showCustomFieldForm([CustomField? existing, int? index]) {
    final isEditing = existing != null;
    final fieldFormKey = GlobalKey<FormState>();
    final labelCtrl = TextEditingController(text: isEditing ? existing.label : '');
    String selectedType = isEditing ? existing.fieldType : 'text';
    bool isRequired = isEditing ? existing.isRequired : false;
    final dropdownOptsCtrl = TextEditingController(text: isEditing ? existing.dropdownOptions.join(', ') : '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 24, right: 24, top: 24),
          child: SingleChildScrollView(
            child: Form(
              key: fieldFormKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(isEditing ? 'Edit Custom Field' : 'Add Custom Field', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: labelCtrl,
                    decoration: const InputDecoration(labelText: 'Field Label (e.g. CNIC Number) *'),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Field label is required' : null,
                  ),
                  const SizedBox(height: 12),
                  ValidatedDropdownMenu(
                    initialSelection: selectedType,
                    label: 'Field Type',
                    showLabelAbove: false,
                    expandedInsets: EdgeInsets.zero,
                    menuHeight: 200,
                    options: const ['text', 'number', 'phone', 'dropdown'],
                    onSelected: (val) => setSheetState(() => selectedType = val ?? 'text'),
                  ),
                  if (selectedType == 'dropdown') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: dropdownOptsCtrl,
                      decoration: const InputDecoration(labelText: 'Options (comma separated) *', hintText: 'Option 1, Option 2, Option 3'),
                      validator: (val) {
                        if (selectedType == 'dropdown' && (val == null || val.trim().isEmpty)) {
                          return 'Dropdown options are required';
                        }
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                  CheckboxListTile(title: const Text('Required Field'), value: isRequired, onChanged: (v) => setSheetState(() => isRequired = v ?? false)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      if (!fieldFormKey.currentState!.validate()) return;
                      final field = CustomField(
                        id: isEditing ? existing.id : DateTime.now().millisecondsSinceEpoch.toString(),
                        label: labelCtrl.text.trim(),
                        fieldType: selectedType,
                        isRequired: isRequired,
                        dropdownOptions: selectedType == 'dropdown' ? dropdownOptsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() : [],
                      );
                      setState(() {
                        if (isEditing && index != null) {
                          _settings.customFields[index] = field;
                        } else {
                          _settings.customFields.add(field);
                        }
                      });
                      _markDirty();
                      Navigator.pop(ctx);
                    },
                    child: const Text('Save Field'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TAB 3 — Purposes
  // ═══════════════════════════════════════════════════════════
  Widget _buildPurposesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Purpose Options', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('These appear as radio buttons on the booking form.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 12),
                  if (_settings.purposes.isEmpty)
                    const Text('No purposes defined.', style: TextStyle(color: Colors.grey)),
                  ..._settings.purposes.asMap().entries.map((entry) {
                    final i = entry.key;
                    final p = entry.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.radio_button_checked, size: 20, color: Colors.grey),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(p, overflow: TextOverflow.ellipsis),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18, color: Colors.blue), 
                            onPressed: () => _showPurposeForm(p, i), 
                            padding: EdgeInsets.zero, 
                            constraints: const BoxConstraints()
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 18, color: Colors.red), 
                            onPressed: () { setState(() => _settings.purposes.removeAt(i)); _markDirty(); }, 
                            padding: EdgeInsets.zero, 
                            constraints: const BoxConstraints()
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _saveSettings, child: const Text('Save Purposes')),
        ],
      ),
    );
  }

  void _showPurposeForm([String? existing, int? index]) {
    final purposeFormKey = GlobalKey<FormState>();
    final ctrl = TextEditingController(text: existing ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 24, right: 24, top: 24),
        child: SingleChildScrollView(
          child: Form(
            key: purposeFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(existing != null ? 'Edit Purpose' : 'Add Purpose', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: ctrl,
                  decoration: const InputDecoration(labelText: 'Purpose Name (e.g. Sadaqah) *'),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Purpose name is required';
                    // Check for duplicates
                    final trimmed = val.trim();
                    final isDuplicate = _settings.purposes.asMap().entries.any(
                      (e) => e.value.toLowerCase() == trimmed.toLowerCase() && e.key != index,
                    );
                    if (isDuplicate) return 'This purpose already exists';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    if (!purposeFormKey.currentState!.validate()) return;
                    setState(() {
                      if (index != null) {
                        _settings.purposes[index] = ctrl.text.trim();
                      } else {
                        _settings.purposes.add(ctrl.text.trim());
                      }
                    });
                    _markDirty();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TAB 4 — Receipt Settings (Branding + Logo + Preview)
  // ═══════════════════════════════════════════════════════════
  Widget _buildReceiptTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Organization Settings Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Organization Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _orgCtrl,
                    decoration: const InputDecoration(labelText: 'Organization Name', hintText: 'e.g. Madrasa Talimul Quran'),
                    onChanged: (v) {
                      _settings.organizationName = v;
                      _markDirty();
                      setState((){});
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _prefixCtrl,
                    decoration: const InputDecoration(labelText: 'Receipt Prefix Text', hintText: 'e.g. RCPT-'),
                    onChanged: (v) {
                      _settings.receiptPrefix = v;
                      _markDirty();
                      setState((){});
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _startNumCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Starting Receipt Number', hintText: 'e.g. 101'),
                    onChanged: (v) {
                      _settings.startingReceiptNumber = int.tryParse(v) ?? 1;
                      _markDirty();
                      setState((){});
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _currencyCtrl,
                    decoration: const InputDecoration(labelText: 'Currency Symbol', hintText: 'e.g. ₹, PKR, \$'),
                    onChanged: (v) {
                      _settings.currencySymbol = v;
                      _markDirty();
                      setState((){});
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Logo Upload Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Receipt Logo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('Upload your organization logo for the receipt header (optional).',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  const SizedBox(height: 16),

                  // Logo preview
                  Center(
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: _settings.logoBase64.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                base64Decode(_settings.logoBase64.contains(',') ? _settings.logoBase64.split(',').last : _settings.logoBase64),
                                fit: BoxFit.contain,
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.image, size: 40, color: Colors.grey.shade400),
                                const SizedBox(height: 4),
                                Text('No Logo', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                      ElevatedButton.icon(
                        onPressed: _pickLogo,
                        icon: const Icon(Icons.upload, size: 16),
                        label: const Text('Upload Logo', style: TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey.shade700,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      if (_settings.logoBase64.isNotEmpty) ...[
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() => _settings.logoBase64 = '');
                            _saveSettings();
                          },
                          icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                          label: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),

          // --- Rules Attachment Upload Section ---
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Receipt Attachment / Rules (Printed on next page)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Upload an image containing rules or instructions. It will be automatically appended as a second page to every receipt.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 20),
                  
                  Center(
                    child: Container(
                      width: 200,
                      height: 150,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: _settings.rulesAttachmentBase64.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                base64Decode(_settings.rulesAttachmentBase64.contains(',') ? _settings.rulesAttachmentBase64.split(',').last : _settings.rulesAttachmentBase64),
                                fit: BoxFit.contain,
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.description, size: 40, color: Colors.grey.shade400),
                                const SizedBox(height: 4),
                                Text('No Attachment', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _pickRulesAttachment,
                          icon: const Icon(Icons.upload, size: 16),
                          label: const Text('Upload Rules Image', style: TextStyle(fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey.shade700,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        if (_settings.rulesAttachmentBase64.isNotEmpty) ...[
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() => _settings.rulesAttachmentBase64 = '');
                              _saveSettings();
                            },
                            icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                            label: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

            ),
          ),

          const SizedBox(height: 16),

          // Receipt Preview Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Receipt Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),

                  // Mini receipt preview
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF0D5C46), width: 2),
                    ),
                    child: Column(
                      children: [
                        // Header
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D5C46),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              if (_settings.logoBase64.isNotEmpty) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.memory(
                                    base64Decode(_settings.logoBase64.contains(',') ? _settings.logoBase64.split(',').last : _settings.logoBase64),
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_settings.organizationName,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const Text('Qurbani Department',
                                        style: TextStyle(color: Colors.white70, fontSize: 10),
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('${_settings.receiptPrefix}1001',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const Text('20/04/2026',
                                        style: TextStyle(color: Colors.white70, fontSize: 10)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Sample fields
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('Name: Sample Name', style: TextStyle(fontSize: 11)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D5C46),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('Total: ${_settings.currencySymbol}2000',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          ElevatedButton(onPressed: _saveSettings, child: const Text('Save Receipt Settings')),
        ],
      ),
    );
  }

  /// Pick an image file from the user's device and convert to base64.
  Future<void> _pickLogo() async {
    final base64Image = await PlatformHelper.instance.pickImageAsBase64();
    if (base64Image != null) {
      // Handle data URI format: "data:image/png;base64,..."
      String cleanBase64 = base64Image;
      if (cleanBase64.contains(',')) {
        cleanBase64 = cleanBase64.split(',').last;
      }
      
      setState(() {
        _settings.logoBase64 = cleanBase64;
      });
      _saveSettings();
    }
  }

  /// Pick an image for rules attachment and convert to base64.
  Future<void> _pickRulesAttachment() async {
    final base64Image = await PlatformHelper.instance.pickImageAsBase64();
    if (base64Image != null) {
      String cleanBase64 = base64Image;
      if (cleanBase64.contains(',')) {
        cleanBase64 = cleanBase64.split(',').last;
      }
      
      setState(() {
        _settings.rulesAttachmentBase64 = cleanBase64;
      });
      _saveSettings();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // TAB 5 — Backup (Google Drive)
  // ═══════════════════════════════════════════════════════════
  bool _backupLoading = false;
  List<Map<String, dynamic>> _backupList = [];
  bool _backupListLoaded = false;

  Widget _buildBackupTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.blueGrey.shade800, Colors.blueGrey.shade600]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.cloud_upload, color: Colors.white, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('Google Drive Backup', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Your data is automatically backed up to Google Drive every 24 hours. You can also create manual backups or restore from a previous backup.',
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                ),
                const SizedBox(height: 16),
                // Backup Now Button
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _backupLoading ? null : _triggerBackup,
                    icon: _backupLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.backup),
                    label: Text(_backupLoading ? 'Creating Backup...' : 'Backup Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blueGrey.shade800,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Backup History
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Backup History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: _loadBackupList,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (!_backupListLoaded)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.cloud_queue, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text('Tap Refresh to load backup history', style: TextStyle(color: Colors.grey.shade500)),
                  ],
                ),
              ),
            )
          else if (_backupList.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text('No backups found', style: TextStyle(color: Colors.grey.shade500)),
                  ],
                ),
              ),
            )
          else
            ..._backupList.map((backup) {
              final filename = backup['filename'] ?? '';
              final sizeKb = backup['size_kb'] ?? 0;
              final createdAt = backup['created_at'] ?? '';
              final fileId = backup['gdrive_file_id'] ?? '';

              // Parse and format the date
              String displayDate = createdAt;
              try {
                final dt = DateTime.parse(createdAt).toLocal();
                displayDate = '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
              } catch (_) {}

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.cloud_done, color: Colors.green, size: 24),
                  ),
                  title: Text(displayDate, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text('${sizeKb} KB', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.restore, color: Colors.orange),
                    tooltip: 'Restore this backup',
                    onPressed: () => _confirmRestore(fileId, displayDate),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _triggerBackup() async {
    setState(() => _backupLoading = true);
    try {
      final result = await DatabaseService.createBackup(
        'taalimulquran@madrasa.com',
        'ahemfariza@0011',
      );
      if (mounted) {
        if (result['success'] == true) {
          final data = result['data'] ?? {};
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ Backup created! (${data['size_kb'] ?? 0} KB)'), backgroundColor: Colors.green),
          );
          _loadBackupList();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ ${result['message']}'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Backup failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _backupLoading = false);
  }

  Future<void> _loadBackupList() async {
    try {
      final result = await DatabaseService.listBackups();
      if (result['success'] == true && mounted) {
        setState(() {
          _backupList = List<Map<String, dynamic>>.from(result['data']?['backups'] ?? []);
          _backupListLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load backups: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _confirmRestore(String fileId, String dateStr) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('⚠️ Restore Backup?'),
        content: Text(
          'This will REPLACE all current bookings, tokens, and categories with the backup from:\n\n$dateStr\n\nThis action cannot be undone!',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _performRestore(fileId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Restore', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _performRestore(String fileId) async {
    setState(() => _backupLoading = true);
    try {
      final result = await DatabaseService.restoreBackup(
        'taalimulquran@madrasa.com',
        'ahemfariza@0011',
        fileId,
      );
      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Backup restored successfully!'), backgroundColor: Colors.green),
          );
          _loadAll(); // Reload all data
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ ${result['message']}'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Restore failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _backupLoading = false);
  }

  // ═══════════════════════════════════════════════════════════
  // TAB 6 — Settings (PIN + Reference Mode)
  // ═══════════════════════════════════════════════════════════
  Widget _buildSettingsTab() {
    final refOptsCtrl = TextEditingController(text: _settings.referenceOptions.join(', '));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          // Reference Mode
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reference Field Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Use Dropdown Instead of Text'),
                    subtitle: const Text('If enabled, reference becomes a dropdown'),
                    value: _settings.referenceAsDropdown,
                    onChanged: (v) { setState(() => _settings.referenceAsDropdown = v); _markDirty(); },
                  ),
                  if (_settings.referenceAsDropdown) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: refOptsCtrl,
                      decoration: const InputDecoration(labelText: 'Dropdown Options (comma separated)', hintText: 'Friend, Social Media, Masjid, Other'),
                      onChanged: (v) {
                        _settings.referenceOptions = v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                        _markDirty();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _saveSettings, child: const Text('Save Settings')),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // CONTEXT-AWARE FAB
  // ═══════════════════════════════════════════════════════════
  Widget? _buildFab() {
    final tabIndex = _tabController.index;

    // Tabs 3 (Receipt) and 4 (Settings) have no "add" action
    if (tabIndex == 3 || tabIndex == 4) return null;

    VoidCallback onPressed;
    String tooltip;

    switch (tabIndex) {
      case 0:
        onPressed = () => _showCategoryForm();
        tooltip = 'Add Category';
        break;
      case 1:
        onPressed = () => _showCustomFieldForm();
        tooltip = 'Add Custom Field';
        break;
      case 2:
        onPressed = () => _showPurposeForm();
        tooltip = 'Add Purpose';
        break;
      default:
        return null;
    }

    return FloatingActionButton(
      onPressed: onPressed,
      tooltip: tooltip,
      backgroundColor: Colors.blueGrey.shade800,
      child: const Icon(Icons.add, color: Colors.white),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final canLeave = await _confirmDiscard();
        if (canLeave && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.category, size: 20), text: 'Categories'),
            Tab(icon: Icon(Icons.build, size: 20), text: 'Form'),
            Tab(icon: Icon(Icons.flag, size: 20), text: 'Purposes'),
            Tab(icon: Icon(Icons.receipt_long, size: 20), text: 'Receipt & Branding'),
            Tab(icon: Icon(Icons.backup, size: 20), text: 'Backup'),
            Tab(icon: Icon(Icons.settings, size: 20), text: 'Settings'),
          ],
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildCategoriesTab(),
                  _buildFormBuilderTab(),
                  _buildPurposesTab(),
                  _buildReceiptTab(),
                  _buildBackupTab(),
                  _buildSettingsTab(),
                ],
              ),
      ),
      floatingActionButton: _buildFab(),
    ),
    );
  }
}
