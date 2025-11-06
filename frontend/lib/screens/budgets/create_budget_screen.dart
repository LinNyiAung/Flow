import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/budget.dart';
import '../../providers/budget_provider.dart';
import 'ai_budget_suggestion_screen.dart';

class CreateBudgetScreen extends StatefulWidget {
  @override
  _CreateBudgetScreenState createState() => _CreateBudgetScreenState();
}

class _CreateBudgetScreenState extends State<CreateBudgetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  BudgetPeriod _selectedPeriod = BudgetPeriod.monthly;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  List<CategoryBudget> _categoryBudgets = [];

  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _calculateEndDate() {
    switch (_selectedPeriod) {
      case BudgetPeriod.weekly:
        final weekStart = _startDate.subtract(Duration(days: _startDate.weekday - 1));
        _endDate = weekStart.add(Duration(days: 6));
        break;
      case BudgetPeriod.monthly:
        _endDate = DateTime(_startDate.year, _startDate.month + 1, 0);
        break;
      case BudgetPeriod.yearly:
        _endDate = DateTime(_startDate.year, 12, 31);
        break;
      case BudgetPeriod.custom:
        break;
    }
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(Duration(days: 365)),
      lastDate: DateTime.now().add(Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: Color(0xFF667eea)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_selectedPeriod != BudgetPeriod.custom) {
          _calculateEndDate();
        }
      });
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(Duration(days: 30)),
      firstDate: _startDate,
      lastDate: DateTime.now().add(Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: Color(0xFF667eea)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
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

  void _navigateToAISuggestion() async {
    if (_selectedPeriod == BudgetPeriod.custom && _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select end date for custom period'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AIBudgetSuggestionScreen(
          period: _selectedPeriod,
          startDate: _startDate,
          endDate: _endDate,
        ),
      ),
    );

    if (result != null && result is AIBudgetSuggestion) {
      setState(() {
        _nameController.text = result.suggestedName;
        _categoryBudgets = result.categoryBudgets;
      });
    }
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

    if (_selectedPeriod == BudgetPeriod.custom && _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select end date for custom period'),
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

    final success = await Provider.of<BudgetProvider>(context, listen: false).createBudget(
      name: _nameController.text,
      period: _selectedPeriod,
      startDate: _startDate,
      endDate: _endDate,
      categoryBudgets: _categoryBudgets,
      totalBudget: totalBudget,
      description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
    );

    setState(() => _isLoading = false);

    if (success) {
      Navigator.pop(context, true);
    } else {
      final error = Provider.of<BudgetProvider>(context, listen: false).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Failed to create budget'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _calculateEndDate();

    final totalBudget = _categoryBudgets.fold<double>(
      0,
      (sum, cat) => sum + cat.allocatedAmount,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Create Budget',
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
              // AI Suggestion Button
              Container(
                margin: EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _navigateToAISuggestion,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome, color: Colors.white, size: 28),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AI Budget Suggestion',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Let AI analyze your spending and suggest budgets',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

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

              // Period Selector
              Text(
                'Budget Period',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF333333),
                ),
              ),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(4),
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
                    _buildPeriodButton('Week', BudgetPeriod.weekly),
                    _buildPeriodButton('Month', BudgetPeriod.monthly),
                    _buildPeriodButton('Year', BudgetPeriod.yearly),
                    _buildPeriodButton('Custom', BudgetPeriod.custom),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // Date Selection
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectStartDate,
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start Date',
                              style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey[600]),
                            ),
                            SizedBox(height: 4),
                            Text(
                              DateFormat('MMM d, yyyy').format(_startDate),
                              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectedPeriod == BudgetPeriod.custom ? _selectEndDate : null,
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _selectedPeriod == BudgetPeriod.custom ? Colors.white : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'End Date',
                              style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey[600]),
                            ),
                            SizedBox(height: 4),
                            Text(
                              _endDate != null ? DateFormat('MMM d, yyyy').format(_endDate!) : 'Auto',
                              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
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

              // Total Budget Display
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Budget',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
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
                          'Create Budget',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodButton(String label, BudgetPeriod period) {
    bool isSelected = _selectedPeriod == period;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedPeriod = period;
            if (period != BudgetPeriod.custom) {
              _calculateEndDate();
            }
          });
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(colors: [Color(0xFF667eea), Color(0xFF764ba2)])
                : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? Colors.white : Colors.grey[600],
            ),
          ),
        ),
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

class _AddCategoryDialog extends StatefulWidget {
  final CategoryBudget? initialCategory;
  final Function(CategoryBudget) onAdd;

  _AddCategoryDialog({this.initialCategory, required this.onAdd});

  @override
  _AddCategoryDialogState createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _categoryController = TextEditingController();
  final _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      _categoryController.text = widget.initialCategory!.mainCategory;
      _amountController.text = widget.initialCategory!.allocatedAmount.toString();
    }
  }

  @override
  void dispose() {
    _categoryController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.initialCategory == null ? 'Add Category' : 'Edit Category',
        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _categoryController,
              decoration: InputDecoration(
                labelText: 'Category Name',
                prefixIcon: Icon(Icons.category, color: Color(0xFF667eea)),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter category name';
                }
                return null;
              },
            ),
            SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Budget Amount',
                prefixIcon: Icon(Icons.attach_money, color: Color(0xFF667eea)),
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
          ],
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
              widget.onAdd(CategoryBudget(
                mainCategory: _categoryController.text,
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
          ),
          child: Text('Save', style: GoogleFonts.poppins(color: Colors.white)),
        ),
      ],
    );
  }
}