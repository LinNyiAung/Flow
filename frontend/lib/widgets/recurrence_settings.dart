import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/recurring_transaction.dart';
import 'package:frontend/services/localization_service.dart';
import '../services/api_service.dart';
import 'package:frontend/services/responsive_helper.dart';

class RecurrenceSettings extends StatefulWidget {
  final TransactionRecurrence? initialRecurrence;
  final DateTime transactionDate;
  final Function(TransactionRecurrence?) onRecurrenceChanged;

  const RecurrenceSettings({
    Key? key,
    this.initialRecurrence,
    required this.transactionDate,
    required this.onRecurrenceChanged,
  }) : super(key: key);

  @override
  _RecurrenceSettingsState createState() => _RecurrenceSettingsState();
}

class _RecurrenceSettingsState extends State<RecurrenceSettings> {
  bool _isEnabled = false;
  RecurrenceFrequency _selectedFrequency = RecurrenceFrequency.monthly;
  int? _selectedDayOfWeek;
  int? _selectedDayOfMonth;
  int? _selectedMonth;
  int? _selectedDayOfYear;
  DateTime? _endDate;
  List<DateTime> _previewDates = [];
  bool _isLoadingPreview = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialRecurrence != null && widget.initialRecurrence!.enabled) {
      _isEnabled = true;
      final config = widget.initialRecurrence!.config!;
      _selectedFrequency = config.frequency;
      _selectedDayOfWeek = config.dayOfWeek;
      _selectedDayOfMonth = config.dayOfMonth;
      _selectedMonth = config.month;
      _selectedDayOfYear = config.dayOfYear;
      _endDate = config.endDate;
      _loadPreview();
    } else {
      _initializeDefaults();
    }
  }

  void _initializeDefaults() {
    final date = widget.transactionDate;
    _selectedDayOfWeek = date.weekday - 1; // 0-6 for Monday-Sunday
    _selectedDayOfMonth = date.day;
    _selectedMonth = date.month;
    _selectedDayOfYear = date.day;
  }

  RecurrenceConfig _buildConfig() {
    return RecurrenceConfig(
      frequency: _selectedFrequency,
      dayOfWeek: _selectedFrequency == RecurrenceFrequency.weekly ? _selectedDayOfWeek : null,
      dayOfMonth: _selectedFrequency == RecurrenceFrequency.monthly ? _selectedDayOfMonth : null,
      month: _selectedFrequency == RecurrenceFrequency.annually ? _selectedMonth : null,
      dayOfYear: _selectedFrequency == RecurrenceFrequency.annually ? _selectedDayOfYear : null,
      endDate: _endDate,
    );
  }

  void _notifyChange() {
    if (_isEnabled) {
      final recurrence = TransactionRecurrence(
        enabled: true,
        config: _buildConfig(),
        lastCreatedDate: widget.transactionDate,
        parentTransactionId: null,
      );
      widget.onRecurrenceChanged(recurrence);
    } else {
      widget.onRecurrenceChanged(null);
    }
  }

  Future<void> _loadPreview() async {
    if (!_isEnabled) {
      setState(() => _previewDates = []);
      return;
    }

    setState(() => _isLoadingPreview = true);

    try {
      final recurrence = TransactionRecurrence(
        enabled: true,
        config: _buildConfig(),
        lastCreatedDate: widget.transactionDate,
        parentTransactionId: null,
      );

      final dates = await ApiService.previewRecurrence(
        recurrence: recurrence,
        startDate: widget.transactionDate,
        count: 5,
      );

      setState(() {
        _previewDates = dates;
        _isLoadingPreview = false;
      });
    } catch (e) {
      setState(() => _isLoadingPreview = false);
      print('Error loading preview: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    return Container(
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
      padding: responsive.padding(all: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with toggle
          Row(
            children: [
              Container(
                padding: responsive.padding(all: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                  ),
                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                ),
                child: Icon(Icons.repeat, color: Colors.white, size: responsive.icon20),
              ),
              SizedBox(width: responsive.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.recurringTransaction,
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF333333),
                      ),
                    ),
                    Text(
                      localizations.recurringTransactionDes,
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isEnabled,
                onChanged: (value) {
                  setState(() {
                    _isEnabled = value;
                    if (value) {
                      _loadPreview();
                    }
                  });
                  _notifyChange();
                },
                activeColor: Color(0xFF667eea),
              ),
            ],
          ),

          if (_isEnabled) ...[
            SizedBox(height: responsive.sp20),
            Divider(),
            SizedBox(height: responsive.sp20),

            // Frequency selector
            Text(
              localizations.repeatFrequency,
              style: GoogleFonts.poppins(
                fontSize: responsive.fs14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
            ),
            SizedBox(height: responsive.sp12),
            ...RecurrenceFrequency.values.map((freq) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedFrequency = freq;
                    });
                    _loadPreview();
                    _notifyChange();
                  },
                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                  child: Container(
                    padding: responsive.padding(all: 16),
                    decoration: BoxDecoration(
                      color: _selectedFrequency == freq
                          ? Color(0xFF667eea).withOpacity(0.1)
                          : Colors.grey[50],
                      borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                      border: Border.all(
                        color: _selectedFrequency == freq
                            ? Color(0xFF667eea)
                            : Colors.grey[300]!,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selectedFrequency == freq
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: _selectedFrequency == freq
                              ? Color(0xFF667eea)
                              : Colors.grey[400],
                        ),
                        SizedBox(width: responsive.sp12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                freq.getDisplayName(context),
                                style: GoogleFonts.poppins(
                                  fontSize: responsive.fs14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF333333),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                freq.getDescription(context),
                                style: GoogleFonts.poppins(
                                  fontSize: responsive.fs12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),

            SizedBox(height: responsive.sp20),

            // Frequency-specific settings
            if (_selectedFrequency == RecurrenceFrequency.weekly)
              _buildWeeklySettings(),
            if (_selectedFrequency == RecurrenceFrequency.monthly)
              _buildMonthlySettings(),
            if (_selectedFrequency == RecurrenceFrequency.annually)
              _buildAnnuallySettings(),

            SizedBox(height: responsive.sp20),

            // End date (optional)
            Text(
              localizations.endDate,
              style: GoogleFonts.poppins(
                fontSize: responsive.fs14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
            ),
            SizedBox(height: responsive.sp8),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _endDate ?? DateTime.now().add(Duration(days: 365)),
                  firstDate: widget.transactionDate.add(Duration(days: 1)),
                  lastDate: DateTime.now().add(Duration(days: 3650)),
                  builder: (context, child) {
                    return Theme(
                      data: ThemeData.light().copyWith(
                        primaryColor: Color(0xFF667eea),
                        colorScheme: ColorScheme.light(
                          primary: Color(0xFF667eea),
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (picked != null) {
                  setState(() {
                    _endDate = picked;
                  });
                  _loadPreview();
                  _notifyChange();
                }
              },
              child: Container(
                padding: responsive.padding(all: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: Color(0xFF667eea)),
                    SizedBox(width: responsive.sp12),
                    Expanded(
                      child: Text(
                        _endDate != null
                            ? DateFormat('MMM dd, yyyy').format(_endDate!)
                            : 'Never ends',
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs14,
                          color: _endDate != null
                              ? Color(0xFF333333)
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                    if (_endDate != null)
                      IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey[600]),
                        onPressed: () {
                          setState(() {
                            _endDate = null;
                          });
                          _loadPreview();
                          _notifyChange();
                        },
                      ),
                  ],
                ),
              ),
            ),

            SizedBox(height: responsive.sp20),

            // Preview section
            Container(
              padding: responsive.padding(all: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF667eea).withOpacity(0.1),
                    Color(0xFF764ba2).withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.preview, color: Color(0xFF667eea), size: responsive.icon20),
                      SizedBox(width: responsive.sp8),
                      Text(
                        localizations.next5Occurrences,
                        style: GoogleFonts.poppins(
                          fontSize: responsive.fs14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF333333),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: responsive.sp12),
                  if (_isLoadingPreview)
                    Center(child: CircularProgressIndicator())
                  else if (_previewDates.isEmpty)
                    Text(
                      'No upcoming occurrences',
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs12,
                        color: Colors.grey[600],
                      ),
                    )
                  else
                    ..._previewDates.map((date) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Row(
                          children: [
                            Icon(Icons.circle, size: 8, color: Color(0xFF667eea)),
                            SizedBox(width: responsive.sp8),
                            Text(
                              DateFormat('MMM dd, yyyy').format(date),
                              style: GoogleFonts.poppins(
                                fontSize: responsive.fs13,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeeklySettings() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final responsive = ResponsiveHelper(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Repeat On',
          style: GoogleFonts.poppins(
            fontSize: responsive.fs14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF333333),
          ),
        ),
        SizedBox(height: responsive.sp12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(7, (index) {
            final isSelected = _selectedDayOfWeek == index;
            return InkWell(
              onTap: () {
                setState(() {
                  _selectedDayOfWeek = index;
                });
                _loadPreview();
                _notifyChange();
              },
              child: Container(
                width: responsive.iconSize(mobile: 44),
                height: responsive.iconSize(mobile: 44),
                decoration: BoxDecoration(
                  color: isSelected ? Color(0xFF667eea) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                  border: Border.all(
                    color: isSelected ? Color(0xFF667eea) : Colors.grey[300]!,
                  ),
                ),
                child: Center(
                  child: Text(
                    days[index],
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.grey[700],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildMonthlySettings() {
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.dayOfMonth,
          style: GoogleFonts.poppins(
            fontSize: responsive.fs14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF333333),
          ),
        ),
        SizedBox(height: responsive.sp12),
        Container(
          padding: responsive.padding(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: DropdownButton<int>(
            value: _selectedDayOfMonth,
            isExpanded: true,
            underline: SizedBox(),
            items: List.generate(31, (index) {
              final day = index + 1;
              return DropdownMenuItem(
                value: day,
                child: Text(
                  'Day $day',
                  style: GoogleFonts.poppins(),
                ),
              );
            }),
            onChanged: (value) {
              setState(() {
                _selectedDayOfMonth = value;
              });
              _loadPreview();
              _notifyChange();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAnnuallySettings() {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final responsive = ResponsiveHelper(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Month',
          style: GoogleFonts.poppins(
            fontSize: responsive.fs14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF333333),
          ),
        ),
        SizedBox(height: responsive.sp12),
        Container(
          padding: responsive.padding(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: DropdownButton<int>(
            value: _selectedMonth,
            isExpanded: true,
            underline: SizedBox(),
            items: List.generate(12, (index) {
              final month = index + 1;
              return DropdownMenuItem(
                value: month,
                child: Text(
                  months[index],
                  style: GoogleFonts.poppins(),
                ),
              );
            }),
            onChanged: (value) {
              setState(() {
                _selectedMonth = value;
              });
              _loadPreview();
              _notifyChange();
            },
          ),
        ),
        SizedBox(height: responsive.sp16),
        Text(
          'Day',
          style: GoogleFonts.poppins(
            fontSize: responsive.fs14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF333333),
          ),
        ),
        SizedBox(height: responsive.sp12),
        Container(
          padding: responsive.padding(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: DropdownButton<int>(
            value: _selectedDayOfYear,
            isExpanded: true,
            underline: SizedBox(),
            items: List.generate(31, (index) {
              final day = index + 1;
              return DropdownMenuItem(
                value: day,
                child: Text(
                  'Day $day',
                  style: GoogleFonts.poppins(),
                ),
              );
            }),
            onChanged: (value) {
              setState(() {
                _selectedDayOfYear = value;
              });
              _loadPreview();
              _notifyChange();
            },
          ),
        ),
      ],
    );
  }
}