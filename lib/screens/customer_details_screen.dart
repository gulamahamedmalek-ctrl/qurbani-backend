import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../models/form_settings.dart';
import '../services/database_service.dart';
import '../services/receipt_generator.dart';
import '../widgets/success_dialog.dart';

class CustomerDetailsScreen extends StatefulWidget {
  final String qurbaniSize;
  final double portionAmount;
  final int hissahPerToken;
  final Map<String, dynamic>? existingBooking;
  final List<dynamic>? existingEntries;

  const CustomerDetailsScreen({
    super.key,
    required this.qurbaniSize,
    required this.portionAmount,
    this.hissahPerToken = 7,
    this.existingBooking,
    this.existingEntries,
  });

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  final _formKey = GlobalKey<FormState>();  // Form validation key
  FormSettings _settings = FormSettings();
  bool _isLoading = true;
  bool _isSubmitting = false;  // Prevent double-submit

  String _selectedPurpose = '';

  final TextEditingController _repNameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _hissahCountController = TextEditingController();

  // Dynamic owners list
  final List<TextEditingController> _ownerNameControllers = [];
  bool _isNiyatKeMutabik = false;
  bool _separateToken = false;

  // Custom field controllers (keyed by field ID)
  final Map<String, TextEditingController> _customFieldControllers = {};
  final Map<String, String?> _customDropdownValues = {};

  // Auto fields
  final String _currentDate = DateFormat('dd-MM-yyyy').format(DateTime.now());
  String _receiptNo = 'RCPT-1001';

  double _totalAmount = 0.0;

  @override
  void initState() {
    super.initState();
    
    if (widget.existingBooking != null) {
      final b = widget.existingBooking!;
      _repNameController.text = b['representative_name'] ?? '';
      _addressController.text = b['address'] ?? '';
      _mobileController.text = b['mobile'] ?? '';
      _referenceController.text = b['reference'] ?? '';
      _hissahCountController.text = (b['hissah_count'] ?? 1).toString();
      _selectedPurpose = b['purpose'] ?? '';
      _receiptNo = b['receipt_no'] ?? '';
      
      if (widget.existingEntries != null && widget.existingEntries!.isNotEmpty) {
        for (var e in widget.existingEntries!) {
          _ownerNameControllers.add(TextEditingController(text: e['owner_name']));
        }
      } else {
        _ownerNameControllers.add(TextEditingController());
      }
    } else {
      _ownerNameControllers.add(TextEditingController());
      _hissahCountController.text = '1';
    }

    _hissahCountController.addListener(_calculateTotal);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await DatabaseService.loadFormSettings();
    setState(() {
      _settings = settings;
      
      if (widget.existingBooking == null) {
        _selectedPurpose = settings.purposes.isNotEmpty ? settings.purposes.first : '';
        _receiptNo = '${settings.receiptPrefix}1001';
      } else {
        if (_selectedPurpose.isEmpty && settings.purposes.isNotEmpty) {
          _selectedPurpose = settings.purposes.first;
        }
      }

      // Initialize custom field controllers
      for (final field in settings.customFields) {
        _customFieldControllers[field.id] = TextEditingController();
      }

      if (widget.existingBooking != null && widget.existingBooking!['custom_fields_data'] != null) {
        try {
          final customData = widget.existingBooking!['custom_fields_data'];
          Map<String, dynamic> parsedData = {};
          if (customData is String) {
            parsedData = jsonDecode(customData);
          } else {
            parsedData = Map<String, dynamic>.from(customData);
          }
          
          for (final field in settings.customFields) {
            if (parsedData.containsKey(field.label)) {
              if (field.fieldType == 'dropdown') {
                _customDropdownValues[field.id] = parsedData[field.label]?.toString();
              } else {
                _customFieldControllers[field.id]?.text = parsedData[field.label]?.toString() ?? '';
              }
            }
          }
        } catch (_) {}
      }

      _isLoading = false;
    });
    _calculateTotal();
  }

