import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/transaction.dart';
import '../../services/api_service.dart';
import '../../providers/transaction_provider.dart';

class AddTransactionScreen extends StatefulWidget {
  @override
  _AddTransactionScreenState createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  TransactionType _selectedType = TransactionType.outflow;
  String? _selectedMainCategory;
  String? _selectedSubCategory;
  List<Category> _categories = [];
  bool _isLoadingCategories = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));

    _loadCategories();
    _animationController.forward();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoadingCategories = true;
    });

    try {
      final categories = await ApiService.getCategories(_selectedType);
      setState(() {
        _categories = categories;
        _selectedMainCategory = null;
        _selectedSubCategory = null;
        _isLoadingCategories = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingCategories = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _selectedType == TransactionType.inflow
                  ? Color(0xFF4CAF50).withOpacity(0.1)
                  : Color(0xFFFF5722).withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(20),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Container(
                        padding: EdgeInsets.all(8),
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
                        child: Icon(Icons.arrow_back, color: Color(0xFF333333)),
                      ),
                    ),
                    SizedBox(width: 16),
                    Text(
                      'Add Transaction',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF333333),
                      ),
                    ),
                  ],
                ),
              ),

              // Form
              Expanded(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Transaction Type Toggle
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.1),
                                    spreadRadius: 2,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedType = TransactionType.outflow;
                                        });
                                        _loadCategories();
                                      },
                                      child: Container(
                                        padding: EdgeInsets.symmetric(vertical: 16),
                                        decoration: BoxDecoration(
                                          color: _selectedType == TransactionType.outflow
                                              ? Color(0xFFFF5722)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.arrow_downward,
                                              color: _selectedType == TransactionType.outflow
                                                  ? Colors.white
                                                  : Colors.grey[600],
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Outflow',
                                              style: GoogleFonts.poppins(
                                                color: _selectedType == TransactionType.outflow
                                                    ? Colors.white
                                                    : Colors.grey[600],
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedType = TransactionType.inflow;
                                        });
                                        _loadCategories();
                                      },
                                      child: Container(
                                        padding: EdgeInsets.symmetric(vertical: 16),
                                        decoration: BoxDecoration(
                                          color: _selectedType == TransactionType.inflow
                                              ? Color(0xFF4CAF50)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.arrow_upward,
                                              color: _selectedType == TransactionType.inflow
                                                  ? Colors.white
                                                  : Colors.grey[600],
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Inflow',
                                              style: GoogleFonts.poppins(
                                                color: _selectedType == TransactionType.inflow
                                                    ? Colors.white
                                                    : Colors.grey[600],
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 24),

                            // Amount Field
                            Text(
                              'Amount',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF333333),
                              ),
                            ),
                            SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(                                    color: Colors.grey.withOpacity(0.1),
                                    spreadRadius: 2,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: TextFormField(
                                controller: _amountController,
                                keyboardType: TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  hintText: '0.00',
                                  prefixText: '\$ ',
                                  prefixStyle: GoogleFonts.poppins(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedType == TransactionType.inflow
                                        ? Color(0xFF4CAF50)
                                        : Color(0xFFFF5722),
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.all(20),
                                ),
                                style: GoogleFonts.poppins(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF333333),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter an amount';
                                  }
                                  if (double.tryParse(value) == null) {
                                    return 'Please enter a valid amount';
                                  }
                                  if (double.parse(value) <= 0) {
                                    return 'Amount must be greater than 0';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            SizedBox(height: 24),

                            // Main Category
                            Text(
                              'Category',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF333333),
                              ),
                            ),
                            SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.1),
                                    spreadRadius: 2,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: _isLoadingCategories
                                  ? Container(
                                      padding: EdgeInsets.all(20),
                                      child: Center(child: CircularProgressIndicator()),
                                    )
                                  : DropdownButtonFormField<String>(
                                      decoration: InputDecoration(
                                        hintText: 'Select main category',
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.all(20),
                                        prefixIcon: Icon(Icons.category_outlined),
                                      ),
                                      value: _selectedMainCategory,
                                      items: _categories.map((category) {
                                        return DropdownMenuItem(
                                          value: category.mainCategory,
                                          child: Text(
                                            category.mainCategory,
                                            style: GoogleFonts.poppins(),
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
                            SizedBox(height: 16),

                            // Sub Category
                            if (_selectedMainCategory != null) ...[
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withOpacity(0.1),
                                      spreadRadius: 2,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: DropdownButtonFormField<String>(
                                  decoration: InputDecoration(
                                    hintText: 'Select sub category',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.all(20),
                                    prefixIcon: Icon(Icons.list_outlined),
                                  ),
                                  value: _selectedSubCategory,
                                  items: _categories
                                      .firstWhere((cat) => cat.mainCategory == _selectedMainCategory)
                                      .subCategories
                                      .map((subCategory) {
                                    return DropdownMenuItem(
                                      value: subCategory,
                                      child: Text(
                                        subCategory,
                                        style: GoogleFonts.poppins(),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedSubCategory = value;
                                    });
                                  },
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please select a sub category';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              SizedBox(height: 24),
                            ],

                            // Description Field
                            Text(
                              'Description (Optional)',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF333333),
                              ),
                            ),
                            SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.1),
                                    spreadRadius: 2,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: TextFormField(
                                controller: _descriptionController,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  hintText: 'Add a note about this transaction...',
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.all(20),
                                  prefixIcon: Padding(
                                    padding: EdgeInsets.only(top: 12),
                                    child: Icon(Icons.notes_outlined),
                                  ),
                                ),
                                style: GoogleFonts.poppins(),
                              ),
                            ),
                            SizedBox(height: 32),

                            // Error Message
                            Consumer<TransactionProvider>(
                              builder: (context, transactionProvider, child) {
                                if (transactionProvider.error != null) {
                                  return Container(
                                    padding: EdgeInsets.all(12),
                                    margin: EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.red[50],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.error_outline, color: Colors.red),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            transactionProvider.error!,
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return SizedBox.shrink();
                              },
                            ),

                            // Add Transaction Button
                            Consumer<TransactionProvider>(
                              builder: (context, transactionProvider, child) {
                                return SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: ElevatedButton(
                                    onPressed: transactionProvider.isLoading ? null : _addTransaction,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _selectedType == TransactionType.inflow
                                          ? Color(0xFF4CAF50)
                                          : Color(0xFFFF5722),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      elevation: 4,
                                    ),
                                    child: transactionProvider.isLoading
                                        ? CircularProgressIndicator(color: Colors.white)
                                        : Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                _selectedType == TransactionType.inflow
                                                    ? Icons.add_circle_outline
                                                    : Icons.remove_circle_outline,
                                                color: Colors.white,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Add ${_selectedType == TransactionType.inflow ? 'Inflow' : 'Outflow'}',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
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

  void _addTransaction() async {
    if (_formKey.currentState!.validate()) {
      final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
      final success = await transactionProvider.createTransaction(
        type: _selectedType,
        mainCategory: _selectedMainCategory!,
        subCategory: _selectedSubCategory!,
        description: _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
        amount: double.parse(_amountController.text),
      );

      if (success) {
        Navigator.pop(context, true); // Return true to indicate success
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}