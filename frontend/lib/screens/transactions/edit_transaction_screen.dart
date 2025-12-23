import 'package:flutter/material.dart';
import 'package:frontend/models/recurring_transaction.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/widgets/recurrence_settings.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // Import for date formatting
import '../../models/transaction.dart';
import '../../services/api_service.dart';
import '../../providers/transaction_provider.dart';
import 'package:frontend/services/responsive_helper.dart';

// Extension for safely finding an element in a list (useful for dropdowns)
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

class EditTransactionScreen extends StatefulWidget {
  final Transaction transaction; // The transaction to be edited

  EditTransactionScreen({required this.transaction});

  @override
  _EditTransactionScreenState createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends State<EditTransactionScreen>
    with TickerProviderStateMixin { // Mixin for animation controllers
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountController;
  late TextEditingController _descriptionController;

  late TransactionType _selectedType;
  String? _selectedMainCategory;
  String? _selectedSubCategory;
  List<Category> _categories = []; // List to hold fetched categories
  bool _isLoadingCategories = false;
  late DateTime _selectedDate; // Will be initialized with the transaction's date

  TransactionRecurrence? _recurrence;

  // Animation controllers for screen transition
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;


  late Currency _selectedCurrency;

  @override
  void initState() {
    super.initState();

    // Initialize form fields with the data from the passed transaction
    _amountController = TextEditingController(text: widget.transaction.amount.toString());
    _descriptionController = TextEditingController(text: widget.transaction.description ?? '');
    _selectedType = widget.transaction.type;
    _selectedMainCategory = widget.transaction.mainCategory;
    _selectedSubCategory = widget.transaction.subCategory;
    _selectedDate = widget.transaction.date; // Initialize with the transaction's date
    _recurrence = widget.transaction.recurrence;
    _selectedCurrency = widget.transaction.currency;

    // Setup animations
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

    _loadCategories(); // Load categories specific to the transaction's type
    _animationController.forward(); // Start the animation
  }

  // Load categories from the API based on the selected transaction type
  Future<void> _loadCategories() async {
    setState(() {
      _isLoadingCategories = true; // Show loading indicator
    });

    try {
      final categories = await ApiService.getCategories(_selectedType);

      // Validate and re-select categories if they exist in the new list
      String? validatedMainCategory = null;
      String? validatedSubCategory = null;

      if (_selectedMainCategory != null && categories.isNotEmpty) {
        final matchingCategory = categories.firstWhereOrNull(
          (cat) => cat.mainCategory == _selectedMainCategory,
        );

        if (matchingCategory != null) {
          validatedMainCategory = matchingCategory.mainCategory; // Keep the valid main category
          if (_selectedSubCategory != null) {
            // Check if the previously selected sub-category is still valid
            if (matchingCategory.subCategories.contains(_selectedSubCategory)) {
              validatedSubCategory = _selectedSubCategory; // Keep the valid sub-category
            }
          }
        }
      }

      setState(() {
        _categories = categories;
        _selectedMainCategory = validatedMainCategory; // Update with validated category
        _selectedSubCategory = validatedSubCategory; // Update with validated sub-category
        _isLoadingCategories = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingCategories = false;
        print("Error loading categories: $e"); // Log error for debugging
      });
    }
  }

  // Function to show the date picker dialog
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate, // Pre-fill with the current selected date
      firstDate: DateTime(2000), // Set the earliest possible date
      lastDate: DateTime.now().add(Duration(days: 365)), // Allow future dates for a year
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
                      onPressed: () => Navigator.pop(context),
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
                        localizations.editTransactionTitle,
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF333333),
                        ),
                      ),
                    ),
                    // Delete Button
                    IconButton(
                      onPressed: () => _showDeleteDialog(), // Show confirmation dialog for deletion
                      icon: Container(
                        padding: responsive.padding(all: 8),
                        decoration: BoxDecoration(
                          color: Colors.red[50], // Light red background for delete
                          borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                        ),
                        child: Icon(Icons.delete_outline, color: Colors.red), // Red delete icon
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
                        key: _formKey,
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
                                        // Only update if the type is changing
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
                                              localizations.outflow,
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
                                        // Only update if the type is changing
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
                                              localizations.inflow,
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
                            child: OutlinedButton.icon(
                              onPressed: () => _showCurrencyConversionDialog(),
                              icon: Icon(Icons.currency_exchange, size: responsive.icon18),
                              label: Text(
                                localizations.convertCurrency,
                                style: GoogleFonts.poppins(fontSize: 14),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Color(0xFF667eea),
                                side: BorderSide(color: Color(0xFF667eea), width: 1.5),
                                padding: responsive.padding(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 24),

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
                                    return localizations.pleaseEnterAValidAmount;
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
                              localizations.dataLabelDate,
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
                              localizations.dataLabelCategory,
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

                            
                            // Show warning if this is an auto-created transaction
                            if (widget.transaction.parentTransactionId != null)
                              FutureBuilder<Transaction?>(
                                future: ApiService.getTransaction(widget.transaction.parentTransactionId!),
                                builder: (context, snapshot) {
                                  // Check if parent transaction has recurrence enabled
                                  final parentRecurrenceEnabled = snapshot.hasData && 
                                      snapshot.data?.recurrence?.enabled == true;

                                  return Container(
                                    padding: responsive.padding(all: 16),
                                    margin: responsive.padding(bottom: 16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Color(0xFFFFF3CD).withOpacity(0.8),
                                          Color(0xFFFFE8A3).withOpacity(0.8),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
                                      border: Border.all(color: Color(0xFFFFC107), width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Color(0xFFFFC107).withOpacity(0.2),
                                          spreadRadius: 1,
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: responsive.padding(all: 8),
                                              decoration: BoxDecoration(
                                                color: Color(0xFFFF9800),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Icon(Icons.auto_awesome, color: Colors.white, size: responsive.icon20),
                                            ),
                                            SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    localizations.autoCreatedTransactionTitle,
                                                    style: GoogleFonts.poppins(
                                                      fontSize: responsive.fs14,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFF333333),
                                                    ),
                                                  ),
                                                  SizedBox(height: 4),
                                                  Text(
                                                    parentRecurrenceEnabled
                                                        ? localizations.autoCreatedDescriptionRecurring
                                                        : localizations.autoCreatedDescriptionDisabled,
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 12,
                                                      color: Colors.grey[700],
                                                      height: 1.3,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 16),
                                        
                                        // ONLY SHOW BUTTON IF PARENT RECURRENCE IS ENABLED
                                        if (parentRecurrenceEnabled)
                                          Container(
                                            width: double.infinity,
                                            child: ElevatedButton.icon(
                                              onPressed: () => _showDisableRecurrenceDialog(),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Color(0xFFFF9800),
                                                padding: responsive.padding(vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                                                ),
                                                elevation: 2,
                                              ),
                                              icon: Icon(Icons.stop_circle_outlined, color: Colors.white, size: responsive.icon20),
                                              label: Text(
                                                localizations.stopFutureAutoCreation,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        
                                        // ALWAYS SHOW VIEW PARENT BUTTON
                                        SizedBox(height: 8),
                                        Container(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            onPressed: () => _viewParentTransaction(),
                                            style: OutlinedButton.styleFrom(
                                              padding: responsive.padding(vertical: 12),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                                              ),
                                              side: BorderSide(color: Color(0xFF667eea), width: 2),
                                            ),
                                            icon: Icon(Icons.repeat, color: Color(0xFF667eea), size: responsive.icon20),
                                            label: Text(
                                              localizations.viewParentTransaction,
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF667eea),
                                              ),
                                            ),
                                          ),
                                        ),
                                        
                                        // SHOW INFO MESSAGE IF PARENT RECURRENCE IS DISABLED
                                        if (!parentRecurrenceEnabled && snapshot.hasData)
                                          Padding(
                                            padding: responsive.padding(top: 12),
                                            child: Container(
                                              padding: responsive.padding(all: 12),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[100],
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.grey[300]!),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(Icons.info_outline, color: Colors.grey[600], size: responsive.icon16),
                                                  SizedBox(width: responsive.sp8),
                                                  Expanded(
                                                    child: Text(
                                                      localizations.recurringScheduleStopped,
                                                      style: GoogleFonts.poppins(
                                                        fontSize: responsive.fs11,
                                                        color: Colors.grey[700],
                                                        height: 1.3,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),

                            // Recurrence Settings (only show if NOT auto-created)
                            if (widget.transaction.parentTransactionId == null)
                              RecurrenceSettings(
                                initialRecurrence: _recurrence,
                                transactionDate: _selectedDate,
                                onRecurrenceChanged: (recurrence) {
                                  setState(() {
                                    _recurrence = recurrence;
                                  });
                                },
                              ),
                            
                            // Show message if auto-created
                            if (widget.transaction.parentTransactionId != null)
                              Container(
                                padding: responsive.padding(all: 16),
                                margin: responsive.padding(bottom: 16),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, color: Colors.grey[600], size: responsive.icon20),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        localizations.recurringSettingsStopDes,
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: Colors.grey[700],
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
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

                            // Update Transaction Button
                            Consumer<TransactionProvider>(
                              builder: (context, transactionProvider, child) {
                                return SizedBox(
                                  width: double.infinity,
                                  height: responsive.cardHeight(baseHeight: 56),
                                  child: ElevatedButton(
                                    onPressed: transactionProvider.isLoading ? null : _updateTransaction, // Disable if loading
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
                                                Icons.update_outlined,
                                                color: Colors.white,
                                              ),
                                              SizedBox(width: responsive.sp8),
                                              Text(
                                                localizations.updateTransactionButton,
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


void _showDisableRecurrenceDialog() {
  final localizations = AppLocalizations.of(context);
  final responsive = ResponsiveHelper(context);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
          ),
          title: Row(
            children: [
              Icon(Icons.stop_circle, color: Color(0xFFFF9800)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  localizations.stopRecurringDialogTitle,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: responsive.fs18,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.stopRecurringDialogContent,
                style: GoogleFonts.poppins(fontSize: 14),
              ),
              SizedBox(height: 12),
              Container(
                padding: responsive.padding(all: 12),
                decoration: BoxDecoration(
                  color: Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Color(0xFFFFC107)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFFFF9800), size: responsive.icon20),
                    SizedBox(width: responsive.sp8),
                    Expanded(
                      child: Text(
                        localizations.stopRecurringDialogInfo,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                localizations.dialogCancel,
                style: GoogleFonts.poppins(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _disableParentRecurrence();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFFF9800),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: responsive.padding(horizontal: 16, vertical: 12),
              ),
              icon: Icon(Icons.stop, color: Colors.white, size: responsive.icon18),
              label: Text(
                localizations.stopRecurringButton,
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
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${_selectedCurrency.symbol} ${_selectedCurrency.displayName}',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
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
                      fontSize: 14,
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
                          style: GoogleFonts.poppins(fontSize: 14),
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
                      fontSize: 14,
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
                    style: GoogleFonts.poppins(fontSize: 14),
                  ),
                  SizedBox(height: 12),

                  // Preview Calculation
                  if (_targetCurrency != null && _rateController.text.isNotEmpty)
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
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF667eea),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '${_selectedCurrency.symbol}${double.parse(_amountController.text).toStringAsFixed(2)} → ${_targetCurrency!.symbol}${(double.parse(_amountController.text) * (double.tryParse(_rateController.text) ?? 1)).toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
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
                onPressed: () async {
                  if (_targetCurrency == null || _rateController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(localizations.pleaseFillAllFields),
                        backgroundColor: Colors.red,
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
                      ),
                    );
                    return;
                  }

                  Navigator.pop(dialogContext);
                  _convertCurrency(_targetCurrency!, rate);
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


void _convertCurrency(Currency targetCurrency, double exchangeRate) {
  final currentAmount = double.tryParse(_amountController.text);
  final localizations = AppLocalizations.of(context);
  final responsive = ResponsiveHelper(context);
  if (currentAmount == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          localizations.pleaseEnterValidAmount,
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(12))),
      ),
    );
    return;
  }

  // Calculate the new amount
  final convertedAmount = currentAmount * exchangeRate;

  // ONLY UPDATE LOCAL STATE - don't save to backend
  setState(() {
    _selectedCurrency = targetCurrency;
    _amountController.text = convertedAmount.toStringAsFixed(2);
  });

  // Show success message
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Currency converted! Amount updated to ${targetCurrency.symbol}${convertedAmount.toStringAsFixed(2)}',
        style: GoogleFonts.poppins(color: Colors.white),
      ),
      backgroundColor: Color(0xFF4CAF50),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(responsive.borderRadius(12))),
      duration: Duration(seconds: 4),
    ),
  );
}

void _disableParentRecurrence() async {
  final localizations = AppLocalizations.of(context);
  final responsive = ResponsiveHelper(context);

    try {
      // Show loading with better styling
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder: (context) => Center(
          child: Container(
            margin: responsive.padding(horizontal: 40),
            padding: responsive.padding(all: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(responsive.borderRadius(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  spreadRadius: 2,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: responsive.padding(all: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 3,
                    ),
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  localizations.stoppingRecurrence,
                  style: GoogleFonts.poppins(
                    fontSize: responsive.fs18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF333333),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  localizations.pleaseWait,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await ApiService.disableParentTransactionRecurrence(widget.transaction.id);
      
      // Close loading dialog
      if (mounted) Navigator.pop(context);
      
      // Show success message with better styling
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Container(
              padding: responsive.padding(vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: responsive.padding(all: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: responsive.icon24,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          localizations.successTitle,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: responsive.fs14,
                          ),
                        ),
                        Text(
                          localizations.successAutoCreationStopped,
                          style: GoogleFonts.poppins(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            backgroundColor: Color(0xFF4CAF50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
            ),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
            margin: responsive.padding(all: 16),
            elevation: 6,
          ),
        );
      }
      
      // Refresh AI data
      if (mounted) {
        final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
        transactionProvider.fetchTransactions();
      }
      
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.pop(context);
      
      // Show error with better styling
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Container(
              padding: responsive.padding(vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: responsive.padding(all: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: responsive.icon24,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          localizations.errorTitle,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: responsive.fs14,
                          ),
                        ),
                        Text(
                          e.toString().replaceAll('Exception: ', ''),
                          style: GoogleFonts.poppins(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            backgroundColor: Color(0xFFFF5722),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
            ),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
            margin: responsive.padding(all: 16),
            elevation: 6,
            action: SnackBarAction(
              label: localizations.dismiss,
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    }
  }


void _viewParentTransaction() async {
  final localizations = AppLocalizations.of(context);
    if (widget.transaction.parentTransactionId == null) return;
    
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
          ),
        ),
      );
      
      final parentTransaction = await ApiService.getTransaction(
        widget.transaction.parentTransactionId!,
      );
      
      // Close loading
      Navigator.pop(context);
      
      // Navigate to parent transaction edit screen
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EditTransactionScreen(transaction: parentTransaction),
        ),
      );
      
      // If parent was modified, refresh this screen
      if (result == true || result == 'deleted') {
        Navigator.pop(context, result);
      }
    } catch (e) {
      // Close loading
      Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${localizations.errorLoadParentFailed} ${e.toString().replaceAll('Exception: ', '')}',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Function to handle the update transaction logic
void _updateTransaction() async {
    if (_formKey.currentState!.validate()) {
      final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
      
      TransactionRecurrence? recurrenceToSend;
      if (_recurrence != null && _recurrence!.enabled) {
        recurrenceToSend = _recurrence;
      } else {
        recurrenceToSend = TransactionRecurrence(
          enabled: false,
          config: null,
          lastCreatedDate: null,
          parentTransactionId: null,
        );
      }
      
      final success = await transactionProvider.updateTransaction(
        transactionId: widget.transaction.id,
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
        recurrence: recurrenceToSend,
      );

      if (success) {
        Navigator.pop(context, true);
      }
    }
  }

  // Function to show the delete confirmation dialog
  void _showDeleteDialog() {
    final localizations = AppLocalizations.of(context);
    final responsive = ResponsiveHelper(context);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
          ),
          title: Text(
            localizations.deleteTransactionTitle,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.red, // Red color for delete title
            ),
          ),
          content: Text(
            localizations.deleteConfirmMessage,
            style: GoogleFonts.poppins(),
          ),
          actions: [
            // Cancel Button
            TextButton(
              onPressed: () => Navigator.pop(context), // Close the dialog
              child: Text(
                localizations.dialogCancel,
                style: GoogleFonts.poppins(
                  color: Colors.grey[600],
                ),
              ),
            ),
            // Delete Button
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close the dialog
                _deleteTransaction(); // Proceed with deletion
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, // Red background for delete button
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                localizations.delete,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Function to handle the actual deletion of the transaction
  void _deleteTransaction() async {
    final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);
    
    // Call deleteTransaction with context for AI integration
    final success = await transactionProvider.deleteTransaction(
      widget.transaction.id, 
      context: context, // Add this line for AI data refresh
    );

    if (success) {
      Navigator.pop(context, 'deleted'); // Pop screen and return 'deleted' string to indicate deletion
    }
    // Error message will be handled by the provider if deletion fails
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