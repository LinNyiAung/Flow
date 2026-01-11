import 'package:flutter/material.dart';
import 'package:frontend/services/api_service.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/localization_service.dart';
import 'package:frontend/services/responsive_helper.dart';

class LanguageSettingsScreen extends StatefulWidget {
  final Function(Locale) onLanguageChanged;

  LanguageSettingsScreen({required this.onLanguageChanged});

  @override
  _LanguageSettingsScreenState createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends State<LanguageSettingsScreen> {
  String _selectedLanguage = 'en';

  @override
  void initState() {
    super.initState();
    _loadCurrentLanguage();
  }

  Future<void> _loadCurrentLanguage() async {
    final languageCode = await LocalizationService.getSelectedLanguage();
    setState(() {
      _selectedLanguage = languageCode;
    });
  }

  Future<void> _changeLanguage(String languageCode) async {
    final responsive = ResponsiveHelper(context);

    // NEW: Update language on backend
    try {
      await ApiService.updateLanguage(languageCode);
    } catch (e) {
      print('Failed to update language on backend: $e');
    }

    await LocalizationService.setSelectedLanguage(languageCode);
    setState(() {
      _selectedLanguage = languageCode;
    });
    widget.onLanguageChanged(Locale(languageCode));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          languageCode == 'en'
              ? 'Language changed to English'
              : 'ဘာသာစကားကို မြန်မာသို့ပြောင်းလဲပြီးပါပြီ',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(responsive.borderRadius(12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final responsive = ResponsiveHelper(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedLanguage == 'en'
              ? 'Language Settings'
              : 'ဘာသာစကားဆက်တင်များ',
          style: GoogleFonts.poppins(
            fontSize: responsive.fs20,
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
        child: ListView(
          padding: responsive.padding(all: 20),
          children: [
            // Header Card
            Container(
              padding: responsive.padding(all: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(
                  responsive.borderRadius(16),
                ),
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
                  Container(
                    padding: responsive.padding(all: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                      ),
                      borderRadius: BorderRadius.circular(
                        responsive.borderRadius(12),
                      ),
                    ),
                    child: Icon(
                      Icons.language,
                      color: Colors.white,
                      size: responsive.icon20,
                    ),
                  ),
                  SizedBox(width: responsive.sp16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedLanguage == 'en'
                              ? 'Select Language'
                              : 'ဘာသာစကားရွေးချယ်ပါ',
                          style: GoogleFonts.poppins(
                            fontSize: responsive.fs16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333),
                          ),
                        ),
                        SizedBox(height: responsive.sp4),
                        Text(
                          _selectedLanguage == 'en'
                              ? 'Choose your preferred language'
                              : 'သင်နှစ်သက်သောဘာသာစကားကိုရွေးချယ်ပါ',
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

            SizedBox(height: responsive.sp24),

            // English Option
            _buildLanguageOption(
              languageCode: 'en',
              languageName: 'English',
              nativeName: 'English',
              flag: '🇬🇧',
            ),

            SizedBox(height: responsive.sp12),

            // Myanmar Option
            _buildLanguageOption(
              languageCode: 'my',
              languageName: 'Myanmar',
              nativeName: 'မြန်မာ',
              flag: '🇲🇲',
            ),

            SizedBox(height: responsive.sp24),

            // Info Card
            Container(
              padding: responsive.padding(all: 16),
              decoration: BoxDecoration(
                color: Color(0xFF2196F3).withOpacity(0.1),
                borderRadius: BorderRadius.circular(
                  responsive.borderRadius(12),
                ),
                border: Border.all(
                  color: Color(0xFF2196F3).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Color(0xFF2196F3),
                    size: responsive.icon20,
                  ),
                  SizedBox(width: responsive.sp12),
                  Expanded(
                    child: Text(
                      _selectedLanguage == 'en'
                          ? 'The app will restart to apply the new language'
                          : 'ဘာသာစကားအသစ်ကိုအသုံးပြုရန် အက်ပ်ကိုပြန်လည်စတင်ပါမည်',
                      style: GoogleFonts.poppins(
                        fontSize: responsive.fs13,
                        color: Color(0xFF2196F3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageOption({
    required String languageCode,
    required String languageName,
    required String nativeName,
    required String flag,
  }) {
    final isSelected = _selectedLanguage == languageCode;
    final responsive = ResponsiveHelper(context);

    return InkWell(
      onTap: () => _changeLanguage(languageCode),
      borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
      child: Container(
        padding: responsive.padding(all: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(responsive.borderRadius(16)),
          border: Border.all(
            color: isSelected
                ? Color(0xFF667eea)
                : Colors.grey.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Color(0xFF667eea).withOpacity(0.2),
                    spreadRadius: 2,
                    blurRadius: 8,
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 4,
                  ),
                ],
        ),
        child: Row(
          children: [
            Text(flag, style: TextStyle(fontSize: responsive.fs32)),
            SizedBox(width: responsive.sp16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    languageName,
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    nativeName,
                    style: GoogleFonts.poppins(
                      fontSize: responsive.fs14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                padding: responsive.padding(all: 8),
                decoration: BoxDecoration(
                  color: Color(0xFF667eea),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check,
                  color: Colors.white,
                  size: responsive.icon20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
