import 'package:flutter/material.dart';
import 'package:frontend/models/recurring_transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/recurrence_settings.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // Import for date formatting
import '../../models/transaction.dart';
import '../../services/api_service.dart';
import '../../providers/transaction_provider.dart';
import 'package:frontend/services/responsive_helper.dart';

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


  TransactionRecurrence? _recurrence;

  // Animation controllers for screen transition
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;


  Currency _selectedCurrency = Currency.usd;

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

        WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      setState(() {
        _selectedCurrency = authProvider.defaultCurrency;
      });
    });

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
    final localizations = AppLocalizations.of(context);
    final responsive = ResponsiveHelper(context);
    
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
                padding: responsive.padding(all: 20),
                child: Row(
                  children: [
                    // Back Button
                    IconButton(
                      onPressed: () => Navigator.pop(context), // Go back to previous screen
                      icon: Container(
                        padding: responsive.padding(all: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
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
                    Expanded(
                      child: Text(
                        localizations.addTransactionTitle,
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF333333),
                        ),
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
                      padding: responsive.padding(all: 20),
                      child: Form(
                        key: _formKey, // Assign form key for validation
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Transaction Type Toggle (Inflow/Outflow)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
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
                                        padding: responsive.padding(vertical: 16),
                                        decoration: BoxDecoration(
                                          color: _selectedType == TransactionType.outflow
                                              ? Color(0xFFFF5722) // Red for outflow
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
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
                                            SizedBox(width: responsive.sp8),
                                            Text(
                                              localizations.outflow, // Label changed from Expense
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
                                        padding: responsive.padding(vertical: 16),
                                        decoration: BoxDecoration(
                                          color: _selectedType == TransactionType.inflow
                                              ? Color(0xFF4CAF50) // Green for inflow
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
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
                                            SizedBox(width: responsive.sp8),
                                            Text(
                                              localizations.inflow, // Label changed from Income
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

                          // ADD CURRENCY SELECTOR HERE
                          Text(
                            localizations.currency,
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF333333),
                            ),
                          ),
                          SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.1),
                                  spreadRadius: 2,
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: DropdownButtonFormField<Currency>(
                              decoration: InputDecoration(
                                hintText: localizations.selectCurrencyT,
                                border: InputBorder.none,
                                contentPadding: responsive.padding(all: 20),
                                
                              ),
                              value: _selectedCurrency,
                              items: Currency.values.map((currency) {
                                return DropdownMenuItem(
                                  value: currency,
                                  child: Text(
                                    '${currency.symbol} - ${currency.displayName}',
                                    style: GoogleFonts.poppins(),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedCurrency = value!;
                                });
                              },
                              validator: (value) {
                                if (value == null) {
                                  return localizations.pleaseSelectCurrency;
                                }
                                return null;
                              },
                            ),
                          ),
                          SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            margin: responsive.padding(bottom: 24),
                            child: OutlinedButton.icon(
                              onPressed: () {
                                if (_amountController.text.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        localizations.enterAmountBeforeConverting,
                                        style: GoogleFonts.poppins(color: Colors.white),
                                      ),
                                      backgroundColor: Colors.orange,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                _showCurrencyConversionDialog();
                              },
                              icon: Icon(Icons.currency_exchange, size: responsive.icon18),
                              label: Text(
                                localizations.convertCurrency,
                                style: GoogleFonts.poppins(fontSize: responsive.fs14, fontWeight: FontWeight.w600),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Color(0xFF667eea),
                                side: BorderSide(color: Color(0xFF667eea), width: 1.5),
                                padding: responsive.padding(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                                ),
                              ),
                            ),
                          ),
                          

                            // Amount Field
                            Text(
                              localizations.amountLabel,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF333333),
                              ),
                            ),
                            SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
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
                                  prefixText: '${_selectedCurrency.symbol} ', // Currency symbol
                                  prefixStyle: GoogleFonts.poppins(
                                    fontSize: responsive.fs24,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedType == TransactionType.inflow
                                        ? Color(0xFF4CAF50)
                                        : Color(0xFFFF5722),
                                  ),
                                  border: InputBorder.none, // Remove default border
                                  contentPadding: responsive.padding(all: 20),
                                ),
                                style: GoogleFonts.poppins(
                                  fontSize: responsive.fs24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF333333),
                                ),
                                // Validation for the amount field
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return localizations.validationAmountRequired;
                                  }
                                  // Check if it's a valid number
                                  if (double.tryParse(value) == null) {
                                    return localizations.validationAmountInvalid;
                                  }
                                  // Check if amount is positive
                                  if (double.parse(value) <= 0) {
                                    return localizations.validationAmountPositive;
                                  }
                                  return null; // Return null if validation passes
                                },
                              ),
                            ),
                            SizedBox(height: 24),

                            // Date Field
                            Text(
                              localizations.dateLabel,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs16,
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
                                  borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withOpacity(0.1),
                                      spreadRadius: 2,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: responsive.padding(all: 20),
                                  child: Row(
                                    children: [
                                      Icon(Icons.calendar_today_outlined), // Calendar icon
                                      SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          DateFormat('yyyy-MM-dd').format(_selectedDate), // Display selected date
                                          style: GoogleFonts.poppins(
                                            fontSize: responsive.fs16,
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
                              localizations.categoryLabel,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF333333),
                              ),
                            ),
                            SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
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
                                      padding: responsive.padding(all: 20),
                                      child: Center(child: CircularProgressIndicator()),
                                    )
                                  : DropdownButtonFormField<String>(
                                      decoration: InputDecoration(
                                        hintText: localizations.selectMainCategoryHint,
                                        border: InputBorder.none,
                                        contentPadding: responsive.padding(all: 20),
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
                                          return localizations.validationMainCategoryRequired;
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
                                  borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
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
                                    hintText: localizations.selectSubCategoryHint,
                                    border: InputBorder.none,
                                    contentPadding: responsive.padding(all: 20),
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
                                      return localizations.validationSubCategoryRequired;
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              SizedBox(height: 24),
                            ],

                            // Description Field (Optional)
                            Text(
                              localizations.descriptionLabel,
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF333333),
                              ),
                            ),
                            SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
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
                                  hintText: localizations.descriptionHint,
                                  border: InputBorder.none,
                                  contentPadding: responsive.padding(all: 20),
                                  prefixIcon: Padding( // Icon padding for alignment
                                    padding: responsive.padding(top: 12),
                                    child: Icon(Icons.notes_outlined),
                                  ),
                                ),
                                style: GoogleFonts.poppins(),
                              ),
                            ),

                            SizedBox(height: 24),

                            // Recurrence Settings
                            RecurrenceSettings(
                              transactionDate: _selectedDate,
                              onRecurrenceChanged: (recurrence) {
                                setState(() {
                                  _recurrence = recurrence;
                                });
                              },
                            ),
                            SizedBox(height: 32),

                            // Display Error Message from TransactionProvider
                            Consumer<TransactionProvider>(
                              builder: (context, transactionProvider, child) {
                                if (transactionProvider.error != null) {
                                  return Container(
                                    padding: responsive.padding(all: 12),
                                    margin: responsive.padding(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.red[50],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.error_outline, color: Colors.red),
                                        SizedBox(width: responsive.sp8),
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
                                  height: responsive.cardHeight(baseHeight: 56),
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
                                              SizedBox(width: responsive.sp8),
                                              Text(
                                                'Add ${_selectedType == TransactionType.inflow ? 'Inflow' : 'Outflow'}',
                                                style: GoogleFonts.poppins(
                                                  fontSize: responsive.fs16,
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


void _showCurrencyConversionDialog() {
  final localizations = AppLocalizations.of(context);
  final TextEditingController _rateController = TextEditingController();
  Currency? _targetCurrency;
  final responsive = ResponsiveHelper(context);

  showDialog(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
            ),
            title: Row(
              children: [
                Icon(Icons.currency_exchange, color: Color(0xFF667eea)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    localizations.convertCurrency,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: responsive.fs18,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current Currency Display
                  Container(
                    padding: responsive.padding(all: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text(
                          localizations.current,
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs14,
                            color: Colors.grey[600],
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${_selectedCurrency.symbol} ${_selectedCurrency.displayName}',
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF333333),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),

                  // Target Currency Selector
                  Text(
                    localizations.convertTo,
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
                    ),
                  ),
                  SizedBox(height: 8),
                  DropdownButtonFormField<Currency>(
                    isExpanded: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: responsive.padding(horizontal: 12, vertical: 8),
                    ),
                    hint: Text(localizations.selectTargetCurrency),
                    value: _targetCurrency,
                    items: Currency.values
                        .where((c) => c != _selectedCurrency)
                        .map((currency) {
                      return DropdownMenuItem(
                        value: currency,
                        child: Text(
                          '${currency.symbol} - ${currency.displayName}',
                          style: GoogleFonts.poppins(fontSize: responsive.fs14),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        _targetCurrency = value;
                      });
                    },
                  ),
                  SizedBox(height: 16),

                  // Exchange Rate Input
                  Text(
                    localizations.exchangeRate,
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
                    ),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: _rateController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: 'e.g., 3000',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: responsive.padding(horizontal: 12, vertical: 8),
                      prefixText: '1 ${_selectedCurrency.symbol} = ',
                      suffixText: _targetCurrency != null ? _targetCurrency!.symbol : '',
                    ),
                    style: GoogleFonts.poppins(fontSize: responsive.fs14),
                  ),
                  SizedBox(height: 12),

                  // Preview Calculation
                  if (_targetCurrency != null && 
                      _rateController.text.isNotEmpty && 
                      _amountController.text.isNotEmpty)
                    Container(
                      padding: responsive.padding(all: 12),
                      decoration: BoxDecoration(
                        color: Color(0xFF667eea).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Color(0xFF667eea).withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            localizations.preview,
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF667eea),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '${_selectedCurrency.symbol}${double.parse(_amountController.text).toStringAsFixed(2)} → ${_targetCurrency!.symbol}${(double.parse(_amountController.text) * (double.tryParse(_rateController.text) ?? 1)).toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(
                              fontSize: responsive.fs14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF333333),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  localizations.dialogCancel,
                  style: GoogleFonts.poppins(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  if (_targetCurrency == null || _rateController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(localizations.pleaseFillAllFields),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  if (_amountController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(localizations.pleaseEnterAmountFirst),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  final rate = double.tryParse(_rateController.text);
                  if (rate == null || rate <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(localizations.pleaseEnterValidExchangeRate),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  Navigator.pop(dialogContext);
                  _applyConversion(_targetCurrency!, rate);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF667eea),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: responsive.padding(horizontal: 16, vertical: 12),
                ),
                child: Text(
                  localizations.convert,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

void _applyConversion(Currency targetCurrency, double exchangeRate) {
  final currentAmount = double.tryParse(_amountController.text);
  final localizations = AppLocalizations.of(context);
  final responsive = ResponsiveHelper(context);
  if (currentAmount == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(localizations.pleaseEnterValidAmount),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  final convertedAmount = currentAmount * exchangeRate;

  setState(() {
    _selectedCurrency = targetCurrency;
    _amountController.text = convertedAmount.toStringAsFixed(2);
  });

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Currency converted! Amount updated to ${targetCurrency.symbol}${convertedAmount.toStringAsFixed(2)}',
        style: GoogleFonts.poppins(color: Colors.white),
      ),
      backgroundColor: Color(0xFF4CAF50),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(12))),
      duration: Duration(seconds: 3),
    ),
  );
}

  // Function to handle adding the transaction
  void _addTransaction() async {
    if (_formKey.currentState!.validate()) {
      final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
      
      final success = await transactionProvider.createTransaction(
        type: _selectedType,
        mainCategory: _selectedMainCategory!,
        subCategory: _selectedSubCategory!,
        date: _selectedDate,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        amount: double.parse(_amountController.text),
        currency: _selectedCurrency,  // ADD THIS LINE
        context: context,
        recurrence: _recurrence,
      );

      if (success) {
        Navigator.pop(context, true);
      }
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