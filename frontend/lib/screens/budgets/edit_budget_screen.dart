import 'package:flutter/material.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/services/api_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/budget.dart';
import '../../providers/budget_provider.dart';

class EditBudgetScreen extends StatefulWidget {
  final Budget budget;

  EditBudgetScreen({required this.budget});

  @override
  _EditBudgetScreenState createState() => _EditBudgetScreenState();
}

class _EditBudgetScreenState extends State<EditBudgetScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;

  late List<CategoryBudget> _categoryBudgets;
  bool _isLoading = false;


  late bool _autoCreateEnabled;     // NEW
  late bool _autoCreateWithAi;      // NEW

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.budget.name);
    _descriptionController = TextEditingController(
      text: widget.budget.description ?? '',
    );
    _categoryBudgets = List.from(widget.budget.categoryBudgets);
    _autoCreateEnabled = widget.budget.autoCreateEnabled;     // NEW
    _autoCreateWithAi = widget.budget.autoCreateWithAi;       // NEW
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String? _validateDuplicateCategory(
    String mainCategory,
    String? subCategory, {
    int? excludeIndex,
  }) {
    // Check for exact duplicates
    for (int i = 0; i < _categoryBudgets.length; i++) {
      // Skip the category being edited
      if (excludeIndex != null && i == excludeIndex) continue;

      var existingCat = _categoryBudgets[i];
      String existingMain = existingCat.mainCategory;
      String? existingSubStr;

      // Parse existing category
      if (existingMain.contains(' - ')) {
        final parts = existingMain.split(' - ');
        existingMain = parts[0];
        existingSubStr = parts[1];
      }

      // Check if it's the same main category with same sub-category (or both have no sub-category)
      if (existingMain == mainCategory) {
        if ((subCategory == null || subCategory == 'All') &&
            existingSubStr == null) {
          return 'This category already exists';
        }
        if (subCategory != null &&
            subCategory != 'All' &&
            existingSubStr == subCategory) {
          return 'This category already exists';
        }
      }
    }
    return null;
  }

  // In create_budget_screen.dart, replace the totalBudget calculation
  double _calculateTotalBudget() {
    Set<String> mainCategories = {};
    List<MapEntry<String, double>> subCategories = [];

    // Separate main categories and sub-categories
    for (var cat in _categoryBudgets) {
      if (cat.mainCategory.contains(' - ')) {
        final parts = cat.mainCategory.split(' - ');
        subCategories.add(MapEntry(parts[0], cat.allocatedAmount));
      } else {
        mainCategories.add(cat.mainCategory);
      }
    }

    double total = 0.0;

    // Add all main category budgets
    for (var cat in _categoryBudgets) {
      if (!cat.mainCategory.contains(' - ')) {
        total += cat.allocatedAmount;
      }
    }

    // Add sub-category budgets only if their main category doesn't exist
    for (var entry in subCategories) {
      if (!mainCategories.contains(entry.key)) {
        total += entry.value;
      }
    }

    return total;
  }

  void _addCategoryBudget() {
    showDialog(
      context: context,
      builder: (context) => _AddCategoryDialog(
        onAdd: (categoryBudget) {
          setState(() {
            _categoryBudgets.add(categoryBudget);
          });
        },
      ),
    );
  }

  void _editCategoryBudget(int index) {
    showDialog(
      context: context,
      builder: (context) => _AddCategoryDialog(
        initialCategory: _categoryBudgets[index],
        editingIndex: index, // Pass the index being edited
        onAdd: (categoryBudget) {
          setState(() {
            _categoryBudgets[index] = categoryBudget;
          });
        },
      ),
    );
  }

  void _removeCategoryBudget(int index) {
    setState(() {
      _categoryBudgets.removeAt(index);
    });
  }

    Future<void> _saveBudget() async {
    if (!_formKey.currentState!.validate()) return;

    if (_categoryBudgets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please add at least one category budget'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final totalBudget = _calculateTotalBudget();

    final success = await Provider.of<BudgetProvider>(context, listen: false)
        .updateBudget(
          budgetId: widget.budget.id,
          name: _nameController.text,
          categoryBudgets: _categoryBudgets,
          totalBudget: totalBudget,
          description: _descriptionController.text.isEmpty
              ? null
              : _descriptionController.text,
          autoCreateEnabled: _autoCreateEnabled,      // NEW
          autoCreateWithAi: _autoCreateWithAi,        // NEW
        );

    setState(() => _isLoading = false);

    if (success) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Budget updated successfully',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } else {
      final error = Provider.of<BudgetProvider>(context, listen: false).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Failed to update budget'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final totalBudget = _calculateTotalBudget();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Edit Budget',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Color(0xFF333333)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF667eea).withOpacity(0.1), Colors.white],
          ),
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.all(20),
            children: [
              // Budget Period Info (Read-only)
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea).withOpacity(0.1),
                      Color(0xFF764ba2).withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Color(0xFF667eea).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFF667eea)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Budget Period (Cannot be changed)',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF333333),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    _buildInfoRow(
                      Icons.calendar_today,
                      'Period',
                      widget.budget.period.name.toUpperCase(),
                    ),
                    _buildInfoRow(
                      Icons.date_range,
                      'Duration',
                      '${DateFormat('MMM d').format(widget.budget.startDate)} - ${DateFormat('MMM d, yyyy').format(widget.budget.endDate)}',
                    ),
                  ],
                ),
              ),

              SizedBox(height: 20),

                // NEW: Currency Display (Read-only)
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.grey[100]!,
                        Colors.grey[50]!,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Currency (Cannot be changed)',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF333333),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Text(
                              widget.budget.currency.symbol,
                              style: GoogleFonts.poppins(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF667eea),
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.budget.currency.displayName,
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Only ${widget.budget.currency.displayName} transactions will affect this budget',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),

              SizedBox(height: 20),

              // Name Field
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Budget Name',
                  hintText: 'e.g., Monthly Expenses',
                  prefixIcon: Icon(Icons.label, color: Color(0xFF667eea)),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter budget name';
                  }
                  return null;
                },
              ),

              SizedBox(height: 16),

              // Description Field
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'Notes about this budget',
                  prefixIcon: Icon(Icons.note, color: Color(0xFF667eea)),
                ),
                maxLines: 2,
              ),

              SizedBox(height: 24),


                            if (widget.budget.period != BudgetPeriod.custom) ...[
                SizedBox(height: 20),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF667eea).withOpacity(0.1),
                        Color(0xFF764ba2).withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Color(0xFF667eea).withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.autorenew, color: Color(0xFF667eea)),
                          SizedBox(width: 8),
                          Text(
                            'Auto-Create Next Budget',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF333333),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Automatically create a new budget when this one ends',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: 12),
                      SwitchListTile(
                        value: _autoCreateEnabled,
                        onChanged: (value) {
                          setState(() {
                            _autoCreateEnabled = value;
                            if (!value) {
                              _autoCreateWithAi = false;
                            }
                          });
                        },
                        title: Text(
                          'Enable Auto-Create',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        activeColor: Color(0xFF667eea),
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (_autoCreateEnabled) ...[
                        Divider(),
                        Text(
                          'Choose how to create the next budget:',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF333333),
                          ),
                        ),
                        SizedBox(height: 8),
                        RadioListTile<bool>(
                          value: false,
                          groupValue: _autoCreateWithAi,
                          onChanged: (value) {
                            setState(() {
                              _autoCreateWithAi = value!;
                            });
                          },
                          title: Text(
                            'Use Current Categories',
                            style: GoogleFonts.poppins(fontSize: 13),
                          ),
                          subtitle: Text(
                            'Keep the same budget amounts for all categories',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                          activeColor: Color(0xFF667eea),
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<bool>(
                          value: true,
                          groupValue: _autoCreateWithAi,
                          onChanged: (value) {
                            setState(() {
                              _autoCreateWithAi = value!;
                            });
                          },
                          title: Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 16,
                                color: Color(0xFF667eea),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'AI-Optimized Budget',
                                style: GoogleFonts.poppins(fontSize: 13),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            'AI analyzes your spending and suggests optimized amounts',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                          activeColor: Color(0xFF667eea),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              SizedBox(height: 24),

              // Category Budgets Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Category Budgets',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addCategoryBudget,
                    icon: Icon(Icons.add_circle, color: Color(0xFF667eea)),
                    label: Text(
                      'Add',
                      style: GoogleFonts.poppins(color: Color(0xFF667eea)),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 12),

              // Warning about editing categories
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange[700],
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Editing categories will reset their spent amounts. Current spending will be recalculated.',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 12),

              // Category Budgets List
              if (_categoryBudgets.isEmpty)
                Container(
                  padding: EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'No categories added yet',
                      style: GoogleFonts.poppins(color: Colors.grey[500]),
                    ),
                  ),
                )
              else
                ..._categoryBudgets.asMap().entries.map((entry) {
                  final index = entry.key;
                  final catBudget = entry.value;
                  return _buildCategoryBudgetCard(catBudget, index);
                }).toList(),

              SizedBox(height: 24),

              // Total Budget Comparison
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'New Total Budget',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                            Text(
                              '${widget.budget.currency.symbol}${totalBudget.toStringAsFixed(2)}',  // NEW: use budget currency
                              style: GoogleFonts.poppins(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Icon(Icons.arrow_forward, color: Colors.white),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Current Total',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                            Text(
                              '${widget.budget.currency.symbol}${widget.budget.totalBudget.toStringAsFixed(2)}',  // NEW: use budget currency
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (totalBudget != widget.budget.totalBudget) ...[
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              totalBudget > widget.budget.totalBudget
                                  ? Icons.trending_up
                                  : Icons.trending_down,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 4),
                            Text(
                              '${totalBudget > widget.budget.totalBudget ? '+' : ''}${widget.budget.currency.symbol}${(totalBudget - widget.budget.totalBudget).toStringAsFixed(2)}',  // NEW: use budget currency
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              SizedBox(height: 24),

              // Save Button
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveBudget,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF667eea),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text(
                          'Save Changes',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),

              SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Color(0xFF667eea), size: 16),
          SizedBox(width: 8),
          Text(
            '$label:',
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBudgetCard(CategoryBudget catBudget, int index) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color(0xFF667eea).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.category, color: Color(0xFF667eea), size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  catBudget.mainCategory,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                Text(
                  '${widget.budget.currency.symbol}${catBudget.allocatedAmount.toStringAsFixed(2)}',  // NEW: use budget currency
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit, color: Color(0xFF667eea), size: 20),
            onPressed: () => _editCategoryBudget(index),
          ),
          IconButton(
            icon: Icon(Icons.delete, color: Colors.red, size: 20),
            onPressed: () => _removeCategoryBudget(index),
          ),
        ],
      ),
    );
  }
}

