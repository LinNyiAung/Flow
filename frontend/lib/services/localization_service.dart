import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalizationService {
  static const String _languageKey = 'selected_language';
  
  static Future<String> getSelectedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageKey) ?? 'en';
  }
  
  static Future<void> setSelectedLanguage(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, languageCode);
  }
}

class AppLocalizations {
  final Locale locale;
  
  AppLocalizations(this.locale);
  
  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }
  
  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();
  
  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      // Home Screen
      'welcome_back': 'Welcome back,',
      'total_balance': 'Total Balance',
      'available': 'Available',
      'allocated_to_goals': 'Allocated to Goals',
      'inflow': 'Inflow',
      'outflow': 'Outflow',
      'ai_assistant': 'AI Assistant',
      'get_personalized_insights': 'Get personalized insights',
      'ai_insights': 'AI Insights',
      'view_comprehensive_analysis': 'View comprehensive financial analysis',
      'recent_transactions': 'Recent Transactions',
      'see_more': 'See More',
      'no_transactions': 'No transactions yet',
      'tap_to_add_first': 'Tap the + button to add your first transaction',
      'add_transaction': 'Add Transaction',
      'manual_entry': 'Manual Entry',
      'type_transaction_details': 'Type transaction details',
      'voice_input': 'Voice Input',
      'speak_your_transaction': 'Speak your transaction',
      'scan_receipt': 'Scan Receipt',
      'take_upload_photo': 'Take or upload receipt photo',
      'premium': 'PREMIUM',
      'transaction_added': 'Transaction added successfully!',
      'transaction_updated': 'Transaction updated successfully!',
      'transaction_deleted': 'Transaction deleted successfully!',
      'dashboard': 'Dashboard',
      'auto_created': 'Auto-created',
    },
    'my': {
      // Home Screen
      'welcome_back': 'ပြန်လည်ကြိုဆိုပါတယ်၊',
      'total_balance': 'စုစုပေါင်းလက်ကျန်ငွေ',
      'available': 'အသုံးပြုနိုင်သော',
      'allocated_to_goals': 'ရည်မှန်းချက်များအတွက် ခွဲဝေထားသည်',
      'inflow': 'ဝင်ငွေ',
      'outflow': 'ထွက်ငွေ',
      'ai_assistant': 'AI လက်ထောက်',
      'get_personalized_insights': 'ကိုယ်ပိုင်ထိုးထွင်းသိမြင်မှုများရယူပါ',
      'ai_insights': 'AI ထိုးထွင်းသိမြင်မှု',
      'view_comprehensive_analysis': 'ပြည့်စုံသောဘဏ္ဍာရေးခွဲခြမ်းစိတ်ဖြာမှုကြည့်ရှုပါ',
      'recent_transactions': 'ငွေသွင်းထုတ်မှတ်တမ်းများ',
      'see_more': 'နောက်ထပ်ကြည့်ရန်',
      'no_transactions': 'ငွေသွင်းထုတ်မှတ်တမ်းမရှိသေးပါ',
      'tap_to_add_first': 'သင့်ရဲ့ပထမဆုံးငွေသွင်းထုတ်မှတ်တမ်းထည့်ရန် + ခလုတ်ကိုနှိပ်ပါ',
      'add_transaction': 'ငွေသွင်းထုတ်မှတ်တမ်းထည့်ရန်',
      'manual_entry': 'လက်ဖြင့်ထည့်ခြင်း',
      'type_transaction_details': 'ငွေသွင်းထုတ်မှတ်တမ်းအသေးစိတ်ရိုက်ထည့်ပါ',
      'voice_input': 'အသံဖြင့်ထည့်ခြင်း',
      'speak_your_transaction': 'သင့်ငွေသွင်းထုတ်မှတ်တမ်းကိုပြောပါ',
      'scan_receipt': 'စကန်ဖတ်ခြင်း',
      'take_upload_photo': 'ငွေလက်ခံဖြတ်ပိုင်းဓာတ်ပုံရိုက်ခြင်း သို့မဟုတ် တင်ခြင်း',
      'premium': 'ပရီမီယံ',
      'transaction_added': 'ငွေသွင်းထုတ်မှတ်တမ်းအောင်မြင်စွာထည့်သွင်းပြီးပါပြီ!',
      'transaction_updated': 'ငွေသွင်းထုတ်မှတ်တမ်းအောင်မြင်စွာပြင်ဆင်ပြီးပါပြီ!',
      'transaction_deleted': 'ငွေသွင်းထုတ်မှတ်တမ်းအောင်မြင်စွာဖျက်ပြီးပါပြီ!',
      'dashboard': 'ဒက်ရှ်ဘုတ်',
      'auto_created': 'အလိုအလျောက်ဖန်တီးထားသည်',
    },
  };
  
  String translate(String key) {
    return _localizedValues[locale.languageCode]?[key] ?? key;
  }
  
  String get welcomeBack => translate('welcome_back');
  String get totalBalance => translate('total_balance');
  String get available => translate('available');
  String get allocatedToGoals => translate('allocated_to_goals');
  String get inflow => translate('inflow');
  String get outflow => translate('outflow');
  String get aiAssistant => translate('ai_assistant');
  String get getPersonalizedInsights => translate('get_personalized_insights');
  String get aiInsights => translate('ai_insights');
  String get viewComprehensiveAnalysis => translate('view_comprehensive_analysis');
  String get recentTransactions => translate('recent_transactions');
  String get seeMore => translate('see_more');
  String get noTransactions => translate('no_transactions');
  String get tapToAddFirst => translate('tap_to_add_first');
  String get addTransaction => translate('add_transaction');
  String get manualEntry => translate('manual_entry');
  String get typeTransactionDetails => translate('type_transaction_details');
  String get voiceInput => translate('voice_input');
  String get speakYourTransaction => translate('speak_your_transaction');
  String get scanReceipt => translate('scan_receipt');
  String get takeUploadPhoto => translate('take_upload_photo');
  String get premium => translate('premium');
  String get transactionAdded => translate('transaction_added');
  String get transactionUpdated => translate('transaction_updated');
  String get transactionDeleted => translate('transaction_deleted');
  String get dashboard => translate('dashboard');
  String get autoCreated => translate('auto_created');
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  
  @override
  bool isSupported(Locale locale) {
    return ['en', 'my'].contains(locale.languageCode);
  }
  
  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }
  
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}