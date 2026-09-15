import 'package:flutter/material.dart';
import 'package:frontend/services/api_service.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/localization_service.dart';

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

    final changedToBurmese = languageCode == 'my';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          changedToBurmese ? 'ဘာသာစကားကို မြန်မာသို့ပြောင်းလဲပြီးပါပြီ' : 'Language changed to English',
          style: changedToBurmese ? GoogleFonts.padauk(fontSize: 14, fontWeight: FontWeight.w400, height: 1.75) : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBurmese = _selectedLanguage == 'my';
    // Manrope has no Myanmar glyphs and Padauk ships weight 400/700 only, so
    // Burmese strings here are set explicitly in Padauk with a weight snapped
    // to one of those two and the line-height bucket the design calls for
    // (1.6 single-line label, 1.75 wrapping body prose, 1.5 app-bar title).
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isBurmese ? 'ဘာသာစကားဆက်တင်များ' : 'Language Settings',
          style: isBurmese ? GoogleFonts.padauk(fontSize: 20, fontWeight: FontWeight.w700, height: 1.5) : null,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              isBurmese ? 'ဘာသာစကားရွေးချယ်ပါ' : 'Select Language',
              style: isBurmese
                  ? GoogleFonts.padauk(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.primary, height: 1.6)
                  : TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.primary),
            ),
          ),

          Card(
            child: Column(
              children: [
                _buildLanguageOption(
                  languageCode: 'en',
                  languageName: 'English',
                  nativeName: 'English',
                ),
                const Divider(),
                _buildLanguageOption(
                  languageCode: 'my',
                  languageName: 'Myanmar',
                  nativeName: 'မြန်မာ',
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              isBurmese
                  ? 'ဘာသာစကားအသစ်ကိုအသုံးပြုရန် အက်ပ်ကိုပြန်လည်စတင်ပါမည်'
                  : 'The app will restart to apply the new language',
              style: isBurmese
                  ? GoogleFonts.padauk(fontSize: 12, fontWeight: FontWeight.w400, color: scheme.onSurfaceVariant, height: 1.75)
                  : TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageOption({
    required String languageCode,
    required String languageName,
    required String nativeName,
  }) {
    final isSelected = _selectedLanguage == languageCode;
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => _changeLanguage(languageCode),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nativeName,
                    // Padauk ships weight 400/700 only (no 500/600) — request
                    // w700 explicitly so the native name actually renders
                    // bold instead of silently falling back to regular.
                    style: GoogleFonts.padauk(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface, height: 1.75),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    languageName,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.6),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle_rounded, color: scheme.primary, size: 22),
          ],
        ),
      ),
    );
  }
}