  @override
  void dispose() {
    _repNameController.dispose();
    for (var controller in _ownerNameControllers) {
      controller.dispose();
    }
    _addressController.dispose();
    _mobileController.dispose();
    _referenceController.dispose();
    _hissahCountController.dispose();
    for (var c in _customFieldControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _calculateTotal() {
    int hissahCount = int.tryParse(_hissahCountController.text) ?? 0;
    if (hissahCount > widget.hissahPerToken) {
      hissahCount = widget.hissahPerToken;
      _hissahCountController.text = hissahCount.toString();
    }
    setState(() {
      _totalAmount = hissahCount * widget.portionAmount;
    });
  }

  void _addOwnerField() {
    if (_ownerNameControllers.length < widget.hissahPerToken) {
      setState(() {
        _ownerNameControllers.add(TextEditingController());
        if (_isNiyatKeMutabik) {
          _ownerNameControllers.last.text = "Niyat ke mutabik";
        }
        _hissahCountController.text = _ownerNameControllers.length.toString();
      });
    }
  }

  void _removeOwnerField(int index) {
    setState(() {
      _ownerNameControllers[index].dispose();
      _ownerNameControllers.removeAt(index);
      _hissahCountController.text = _ownerNameControllers.length.toString();
    });
  }

  void _toggleNiyat(bool? val) {
    setState(() {
      _isNiyatKeMutabik = val ?? false;
      if (_isNiyatKeMutabik) {
        for (var c in _ownerNameControllers) {
          c.text = "Niyat ke mutabik";
        }
      } else {
        for (var c in _ownerNameControllers) {
          if (c.text == "Niyat ke mutabik") c.clear();
        }
      }
    });
  }

  // ═══════════════════════════════════════════════════════
  // VALIDATION HELPERS — Reusable validators
  // ═══════════════════════════════════════════════════════
  String? _validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  String? _validateMobile(String? value) {
    if (value == null || value.trim().isEmpty) return 'Mobile number is required';
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 10) return 'Mobile number must be at least 10 digits';
    if (digits.length > 15) return 'Mobile number is too long';
    return null;
  }

  Widget _buildTextField(String label, TextEditingController controller, {
    TextInputType type = TextInputType.text,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        keyboardType: type,
        enabled: enabled,
        decoration: InputDecoration(labelText: label),
        validator: validator,
      ),
    );
  }

