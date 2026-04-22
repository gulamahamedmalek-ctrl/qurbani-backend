import 'package:flutter/material.dart';
import 'customer_details_screen.dart';
import 'admin_dashboard_screen.dart';
import '../services/database_service.dart';
import '../models/qurbani_category.dart';
import '../models/form_settings.dart';

class HissaConfigurationScreen extends StatefulWidget {
  const HissaConfigurationScreen({super.key});

  @override
  State<HissaConfigurationScreen> createState() => _HissaConfigurationScreenState();
}

class _HissaConfigurationScreenState extends State<HissaConfigurationScreen> {
  List<QurbaniCategory> _categories = [];
  QurbaniCategory? _selectedCategory;
  bool _isLoading = true;
  String _currencySymbol = '₹';
  
  int _adminTapCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    final data = await DatabaseService.loadCategories();
    final settings = await DatabaseService.loadFormSettings();
    setState(() {
      _categories = data;
      _currencySymbol = settings.currencySymbol;
      _isLoading = false;
      // Reset selection if it no longer exists
      if (_selectedCategory != null && !_categories.any((c) => c.id == _selectedCategory!.id)) {
        _selectedCategory = null;
      }
    });
  }

  void _onTitleTapped() {
    _adminTapCount++;
    if (_adminTapCount >= 5) {
      _adminTapCount = 0;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AdminDashboardScreen()),
      ).then((_) => _loadCategories()); // refresh data when returning from admin
    }
  }

  Widget _buildSelectionCard({
    required QurbaniCategory category,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
             color: isSelected ? theme.colorScheme.primary : Colors.grey.shade300,
             width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? theme.colorScheme.primary : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.scale_outlined,
                color: isSelected ? Colors.white : Colors.grey.shade500,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? theme.colorScheme.primary : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    category.subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Price: $_currencySymbol${category.amount.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: theme.colorScheme.primary,
                size: 26,
              )
            else
              Icon(
                Icons.radio_button_unchecked,
                color: Colors.grey.shade300,
                size: 26,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _onTitleTapped,
          child: const Text('Qurbani Hissah'),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48.0, // account for padding
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // TOP CONTENT
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Select Qurbani Category',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Choose the size of the Qurbani. Prices are predefined.',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.3),
                        ),
                        const SizedBox(height: 24),
                        
                        if (_isLoading)
                          const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
                        else if (_categories.isEmpty)
                          SizedBox(
                            height: 200,
                            child: Center(
                              child: Text(
                                'No categories available.\nAsk an admin to add them.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _categories.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 16),
                            itemBuilder: (context, index) {
                              final cat = _categories[index];
                              return _buildSelectionCard(
                                category: cat,
                                isSelected: _selectedCategory?.id == cat.id,
                                onTap: () {
                                  setState(() {
                                    _selectedCategory = cat;
                                  });
                                },
                              );
                            },
                          ),
                          
                        const SizedBox(height: 32), 
                      ],
                    ),
                    
                    // BOTTOM CONTENT
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton(
                          onPressed: _selectedCategory == null
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => CustomerDetailsScreen(
                                        qurbaniSize: _selectedCategory!.title,
                                        portionAmount: _selectedCategory!.amount,
                                        hissahPerToken: _selectedCategory!.hissahPerToken,
                                      ),
                                    ),
                                  );
                                },
                          child: const Text('Continue to Next Step'),
                        ),
                        const SizedBox(height: 8), 
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
