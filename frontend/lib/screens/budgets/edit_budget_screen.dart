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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.budget.name);
    _descriptionController = TextEditingController(text: widget.budget.description ?? '');
    _categoryBudgets = List.from(widget.budget.categoryBudgets);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
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

    final totalBudget = _categoryBudgets.fold<double>(
      0,
      (sum, cat) => sum + cat.allocatedAmount,
    );

    final success = await Provider.of<BudgetProvider>(context, listen: false).updateBudget(
      budgetId: widget.budget.id,
      name: _nameController.text,
      categoryBudgets: _categoryBudgets,
      totalBudget: totalBudget,
      description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
    );

    setState(() => _isLoading = false);

    if (success) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Budget updated successfully', style: GoogleFonts.poppins(color: Colors.white)),
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
    final totalBudget = _categoryBudgets.fold<double>(
      0,
      (sum, cat) => sum + cat.allocatedAmount,
    );

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
            colors: [
              Color(0xFF667eea).withOpacity(0.1),
              Colors.white,
            ],
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
                    colors: [Color(0xFF667eea).withOpacity(0.1), Color(0xFF764ba2).withOpacity(0.1)],
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
                        Text(
                          'Budget Period (Cannot be changed)',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF333333),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    _buildInfoRow(Icons.calendar_today, 'Period', widget.budget.period.name.toUpperCase()),
                    _buildInfoRow(
                      Icons.date_range,
                      'Duration',
                      '${DateFormat('MMM d').format(widget.budget.startDate)} - ${DateFormat('MMM d, yyyy').format(widget.budget.endDate)}',
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
                    Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 20),
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
                              '\$${totalBudget.toStringAsFixed(2)}',
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
                              '\$${widget.budget.totalBudget.toStringAsFixed(2)}',
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
                              totalBudget > widget.budget.totalBudget ? Icons.trending_up : Icons.trending_down,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 4),
                            Text(
                              '${totalBudget > widget.budget.totalBudget ? '+' : ''}\$${(totalBudget - widget.budget.totalBudget).toStringAsFixed(2)}',
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
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey[600],
            ),
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
                  '\$${catBudget.allocatedAmount.toStringAsFixed(2)}',
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
  final Function(CategoryBudget) onAdd;

  _AddCategoryDialog({this.initialCategory, required this.onAdd});

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
    if (widget.initialCategory != null) {
      // Parse the category name if it contains " - "
      final categoryName = widget.initialCategory!.mainCategory;
      if (categoryName.contains(' - ')) {
        final parts = categoryName.split(' - ');
        _selectedMainCategory = parts[0];
        _selectedSubCategory = parts[1];
      } else {
        _selectedMainCategory = categoryName;
      }
      _amountController.text = widget.initialCategory!.allocatedAmount.toString();
    }
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
        widget.initialCategory == null ? 'Add Category Budget' : 'Edit Category Budget',
        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                          ),
                        ),
                      )
                    : DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          hintText: 'Select main category',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          prefixIcon: Icon(Icons.category, color: Color(0xFF667eea)),
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
                            _selectedSubCategory = null;
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
              
              if (_selectedMainCategory != null) ...[
                SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      hintText: 'Sub category (optional)',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      prefixIcon: Icon(Icons.list_outlined, color: Color(0xFF667eea)),
                    ),
                    isExpanded: true,
                    value: _selectedSubCategory,
                    items: [
                      DropdownMenuItem(
                        value: 'All',
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
                      ..._categories
                          .firstWhere(
                            (cat) => cat.mainCategory == _selectedMainCategory,
                            orElse: () => Category(mainCategory: '', subCategories: []),
                          )
                          .subCategories
                          .map((subCategory) {
                        return DropdownMenuItem(
                          value: subCategory,
                          child: Text(
                            subCategory,
                            style: GoogleFonts.poppins(fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
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
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Budget Amount',
                  hintText: '0.00',
                  prefixIcon: Icon(Icons.attach_money, color: Color(0xFF667eea)),
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
                  if (double.tryParse(value) == null || double.parse(value) <= 0) {
                    return 'Please enter valid amount';
                  }
                  return null;
                },
              ),
              
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
                      Icon(Icons.info_outline, size: 16, color: Color(0xFF667eea)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedSubCategory == null || _selectedSubCategory == 'All'
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
          child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey[600])),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              String displayName = _selectedMainCategory!;
              if (_selectedSubCategory != null && _selectedSubCategory != 'All') {
                displayName += ' - $_selectedSubCategory';
              }
              
              widget.onAdd(CategoryBudget(
                mainCategory: displayName,
                allocatedAmount: double.parse(_amountController.text),
                spentAmount: 0,
                percentageUsed: 0,
                isExceeded: false,
              ));
              Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFF667eea),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text('Save', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}