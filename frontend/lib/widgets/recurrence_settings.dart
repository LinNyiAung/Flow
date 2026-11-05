import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/recurring_transaction.dart';
import 'package:frontend/services/localization_service.dart';
import '../services/api_service.dart';
import 'package:frontend/services/responsive_helper.dart';
import 'package:frontend/utils/date_picker_bounds.dart';

/// The schedule picker shown in the Repeat sheet. It has no on/off switch
/// of its own: the caller's Repeat row switch turns repeat on (by opening
/// this) and off, so showing it means repeat is on. With no enabled
/// [initialRecurrence] it starts from defaults based on [transactionDate]
/// and reports that recurrence right away.
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
    final initial = widget.initialRecurrence;
    if (initial != null && initial.enabled && initial.config != null) {
      final config = initial.config!;
      _selectedFrequency = config.frequency;
      _selectedDayOfWeek = config.dayOfWeek;
      _selectedDayOfMonth = config.dayOfMonth;
      _selectedMonth = config.month;
      _selectedDayOfYear = config.dayOfYear;
      _endDate = config.endDate;
    } else {
      _initializeDefaults();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _notifyChange();
      });
    }
    _loadPreview();
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
    widget.onRecurrenceChanged(TransactionRecurrence(
      enabled: true,
      config: _buildConfig(),
      lastCreatedDate: widget.transactionDate,
      parentTransactionId: null,
    ));
  }

  Future<void> _loadPreview() async {
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

      if (!mounted) return;
      setState(() {
        _previewDates = dates;
        _isLoadingPreview = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingPreview = false);
      print('Error loading preview: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
        boxShadow: [BoxShadow(color: Theme.of(context).cardTheme.shadowColor ?? const Color(0x1A101815), blurRadius: 8)],
      ),
      padding: responsive.padding(all: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Frequency selector
          Text(
            localizations.repeatFrequency,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: responsive.sp12),
          ...RecurrenceFrequency.values.map((freq) {
            final selected = _selectedFrequency == freq;
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
                    color: selected ? scheme.primaryContainer : scheme.surface,
                    borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                    border: Border.all(color: selected ? scheme.primary : scheme.outline, width: selected ? 2 : 1),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                        color: selected ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                      SizedBox(width: responsive.sp12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              freq.getDisplayName(context),
                              style: TextStyle(
                                fontSize: responsive.fs14,
                                fontWeight: FontWeight.w600,
                                color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              freq.getDescription(context),
                              style: TextStyle(
                                fontSize: responsive.fs12,
                                color: selected
                                    ? scheme.onPrimaryContainer.withValues(alpha: 0.82)
                                    : scheme.onSurfaceVariant,
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
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: responsive.sp8),
          InkWell(
            onTap: () async {
              // The transaction date may have moved past the saved end
              // date (or past now + 365): clamp instead of asserting.
              final firstDate = widget.transactionDate.add(Duration(days: 1));
              final bounds = DatePickerBounds.clamped(
                initialDate: _endDate ?? DateTime.now().add(Duration(days: 365)),
                firstDate: firstDate,
                lastDate: laterDate(DateTime.now().add(Duration(days: 3650)), firstDate),
              );
              final picked = await showDatePicker(
                context: context,
                initialDate: bounds.initialDate,
                firstDate: bounds.firstDate,
                lastDate: bounds.lastDate,
              );
              if (picked != null) {
                setState(() {
                  _endDate = picked;
                });
                _loadPreview();
                _notifyChange();
              }
            },
            borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
            child: Container(
              padding: responsive.padding(all: 16),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                border: Border.all(color: scheme.outline),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, color: scheme.primary),
                  SizedBox(width: responsive.sp12),
                  Expanded(
                    child: Text(
                      _endDate != null
                          ? DateFormat('MMM dd, yyyy').format(_endDate!)
                          : localizations.neverEnds,
                      style: TextStyle(
                        fontSize: responsive.fs14,
                        color: _endDate != null ? scheme.onSurface : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_endDate != null)
                    IconButton(
                      icon: Icon(Icons.clear_rounded, color: scheme.onSurfaceVariant),
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
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.visibility_rounded, color: scheme.onPrimaryContainer, size: responsive.icon20),
                    SizedBox(width: responsive.sp8),
                    // Flexible: the Myanmar label wraps at large font sizes.
                    Flexible(
                      child: Text(
                        localizations.next5Occurrences,
                        style: TextStyle(
                          fontSize: responsive.fs14,
                          fontWeight: FontWeight.w600,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: responsive.sp12),
                if (_isLoadingPreview)
                  Center(child: CircularProgressIndicator(color: scheme.primary))
                else if (_previewDates.isEmpty)
                  Text(
                    localizations.noUpcomingOccurrences,
                    style: TextStyle(
                      fontSize: responsive.fs12,
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.82),
                    ),
                  )
                else
                  ..._previewDates.map((date) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 8, color: scheme.onPrimaryContainer),
                          SizedBox(width: responsive.sp8),
                          Text(
                            DateFormat('MMM dd, yyyy').format(date),
                            style: TextStyle(fontSize: responsive.fs13, color: scheme.onPrimaryContainer),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklySettings() {
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final days = [
      localizations.weekdayMon,
      localizations.weekdayTue,
      localizations.weekdayWed,
      localizations.weekdayThu,
      localizations.weekdayFri,
      localizations.weekdaySat,
      localizations.weekdaySun,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.repeatOn,
          style: TextStyle(fontSize: responsive.fs14, fontWeight: FontWeight.w600, color: scheme.onSurface),
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
              borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
              child: Container(
                width: responsive.iconSize(mobile: 44),
                height: responsive.iconSize(mobile: 44),
                decoration: BoxDecoration(
                  color: isSelected ? scheme.primary : scheme.surface,
                  borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
                  border: Border.all(color: isSelected ? scheme.primary : scheme.outline),
                ),
                child: Center(
                  child: Text(
                    days[index],
                    style: TextStyle(
                      fontSize: responsive.fs13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : scheme.onSurfaceVariant,
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
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.dayOfMonth,
          style: TextStyle(fontSize: responsive.fs14, fontWeight: FontWeight.w600, color: scheme.onSurface),
        ),
        SizedBox(height: responsive.sp12),
        Container(
          padding: responsive.padding(horizontal: 16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
            border: Border.all(color: scheme.outline),
          ),
          child: DropdownButton<int>(
            value: _selectedDayOfMonth,
            isExpanded: true,
            underline: SizedBox(),
            dropdownColor: Theme.of(context).cardTheme.color,
            style: TextStyle(color: scheme.onSurface, fontSize: responsive.fs14),
            items: List.generate(31, (index) {
              final day = index + 1;
              return DropdownMenuItem(
                value: day,
                child: Text('${localizations.dayLabel} $day'),
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
    final responsive = ResponsiveHelper(context);
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final months = [
      localizations.monthJanuary,
      localizations.monthFebruary,
      localizations.monthMarch,
      localizations.monthApril,
      localizations.monthMay,
      localizations.monthJune,
      localizations.monthJuly,
      localizations.monthAugust,
      localizations.monthSeptember,
      localizations.monthOctober,
      localizations.monthNovember,
      localizations.monthDecember,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.month,
          style: TextStyle(fontSize: responsive.fs14, fontWeight: FontWeight.w600, color: scheme.onSurface),
        ),
        SizedBox(height: responsive.sp12),
        Container(
          padding: responsive.padding(horizontal: 16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
            border: Border.all(color: scheme.outline),
          ),
          child: DropdownButton<int>(
            value: _selectedMonth,
            isExpanded: true,
            underline: SizedBox(),
            dropdownColor: Theme.of(context).cardTheme.color,
            style: TextStyle(color: scheme.onSurface, fontSize: responsive.fs14),
            items: List.generate(12, (index) {
              final month = index + 1;
              return DropdownMenuItem(
                value: month,
                child: Text(months[index]),
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
          localizations.dayLabel,
          style: TextStyle(fontSize: responsive.fs14, fontWeight: FontWeight.w600, color: scheme.onSurface),
        ),
        SizedBox(height: responsive.sp12),
        Container(
          padding: responsive.padding(horizontal: 16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
            border: Border.all(color: scheme.outline),
          ),
          child: DropdownButton<int>(
            value: _selectedDayOfYear,
            isExpanded: true,
            underline: SizedBox(),
            dropdownColor: Theme.of(context).cardTheme.color,
            style: TextStyle(color: scheme.onSurface, fontSize: responsive.fs14),
            items: List.generate(31, (index) {
              final day = index + 1;
              return DropdownMenuItem(
                value: day,
                child: Text('${localizations.dayLabel} $day'),
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