  Widget _buildCustomField(CustomField field) {
    if (field.fieldType == 'dropdown') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: DropdownButtonFormField<String>(
          value: _customDropdownValues[field.id],
          decoration: InputDecoration(labelText: '${field.label}${field.isRequired ? " *" : ""}'),
          items: field.dropdownOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
          onChanged: (val) => setState(() => _customDropdownValues[field.id] = val),
          validator: field.isRequired ? (val) => val == null || val.isEmpty ? '${field.label} is required' : null : null,
        ),
      );
    }

    TextInputType keyType = TextInputType.text;
    if (field.fieldType == 'number') keyType = TextInputType.number;
    if (field.fieldType == 'phone') keyType = TextInputType.phone;

    return _buildTextField(
      '${field.label}${field.isRequired ? " *" : ""}',
      _customFieldControllers[field.id] ?? TextEditingController(),
      type: keyType,
      validator: field.isRequired ? (val) => _validateRequired(val, field.label) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Customer Details')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Auto Fields Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: Text('Date: $_currentDate', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
                  Flexible(child: Text('Receipt No: $_receiptNo', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary))),
                ],
              ),
              const Divider(height: 32),

              // Dynamic Purpose Selection
              if (_settings.purposes.isNotEmpty) ...[
                const Text('Purpose', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                ..._settings.purposes.map((purpose) {
                  return RadioListTile<String>(
                    value: purpose,
                    groupValue: _selectedPurpose,
                    onChanged: (val) => setState(() => _selectedPurpose = val!),
                    title: Text(purpose, style: const TextStyle(fontSize: 14)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  );
                }),
                const SizedBox(height: 8),
              ],

              // Rep Name (conditional)
              if (_settings.showRepresentativeName)
                _buildTextField('Representative Name *', _repNameController,
                  validator: (val) => _validateRequired(val, 'Representative Name'),
                ),

              // Name in the Qurbani
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Flexible(
                    child: Text('Name in the Qurbani', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _isNiyatKeMutabik,
                          onChanged: _toggleNiyat,
                          activeColor: theme.colorScheme.primary,
                          visualDensity: VisualDensity.compact,
                        ),
                        const Flexible(child: Text('Niyat ke mutabik', style: TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                ],
              ),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _ownerNameControllers.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _ownerNameControllers[index],
                            enabled: !_isNiyatKeMutabik,
                            decoration: InputDecoration(labelText: 'Name ${index + 1} *'),
                            validator: (val) => _validateRequired(val, 'Name ${index + 1}'),
                          ),
                        ),
                        if (_ownerNameControllers.length > 1)
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: _isNiyatKeMutabik ? null : () => _removeOwnerField(index),
                          ),
                      ],
                    ),
                  );
                },
              ),

              // Add button — always visible, disabled when at max or niyat mode
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: (_ownerNameControllers.length < widget.hissahPerToken && !_isNiyatKeMutabik) ? _addOwnerField : null,
                  icon: const Icon(Icons.add),
                  label: Text('Add Another Name (Max ${widget.hissahPerToken})'),
                ),
              ),

              const SizedBox(height: 24),

              // Standard Fields (conditional)
              if (_settings.showAddress)
                _buildTextField('Address', _addressController,
                  type: TextInputType.streetAddress,
                  validator: (val) => _validateRequired(val, 'Address'),
                ),
              if (_settings.showMobileNumber)
                _buildTextField('Mobile Number *', _mobileController,
                  type: TextInputType.phone,
                  validator: _validateMobile,
                ),

              // Reference field — text or dropdown
              if (_settings.showReference) ...[
                if (_settings.referenceAsDropdown && _settings.referenceOptions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: DropdownButtonFormField<String>(
                      value: _referenceController.text.isNotEmpty && _settings.referenceOptions.contains(_referenceController.text) ? _referenceController.text : null,
                      decoration: const InputDecoration(labelText: 'Reference'),
                      isExpanded: true,
                      items: _settings.referenceOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
                      selectedItemBuilder: (context) {
                        return _settings.referenceOptions.map((opt) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Text(opt, overflow: TextOverflow.ellipsis, maxLines: 1),
                          );
                        }).toList();
                      },
                      onChanged: (val) => _referenceController.text = val ?? '',
                    ),
                  )
                else
                  _buildTextField('Reference (How did you hear about us?)', _referenceController),
              ],

              // Dynamic Custom Fields
              ..._settings.customFields.map((f) => _buildCustomField(f)),

              // Hissah count (auto-counted, read-only)
              _buildTextField('Number of Hissah (Auto-counted, Max ${widget.hissahPerToken})', _hissahCountController, type: TextInputType.number, enabled: false),

              const SizedBox(height: 16),

              // Total Calculation Box
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(child: Text('Total Amount:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('${_settings.currencySymbol}${_totalAmount.toStringAsFixed(2)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Separate Token checkbox
              if (widget.existingBooking == null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _separateToken ? const Color(0xFF0D5C46).withOpacity(0.08) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _separateToken ? const Color(0xFF0D5C46) : Colors.grey.shade300),
                  ),
                  child: CheckboxListTile(
                    value: _separateToken,
                    onChanged: (val) => setState(() => _separateToken = val ?? false),
                    activeColor: const Color(0xFF0D5C46),
                    title: const Text('Keep Family Together', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    subtitle: const Text('Creates a dedicated token for this booking so all members stay in the same animal.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    secondary: Icon(_separateToken ? Icons.family_restroom : Icons.group, color: _separateToken ? const Color(0xFF0D5C46) : Colors.grey),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),

              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: _isSubmitting ? null : () async {
                  // STEP 1: Validate all form fields
                  if (!_formKey.currentState!.validate()) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please fix the errors above before submitting.'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }

                  // STEP 2: Prevent double-submit
                  setState(() => _isSubmitting = true);

                  // Collect owner names
                  final ownerNames = _ownerNameControllers
                      .map((c) => c.text.trim())
                      .where((n) => n.isNotEmpty)
                      .toList();

                  // Collect custom field values
                  final customData = <String, dynamic>{};
                  for (final field in _settings.customFields) {
                    if (field.fieldType == 'dropdown') {
                      customData[field.label] = _customDropdownValues[field.id] ?? '';
                    } else {
                      customData[field.label] = _customFieldControllers[field.id]?.text.trim() ?? '';
                    }
                  }

                  if (widget.existingBooking != null) {
                    final payload = {
                      'category_title': widget.qurbaniSize,
                      'amount_per_hissah': widget.portionAmount,
                      'purpose': _selectedPurpose,
                      'representative_name': _repNameController.text.trim(),
                      'owner_names': ownerNames,
                      'hissah_count': int.tryParse(_hissahCountController.text) ?? 1,
                      'total_amount': _totalAmount,
                      'address': _addressController.text.trim(),
                      'mobile': _mobileController.text.trim(),
                      'reference': _referenceController.text.trim(),
                      'custom_fields_data': customData,
                    };
                    final result = await DatabaseService.editBooking(widget.existingBooking!['id'], payload);
                    
                    if (!mounted) return;
                    setState(() => _isSubmitting = false);
                    
                    if (result['success'] == true) {
                       Navigator.pop(context, true);
                    } else {
                       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${result['message']}'), backgroundColor: Colors.red));
                    }
                  } else {
                    final result = await DatabaseService.createBooking(
                      categoryTitle: widget.qurbaniSize,
                      amountPerHissah: widget.portionAmount,
                      purpose: _selectedPurpose,
                      representativeName: _repNameController.text.trim(),
                      ownerNames: ownerNames,
                      hissahCount: int.tryParse(_hissahCountController.text) ?? 1,
                      totalAmount: _totalAmount,
                      address: _addressController.text.trim(),
                      mobile: _mobileController.text.trim(),
                      reference: _referenceController.text.trim(),
                      customFieldsData: customData,
                      separateToken: _separateToken,
                    );

                    if (!mounted) return;
                    setState(() => _isSubmitting = false);

                    if (result['success'] == true) {
                    final receiptNo = result['data']?['receipt_no'] ?? '';
                    final tokenAssignments = (result['data']?['token_assignments'] as List<dynamic>?)
                        ?.map((a) => Map<String, dynamic>.from(a))
                        .toList() ?? [];
                    final ownerNames = _ownerNameControllers
                        .map((c) => c.text.trim())
                        .where((n) => n.isNotEmpty)
                        .toList();
                    if (!mounted) return;
                    await showBookingSuccessDialog(
                      context,
                      receiptNo: receiptNo,
                      categoryTitle: widget.qurbaniSize,
                      totalAmount: _totalAmount,
                      hissahCount: int.tryParse(_hissahCountController.text) ?? 1,
                      currencySymbol: _settings.currencySymbol,
                      tokenAssignments: tokenAssignments,
                      onDownloadReceipt: () {
                        ReceiptGenerator.generateAndPrint(
                          receiptNo: receiptNo,
                          date: _currentDate,
                          categoryTitle: widget.qurbaniSize,
                          representativeName: _repNameController.text.trim(),
                          referenceName: _referenceController.text.trim(),
                          ownerNames: ownerNames,
                          address: _addressController.text.trim(),
                          mobile: _mobileController.text.trim(),
                          purpose: _selectedPurpose,
                          amountPerHissah: widget.portionAmount,
                          hissahCount: int.tryParse(_hissahCountController.text) ?? 1,
                          totalAmount: _totalAmount,
                          currencySymbol: _settings.currencySymbol,
                          organizationName: _settings.organizationName,
                          tokenAssignments: tokenAssignments,
                          maxSlots: widget.hissahPerToken,
                          logoBase64: _settings.logoBase64,
                        );
                      },
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: ${result['message']}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  }
                },
                child: _isSubmitting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Submit Booking'),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
