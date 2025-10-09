import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // Import for date formatting
import '../../models/transaction.dart';
import '../../services/api_service.dart';
import '../../providers/transaction_provider.dart';

// Extension for safely finding an element in a list
extension FirstWhereOrNullExtension<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (E element in this) {
      if (test(element)) {
        return element;
      }
    }
    return null;
  }
}

class AddTransactionScreen extends StatefulWidget {
  @override
  _AddTransactionScreenState createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen>
    with TickerProviderStateMixin { // Mixin for animation controllers
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  TransactionType _selectedType = TransactionType.outflow; // Default to outflow (expense)
  String? _selectedMainCategory;
  String? _selectedSubCategory;
  List<Category> _categories = []; // List to hold fetched categories
  bool _isLoadingCategories = false;
  DateTime _selectedDate = DateTime.now(); // Default date is today

  // Animation controllers for screen transition
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    // Initialize animations
    _animationController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 0.1), // Start slightly above
      end: Offset.zero, // End at original position
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));

    _loadCategories(); // Load categories when the screen initializes
    _animationController.forward(); // Start the animation
  }

  // Load categories from the API based on the selected transaction type
  Future<void> _loadCategories() async {
    setState(() {
      _isLoadingCategories = true; // Show loading indicator
    });

    try {
      final categories = await ApiService.getCategories(_selectedType);
      setState(() {
        _categories = categories;
        // Reset selected categories when type changes or categories load to ensure validity
        _selectedMainCategory = null;
        _selectedSubCategory = null;
        _isLoadingCategories = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingCategories = false;
        // Optionally display an error message to the user
        print("Error loading categories: $e");
      });
    }
  }

  // Function to show the date picker dialog
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate, // Pre-fill with the current selected date
      firstDate: DateTime(2000), // Set the earliest possible date
      lastDate: DateTime.now().add(Duration(days: 365)), // Set the latest possible date (1 year from now)
      builder: (BuildContext context, Widget? child) {
        // Customize the date picker theme
        return Theme(
          data: ThemeData.light().copyWith(
            // Dynamically set accent color based on transaction type
            primaryColor: _selectedType == TransactionType.inflow ? Colors.green : Colors.red, // Header and accent colors
            hintColor: _selectedType == TransactionType.inflow ? Colors.green : Colors.red, // For selected day
            colorScheme: ColorScheme.light(
              primary: _selectedType == TransactionType.inflow ? Colors.green : Colors.red, // Primary color for app bar
              onPrimary: Colors.white, // Text color on primary
              surface: Colors.white, // Background of the calendar
              onSurface: Colors.black, // Text color for day numbers
            ),
            dialogBackgroundColor: Colors.white, // Background of the date picker dialog
            appBarTheme: AppBarTheme( // Theme for the date picker's app bar
              backgroundColor: _selectedType == TransactionType.inflow ? Colors.green : Colors.red,
              elevation: 0,
            ),
          ),
          child: child!,
        );
      },
    );
    // If a date was picked and it's different from the current selection, update the state
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    // Access the TransactionProvider for state management
    final transactionProvider = Provider.of<TransactionProvider>(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          // Dynamic gradient based on transaction type
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _selectedType == TransactionType.inflow
                  ? Color(0xFF4CAF50).withOpacity(0.1) // Light green for inflow
                  : Color(0xFFFF5722).withOpacity(0.1), // Light red for outflow
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header Section
              Container(
                padding: EdgeInsets.all(20),
                child: Row(
                  children: [
                    // Back Button
                    IconButton(
                      onPressed: () => Navigator.pop(context), // Go back to previous screen
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
                    // Screen Title
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

              // Form Section
              Expanded(
                child: FadeTransition( // Apply fade animation
                  opacity: _fadeAnimation,
                  child: SlideTransition( // Apply slide animation
                    position: _slideAnimation,
                    child: SingleChildScrollView( // Allow scrolling for form content
                      padding: EdgeInsets.all(20),
                      child: Form(
                        key: _formKey, // Assign form key for validation
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Transaction Type Toggle (Inflow/Outflow)
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
                                  // Outflow Button
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        if (_selectedType != TransactionType.outflow) {
                                          setState(() {
                                            _selectedType = TransactionType.outflow;
                                            _selectedMainCategory = null; // Reset selections
                                            _selectedSubCategory = null;
                                          });
                                          _loadCategories(); // Reload categories for the new type
                                        }
                                      },
                                      child: Container(
                                        padding: EdgeInsets.symmetric(vertical: 16),
                                        decoration: BoxDecoration(
                                          color: _selectedType == TransactionType.outflow
                                              ? Color(0xFFFF5722) // Red for outflow
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
                                              'Outflow', // Label changed from Expense
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
                                  // Inflow Button
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        if (_selectedType != TransactionType.inflow) {
                                          setState(() {
                                            _selectedType = TransactionType.inflow;
                                            _selectedMainCategory = null; // Reset selections
                                            _selectedSubCategory = null;
                                          });
                                          _loadCategories(); // Reload categories for the new type
                                        }
                                      },
                                      child: Container(
                                        padding: EdgeInsets.symmetric(vertical: 16),
                                        decoration: BoxDecoration(
                                          color: _selectedType == TransactionType.inflow
                                              ? Color(0xFF4CAF50) // Green for inflow
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
                                              'Inflow', // Label changed from Income
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
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.1),
                                    spreadRadius: 2,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: TextFormField(
                                controller: _amountController,
                                keyboardType: TextInputType.numberWithOptions(decimal: true), // Allow decimal input
                                decoration: InputDecoration(
                                  hintText: '0.00',
                                  prefixText: '\$ ', // Currency symbol
                                  prefixStyle: GoogleFonts.poppins(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedType == TransactionType.inflow
                                        ? Color(0xFF4CAF50)
                                        : Color(0xFFFF5722),
                                  ),
                                  border: InputBorder.none, // Remove default border
                                  contentPadding: EdgeInsets.all(20),
                                ),
                                style: GoogleFonts.poppins(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF333333),
                                ),
                                // Validation for the amount field
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter an amount';
                                  }
                                  // Check if it's a valid number
                                  if (double.tryParse(value) == null) {
                                    return 'Please enter a valid amount';
                                  }
                                  // Check if amount is positive
                                  if (double.parse(value) <= 0) {
                                    return 'Amount must be greater than 0';
                                  }
                                  return null; // Return null if validation passes
                                },
                              ),
                            ),
                            SizedBox(height: 24),

                            // Date Field
                            Text(
                              'Date',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF333333),
                              ),
                            ),
                            SizedBox(height: 8),
                            InkWell( // Make the date field tappable to open date picker
                              onTap: () => _selectDate(context),
                              child: Container(
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
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Row(
                                    children: [
                                      Icon(Icons.calendar_today_outlined), // Calendar icon
                                      SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          DateFormat('yyyy-MM-dd').format(_selectedDate), // Display selected date
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            color: Color(0xFF333333),
                                          ),
                                        ),
                                      ),
                                      Icon(Icons.arrow_drop_down), // Dropdown indicator
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 24),

                            // Main Category Field
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
                              // Show loading indicator while fetching categories
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
                                      value: _selectedMainCategory, // Current selected value
                                      items: _categories.map((category) { // Map categories to DropdownMenuItem
                                        return DropdownMenuItem(
                                          value: category.mainCategory,
                                          child: Text(
                                            category.mainCategory,
                                            style: GoogleFonts.poppins(),
                                          ),
                                        );
                                      }).toList(),
                                      // When a category is selected
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedMainCategory = value;
                                          _selectedSubCategory = null; // Reset sub-category when main changes
                                        });
                                      },
                                      // Validation for main category
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Please select a main category';
                                        }
                                        return null;
                                      },
                                    ),
                            ),
                            SizedBox(height: 16),

                            // Sub Category Field (conditionally displayed)
                            if (_selectedMainCategory != null) ...[ // Only show if a main category is selected
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
                                  value: _selectedSubCategory, // Current selected value
                                  // Safely get sub-categories from the selected main category
                                  items: _categories.isEmpty || _selectedMainCategory == null
                                      ? [] // Return empty list if no categories or no main category selected
                                      : _categories
                                          .firstWhereOrNull((cat) => cat.mainCategory == _selectedMainCategory)
                                          ?.subCategories // Use ?. for safe navigation
                                          .map((subCategory) { // Map sub-categories to DropdownMenuItem
                                        return DropdownMenuItem(
                                          value: subCategory,
                                          child: Text(
                                            subCategory,
                                            style: GoogleFonts.poppins(),
                                          ),
                                        );
                                      }).toList() ?? [], // Use ?? [] as fallback if .subCategories is null or firstWhereOrNull returns null

                                  // When a sub-category is selected
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedSubCategory = value;
                                    });
                                  },
                                  // Validation for sub category
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

                            // Description Field (Optional)
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
                                maxLines: 3, // Allow multiple lines for description
                                decoration: InputDecoration(
                                  hintText: 'Add a note about this transaction...',
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.all(20),
                                  prefixIcon: Padding( // Icon padding for alignment
                                    padding: EdgeInsets.only(top: 12),
                                    child: Icon(Icons.notes_outlined),
                                  ),
                                ),
                                style: GoogleFonts.poppins(),
                              ),
                            ),
                            SizedBox(height: 32),

                            // Display Error Message from TransactionProvider
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
                                return SizedBox.shrink(); // Return empty if no error
                              },
                            ),

                            // Add Transaction Button
                            Consumer<TransactionProvider>(
                              builder: (context, transactionProvider, child) {
                                return SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: ElevatedButton(
                                    onPressed: transactionProvider.isLoading ? null : _addTransaction, // Disable button if loading
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _selectedType == TransactionType.inflow
                                          ? Color(0xFF4CAF50) // Green for inflow button
                                          : Color(0xFFFF5722), // Red for outflow button
                                    ),
                                    child: transactionProvider.isLoading
                                        ? CircularProgressIndicator(color: Colors.white) // Show spinner if loading
                                        : Row( // Button text with icon
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

  // Function to handle adding the transaction
  void _addTransaction() async {
    if (_formKey.currentState!.validate()) { // Ensure form is valid
      final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
      
      // Call the createTransaction method from the provider with context for AI integration
      final success = await transactionProvider.createTransaction(
        type: _selectedType,
        mainCategory: _selectedMainCategory!,
        subCategory: _selectedSubCategory!,
        date: _selectedDate, // Pass the selected date
        description: _descriptionController.text.trim().isEmpty
            ? null // Set to null if description is empty
            : _descriptionController.text.trim(),
        amount: double.parse(_amountController.text), // Parse amount string to double
        context: context, // Add this line for AI data refresh
      );

      if (success) {
        Navigator.pop(context, true); // Pop screen and return true to indicate success
      }
      // If not successful, the error message will be displayed in the UI
    }
  }

  // Dispose of controllers to prevent memory leaks
  @override
  void dispose() {
    _animationController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}