// Reuse the same dialog from CreateBudgetScreen
class _AddCategoryDialog extends StatefulWidget {
  final CategoryBudget? initialCategory;
  final int? editingIndex; // For edit screen
  final Function(CategoryBudget) onAdd;

  _AddCategoryDialog({
    this.initialCategory,
    this.editingIndex,
    required this.onAdd,
  });

  @override
  _AddCategoryDialogState createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();

  String? _selectedMainCategory;
  String? _selectedSubCategory;
  List<Category> _categories = [];
  bool _isLoadingCategories = false;

  @override
  void initState() {
    super.initState();
    
    // Set amount immediately
    if (widget.initialCategory != null) {
      _amountController.text = widget.initialCategory!.allocatedAmount.toString();
    }
    
    // Load categories, then parse initial values
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoadingCategories = true;
    });

    try {
      final categories = await ApiService.getCategories(TransactionType.outflow);
      
      setState(() {
        _categories = categories;
        _isLoadingCategories = false;
        
        // NOW parse the initial category after categories are loaded
        if (widget.initialCategory != null) {
          final categoryName = widget.initialCategory!.mainCategory;
          if (categoryName.contains(' - ')) {
            final parts = categoryName.split(' - ');
            final mainCat = parts[0];
            final subCat = parts[1];
            
            // Validate that this main category exists
            if (_categories.any((cat) => cat.mainCategory == mainCat)) {
              _selectedMainCategory = mainCat;
              
              // Validate that this sub-category exists under this main category
              final mainCategory = _categories.firstWhere(
                (cat) => cat.mainCategory == mainCat,
              );
              if (mainCategory.subCategories.contains(subCat)) {
                _selectedSubCategory = subCat;
              }
            }
          } else {
            // Just a main category
            if (_categories.any((cat) => cat.mainCategory == categoryName)) {
              _selectedMainCategory = categoryName;
              _selectedSubCategory = null;
            }
          }
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingCategories = false;
      });
      print("Error loading categories: $e");
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.initialCategory == null
            ? 'Add Category Budget'
            : 'Edit Category Budget',
        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main Category Dropdown
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: _isLoadingCategories
                    ? Container(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF667eea),
                            ),
                          ),
                        ),
                      )
                    : DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          hintText: 'Select main category',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          prefixIcon: Icon(
                            Icons.category,
                            color: Color(0xFF667eea),
                          ),
                        ),
                        isExpanded: true,
                        value: _selectedMainCategory,
                        items: _categories.map((category) {
                          return DropdownMenuItem(
                            value: category.mainCategory,
                            child: Text(
                              category.mainCategory,
                              style: GoogleFonts.poppins(fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedMainCategory = value;
                            _selectedSubCategory = null; // Reset sub-category
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please select a main category';
                          }
                          return null;
                        },
                      ),
              ),

              // Sub Category Dropdown (Optional)
              if (_selectedMainCategory != null && !_isLoadingCategories) ...[
                SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: DropdownButtonFormField<String?>(
                    decoration: InputDecoration(
                      hintText: 'Sub category (optional)',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      prefixIcon: Icon(
                        Icons.list_outlined,
                        color: Color(0xFF667eea),
                      ),
                    ),
                    isExpanded: true,
                    value: _selectedSubCategory,
                    items: [
                      // Add "All" option for optional sub-category selection
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'All (no filter)',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey[600],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Add actual sub-categories for the selected main category
                      ..._categories
                          .firstWhere(
                            (cat) => cat.mainCategory == _selectedMainCategory,
                            orElse: () =>
                                Category(mainCategory: '', subCategories: []),
                          )
                          .subCategories
                          .map((subCategory) {
                            return DropdownMenuItem<String?>(
                              value: subCategory,
                              child: Text(
                                subCategory,
                                style: GoogleFonts.poppins(fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          })
                          .toList(),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedSubCategory = value;
                      });
                    },
                  ),
                ),
              ],

              SizedBox(height: 16),

              // Amount Field
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Budget Amount',
                  hintText: '0.00',
                  prefixIcon: Icon(
                    Icons.attach_money,
                    color: Color(0xFF667eea),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Color(0xFF667eea), width: 2),
                  ),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter amount';
                  }
                  if (double.tryParse(value) == null ||
                      double.parse(value) <= 0) {
                    return 'Please enter valid amount';
                  }
                  return null;
                },
              ),

              // Info text about sub-categories
              if (_selectedMainCategory != null) ...[
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color(0xFF667eea).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Color(0xFF667eea),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedSubCategory == null
                              ? 'Budget will track all sub-categories in $_selectedMainCategory'
                              : 'Budget will only track $_selectedSubCategory',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Color(0xFF667eea),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: GoogleFonts.poppins(color: Colors.grey[600]),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              // Create display name based on selections
              String displayName = _selectedMainCategory!;
              if (_selectedSubCategory != null) {
                displayName += ' - $_selectedSubCategory';
              }

              // Validate for duplicates
              final editParent = context
                  .findAncestorStateOfType<_EditBudgetScreenState>();
              
              String? error;
              if (editParent != null) {
                error = editParent._validateDuplicateCategory(
                  _selectedMainCategory!,
                  _selectedSubCategory,
                  excludeIndex: widget.editingIndex,
                );
              }
              
              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(error, style: GoogleFonts.poppins()),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              widget.onAdd(
                CategoryBudget(
                  mainCategory: displayName,
                  allocatedAmount: double.parse(_amountController.text),
                  spentAmount: 0,
                  percentageUsed: 0,
                  isExceeded: false,
                ),
              );
              Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFF667eea),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(
            'Save',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}