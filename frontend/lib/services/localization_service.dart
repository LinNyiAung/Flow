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
      'toePwar': 'Toe Pwar',
      'welcomeBack': 'Welcome back,',
      'totalBalance': 'Total Balance',
      'available': 'Available',
      'allocatedToGoals': 'Allocated to Goals',
      'inflow': 'Inflow',
      'outflow': 'Outflow',
      'aiAssistant': 'AI Assistant',
      'getPersonalizedInsights': 'Get personalized insights',
      'aiInsights': 'AI Insights',
      'viewComprehensiveAnalysis': 'View comprehensive financial analysis',
      'recentTransactions': 'Recent',
      'seeMore': 'See all',
      'noTransactions': 'No transactions yet',
      'tapToAddFirst': 'Tap the + button to add your first transaction',
      'addTransaction': 'Add Transaction',
      'manualEntry': 'Manual Entry',
      'typeTransactionDetails': 'Type transaction details',
      'voiceInput': 'Voice Input',
      'speakYourTransaction': 'Speak your transaction',
      'scanReceipt': 'Scan Receipt',
      'takeUploadPhoto': 'Take or upload receipt photo',
      'premium': 'PREMIUM',
      'transactionAdded': 'Transaction added successfully!',
      'transactionUpdated': 'Transaction updated successfully!',
      'transactionDeleted': 'Transaction deleted successfully!',
      'dashboard': 'Dashboard',
      'autoCreated': 'Auto-created',
      'viewAllCurrencies':'View All Currencies',
      'allCurrencyBalances':'All Currency Balances',
      'default':'Default',


      // Additions for Drawer Navigation
      'drawerWelcome': 'Welcome',
      'drawerLogout': 'Logout',
      'dialogCancel': 'Cancel',
      'dialogLogoutConfirm': 'Are you sure you want to logout?',
      'transactions': 'Transactions',
      'goals': 'Goals',
      'budgets': 'Budgets',
      'inflowAnalytics': 'Inflow Analytics',
      'outflowAnalytics': 'Outflow Analytics',
      'financialReports': 'Financial Reports',
      'settings': 'Settings',
      'expiresOn': 'Expires',

      // Additions for Add Transaction Screen
      'addTransactionTitle': 'New entry',
      'currency': 'Currency',
      'convertCurrency': 'Convert Currency',
      'current': 'Current: ',
      'convertTo': 'Convert To: ',
      'exchangeRate': 'Exchange Rate:',
      'convert': 'Convert',
      'selectTargetCurrency': 'Select target currency',
      'amountLabel': 'Amount',
      'dateLabel': 'Date',
      'categoryLabel': 'Category',
      'selectMainCategoryHint': 'Select main category',
      'selectSubCategoryHint': 'Select sub category',
      'descriptionLabel': 'Description (Optional)',
      'descriptionHint': 'Add a note about this transaction...',
      'addOutflowButton': 'Add Outflow',
      'addInflowButton': 'Add Inflow',
      'validationAmountInvalid': 'Please enter a valid amount',
      'validationAmountPositive': 'Amount must be greater than 0',
      'validationMainCategoryRequired': 'Please select a main category',
      'validationSubCategoryRequired': 'Please select a sub category',
      'recurringTransaction': 'Recurring Transaction',
      'recurringTransactionDes': 'Automatically create this transaction',
      'repeatFrequency': 'Repeat Frequency',
      'dayOfMonth': 'Day of Month',
      'daily': 'Daily',
      'weekly': 'Weekly',
      'monthly': 'Monthly',
      'annually': 'Annually',
      'dailyDes':'Repeats every day',
      'weeklyDes': 'Repeats on a selected day of the week',
      'monthlyDes': 'Repeats on a selected date of the month',
      'annuallyDes': 'Repeats on a selected date of the year',
      'endDate': 'End Date (Optional)',
      'next5Occurrences': 'Next 5 Occurrences',
      'enterAmountBeforeConverting': 'Please enter amount first before converting',
      'preview': 'Preview:',
      'pleaseFillAllFields': 'Please fill all fields',
      'pleaseEnterAmountFirst': 'Please enter amount first',
      'pleaseEnterValidExchangeRate': 'Please enter a valid exchange rate',
      'pleaseEnterValidAmount': 'Please enter a valid amount first',
      'neverEnds': 'Never ends',

      // Additions for Edit Transaction Screen
      'editTransactionTitle': 'Edit Transaction',
      'deleteTransactionTitle': 'Delete Transaction',
      'deleteConfirmMessage': 'Are you sure you want to delete this transaction? This action cannot be undone.',
      'autoCreatedTransactionTitle': 'Auto-Created Transaction',
      'autoCreatedDescriptionRecurring': 'This was automatically created from a recurring transaction.',
      'autoCreatedDescriptionDisabled': 'This was automatically created from a recurring transaction (now disabled).',
      'stopFutureAutoCreation': 'Stop Future Auto-Creation',
      'viewParentTransaction': 'View Parent Transaction',
      'stopRecurringDialogTitle': 'Stop Recurring Transaction?',
      'stopRecurringDialogContent': 'This will stop automatic creation of future transactions.',
      'stopRecurringDialogInfo': 'Existing transactions will not be affected.',
      'stopRecurringButton': 'Stop Recurring',
      'stoppingRecurrence': 'Stopping Recurrence',
      'pleaseWait': 'Please wait...',
      'successTitle': 'Success!',
      'successAutoCreationStopped': 'Future auto-creation has been stopped',
      'errorTitle': 'Error',
      'errorLoadParentFailed': 'Failed to load parent transaction:',
      'updateTransactionButton': 'Update Transaction',
      'selectCurrencyT': 'Select currency',
      'recurringScheduleStopped': 'The recurring schedule for this transaction has been stopped.',
      'recurringSettingsStopDes': 'Recurring settings are managed by the parent transaction. Use the button above to stop future auto-creation.',
      'dismiss': 'DISMISS',

      // Additions for Image Input Screen
      'imageInputTitle': 'Image Input',
      'premiumFeatureTitle': 'Premium Feature',
      'premiumFeatureUpgradeDescImg': 'Upgrade to use image input for transactions',
      'upgradeNowButton': 'Upgrade Now',
      'tapToAddImagePlaceholder': 'Tap to add receipt image',
      'cameraOrGalleryPlaceholder': 'Camera or Gallery',
      'chooseDifferentImageButton': 'Choose Different Image',
      'analyzingReceipt': 'Analyzing receipt...',
      'extractedTransactionTitle': 'Extracted Transaction',
      'dataLabelType': 'Type',
      'dataLabelAmount': 'Amount',
      'dataLabelCategory': 'Category',
      'dataLabelDate': 'Date',
      'dataLabelDescription': 'Description',
      'aiReasoningLabel': 'AI Reasoning:',
      'confidenceLabel': 'Confidence:',
      'saveTransactionButton': 'Save Transaction',
      'errorCaptureImage': 'Failed to capture image:',
      'errorPickImage': 'Failed to pick image:',
      'chooseImageSourceModalTitle': 'Choose Image Source',
      'cameraListTileTitle': 'Camera',
      'cameraListTileSubtitle': 'Take a photo of receipt',
      'galleryListTileTitle': 'Gallery',
      'galleryListTileSubtitle': 'Choose from gallery',

      // Additions for Voice Input Screen
      'voiceInputTitle': 'Voice Input',
      'premiumFeatureUpgradeDescVoice': 'Upgrade to use voice input for transactions',
      'recordingStatus': 'Recording... Tap to stop',
      'tapToRecordStatus': 'Tap to start recording\nYou can describe multiple transactions',
      'transcriptionTitle': 'Transcription',
      'errorStartRecording': 'Failed to start recording:',
      'errorStopRecording': 'Failed to stop recording:',
      'analyzingTransactions': 'Analyzing transactions...',

      // Additions for Transactions List Screen
      'allTransactionsTitle': 'All Transactions',
      'filtersSectionTitle': 'Filters',
      'transactionTypeFilterLabel': 'Transaction Type:',
      'filterChipAll': 'All',
      'dateRangeFilterLabel': 'Date Range:',
      'selectDateRangeButton': 'Select Date Range',
      'loadingMoreIndicator': 'Loading more...',
      'emptyStateTitle': 'No transactions found',
      'emptyStateSubtitle': 'Try adjusting your filters or adding a transaction.',
      'clearAllFiltersButton': 'Clear All Filters',
      'clearDateFilterTooltip': 'Clear Date Filter',
      'addTransactionFabTooltip': 'Add New Transaction',
      'currencyFilter': 'Currency Filter',

      //Goals screen
      'financialGoals': 'Financial Goals',
      'goalsSummary': 'Goals Summary',
      'active': 'Active',
      'achieved': 'Achieved',
      'total': 'Total',
      'byCurrency': 'By Currency',
      'availableBalance': 'Available Balance',
      'forGoals': 'for goals',
      'availableForGoals': 'Available for Goals',
      'selected': 'Selected',
      'goalCreatedSuccessfully': 'Goal created successfully!',
      'goalDeletedSuccessfully': 'Goal deleted successfully!',
      'noGoalsYet': 'No goals yet',
      'createGoalGetStarted': 'Create your first financial goal to get started!',


      //Add goal screen
      'createNewGoal': 'Create New Goal',
      'goalName': 'Goal Name',
      'goalType': 'Goal Type',
      'targetAmount': 'Target Amount',
      'initialContribution': 'Initial Contribution (Optional)',
      'targetDate': 'Target Date (Optional)',
      'createGoal': 'Create Goal',
      'failedToCreateGoal': 'Failed to create goal',
      'pleaseEnterAGoalName': 'Please enter a goal name',
      'pleaseEnterTargetAmount': 'Please enter target amount',
      'pleaseEnterAValidAmount': 'Please enter a valid amount',
      'insufficientBalance': 'Insufficient balance',
      'selectTargetDate': 'Select target date (Optional)',
      'egEmergencyFund': 'e.g., Emergency Fund',


      // goal detail screen
      'goalInformation': 'Goal Information',
      'fundsAddedSuccessfully': 'Funds added successfully!',
      'fundsWithdrawnSuccessfully': 'Funds withdrawn successfully!',
      'manageFunds': 'Manage Funds',
      'currentProgress': 'Current Progress',
      'currentAmount': 'Current Amount',
      'remaining': 'Remaining',
      'targetDateDetail': 'Target Date',
      'created': 'Created',
      'withdraw': 'Withdraw',
      'add': 'Add',
      'editGoal': 'Edit Goal',
      'enterAGoalName': 'Please enter a goal name',
      'goalUpdatedSuccessfully': 'Goal updated successfully!',
      'failedToUpdateGoal': 'Failed to update goal',
      'save': 'Save',
      'deleteGoal': 'Delete Goal',
      'deleteGoalConfirmation': 'Are you sure you want to delete this goal? The allocated funds will be returned to your balance.',
      'delete': 'Delete',
      'failedToDeleteGoal': 'Failed to delete goal',
      'goalDetails': 'Goal Details',


      //budgets screen
      'budgetCreatedSuccessfully':'Budget created successfully!',
      'budgetDeletedSuccessfully': 'Budget deleted successfully!',
      'budgetSummary': 'Budget Summary',
      'exceeded': 'Exceeded',
      'allCurrencies': 'All Currencies',
      'createNewBudget': 'Create New Budget',
      'upcoming': 'UPCOMING',
      'exceededCap': 'EXCEEDED',
      'completed': 'COMPLETED',
      'activeCap': 'ACTIVE',
      'auto': 'AUTO',
      'noBudgetsYet': 'No budgets yet',
      'createYourFirstBudget': 'Create your first budget to track spending!',

      //create budget screen
      'categoryAlreadyExists':'This category already exists',
      'selectEndDate': 'Please select end date for custom period',
      'addOneCategoryBudget': 'Please add at least one category budget',
      'failedToCreateBudget': 'Failed to create budget',
      'createBudget': 'Create Budget',
      'selectCurrency': 'Select currency for this budget',
      'pleaseSelectCurrency': 'Please select a currency',
      'aiFeatures': 'AI Features',
      'getAiPoweredBudgetSuggestions': 'Get AI-powered budget suggestions',
      'tapToUseAiBudgetSuggestions': 'Tap to use AI budget suggestions',
      'context': 'Context (Optional)',
      'addContext': 'Add context to help AI create better budgets',
      'generateAiBudget': 'Generate AI Budget',
      'aiWillAnalyzeAndSuggestBudgets' : 'AI will analyze your spending and suggest category budgets',
      'budgetName': 'Budget Name',
      'enterBudgetName': 'Please enter budget name',
      'budgetPeriod': 'Budget Period',
      'week': 'Week',
      'month': 'Month',
      'year': 'Year',
      'custom': 'Custom',
      'startDate': 'Start Date',
      'endDateNoOp': 'End Date',
      'autoCreateNextBudget':  'Auto-Create Next Budget',
      'automaticallyCreateNewBudget': 'Automatically create a new budget when this one ends',
      'enableAutoCreate': 'Enable Auto-Create',
      'chooseHowToCreateNextBudget': 'Choose how to create the next budget:',
      'useCurrentCategories': 'Use Current Categories',
      'keepTheSameBudgetAmounts': 'Keep the same budget amounts for all categories',
      'aiOptimizedBudget': 'AI-Optimized Budget',
      'aiAnalyzesSpendingAndSuggestsAmounts': 'AI analyzes your spending and suggests optimized amounts',
      'categoryBudgets': 'Category Budgets',
      'noCategoriesAddedYet': 'No categories added yet',
      'totalBudget': 'Total Budget',
      'addCategoryBudget': 'Add Category Budget',
      'editCategoryBudget': 'Edit Category Budget',
      'subCategory': 'Sub category (optional)',
      'allNoFilter': 'All (no filter)',
      'budgetAmount': 'Budget Amount',
      'enterAmount': 'Please enter amount',
      'enterValidAmount': 'Please enter valid amount',
      'notesThisBudget': 'Notes about this budget',
      'egMonthlyExpenses': 'e.g., Monthly Expenses',
      'egTravelingHolidaySeason': 'e.g., "Traveling this week" or "Holiday season"',


      //edit budget screen
      'budgetUpdatedSuccessfully': 'Budget updated successfully',
      'failedToUpdateBudget': 'Failed to update budget',
      'editBudget': 'Edit Budget',
      'budgetPeriodC': 'Budget Period (Cannot be changed)',
      'period': 'Period',
      'duration': 'Duration',
      'currencyC': 'Currency (Cannot be changed)',
      'editingCategoriesRecalculateAlert': 'Editing categories will reset their spent amounts. Current spending will be recalculated.',
      'newTotalBudget': 'New Total Budget',
      'currentTotal': 'Current Total',
      'saveChanges': 'Save Changes',


      //budget detail screen
      'deleteBudget': 'Delete Budget',
      'deleteBudgetAlert': 'Are you sure you want to delete this budget? This action cannot be undone.',
      'deleted': 'deleted',
      'failedToDeleteBudget': 'Failed to delete budget',
      'startsIn': 'Starts In',
      'ended': 'Ended',
      'daysRemaining': 'Days Remaining',
      'budgetDetails': 'Budget Details',
      'budgetWasAutomaticallyCreatedAi': 'This budget was automatically created with AI optimization',
      'budgetWasAutomaticallyCreatedPrevious': 'This budget was automatically created from the previous budget',
      'autoCreateEnabled': 'Auto-Create Enabled',
      'nextBudgetWillBeAiOptimized': 'Next budget will be AI-optimized based on your spending',
      'nextBudgetWillUseSameAmounts': 'Next budget will use the same category amounts',
      'budgetExceeded': 'Budget Exceeded',
      'budgetExceededAlert': 'You\'ve spent more than your allocated budget. Consider reducing spending in exceeded categories.',
      'approachingBudgetLimit': 'Approaching Budget Limit',
      'used': 'Used',
      'categories': 'categories',
      'deleting': 'deleting',

      //ai budget suggestion screen
      'analysisSummary': 'Analysis Summary',
      'transactionsAnalyzed': 'Transactions Analyzed',
      'analysisPeriod': 'Analysis Period',
      'categoriesFound': 'Categories Found',
      'avgMonthlyIncome': 'Avg Monthly Income',
      'avgMonthlyExpenses': 'Avg Monthly Expenses',
      'activeGoals': 'Active Goals',
      'close': 'Close',
      'aiBudgetSuggestion': 'AI Budget Suggestion',
      'analysisDetails': 'Analysis Details',
      'failedToGenerateSuggestion': 'Failed to Generate Suggestion',
      'tryAgain': 'Try Again',
      'dataConfidence': 'Data Confidence',
      'highConfidence': 'High confidence based on your data',
      'moderateConfidence': 'Moderate confidence - limited data',
      'lowConfidence': 'Low confidence - very limited data',
      'yourContext': 'Your Context',
      'importantNotes': 'Important Notes',
      'suggestedBudgetPlan': 'Suggested Budget Plan',
      'name': 'Name',
      'aiAnalysis': 'AI Analysis',
      'useThisBudget': 'Use This Budget',


      //ai chat screen
      'responseStyle': 'Response Style',
      'chooseAiResponses': 'Choose how detailed you want the AI responses',
      'thinking': 'Thinking...',
      'financialAdvisor': 'Financial advisor',
      'stopResponse': 'Stop response',
      'changeResponseStyle': 'Change response style',
      'clearHistory': 'Clear History',
      'loadingChatHistory': 'Loading chat history...',
      'upgradeToPremium': 'Upgrade to Premium',
      'unlockFullCapabilities': 'Unlock full AI chat capabilities',
      'upgrade': 'Upgrade',
      'helloAi': 'Hello! I\'m your AI financial assistant',
      'aiChatDes': 'I can help you analyze your spending, provide insights, and answer questions about your finances.',
      'tryAskingMeSomething': 'Try asking me something like:',
      'aiIsTyping': 'AI is typing...',
      'upgradeToPremiumToChat': 'Upgrade to Premium to chat',
      'aiIsResponding': 'AI is responding...',
      'askAboutFinances': 'Ask me about your finances...',
      'clearChatHistory': 'Clear Chat History',
      'clearChatHistoryAlert': 'Are you sure you want to clear all chat history? This action cannot be undone.',
      'clear': 'Clear',
      'generatingInsights': 'Generating insights...',
      'insightsRegeneratedSuccessfully': 'Insights regenerated successfully!',
      'failedToRegenerateInsights': 'Failed to regenerate insights',
      'deepSpendingAnalysis': 'Deep spending analysis',
      'personalizedRecommendations': 'Personalized recommendations',
      'financialHealthScore': 'Financial health score',
      'savingsOpportunities': 'Savings opportunities',
      'budgetOptimizationTips': 'Budget optimization tips',
      'analyzingYourFinancialData': 'Analyzing your financial data...',
      'thisMayTakeFewSeconds': 'This may take a few seconds',
      'failedToLoadInsights': 'Failed to load insights',
      'noInsightsAvailable': 'No insights available',
      'addTransactionsGoalsToGenerateInsights': 'Add transactions and goals to generate insights',
      'aiGeneratedInsights': 'AI-Generated Insights',
      'normal': 'Normal',
      'concise': 'Concise',
      'detailed': 'Detailed',
      'balancedResponses': 'Balanced responses',
      'briefDirect': 'Brief & direct',
      'thoroughExplanations': 'Thorough explanations',

      //notification screen
      'notifications': 'Notifications',
      'markedAsRead': 'All notifications marked as read',
      'markAllRead': 'Mark all read',
      'notificationDeleted': 'Notification deleted',
      'undo': 'UNDO',
      'noNotificationsYet': 'No notifications yet',
      'notifyGoalsProgress': 'We\'ll notify you about your financial goals progress',


      //reports screen
      'selectStartEndDates': 'Please select both start and end dates',
      'reportDownloadedSuccessfully': 'Report downloaded successfully!',
      'open': 'Open',
      'downloadPDF': 'Download PDF',
      'currencyR': 'Currency:',
      'generatingReport': 'Generating report...',
      'selectDatesToGenerateReport': 'Select both dates to generate report',
      'select': 'Select',
      'reportPeriod': 'Report Period',
      'netBalance': 'Net Balance',
      'income': 'Income',
      'expenses': 'Expenses',
      'goalsAllocated': 'Goals Allocated',
      'dailyAverages': 'Daily Averages',
      'averageDailyIncome': 'Average Daily Income',
      'averageDailyExpenses': 'Average Daily Expenses',
      'incomeByCategory': 'Income by Category',
      'expensesByCategory': 'Expenses by Category',
      'goalsProgress': 'Goals Progress',
      'multiCurrencyReport': 'Multi-Currency Report',
      'overview': 'Overview',
      'totalTransactions': 'Total Transactions',
      'currencies': 'Currencies',
      'allGoals': 'All Goals',
      'avgDailyIncome': 'Avg. Daily Income',
      'avgDailyExpenses': 'Avg. Daily Expenses',
      'viewCategories': 'View Categories',
      'topIncomeCategories': 'Top Income Categories',
      'topExpenseCategories': 'Top Expense Categories',
      'account': 'Account',
      'editProfile': 'Edit Profile',
      'updateYourName': 'Update your name',
      'profileUpdatedSuccessfully': 'Profile updated successfully!',
      'changePassword': 'Change Password',
      'updateYourPassword': 'Update your password',
      'passwordChangedSuccessfully': 'Password changed successfully!',
      'language': 'Language',
      'changeAppLanguage': 'Change app language',
      'changeDefaultCurrency': 'Change default currency',
      'appearance': 'Appearance',
      'theme': 'Theme',
      'themeSystem': 'System',
      'themeLight': 'Light',
      'themeDark': 'Dark',
      'themeSystemDesc': 'Match device setting',
      'themeLightDesc': 'Always use light theme',
      'themeDarkDesc': 'Always use dark theme',
      'notificationSettings': 'Notification Settings',
      'manageNotificationPreferences': 'Manage notification preferences',
      'subscription': 'Subscription',
      'manageSubscription': 'Manage Subscription',
      'viewManageSubscription': 'View and manage your subscription',
      'unlockPremiumFeatures': 'Unlock all premium features',
      'about': 'About',
      'aboutToePwar': 'About Toe Pwar',


      //notification settings screen
      'notificationsEnabled': 'Notifications enabled! 🔔',
      'changeNotificationSettingsDes': 'To change notification settings, please go to your device settings.',
      'openSettings': 'Open Settings',
      'testNotification': 'Test Notification 🎉',
      'testNotificationDes': 'This is a test notification from Flow Finance!',
      'testNotificationMsg': 'Test notification sent! Check your notification tray.',
      'resetToDefaults': 'Reset to Defaults?',
      'enableAllNotificationTypes': 'This will enable all notification types. Are you sure?',
      'notificationPreferencesReset': 'Notification preferences reset to defaults',
      'failedToResetPreferences': 'Failed to reset preferences',
      'reset': 'Reset',
      'resetToDefaultsWQ': 'Reset to defaults',
      'pushNotifications': 'Push Notifications',
      'receiveUpdatesAboutFinances': 'Receive updates about your finances',
      'sendTestNotification': 'Send Test Notification',
      'customizeNotificationsReceive': 'Customize which notifications you want to receive',
      'notificationTypes': 'Notification Types',
      'progressUpdates': 'Progress Updates',
      'notifiedMilestones': 'Notified at 25%, 50%, 75% milestones',
      'milestoneReached': 'Milestone Reached',
      'thousandSavedTowardsGoal': 'Every \$1,000 saved towards goal',
      'deadlineApproaching': 'Deadline Approaching',
      'reminders': 'Reminders at 14, 7, and 3 days before',
      'goalAchieved': 'Goal Achieved',
      'celebrate': 'Celebrate when you reach your target!',
      'budgetStarted': 'Budget Started',
      'whenNewBudgetBegins': 'When a new budget period begins',
      'periodEndingSoon': 'Period Ending Soon',
      'reminderBudgets': 'Reminder 3 days before period ends',
      'budgetThreshold': 'Budget Threshold',
      'alertBudget': 'Alert when 80% of budget is spent',
      'whenOverBudgetLimit': 'When you go over your budget limit',
      'autoCreatedBudget': 'Auto-Created Budget',
      'budgetCreatedAutomatically': 'New budget created automatically',
      'budgetNowActive': 'Budget Now Active',
      'whenBudgetBecomesActive': 'When an upcoming budget becomes active',
      'largeTransaction': 'Large Transaction',
      'alertsLargeExpenses': 'Alerts for unusually large expenses',
      'unusualSpending': 'Unusual Spending',
      'whenSpendingPatternsChange': 'When spending patterns change',
      'paymentReminders': 'Payment Reminders',
      'upcomingPayments': 'Upcoming recurring payments',
      'recurringCreated': 'Recurring Created',
      'recurringEnded': 'Recurring Ended',
      'whenRecurringEnds': 'When recurring series ends',
      'recurringDisabled': 'Recurring Disabled',
      'whenRecurrenceDisabled': 'When recurrence is disabled',
      'whenRecurringTransactionsCreated': 'When recurring transactions are created',
      'weeklyInsights': 'Weekly Insights',
      'whenWeeklyInsightsReady': 'Get notified when your weekly financial insights are generated every Sunday',


      //edit profile screen
      'failedUpdateProfile': 'Failed to update profile',
      'discardChanges': 'Discard Changes?',
      'discardChangesAlert': 'You have unsaved changes. Are you sure you want to discard them?',
      'keepEditing': 'Keep Editing',
      'discard': 'Discard',
      'tapIconChangeAvatar': 'Tap icon to change avatar',
      'fullName': 'Full Name',
      'enterFullName': 'Enter your full name',
      'pleaseEnterName': 'Please enter your name',
      'nameTwoCharacters': 'Name must be at least 2 characters',
      'emailAddress': 'Email Address',
      'emailCannotChanged':  'Email cannot be changed',
      'haveUnsavedChanges': 'You have unsaved changes',
      'dangerZone': 'Danger Zone',
      'dangerZoneDes': 'Deleting your account will permanently remove all your data including transactions, goals, budgets, and insights. This action cannot be undone.',
      'deleteAccount': 'Delete Account',
      'deleteAccountQ': 'Delete Account?',
      'willPermanentlyDelete': 'This will permanently delete:',
      'allYourTransactions': 'All your transactions',
      'allYourFinancialGoals': 'All your financial goals',
      'allYourBudgets': 'All your budgets',
      'allYourAiInsights': 'All your AI insights',
      'allYourChatHistory': 'All your chat history',
      'yourAccountInformation': 'Your account information',
      'actionCannotBeUndone': 'This action cannot be undone!',


      //currency settings screen
      'currencySettings': 'Currency Settings',
      'selectDefaultCurrency': 'Select Default Currency',
      'preferredCurrency': 'Choose your preferred currency',
      'eachCurrencyOwnBalance': 'You can add transactions in any currency. Each currency has its own balance.',


      //change password screen
      'passwordSixCharacters': 'Password must be at least 6 characters long',
      'currentPassword': 'Current Password',
      'enterCurrentPassword': 'Enter your current password',
      'pleaseEnterCurrentPassword': 'Please enter your current password',
      'newPassword': 'New Password',
      'enterNewPassword': 'Enter your new password',
      'pleaseEnterNewPassword': 'Please enter a new password',
      'newPasswordDifferentCurrentPassword': 'New password must be different from current password',
      'confirmNewPassword': 'Confirm New Password',
      'confirmYourNewPassword': 'Confirm your new password',
      'pleaseConfirmNewPassword': 'Please confirm your new password',
      'passwordsNotMatch': 'Passwords do not match',


      //outflow analytics screen
      'yearly': 'Yearly',
      'totalSpending': 'Total Spending',
      'spendingByCategory': 'Spending by Category',
      'noDataAvailable': 'No data available',
      'addTransactionsSeeSpendingAnalytics': 'Add some transactions to see your spending analytics',
      'byDayOfWeek': 'By Day of Week',
      'byMonth': 'By Month',
      'byYear': 'By Year',
      'customPeriod': 'Custom Period',
      'spendingDayOfWeek': 'Spending by Day of Week',
      'spendingMonth': 'Spending by Month',
      'spendingYear': 'Spending by Year',
      'spendingOverTime': 'Spending Over Time',


      //inflow analytics screen
      'totalIncome': 'Total Income',
      'addIncomeSeeAnalytics': 'Add some income transactions to see your analytics',
      'incomeDayOfWeek': 'Income by Day of Week',
      'incomeByMonth': 'Income by Month',
      'incomeByYear': 'Income by Year',
      'incomeOverTime': 'Income Over Time',



      //subscription screen
      'welcomeToPremium': 'Welcome to Premium!',
      'accessAllPremiumFeatures': 'You now have access to all premium features.',
      'getStarted': 'Get Started',
      'premiumStatus': 'Premium Status',
      'premiumActive': 'Premium Active',
      'premiumFeatures': 'Premium Features',
      'aiBudgetSuggestions': 'AI Budget Suggestions',
      'aiBudgetSuggestionsDes': 'Get smart budget recommendations based on your spending patterns',
      'voiceInputDes': 'Add transactions by simply speaking',
      'receiptScanning': 'Receipt Scanning',
      'receiptScanningDes': 'Scan receipts and auto-extract transaction details',
      'aiFinancialAssistant': 'AI Financial Assistant',
      'aiFinancialAssistantDes': 'Chat with AI for personalized financial advice',
      'aiInsightsDes': 'Get deep insights into your spending habits',
      'premiumPlan': 'Premium Plan',
      'tryCancelAnytime': 'Try 30 days • Cancel anytime',
      'contactAdmin': 'Contact Admin to Upgrade',
      'contactSupport' : 'Please contact Admin support to activate Premium.',


      // Feedback Screen
      'sendFeedback': 'Send Feedback',
      'weValueYourInput': 'We value your input',
      'feedbackHeaderSubtitle': 'Help us improve Flow Finance by sharing your thoughts or reporting issues.',
      'whatIsThisRegarding': 'What is this regarding?',
      'howRateExperience': 'How would you rate your experience?',
      'tellUsMore': 'Tell us more',
      'feedbackHint': 'Describe your issue or share your ideas...',
      'submitFeedback': 'Submit Feedback',
      'pleaseSelectRating': 'Please select a rating',
      'feedbackSubmittedSuccess': 'Thank you for your feedback!',
      'feedbackFailed': 'Failed to submit feedback',
      'pleaseEnterMessage': 'Please enter a message',
      'feedbackMinLength': 'Please provide more details (at least 10 characters)',
      // Feedback Categories
      'feedbackCategoryGeneral': 'General Inquiry',
      'feedbackCategoryBug': 'Report a Bug',
      'feedbackCategoryFeature': 'Feature Request',
      'feedbackCategoryUsability': 'Usability Issue',
      'feedbackCategoryOther': 'Other',
      'feedbackDesc': 'Report bugs or request features',

      // Localization sweep — widgets/providers batch
      'badgeTryFree': 'TRY FREE',
      'badgeThreeNew': '3 NEW',
      'badgeFreeMonth': 'FREE MONTH',
      'askAi': 'Ask AI',
      'chatWithAiAssistant': 'Chat with AI Assistant',
      'noUpcomingOccurrences': 'No upcoming occurrences',
      'repeatOn': 'Repeat On',
      'dayLabel': 'Day',
      'weekdayMon': 'Mon',
      'weekdayTue': 'Tue',
      'weekdayWed': 'Wed',
      'weekdayThu': 'Thu',
      'weekdayFri': 'Fri',
      'weekdaySat': 'Sat',
      'weekdaySun': 'Sun',
      'monthJanuary': 'January',
      'monthFebruary': 'February',
      'monthMarch': 'March',
      'monthApril': 'April',
      'monthMay': 'May',
      'monthJune': 'June',
      'monthJuly': 'July',
      'monthAugust': 'August',
      'monthSeptember': 'September',
      'monthOctober': 'October',
      'monthNovember': 'November',
      'monthDecember': 'December',
      'premiumFeatureDialogContent': 'This feature requires a premium subscription. Upgrade now to unlock all features!',

      // Localization sweep — transactions batch
      'pickCategoryTitle': 'Pick a category',
      'thenChooseSubCategoryHint': 'Then choose a sub-category inside it',
      'chooseSubCategoryTitle': 'Choose a sub-category',
      'noCategoriesLabel': 'No categories',
      'subCategoriesCountLabel': 'sub-categories',
      'chooseCategoryFallback': 'Choose a category',
      'categoryAndSubCategoryFallback': 'Category and sub-category',
      'repeatLabel': 'Repeat',
      'doneLabel': 'Done',
      'offLabel': 'Off',
      'egExchangeRateHint': 'e.g., 3000',
      'speakItTooltip': 'Speak it',
      'keepItButton': 'Keep it',
      'currencyConvertedMessage': 'Currency converted! Amount updated to',
      'addAReceiptTitle': 'Add a receipt',
      'whatWeReadLabel': 'WHAT WE READ',
      'whatWeReadDescription': 'Merchant, date, amount and category — nothing is saved until you confirm.',
      'useDifferentPhotoButton': 'Use a different photo',
      'failedToSaveTransactionFallback': 'Failed to save transaction',
      'successfullySavedPrefix': 'Successfully saved',
      'transactionsSuffix': 'transaction(s)',
      'whatYouSaidLabel': 'WHAT YOU SAID',
      'fromOneRecordingLabel': 'from one recording',
      'foundLabel': 'Found',
      'transactionSingularLabel': 'Transaction',
      'multipleSpendsWarning': 'Your sentence held multiple separate spends, so they are logged separately — untick anything you did not mean.',
      'selectedTotalLabel': 'Selected total',
      'recordAgainButton': 'Record again',
      'mixedCurrenciesLabel': 'Mixed currencies',
      'oneTransactionLabel': '1 transaction',
      'transactionsCountSuffix': 'transactions',

      // Localization sweep — auth screens batch
      'loginTagline': 'Money that grows because you watch it',
      'emailLabel': 'Email',
      'enterEmailError': 'Please enter your email',
      'enterValidEmailError': 'Please enter a valid email',
      'passwordLabel': 'Password',
      'enterPasswordError': 'Please enter your password',
      'forgotPasswordQuestion': 'Forgot password?',
      'signIn': 'Sign in',
      'newHerePrefix': 'New here? ',
      'createAnAccount': 'Create an account',
      'registerTagline': 'Two minutes now, and the app starts learning what your money does.',
      'fullNameLabel': 'Full name',
      'passwordMinLengthError': 'Password must be at least 6 characters',
      'confirmPasswordLabel': 'Confirm password',
      'confirmPasswordError': 'Please confirm your password',
      'byContinuingAcceptPrefix': 'By continuing you accept the ',
      'termsLinkText': 'terms',
      'andConnector': ' and ',
      'privacyPolicyLinkText': 'privacy policy',
      'neverSellDataSuffix': '. We never sell your data.',
      'createAccountButton': 'Create account',
      'alreadyHaveAccountPrefix': 'Already have one? ',
      'oneTapLeft': 'One tap left',
      'verificationLinkSentPrefix': 'We sent a verification link to\n',
      'whyExtraStepTitle': 'Why the extra step',
      'emailVerificationExplanation': 'Your email is the only way back into the account if you forget the password — so it has to be an address you really hold. Nothing is charged and no other email follows.',
      'verifiedSignInButton': 'I\'ve verified — sign in',
      'nothingArrivedPrefix': 'Nothing arrived? Check spam, or ',
      'useDifferentAddressLink': 'use a different address',
      'termsAndConditionsTitle': 'Terms and Conditions',
      'welcomeToToePwarTagline': 'Welcome to Toe Pwar - Personal Finance AI',
      'termsAndConditionsBody': 'By using Toe Pwar, you agree to:\n\n1. Use the app for personal financial management only\n\n2. Provide accurate information when creating transactions\n\n3. Keep your account credentials secure\n\n4. Not misuse AI features or attempt to manipulate the system\n\n5. Understand that financial insights are suggestions, not professional advice\n\n6. Accept that premium features require an active subscription\n\n7. Allow us to process your financial data to provide personalized insights',
      'privacyPolicyTitle': 'Privacy Policy',
      'yourPrivacyMattersTitle': 'Your Privacy Matters',
      'privacyPolicyBody': 'We collect and use your data to:\n\n• Provide personalized financial insights\n• Improve our AI recommendations\n• Secure your account and transactions\n• Send important notifications about your finances\n\nWe protect your data by:\n\n• Encrypting all sensitive information\n• Never sharing your data with third parties without consent\n• Allowing you to delete your data at any time\n• Following industry-standard security practices\n\nYour financial data is stored securely and used only to enhance your experience with Toe Pwar.',
      'resetPasswordTitle': 'Reset your password',
      'resetPasswordSubtitle': 'We\'ll email a six-digit code to the address on the account.',
      'emailAddressLabel': 'Email address',
      'sendCodeButton': 'Send the code',
      'enterAllSixDigitsError': 'Please enter all 6 digits',
      'newCodeSentMessage': 'A new code has been sent to your email.',
      'enterTheCodeTitle': 'Enter the code',
      'sentCodeToPrefix': 'Sent to',
      'expiresInTenMinutes': 'It expires in ten minutes.',
      'verifyCodeButton': 'Verify code',
      'didntGetItPrefix': 'Didn\'t get it? ',
      'resendInPrefix': 'Resend in',
      'sendNewCodeButton': 'Send a new code',
      'passwordResetTitle': 'Password reset!',
      'passwordResetSuccessMessage': 'Your password has been updated successfully. You can now log in with your new password.',
      'backToLogin': 'Back to login',
      'chooseNewPasswordTitle': 'Choose a new password',
      'codeAcceptedSubtitle': 'Code accepted. At least six characters.',
      'newPasswordLabel': 'New password',
      'pleaseEnterAPasswordError': 'Please enter a password',
      'minimumSixCharactersError': 'Minimum 6 characters',
      'confirmItLabel': 'Confirm it',
      'saveAndSignInButton': 'Save and sign in',

      // Localization sweep — legal text + force update batch
      'privacyPolicySubtitle': 'Your privacy matters to us · Last updated Jan 2025',
      'privacyIntroTitle': '1. Introduction',
      'privacyIntroBody': 'Toe Pwar ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application.',
      'privacyInfoCollectTitle': '2. Information We Collect',
      'privacyInfoCollectBody': 'We collect several types of information:\n\nPersonal Information:\n• Name and email address\n• Account credentials\n• Profile information\n\nFinancial Data:\n• Transaction details (amount, category, date)\n• Budget information\n• Financial goals\n• Account balances\n\nUsage Information:\n• App usage patterns\n• Feature interactions\n• Device information',
      'privacyUseInfoTitle': '3. How We Use Your Information',
      'privacyUseInfoBody': 'We use your information to:\n\n• Provide and maintain our services\n• Generate personalized financial insights using AI\n• Create budget recommendations\n• Send notifications about your finances\n• Improve our app and AI algorithms\n• Ensure security and prevent fraud\n• Communicate with you about updates and features',
      'privacyDataSecurityTitle': '4. Data Security',
      'privacyDataSecurityBody': 'We implement industry-standard security measures:\n\n• Encryption of sensitive data in transit and at rest\n• Secure authentication mechanisms\n• Regular security audits\n• Access controls and monitoring\n• Secure data storage practices\n\nHowever, no method of transmission over the internet is 100% secure. We cannot guarantee absolute security.',
      'privacyDataSharingTitle': '5. Data Sharing',
      'privacyDataSharingBody': 'We do not sell your personal information. We may share data only in these limited circumstances:\n\n• With your explicit consent\n• To comply with legal obligations\n• To protect our rights and prevent fraud\n• With service providers who assist our operations (under strict confidentiality agreements)\n\nThird-party service providers are contractually obligated to protect your data.',
      'privacyAiProcessingTitle': '6. AI and Data Processing',
      'privacyAiProcessingBody': 'Our AI features process your financial data to:\n\n• Analyze spending patterns\n• Generate personalized insights\n• Provide budget recommendations\n• Predict future trends\n\nWhen you ask the assistant a question or generate a budget, the relevant records are sent for that request. All AI processing is done with your data privacy in mind — we use aggregated and anonymized data to improve our AI models, and your records are not used to train anything beyond that request.',
      'privacyYourRightsTitle': '7. Your Rights',
      'privacyYourRightsBody': 'You have the right to:\n\n• Access your personal information\n• Correct inaccurate data\n• Delete your account and data\n• Export your data\n• Opt-out of certain data processing\n• Withdraw consent at any time\n\nTo exercise these rights, contact us or use the app settings.',
      'privacyDataRetentionTitle': '8. Data Retention',
      'privacyDataRetentionBody': 'We retain your information for as long as:\n\n• Your account is active\n• Necessary to provide services\n• Required by law\n\nWhen you delete your account, we will permanently delete your data within 30 days, except where required by law to retain it.',
      'privacyChildrensTitle': '9. Children\'s Privacy',
      'privacyChildrensBody': 'Toe Pwar is not intended for users under 18 years of age. We do not knowingly collect information from children. If you believe we have collected information from a child, please contact us immediately.',
      'privacyIntlTransfersTitle': '10. International Data Transfers',
      'privacyIntlTransfersBody': 'Your information may be transferred to and processed in countries other than your own. We ensure appropriate safeguards are in place to protect your data in accordance with this Privacy Policy.',
      'privacyChangesTitle': '11. Changes to Privacy Policy',
      'privacyChangesBody': 'We may update this Privacy Policy periodically. We will notify you of significant changes through the app or email. Your continued use after changes indicates acceptance of the updated policy.',
      'privacyContactTitle': '12. Contact Us',
      'privacyContactBody': 'If you have questions about this Privacy Policy or our data practices:\n\nEmail: toepwarai@gmail.com\nWebsite: www.toepwar.com\n\nWe will respond to your inquiry within 30 days.',
      'privacySecurityNotice': 'Your data is encrypted and protected with industry-standard security measures',
      'termsTitle': 'Terms and Conditions',
      'termsSubtitle': 'Last updated: January 2025',
      'termsAcceptanceTitle': '1. Acceptance of Terms',
      'termsAcceptanceBody': 'By accessing and using Toe Pwar ("the App"), you accept and agree to be bound by these Terms and Conditions. If you do not agree to these terms, please do not use the App.',
      'termsUseOfServiceTitle': '2. Use of Service',
      'termsUseOfServiceBody': 'Toe Pwar provides personal finance management tools, including:\n\n• Transaction tracking and categorization\n• AI-powered financial insights and recommendations\n• Budget management and goal tracking\n• Financial reports and analytics\n\nYou agree to use the App for personal financial management purposes only.',
      'termsAccountRegTitle': '3. Account Registration',
      'termsAccountRegBody': 'You must provide accurate and complete information when creating an account. You are responsible for:\n\n• Maintaining the confidentiality of your account credentials\n• All activities that occur under your account\n• Notifying us immediately of any unauthorized use',
      'termsUserResponsibilitiesTitle': '4. User Responsibilities',
      'termsUserResponsibilitiesBody': 'You agree to:\n\n• Provide accurate financial information\n• Not misuse AI features or attempt to manipulate the system\n• Not use the App for any illegal purposes\n• Not share your account with others\n• Comply with all applicable laws and regulations',
      'termsAiFeaturesTitle': '5. AI-Powered Features',
      'termsAiFeaturesBody': 'Our AI features provide suggestions and insights based on your financial data. Please note:\n\n• AI insights are suggestions, not professional financial advice\n• You should verify all recommendations before taking action\n• We are not liable for decisions made based on AI suggestions\n• Results may vary based on your financial situation',
      'termsPremiumSubTitle': '6. Premium Subscription',
      'termsPremiumSubBody': 'Premium features require an active subscription:\n\n• Subscriptions are billed according to your chosen plan\n• You can cancel at any time before the next billing cycle\n• Refunds are provided according to our refund policy\n• Access to premium features ends when subscription expires',
      'termsDataProcessingTitle': '7. Data Processing',
      'termsDataProcessingBody': 'We process your financial data to:\n\n• Provide personalized insights and recommendations\n• Improve our services and AI algorithms\n• Generate reports and analytics\n• Ensure security and prevent fraud\n\nAll data processing complies with our Privacy Policy.',
      'termsIntellectualPropertyTitle': '8. Intellectual Property',
      'termsIntellectualPropertyBody': 'All content, features, and functionality of the App are owned by Toe Pwar and protected by copyright, trademark, and other laws. You may not:\n\n• Copy, modify, or distribute our content\n• Reverse engineer or attempt to extract source code\n• Use our trademarks without permission',
      'termsLimitationLiabilityTitle': '9. Limitation of Liability',
      'termsLimitationLiabilityBody': 'Toe Pwar is provided "as is" without warranties. We are not liable for:\n\n• Financial decisions made using the App\n• Loss of data or service interruptions\n• Indirect or consequential damages\n• Third-party actions or content',
      'termsTerminationTitle': '10. Termination',
      'termsTerminationBody': 'We reserve the right to:\n\n• Suspend or terminate your account for violations\n• Modify or discontinue services at any time\n• Remove content that violates these terms\n\nYou may delete your account at any time from the app settings.',
      'termsChangesTitle': '11. Changes to Terms',
      'termsChangesBody': 'We may update these Terms and Conditions periodically. Continued use of the App after changes constitutes acceptance of the new terms. We will notify users of significant changes.',
      'termsContactInfoTitle': '12. Contact Information',
      'termsContactInfoBody': 'For questions about these Terms and Conditions, please contact us at:\n\nEmail: toepwarai@gmail.com\nWebsite: www.toepwar.com',
      'termsAcceptanceNotice': 'By using Toe Pwar, you agree to these Terms and Conditions',
      'noBrowserFoundMessage': 'No browser found. Please visit manually:',
      'copyLabel': 'Copy',
      'forceUpdateTitle': 'Time for an update',
      'forceUpdateDefaultMessage': 'A new version is available. Please update to continue using the app.',
      'whatsNewInVersion': 'WHAT\'S NEW IN',
      'whatsNewLabel': 'WHAT\'S NEW',
      'youHaveVersion': 'You have',
      'updateNowButton': 'Update now',
      'updateSafetyNotice': 'Your records stay on the device — nothing is lost by updating.',

      // Localization sweep — settings screens batch
      'passwordStrengthWeak': 'Weak',
      'passwordStrengthFair': 'Fair',
      'passwordStrengthGood': 'Good',
      'passwordStrengthStrong': 'Strong',
      'failedToChangePassword': 'Failed to change password',
      'errorOccurred': 'An error occurred:',
      'passwordChangeSignOutNotice': 'Changing your password signs out other devices. Your transactions and budgets are untouched.',
      'defaultCurrencyUpdatedTo': 'Default currency updated to',
      'failedToUpdateCurrency': 'Failed to update currency',
      'howCurrenciesWorkHere': 'HOW CURRENCIES WORK HERE',
      'accountDeletedSuccessfully': 'Account deleted successfully',
      'failedToDeleteAccount': 'Failed to delete account',
      'ratingHelper1': 'Sorry to hear that — tell us what went wrong below.',
      'ratingHelper2': 'Thanks — what could be better?',
      'ratingHelper3': 'Good to know. What would make it great?',
      'ratingHelper4': 'Glad you like it — anything to polish?',
      'ratingHelper5': 'Wonderful! Thanks for the love.',
      'ratingHelperDefault': 'Tap a star to rate your experience',
      'charCountMinimumSuffix': '/10 minimum',
      'languageChangedToEnglish': 'Language changed to English',
      'languageChangedToBurmese': 'Language changed to Myanmar',
      'languageSettingsTitle': 'Language Settings',
      'selectLanguageLabel': 'Select Language',
      'languageRestartNotice': 'The app will restart to apply the new language',
      'failedToUpdatePreference': 'Failed to update preference',
      'monthlyInsightsTitle': 'Monthly Insights',
      'monthlyInsightsDesc': 'When your monthly insights are ready',
      'defaultUserName': 'User',
      'premiumMemberLabel': 'Premium Member',
      'freePlanLabel': 'Free Plan',
      'currentLanguageName': 'English',
      'appVersion': 'Version 1.0.0',
      'viewOurPrivacyPolicy': 'View our privacy policy',
      'viewTermsAndConditions': 'View terms and conditions',
      'appDescription': 'Toe Pwar is your personal finance management app with AI-powered insights and budget tracking.',
      'copyrightNotice': '© 2025 Toe Pwar. All rights reserved.',

      // Localization sweep — home/ai/insights/reports/charts/notifications/subscription batch
      'spendingPace': 'Spending pace',
      'insight': 'Insight',
      'eachCurrencyOwnBalanceNote': 'Each keeps its own balance — nothing is converted behind your back.',
      'errorLoadCurrencyBalances': 'Failed to load currency balances:',
      'suggestionCurrentBalance': 'What\'s my current balance?',
      'suggestionSpendThisMonth': 'How much did I spend this month?',
      'suggestionTopSpendingCategories': 'What are my top spending categories?',
      'suggestionMoneySavingTips': 'Give me money-saving tips',
      'suggestionIncomeVsExpenses': 'Show me my income vs expenses',
      'suggestionSpendOnFood': 'How much did I spend on food?',
      'answers': 'Answers:',
      'clearThisConversation': 'Clear this conversation?',
      'chatMessageSingular': 'message',
      'chatMessagePlural': 'messages',
      'clearChatConsequence': 'and the answers go for good. Your transactions, budgets and goals are untouched — the assistant reads them fresh next time.',
      'keepIt': 'Keep it',
      'fallbackQuestionTighterMonth': 'Why is this month tighter?',
      'assistantAnswersFromRecords': 'The assistant answers from your own records.',
      'spendingPaceCategoryComparisons': 'Spending pace, category comparisons, whether a purchase fits, what repeats — with your numbers, not general advice.',
      'tryOneMonthFree': 'Try one month free',
      'noCardRequiredCancelAnyTime': 'No card required · cancel any time',
      'errorLoadingTransactions': 'Error loading transactions:',
      'moneyInLabel': 'Money in ·',
      'moneyOutLabel': 'Money out ·',
      'avgPerEntry': 'Avg / entry',
      'spentLabel': 'spent',
      'biggestOutflowCategoryMiddle': 'is your biggest outflow category —',
      'biggestOutflowCategorySuffix': 'of spending this period.',
      'biggestIncomeSourceMiddle': 'is your biggest income source —',
      'biggestIncomeSourceSuffix': 'of what came in this period.',
      'regenerate': 'Regenerate',
      'threeInsightsWaiting': 'Three insights are waiting. Premium reads your own transactions weekly — no manual work.',
      'swipeNotificationToDelete': 'Swipe a notification to delete it',
      'justNow': 'Just now',
      'minutesAgoSuffix': 'm ago',
      'hoursAgoSuffix': 'h ago',
      'daysAgoSuffix': 'd ago',
      'errorDownloadReport': 'Failed to download report:',
      'exportThisReport': 'Export this report',
      'chartsCategoryTablesDailyAverages': 'Charts, category tables and daily averages',
      'sendItOn': 'Send it on',
      'samePdfToViberOrEmail': 'Same PDF, straight to Viber or email',
      'ofTotal': 'of total',
      'txnsAbbrev': 'txns',
      'welcomeToPremiumCelebration': '🎉 Welcome to Premium!',
      'oneMonthFreePremiumAccess': 'You now have 1 month of free premium access. Enjoy all features!',
      'letsGo': 'Let\'s go!',
      'couldNotClaimFreeTrial': 'Could not claim free trial.',
      'oneMonthFreeCaps': 'ONE MONTH FREE',
      'letAppReadYourMoney': 'Let the app read your money for you.',
      'weeklyInsightsReceiptScanningVoiceAiBudgets': 'Weekly insights, receipt scanning, voice entry and AI budgets — on your own transactions.',
      'claiming': 'Claiming…',
      'claimOneMonthFree': 'Claim 1 month free',
      'noCardRequiredThenContactUs': 'No card required · then contact us to continue',

      // Localization sweep — budgets/goals batch
      'startsOnPrefix': 'Starts',
      'startsInDaysPrefix': 'Starts in',
      'daysSuffix': 'days',
      'endedDaysAgoPrefix': 'Ended',
      'daysRemainingSuffix': 'days remaining',
      'budgetWillStartOnPrefix': 'This budget will start on',
      'noSpendingTrackedYetSuffix': '. No spending is tracked yet.',
      'budgetEndedOnPrefix': 'This budget ended on',
      'onlyTransactionsInPrefix': 'Only transactions in',
      'willAffectThisBudgetSuffix': 'will affect this budget',
      'fixedForThisBudget': 'FIXED FOR THIS BUDGET',
      'periodCurrencyLockedNotice': 'Period and currency can\'t change once a budget has spending against it — create a new budget instead.',
      'capAlreadySpentTitle': 'This cap is already spent',
      'alreadyHaveMoreSpent': 'already have more spent than the new cap allows.',
      'alreadyHasMoreSpent': 'already has more spent than the new cap allows.',
      'totalCapLabel': 'TOTAL CAP',
      'analyzingYourPrefix': 'Analyzing your',
      'spendingPatternsSuffix': 'spending patterns...',
      'genericErrorOccurred': 'An error occurred',
      'savedTowardsGoals': 'Saved towards goals',
      'failedToLoadBalances': 'Failed to load balances:',
      'dueDatePrefix': 'Due',
      'operationFailed': 'Operation failed',
      'moneyHeldNotSpendable': 'Money held for this goal isn\'t spendable',
      'heldFundsExplanation': 'It comes out of your available balance, so the dashboard never offers you money you\'ve promised elsewhere.',
    },
    'my': {
      // Home Screen
      'toePwar': 'တိုးပွား',
      'welcomeBack': 'ပြန်လာတာ ကြိုဆိုပါတယ်၊',
      'totalBalance': 'စုစုပေါင်း လက်ကျန်ငွေ',
      'available': 'အသုံးပြုနိုင်သော',
      'allocatedToGoals': 'ရည်မှန်းချက်များသို့ ခွဲဝေထားသော',
      'inflow': 'ဝင်ငွေ',
      'outflow': 'ထွက်ငွေ',
      'aiAssistant': 'AI အကူအညီပေးသူ',
      'getPersonalizedInsights': 'ကိုယ်ပိုင်အခြေအနေအလိုက် အကြံပြုချက်များ ရယူပါ',
      'aiInsights': 'AI သုံးသပ်ချက်များ',
      'viewComprehensiveAnalysis': 'ငွေကြေး ခွဲခြမ်းစိတ်ဖြာမှု အပြည့်အစုံ ကြည့်ရန်',
      'recentTransactions': 'လတ်တလောငွေစာရင်းသွင်းမှုများ',
      'seeMore': 'ကြည့်ရန်',
      'noTransactions': 'ငွေစာရင်းသွင်းမှု မရှိသေးပါ',
      'tapToAddFirst': 'ပထမဆုံး ငွေစာရင်းသွင်းမှုပြုလုပ်ရန် + ခလုတ်ကို နှိပ်ပါ',
      'addTransaction': 'ငွေစာရင်းသွင်းရန်',
      'manualEntry': 'ကိုယ်တိုင် ထည့်ရန်',
      'typeTransactionDetails': 'ငွေစာရင်းအသေးစိတ်ကို ရိုက်ထည့်ပါ',
      'voiceInput': 'အသံဖြင့် ထည့်ရန်',
      'speakYourTransaction': 'သင့်ငွေစာရင်းအချက်အလက်ကို ပြောပါ',
      'scanReceipt': 'ဘောက်ချာ စကင်ဖတ်ရန်',
      'takeUploadPhoto': 'ဘောက်ချာ ဓာတ်ပုံ ရိုက်ယူ / တင်ရန်',
      'premium': 'ပရီမီယံ',
      'transactionAdded': 'ငွေစာရင်းသွင်းကို အောင်မြင်စွာ ထည့်သွင်းပြီးပါပြီ',
      'transactionUpdated': 'ငွေစာရင်းသွင်းကို အောင်မြင်စွာ ပြင်ဆင်ပြီးပါပြီ',
      'transactionDeleted': 'ငွေစာရင်းသွင်းကို အောင်မြင်စွာ ဖျက်ပြီးပါပြီ',
      'dashboard': 'ဒက်ရှ်ဘုတ်',
      'autoCreated': 'အလိုအလျောက် ဖန်တီးထားသော',
      'viewAllCurrencies':'ငွေကြေးအမျိုးအစားအားလုံးကြည့်ရန်',
      'allCurrencyBalances':'ငွေကြေးအားလုံး၏ လက်ကျန်များ',
      'default':'မူရင်း',

      // Additions for Drawer Navigation
      'drawerWelcome': 'ကြိုဆိုပါတယ်',
      'drawerLogout': 'အကောင့်ထွက်ရန်',
      'dialogCancel': 'ပယ်ဖျက်ရန်',
      'dialogLogoutConfirm': 'အကောင့်ထွက်ရန် သေချာပါသလား?',
      'transactions': 'ငွေစာရင်းများ',
      'goals': 'ရည်မှန်းချက်များ',
      'budgets': 'ဘတ်ဂျက်များ',
      'inflowAnalytics': 'ဝင်ငွေ ခွဲခြမ်းစိတ်ဖြာမှု',
      'outflowAnalytics': 'ထွက်ငွေ ခွဲခြမ်းစိတ်ဖြာမှု',
      'financialReports': 'ငွေကြေး အစီရင်ခံစာများ',
      'settings': 'ဆက်တင်များ',
      'expiresOn': 'သက်တမ်းကုန်ဆုံးမည့်ရက်',

      // Additions for Add Transaction Screen
      'addTransactionTitle': 'ငွေစာရင်းသွင်းရန်',
      'currency': 'ငွေကြေးအမျိုးအစား',
      'convertCurrency': 'ငွေကြေး ပြောင်းလဲရန်',
      'current': 'လက်ရှိ: ',
      'convertTo': 'ပြောင်းလဲမည့် ငွေကြေး: ',
      'exchangeRate': 'ငွေလဲနှုန်း:',
      'convert': 'ပြောင်းလဲရန်',
      'selectTargetCurrency': 'ပြောင်းလဲလိုသည့်ငွေကြေးအမျိုးအစားကိုရွေးပါ',
      'amountLabel': 'ပမာဏ',
      'dateLabel': 'ရက်စွဲ',
      'categoryLabel': 'အမျိုးအစား',
      'selectMainCategoryHint': 'အဓိက အမျိုးအစားကို ရွေးပါ',
      'selectSubCategoryHint': 'အမျိုးအစားခွဲကို ရွေးပါ',
      'descriptionLabel': 'ဖော်ပြချက် (မဖြစ်မနေမဟုတ်)',
      'descriptionHint': 'ဤငွေစာရင်းသွင်းမှုအကြောင်း မှတ်စုထည့်ပါ...',
      'addOutflowButton': 'ထွက်ငွေ ထည့်ရန်',
      'addInflowButton': 'ဝင်ငွေ ထည့်ရန်',
      'validationAmountInvalid': 'မှန်ကန်သော ပမာဏကို ထည့်ပါ',
      'validationAmountPositive': 'ပမာဏသည် 0 ထက်ကြီးရမည်',
      'validationMainCategoryRequired': 'အဓိက အမျိုးအစားကို ရွေးချယ်ပါ',
      'validationSubCategoryRequired': 'အမျိုးအစားခွဲကို ရွေးချယ်ပါ',
      'recurringTransaction': 'ထပ်တလဲလဲ ငွေစာရင်းသွင်းမှု',
      'recurringTransactionDes': 'ဤငွေစာရင်းသွင်းမှုကို အလိုအလျောက် ဖန်တီးပါ',
      'repeatFrequency': 'ထပ်တလဲလဲ ပြုလုပ်မည့် အကြိမ်ရေ',
      'dayOfMonth': 'လစဉ် ရက်စွဲ',
      'daily': 'နေ့စဉ်',
      'weekly': 'အပတ်စဉ်',
      'monthly': 'လစဉ်',
      'annually': 'နှစ်စဉ်',
      'dailyDes':'နေ့တိုင်း ထပ်တလဲလဲ ပြုလုပ်မည်',
      'weeklyDes': 'ရွေးချယ်ထားသော ရက်သတ္တပတ်၏ နေ့တွင် ထပ်တလဲလဲ ပြုလုပ်မည်',
      'monthlyDes': 'ရွေးချယ်ထားသော လ၏ ရက်စွဲတွင် ထပ်တလဲလဲ ပြုလုပ်မည်',
      'annuallyDes': 'ရွေးချယ်ထားသော နှစ်၏ ရက်စွဲတွင် ထပ်တလဲလဲ ပြုလုပ်မည်',
      'endDate': 'ပြီးဆုံးမည့်ရက် (မဖြစ်မနေမဟုတ်)',
      'next5Occurrences': 'နောက်ထပ် ၅ ကြိမ် ဖြစ်ပေါ်မည့်ရက်များ',
      'enterAmountBeforeConverting': 'မပြောင်းလဲမီ ပမာဏကို ဦးစွာ ထည့်သွင်းပါ',
      'preview': 'အကြိုကြည့်ရှုရန်:',
      'pleaseFillAllFields': 'ကျေးဇူးပြု၍ အကွက်အားလုံးကို ဖြည့်ပါ',
      'pleaseEnterAmountFirst': 'ကျေးဇူးပြု၍ ပမာဏကို ဦးစွာ ထည့်သွင်းပါ',
      'pleaseEnterValidExchangeRate': 'ကျေးဇူးပြု၍ မှန်ကန်သော ငွေလဲနှုန်းကို ထည့်သွင်းပါ',
      'pleaseEnterValidAmount': 'ကျေးဇူးပြု၍ မှန်ကန်သော ပမာဏကို ဦးစွာ ထည့်သွင်းပါ',
      'neverEnds': 'ရပ်တန့်မည့်အချိန်မရှိပါ',

      // Additions for Edit Transaction Screen
      'editTransactionTitle': 'ငွေစာရင်းသွင်းမှု ပြင်ဆင်ရန်',
      'deleteTransactionTitle': 'ငွေစာရင်းသွင်းမှု ဖျက်ရန်',
      'deleteConfirmMessage': 'ဤငွေစာရင်းသွင်းမှုကို ဖျက်ရန် သေချာပါသလား? ဤလုပ်ဆောင်ချက်ကို ပြန်ဖျက်၍ မရပါ',
      'autoCreatedTransactionTitle': 'အလိုအလျောက် ဖန်တီးထားသော ငွေစာရင်းသွင်းမှု',
      'autoCreatedDescriptionRecurring': 'ဤငွေစာရင်းသွင်းမှုသည် အလိုအလျောက် ဖန်တီးထားခြင်း ဖြစ်သည်',
      'autoCreatedDescriptionDisabled': 'ဤငွေစာရင်းသွင်းမှုသည် အလိုအလျောက် ဖန်တီးထားခြင်း ဖြစ်သည် (ယခု ပိတ်ထားသည်)',
      'stopFutureAutoCreation': 'အလိုအလျောက် ဖန်တီးခြင်းကို ရပ်ရန်',
      'viewParentTransaction': 'မူရင်း ငွေစာရင်းသွင်းမှုကို ကြည့်ရန်',
      'stopRecurringDialogTitle': 'ထပ်တလဲလဲ ငွေစာရင်းသွင်းမှုကို ရပ်မလား?',
      'stopRecurringDialogContent': 'ဤအရာက နောင် ငွေစာရင်းသွင်းမှုများ အလိုအလျောက် ဖန်တီးခြင်းကို ရပ်တန့်စေမည်ဖြစ်သည်',
      'stopRecurringDialogInfo': 'လက်ရှိ ငွေစာရင်းသွင်းမှုများကို သက်ရောက်မှုရှိမည် မဟုတ်ပါ',
      'stopRecurringButton': 'ထပ်တလဲလဲ ပြုလုပ်ခြင်းကို ရပ်ရန်',
      'stoppingRecurrence': 'ထပ်တလဲလဲ ပြုလုပ်ခြင်း ရပ်ဆိုင်းနေသည်',
      'pleaseWait': 'ခဏ စောင့်ပါ...',
      'successTitle': 'အောင်မြင်သည်!',
      'successAutoCreationStopped': 'နောင် အလိုအလျောက် ဖန်တီးခြင်းကို ရပ်တန့်ပြီးပါပြီ',
      'errorTitle': 'အမှား',
      'errorLoadParentFailed': 'မူရင်း ငွေစာရင်းသွင်းမှုကို ဖော်ပြရန် မအောင်မြင်ပါ:',
      'updateTransactionButton': 'ငွေစာရင်းသွင်းမှုကို ပြင်ရန်',
      'selectCurrencyT': 'ငွေကြေးအမျိုးအစားကို ရွေးပါ',
      'recurringScheduleStopped': 'ဤငွေစာရင်းသွင်းမှုအတွက် ထပ်တလဲလဲ အချိန်ဇယားကို ရပ်တန့်ပြီးပါပြီ',
      'recurringSettingsStopDes': 'ထပ်တလဲလဲ ဆက်တင်များကို မူရင်း ငွေစာရင်းသွင်းမှုမှ စီမံခန့်ခွဲသည် နောင် အလိုအလျောက် ဖန်တီးခြင်းကို ရပ်ရန် အထက်ပါ ခလုတ်ကို အသုံးပြုပါ',
      'dismiss': 'ပယ်ဖျက်ရန်',

      // Additions for Image Input Screen
      'imageInputTitle': 'ပုံ ထည့်သွင်းခြင်း',
      'premiumFeatureTitle': 'ပရီမီယံ ဝန်ဆောင်မှု',
      'premiumFeatureUpgradeDescImg': 'ငွေစာရင်းသွင်းမှုအတွက် ပုံ ထည့်သွင်းခြင်းကို အသုံးပြုရန် အဆင့်မြှင့်ပါ',
      'upgradeNowButton': 'အဆင့်မြှင့်ပါ',
      'tapToAddImagePlaceholder': 'ဘောင်ချာပုံ ထည့်ရန် နှိပ်ပါ',
      'cameraOrGalleryPlaceholder': 'ကင်မရာ သို့မဟုတ် ဓာတ်ပုံပြခန်း',
      'chooseDifferentImageButton': 'အခြားပုံကို ရွေးပါ',
      'analyzingReceipt': 'ဘောင်ချာကို ခွဲခြမ်းစိတ်ဖြာနေသည်...',
      'extractedTransactionTitle': 'ထုတ်ယူထားသော ငွေစာရင်းသွင်းမှု',
      'dataLabelType': 'အမျိုးအစား',
      'dataLabelAmount': 'ပမာဏ',
      'dataLabelCategory': 'အမျိုးအစား',
      'dataLabelDate': 'ရက်စွဲ',
      'dataLabelDescription': 'ဖော်ပြချက်',
      'aiReasoningLabel': 'AI စဉ်းစားတွေးခေါ်မှု:',
      'confidenceLabel': 'ယုံကြည်စိတ်ချရမှု:',
      'saveTransactionButton': 'ငွေစာရင်းသွင်းမှု သိမ်းဆည်းရန်',
      'errorCaptureImage': 'ပုံရိုက်ယူရန် မအောင်မြင်ပါ:',
      'errorPickImage': 'ပုံရွေးရန် မအောင်မြင်ပါ:',
      'chooseImageSourceModalTitle': 'ပုံအရင်းမြစ်ကို ရွေးချယ်ပါ',
      'cameraListTileTitle': 'ကင်မရာ',
      'cameraListTileSubtitle': 'ဘောင်ချာ ဓာတ်ပုံရိုက်ပါ',
      'galleryListTileTitle': 'ဓာတ်ပုံပြခန်း',
      'galleryListTileSubtitle': 'ဓာတ်ပုံပြခန်းမှ ရွေးချယ်ပါ',

      // Additions for Voice Input Screen
      'voiceInputTitle': 'အသံဖြင့် ထည့်ခြင်း',
      'premiumFeatureUpgradeDescVoice': 'ငွေစာရင်းသွင်းမှုအတွက် အသံဖြင့် ထည့်ခြင်းကို အသုံးပြုရန် အဆင့်မြှင့်ပါ',
      'recordingStatus': 'အသံသွင်းနေသည်... ရပ်ရန် နှိပ်ပါ',
      'tapToRecordStatus': 'အသံသွင်းခြင်း စတင်ရန် နှိပ်ပါ\nငွေစာရင်းသွင်းမှုများစွာကို ဖော်ပြနိုင်သည်',
      'transcriptionTitle': 'ကူးယူဖော်ပြချက်',
      'errorStartRecording': 'အသံသွင်းခြင်း စတင်ရန် မအောင်မြင်ပါ:',
      'errorStopRecording': 'အသံသွင်းခြင်း ရပ်ရန် မအောင်မြင်ပါ:',
      'analyzingTransactions': 'ငွေစာရင်းသွင်းမှုများကို ခွဲခြမ်းစိတ်ဖြာနေသည်...',

      // Additions for Transactions List Screen
      'allTransactionsTitle': 'ငွေစာရင်းသွင်းမှုများ အားလုံး',
      'filtersSectionTitle': 'စစ်ထုတ်မှုများ',
      'transactionTypeFilterLabel': 'ငွေစာရင်းသွင်းမှု အမျိုးအစား:',
      'filterChipAll': 'အားလုံး',
      'dateRangeFilterLabel': 'ရက်စွဲ အပိုင်းအခြား:',
      'selectDateRangeButton': 'ရက်စွဲ အပိုင်းအခြားကို ရွေးပါ',
      'loadingMoreIndicator': 'ထပ်မံ တင်နေသည်...',
      'emptyStateTitle': 'ငွေစာရင်းသွင်းမှု မတွေ့ရှိပါ',
      'emptyStateSubtitle': 'သင်၏ စစ်ထုတ်မှုများကို ပြင်ဆင်ပါ သို့မဟုတ် ငွေစာရင်းသွင်းမှု ထည့်သွင်းကြည့်ပါ',
      'clearAllFiltersButton': 'စစ်ထုတ်မှုများ အားလုံး ရှင်းလင်းရန်',
      'clearDateFilterTooltip': 'ရက်စွဲ စစ်ထုတ်မှုကို ရှင်းလင်းရန်',
      'addTransactionFabTooltip': 'ငွေစာရင်းသွင်းမှု အသစ် ထည့်ရန်',
      'currencyFilter': 'ငွေကြေးအမျိုးအစား စစ်ထုတ်မှု',

      //Goals screen
      'financialGoals': 'ငွေကြေး ရည်မှန်းချက်များ',
      'goalsSummary': 'ရည်မှန်းချက်များ အကျဉ်းချုပ်',
      'active': 'ဆောင်ရွက်ဆဲ',
      'achieved': 'အောင်မြင်ပြီး',
      'total': 'စုစုပေါင်း',
      'byCurrency': 'ငွေကြေးအမျိုးအစားအလိုက်',
      'availableBalance': 'အသုံးပြုနိုင်သော လက်ကျန်ငွေ',
      'forGoals': 'ရည်မှန်းချက်များအတွက်',
      'availableForGoals': 'ရည်မှန်းချက်များအတွက် ရရှိနိုင်သော',
      'selected': 'ရွေးချယ်ထားသော',
      'goalCreatedSuccessfully': 'ရည်မှန်းချက် အောင်မြင်စွာ ဖန်တီးပြီးပါပြီ',
      'goalDeletedSuccessfully': 'ရည်မှန်းချက် အောင်မြင်စွာ ဖျက်ပြီးပါပြီ',
      'noGoalsYet': 'ရည်မှန်းချက် မရှိသေးပါ',
      'createGoalGetStarted': 'စတင်ရန် သင်၏ ပထမဆုံး ငွေကြေး ရည်မှန်းချက်ကို ဖန်တီးပါ!',

      //Add goal screen
      'createNewGoal': 'ရည်မှန်းချက် အသစ် ဖန်တီးရန်',
      'goalName': 'ရည်မှန်းချက် အမည်',
      'goalType': 'ရည်မှန်းချက် အမျိုးအစား',
      'targetAmount': 'ရည်မှန်းချက် ပမာဏ',
      'initialContribution': 'ကနဦး မတည်ငွေ (မဖြစ်မနေမဟုတ်)',
      'targetDate': 'ပြီးစီးရမည့်ရက် (မဖြစ်မနေမဟုတ်)',
      'createGoal': 'ရည်မှန်းချက် ဖန်တီးရန်',
      'failedToCreateGoal': 'ရည်မှန်းချက် ဖန်တီးရန် မအောင်မြင်ပါ',
      'pleaseEnterAGoalName': 'ကျေးဇူးပြု၍ ရည်မှန်းချက် အမည်ကို ထည့်သွင်းပါ',
      'pleaseEnterTargetAmount': 'ကျေးဇူးပြု၍ ရည်မှန်းချက် ပမာဏကို ထည့်သွင်းပါ',
      'pleaseEnterAValidAmount': 'ကျေးဇူးပြု၍ မှန်ကန်သော ပမာဏကို ထည့်သွင်းပါ',
      'insufficientBalance': 'လက်ကျန်ငွေ မလုံလောက်ပါ',
      'selectTargetDate': 'ရည်မှန်းချက် ပြီးစီးရမည့်ရက်ကို ရွေးချယ်ပါ (မဖြစ်မနေမဟုတ်)',
      'egEmergencyFund': 'ဥပမာ၊ အရေးပေါ် ရန်ပုံငွေ',

      // goal detail screen
      'goalInformation': 'ရည်မှန်းချက် အချက်အလက်',
      'fundsAddedSuccessfully': 'ငွေဖြည့်သွင်းမှု အောင်မြင်ပါသည်',
      'fundsWithdrawnSuccessfully': 'ငွေထုတ်ယူမှု အောင်မြင်ပါသည်',
      'manageFunds': 'ငွေဖြည့်/ငွေထုတ်',
      'currentProgress': 'လက်ရှိ တိုးတက်မှု',
      'currentAmount': 'လက်ရှိ ပမာဏ',
      'remaining': 'ကျန်ရှိသော',
      'targetDateDetail': 'ပြီးစီးရမည့်ရက်',
      'created': 'ဖန်တီးသည့်ရက်',
      'withdraw': 'ထုတ်ယူရန်',
      'add': 'ထည့်ရန်',
      'editGoal': 'ရည်မှန်းချက် ပြင်ဆင်ရန်',
      'enterAGoalName': 'ကျေးဇူးပြု၍ ရည်မှန်းချက် အမည်ကို ထည့်သွင်းပါ',
      'goalUpdatedSuccessfully': 'ရည်မှန်းချက် အောင်မြင်စွာ ပြင်ဆင်ပြီးပါပြီ',
      'failedToUpdateGoal': 'ရည်မှန်းချက် ပြင်ဆင်ရန် မအောင်မြင်ပါ',
      'save': 'သိမ်းဆည်းရန်',
      'deleteGoal': 'ရည်မှန်းချက် ဖျက်ရန်',
      'deleteGoalConfirmation': 'ဤရည်မှန်းချက်ကို ဖျက်ရန် သေချာပါသလား? ခွဲဝေထားသော ငွေများကို သင့်လက်ကျန်ငွေစာရင်းသို့ ပြန်လည်ရောက်ရှိမည်ဖြစ်သည်',
      'delete': 'ဖျက်ရန်',
      'failedToDeleteGoal': 'ရည်မှန်းချက် ဖျက်ရန် မအောင်မြင်ပါ',
      'goalDetails': 'ရည်မှန်းချက် အသေးစိတ်',

      //budgets screen
      'budgetCreatedSuccessfully':'ဘတ်ဂျက် အောင်မြင်စွာ ဖန်တီးပြီးပါပြီ',
      'budgetDeletedSuccessfully': 'ဘတ်ဂျက် အောင်မြင်စွာ ဖျက်ပြီးပါပြီ',
      'budgetSummary': 'ဘတ်ဂျက် အကျဉ်းချုပ်',
      'exceeded': 'ကျော်လွန်သွားသော',
      'allCurrencies': 'ငွေကြေးအမျိုးအစားအားလုံး',
      'createNewBudget': 'ဘတ်ဂျက် အသစ် ဖန်တီးရန်',
      'upcoming': 'မကြာမီလာမည်',
      'exceededCap': 'ကျော်လွန်သွားသော',
      'completed': 'ပြီးစီးသော',
      'activeCap': 'ဆောင်ရွက်ဆဲ',
      'auto': 'အလိုအလျောက်',
      'noBudgetsYet': 'ဘတ်ဂျက် မရှိသေးပါ',
      'createYourFirstBudget': 'သုံးစွဲမှုကို ခြေရာခံရန် သင်၏ ပထမဆုံး ဘတ်ဂျက်ကို ဖန်တီးပါ!',

      //create budget screen
      'categoryAlreadyExists':'ဤအမျိုးအစားသည် ရှိပြီးသားဖြစ်သည်',
      'selectEndDate': 'စိတ်ကြိုက်ကာလအတွက် ပြီးဆုံးမည့်ရက်ကို ရွေးချယ်ပါ',
      'addOneCategoryBudget': 'အနည်းဆုံး အမျိုးအစား ဘတ်ဂျက်တစ်ခုကို ထည့်သွင်းပါ',
      'failedToCreateBudget': 'ဘတ်ဂျက် ဖန်တီးရန် မအောင်မြင်ပါ',
      'createBudget': 'ဘတ်ဂျက် ဖန်တီးရန်',
      'selectCurrency': 'ဤဘတ်ဂျက်အတွက် ငွေကြေးအမျိုးအစားကို ရွေးပါ',
      'pleaseSelectCurrency': 'ကျေးဇူးပြု၍ ငွေကြေးအမျိုးအစားကို ရွေးချယ်ပါ',
      'aiFeatures': 'AI ဝန်ဆောင်မှုများ',
      'getAiPoweredBudgetSuggestions': 'AI-မှ ပေးသော ဘတ်ဂျက် အကြံပြုချက်များကို ရယူပါ',
      'tapToUseAiBudgetSuggestions': 'AI ဘတ်ဂျက် အကြံပြုချက်များကို အသုံးပြုရန် နှိပ်ပါ',
      'context': 'အကြောင်းအရာ (မဖြစ်မနေမဟုတ်)',
      'addContext': 'AI မှ ပိုမိုကောင်းမွန်သော ဘတ်ဂျက်များ ဖန်တီးနိုင်ရန် အကြောင်းအရာ ထည့်ပါ',
      'generateAiBudget': 'AI ဖြင့် ဘတ်ဂျက် ရေးဆွဲမည်',
      'aiWillAnalyzeAndSuggestBudgets' : 'AI သည် သင့်သုံးစွဲမှုကို ခွဲခြမ်းစိတ်ဖြာပြီး အမျိုးအစားအလိုက် ဘတ်ဂျက်များကို အကြံပြုမည်',
      'budgetName': 'ဘတ်ဂျက် အမည်',
      'enterBudgetName': 'ကျေးဇူးပြု၍ ဘတ်ဂျက် အမည်ကို ထည့်သွင်းပါ',
      'budgetPeriod': 'ဘတ်ဂျက် ကာလ',
      'week': 'အပတ်',
      'month': 'လ',
      'year': 'နှစ်',
      'custom': 'စိတ်ကြိုက်ကာလ',
      'startDate': 'စတင်မည့်ရက်',
      'endDateNoOp': 'ပြီးဆုံးမည့်ရက်',
      'autoCreateNextBudget':  'နောက်ဘတ်ဂျက်ကိုအလိုအလျောက်ဖန်တီးရန်',
      'automaticallyCreateNewBudget': 'ဤဘတ်ဂျက် ပြီးဆုံးသည့်အခါ ဘတ်ဂျက်အသစ်ကို အလိုအလျောက် ဖန်တီးပါ',
      'enableAutoCreate': 'အလိုအလျောက် ဖန်တီးခြင်း ဖွင့်ရန်',
      'chooseHowToCreateNextBudget': 'နောက်ဘတ်ဂျက်ကို မည်သို့ ဖန်တီးမည်ကို ရွေးချယ်ပါ:',
      'useCurrentCategories': 'လက်ရှိ အမျိုးအစားများကို အသုံးပြုရန်',
      'keepTheSameBudgetAmounts': 'အမျိုးအစားအားလုံးအတွက် တူညီသော ဘတ်ဂျက် ပမာဏများကို ထားရှိရန်',
      'aiOptimizedBudget': 'AI-မှ အကောင်းဆုံးဖြစ်အောင် ပြုလုပ်ထားသော ဘတ်ဂျက်',
      'aiAnalyzesSpendingAndSuggestsAmounts': 'AI သည် သင့်သုံးစွဲမှုကို ခွဲခြမ်းစိတ်ဖြာပြီး အကောင်းဆုံး ပမာဏများကို အကြံပြုမည်',
      'categoryBudgets': 'အမျိုးအစားအလိုက်ဘတ်ဂျက်များ',
      'noCategoriesAddedYet': 'အမျိုးအစားများ မထည့်သွင်းရသေးပါ',
      'totalBudget': 'စုစုပေါင်း ဘတ်ဂျက်',
      'addCategoryBudget': 'အမျိုးအစားအလိုက် ဘတ်ဂျက် ထည့်ရန်',
      'editCategoryBudget': 'အမျိုးအစား ဘတ်ဂျက် ပြင်ဆင်ရန်',
      'subCategory': 'အမျိုးအစားခွဲ (မဖြစ်မနေမဟုတ်)',
      'allNoFilter': 'အားလုံး',
      'budgetAmount': 'ဘတ်ဂျက် ပမာဏ',
      'enterAmount': 'ကျေးဇူးပြု၍ ပမာဏကို ထည့်သွင်းပါ',
      'enterValidAmount': 'ကျေးဇူးပြု၍ မှန်ကန်သော ပမာဏကို ထည့်သွင်းပါ',
      'notesThisBudget': 'ဤဘတ်ဂျက်နှင့်ပတ်သက်သော မှတ်စုများ',
      'egMonthlyExpenses': 'ဥပမာ၊ လစဉ် အသုံးစရိတ်များ',
      'egTravelingHolidaySeason': 'ဥပမာ၊ "ဒီတစ်ပတ် ခရီးသွားမယ်" သို့မဟုတ် "အားလပ်ရက် ရာသီ"',

      //edit budget screen
      'budgetUpdatedSuccessfully': 'ဘတ်ဂျက် အောင်မြင်စွာ ပြင်ဆင်ပြီးပါပြီ',
      'failedToUpdateBudget': 'ဘတ်ဂျက် ပြင်ဆင်ရန် မအောင်မြင်ပါ',
      'editBudget': 'ဘတ်ဂျက် ပြင်ဆင်ရန်',
      'budgetPeriodC': 'ဘတ်ဂျက် ကာလ (ပြောင်းလဲ၍ မရပါ)',
      'period': 'ကာလ',
      'duration': 'ကြာချိန်',
      'currencyC': 'ငွေကြေးအမျိုးအစား (ပြောင်းလဲ၍ မရပါ)',
      'editingCategoriesRecalculateAlert': 'အမျိုးအစားများကို ပြင်ဆင်ခြင်းသည် သုံးစွဲထားသော ပမာဏများကို ပြန်လည်သတ်မှတ်မည်ဖြစ်သည် လက်ရှိသုံးစွဲမှုကို ပြန်လည်တွက်ချက်မည်',
      'newTotalBudget': 'စုစုပေါင်း ဘတ်ဂျက် အသစ်',
      'currentTotal': 'လက်ရှိ စုစုပေါင်း',
      'saveChanges': 'အပြောင်းအလဲများကို သိမ်းဆည်းရန်',

      //budget detail screen
      'deleteBudget': 'ဘတ်ဂျက် ဖျက်ရန်',
      'deleteBudgetAlert': 'ဤဘတ်ဂျက်ကို ဖျက်ရန် သေချာပါသလား? ဤလုပ်ဆောင်ချက်ကို ပြန်ပြင်၍ မရပါ',
      'deleted': 'ဖျက်လိုက်ပြီ',
      'failedToDeleteBudget': 'ဘတ်ဂျက် ဖျက်ရန် မအောင်မြင်ပါ',
      'startsIn': 'စတင်ရန် ကျန်ရှိချိန်',
      'ended': 'ပြီးဆုံးသွားပြီ',
      'daysRemaining': 'ကျန်ရှိသော ရက်များ',
      'budgetDetails': 'ဘတ်ဂျက် အသေးစိတ်',
      'budgetWasAutomaticallyCreatedAi': 'ဤဘတ်ဂျက်ကို AI နည်းပညာဖြင့် အကောင်းဆုံးဖြစ်အောင် ချိန်ညှိ၍ အလိုအလျောက် ရေးဆွဲပေးထားခြင်း ဖြစ်ပါသည်',
      'budgetWasAutomaticallyCreatedPrevious': 'ဤဘတ်ဂျက်ကို အရင်ဘတ်ဂျက်မှ အလိုအလျောက် ဖန်တီးထားခြင်း ဖြစ်သည်',
      'autoCreateEnabled': 'အလိုအလျောက် ဖန်တီးခြင်း ဖွင့်ထားသည်',
      'nextBudgetWillBeAiOptimized': 'နောက်ထပ်ဘတ်ဂျက်ကို သင်၏ သုံးစွဲမှုအလေ့အထပေါ် မူတည်၍ AI ဖြင့် အကောင်းဆုံးဖြစ်အောင် ချိန်ညှိပေးသွားမည် ဖြစ်ပါသည်',
      'nextBudgetWillUseSameAmounts': 'နောက်ဘတ်ဂျက်တွင် တူညီသော အမျိုးအစား ပမာဏများကို အသုံးပြုမည်',
      'budgetExceeded': 'ဘတ်ဂျက် ကျော်လွန်သွားသည်',
      'budgetExceededAlert': 'သင်သည် ခွဲဝေထားသော ဘတ်ဂျက်ထက် ပိုမို သုံးစွဲခဲ့သည် ကျော်လွန်သွားသော အမျိုးအစားများတွင် သုံးစွဲမှုကို လျှော့ချရန် စဉ်းစားပါ',
      'approachingBudgetLimit': 'ဘတ်ဂျက် ကန့်သတ်ချက်သို့ နီးကပ်လာသည်',
      'used': 'အသုံးပြုပြီး',
      'categories': 'အမျိုးအစား',
      'deleting': 'ဖျက်နေသည်',

      //ai budget suggestion screen
      'analysisSummary': 'ခွဲခြမ်းစိတ်ဖြာချက် အကျဉ်းချုပ်',
      'transactionsAnalyzed': 'ခွဲခြမ်းစိတ်ဖြာခဲ့သော ငွေစာရင်းသွင်းမှုများ',
      'analysisPeriod': 'ခွဲခြမ်းစိတ်ဖြာမှု ကာလ',
      'categoriesFound': 'တွေ့ရှိသော အမျိုးအစားများ',
      'avgMonthlyIncome': 'ပျမ်းမျှ လစဉ် ဝင်ငွေ',
      'avgMonthlyExpenses': 'ပျမ်းမျှ လစဉ် အသုံးစရိတ်များ',
      'activeGoals': 'ဆောင်ရွက်ဆဲ ရည်မှန်းချက်များ',
      'close': 'ပိတ်ရန်',
      'aiBudgetSuggestion': 'AI ဘတ်ဂျက် အကြံပြုချက်',
      'analysisDetails': 'ခွဲခြမ်းစိတ်ဖြာချက် အသေးစိတ်',
      'failedToGenerateSuggestion': 'အကြံပြုချက် ထုတ်လုပ်ရန် မအောင်မြင်ပါ',
      'tryAgain': 'ထပ်ကြိုးစားပါ',
      'dataConfidence': 'ဒေတာ ယုံကြည်စိတ်ချရမှု',
      'highConfidence': 'သင့်ဒေတာအပေါ် အခြေခံ၍ ယုံကြည်စိတ်ချရမှု မြင့်မားသည်',
      'moderateConfidence': 'ယုံကြည်စိတ်ချရမှု အသင့်အတင့် - အချက်အလက် အကန့်အသတ်ရှိနေသည်',
      'lowConfidence': 'ယုံကြည်စိတ်ချရမှု နည်းပါး - အချက်အလက် အလွန်အကန့်အသတ်ရှိနေသည်',
      'yourContext': 'သင့် အကြောင်းအရာ',
      'importantNotes': 'အရေးကြီး မှတ်စုများ',
      'suggestedBudgetPlan': 'အကြံပြုထားသော ဘတ်ဂျက် အစီအစဉ်',
      'name': 'အမည်',
      'aiAnalysis': 'AI ခွဲခြမ်းစိတ်ဖြာချက်',
      'useThisBudget': 'အသုံးပြုရန်',

      //ai chat screen
      'responseStyle': 'တုံ့ပြန်မှု ပုံစံ',
      'chooseAiResponses': 'AI ၏ တုံ့ပြန်မှုများ မည်မျှအသေးစိတ်စေချင်သည်ကို ရွေးချယ်ပါ',
      'thinking': 'စဉ်းစားနေသည်...',
      'financialAdvisor': 'ငွေကြေး အကြံပေး',
      'stopResponse': 'တုံ့ပြန်မှုကို ရပ်ရန်',
      'changeResponseStyle': 'တုံ့ပြန်မှု ပုံစံကို ပြောင်းရန်',
      'clearHistory': 'မှတ်တမ်း ရှင်းလင်းရန်',
      'loadingChatHistory': 'ပြောဆိုမှုမှတ်တမ်းများ ဖော်ပြရန် စောင့်ဆိုင်းနေပါ....',
      'upgradeToPremium': 'ပရီမီယံသို့ အဆင့်မြှင့်ပါ',
      'unlockFullCapabilities': 'AI နှင့် ပြောဆိုနိုင်သည့် စွမ်းရည်အပြည့်ကို ရယူပါ',
      'upgrade': 'အဆင့်မြှင့်ရန်',
      'helloAi': 'မင်္ဂလာပါ! ကျွန်ုပ်သည် သင့်၏ AI ငွေကြေး အကူအညီပေးသူ ဖြစ်ပါသည်',
      'aiChatDes': 'သင့်သုံးစွဲမှုကို ခွဲခြမ်းစိတ်ဖြာခြင်း၊ ထိုးထွင်းသိမြင်မှုများ ပေးခြင်းနှင့် သင့်ငွေကြေးဆိုင်ရာ မေးခွန်းများကို ဖြေကြားခြင်းတို့ဖြင့် ကျွန်ုပ် ကူညီနိုင်ပါသည်',
      'tryAskingMeSomething': 'ဤကဲ့သို့ မေးကြည့်ပါ:',
      'aiIsTyping': 'AI စာရိုက်နေသည်...',
      'upgradeToPremiumToChat': 'စကားပြောရန် ပရီမီယံသို့ အဆင့်မြှင့်ပါ',
      'aiIsResponding': 'AI တုံ့ပြန်နေသည်...',
      'askAboutFinances': 'သင့်ငွေကြေးအကြောင်း မေးပါ...',
      'clearChatHistory': 'စကားပြော မှတ်တမ်း ရှင်းလင်းရန်',
      'clearChatHistoryAlert': 'စကားပြော မှတ်တမ်း အားလုံးကို ရှင်းလင်းရန် သေချာပါသလား? ဤလုပ်ဆောင်ချက်ကို ပြန်ပြင်၍ မရပါ',
      'clear': 'ရှင်းလင်းရန်',
      'generatingInsights': 'အချက်အလက်များကို သုံးသပ်နေသည်...',
      'insightsRegeneratedSuccessfully': 'သုံးသပ်ချက်အသစ်များ ရယူပြီးပါပြီ',
      'failedToRegenerateInsights': 'သုံးသပ်ချက်အသစ်ရယူရန် အဆင်မပြေပါ',
      'deepSpendingAnalysis': 'အသုံးစရိတ်များကို အသေးစိတ် ခွဲခြမ်းစိတ်ဖြာချက်',
      'personalizedRecommendations': 'သင့်အတွက် အကြံပြုချက်များ',
      'financialHealthScore': 'ငွေကြေးဆိုင်ရာ ကျန်းမာမှု အခြေအနေ',
      'savingsOpportunities': 'ငွေပိုစုနိုင်မည့် အခွင့်အလမ်းများ',
      'budgetOptimizationTips': 'ဘတ်ဂျက်ကို အကောင်းဆုံးဖြစ်အောင် လုပ်ဆောင်ရန် အကြံပြုချက်များ',
      'analyzingYourFinancialData': 'သင့်ငွေကြေး ဒေတာကို ခွဲခြမ်းစိတ်ဖြာနေသည်...',
      'thisMayTakeFewSeconds': '၎င်းသည် စက္ကန့်အနည်းငယ် ကြာနိုင်သည်',
      'failedToLoadInsights': 'သုံးသပ်ချက်များ ဖော်ပြ၍ မရပါ',
      'noInsightsAvailable': 'သုံးသပ်ချက်များ မရရှိနိုင်ပါ',
      'addTransactionsGoalsToGenerateInsights': 'သုံးသပ်ချက်များ ပြုလုပ်ရန် ငွေစာရင်းသွင်းမှုများနှင့် ရည်မှန်းချက်များကို ထည့်ပါ',
      'aiGeneratedInsights': 'AI သုံးသပ်ချက်များ',
      'normal': 'ပုံမှန်',
      'concise': 'ကျစ်လျစ်သော',
      'detailed': 'အသေးစိတ်',
      'balancedResponses': 'မျှတသော တုံ့ပြန်မှုများ',
      'briefDirect': 'အတိုချုပ်နှင့် တိုက်ရိုက်',
      'thoroughExplanations': 'ပြည့်စုံသော ရှင်းလင်းချက်များ',

      //notification screen
      'notifications': 'အကြောင်းကြားချက်များ',
      'markedAsRead': 'အကြောင်းကြားချက်များ အားလုံးကို ဖတ်ပြီးဟု အမှတ်အသားပြုပြီးပါပြီ',
      'markAllRead': 'ဖတ်ပြီးဟုအမှတ်အသားပြုရန်',
      'notificationDeleted': 'အကြောင်းကြားချက် ဖျက်လိုက်ပြီ',
      'undo': 'ပြန်ဖျက်ရန်',
      'noNotificationsYet': 'အကြောင်းကြားချက် မရှိသေးပါ',
      'notifyGoalsProgress': 'သင်၏ ငွေကြေးဆိုင်ရာ ရည်မှန်းချက် တိုးတက်မှုအခြေအနေများကို ကျွန်ုပ်တို့ အသိပေးသွားပါမည်',

      //reports screen
      'selectStartEndDates': 'ကျေးဇူးပြု၍ စတင်မည့်ရက်နှင့် ပြီးဆုံးမည့်ရက် နှစ်ခုလုံးကို ရွေးချယ်ပါ',
      'reportDownloadedSuccessfully': 'အစီရင်ခံစာ အောင်မြင်စွာ ဒေါင်းလုဒ်လုပ်ပြီးပါပြီ',
      'open': 'ဖွင့်ရန်',
      'downloadPDF': 'PDF ဒေါင်းလုဒ်လုပ်ရန်',
      'currencyR': 'ငွေကြေး:',
      'generatingReport': 'အစီရင်ခံစာ ထုတ်လုပ်နေသည်...',
      'selectDatesToGenerateReport': 'အစီရင်ခံစာ ထုတ်လုပ်ရန် ရက်စွဲနှစ်ခုလုံးကို ရွေးချယ်ပါ',
      'select': 'ရွေးချယ်ရန်',
      'reportPeriod': 'အစီရင်ခံစာ ကာလ',
      'netBalance': 'အသားတင် လက်ကျန်ငွေ',
      'income': 'ဝင်ငွေ',
      'expenses': 'အသုံးစရိတ်များ',
      'goalsAllocated': 'ရည်မှန်းချက်များသို့ ခွဲဝေထားသော',
      'dailyAverages': 'နေ့စဉ် ပျမ်းမျှ',
      'averageDailyIncome': 'ပျမ်းမျှ နေ့စဉ် ဝင်ငွေ',
      'averageDailyExpenses': 'ပျမ်းမျှ နေ့စဉ် အသုံးစရိတ်',
      'incomeByCategory': 'အမျိုးအစားအလိုက် ဝင်ငွေ',
      'expensesByCategory': 'အမျိုးအစားအလိုက် အသုံးစရိတ်',
      'goalsProgress': 'ရည်မှန်းချက်များ တိုးတက်မှု',
      'multiCurrencyReport': 'ငွေကြေးမျိုးစုံ အစီရင်ခံစာ',
      'overview': 'ခြုံငုံကြည့်ရှုမှု',
      'totalTransactions': 'စုစုပေါင်း ငွေစာရင်းသွင်းမှုများ',
      'currencies': 'ငွေကြေးအမျိုးအစားများ',
      'allGoals': 'ရည်မှန်းချက်များ အားလုံး',
      'avgDailyIncome': 'ပျမ်းမျှ နေ့စဉ် ဝင်ငွေ',
      'avgDailyExpenses': 'ပျမ်းမျှ နေ့စဉ် အသုံးစရိတ်',
      'viewCategories': 'အမျိုးအစားများ ကြည့်ရန်',
      'topIncomeCategories': 'ထိပ်တန်း ဝင်ငွေ အမျိုးအစားများ',
      'topExpenseCategories': 'ထိပ်တန်း အသုံးစရိတ် အမျိုးအစားများ',
      'account': 'အကောင့်',
      'editProfile': 'ပရိုဖိုင် ပြင်ဆင်ရန်',
      'updateYourName': 'သင့်အမည်ကို ပြင်ပါ',
      'profileUpdatedSuccessfully': 'ပရိုဖိုင် အောင်မြင်စွာ ပြင်ပြီးပါပြီ',
      'changePassword': 'စကားဝှက် ပြောင်းရန်',
      'updateYourPassword': 'သင့်စကားဝှက်ကို ပြင်ပါ',
      'passwordChangedSuccessfully': 'စကားဝှက် အောင်မြင်စွာ ပြောင်းပြီးပါပြီ',
      'language': 'ဘာသာစကား',
      'changeAppLanguage': 'အက်ပ် ဘာသာစကား ပြောင်းရန်',
      'changeDefaultCurrency': 'မူရင်း ငွေကြေးအမျိုးအစား ပြောင်းရန်',
      'appearance': 'အသွင်အပြင်',
      'theme': 'အပြင်အဆင်',
      'themeSystem': 'စနစ်အလိုက်',
      'themeLight': 'အလင်း',
      'themeDark': 'အမှောင်',
      'themeSystemDesc': 'စက်ပစ္စည်း ဆက်တင်နှင့် ကိုက်ညီအောင်',
      'themeLightDesc': 'အလင်းအပြင်အဆင် အမြဲသုံးရန်',
      'themeDarkDesc': 'အမှောင်အပြင်အဆင် အမြဲသုံးရန်',
      'notificationSettings': 'အကြောင်းကြားချက် ဆက်တင်များ',
      'manageNotificationPreferences': 'အကြောင်းကြားချက် စိတ်ကြိုက်ရွေးချယ်မှုများကို စီမံခန့်ခွဲရန်',
      'subscription': 'ပရီမီယံစာရင်းသွင်းမှု',
      'manageSubscription': 'ပရီမီယံစာရင်းသွင်းမှုကို စီမံခန့်ခွဲရန်',
      'viewManageSubscription': 'သင့်ပရီမီယံစာရင်းသွင်းမှုကို ကြည့်ရှုပြီး စီမံခန့်ခွဲပါ',
      'unlockPremiumFeatures': 'ပရီမီယံ ဝန်ဆောင်မှုများ အားလုံးကို ဖွင့်ရန်',
      'about': 'အကြောင်း',
      'aboutToePwar': 'တိုးပွား အကြောင်း',

      //notification settings screen
      'notificationsEnabled': 'အကြောင်းကြားချက်များ ဖွင့်ထားသည်! 🔔',
      'changeNotificationSettingsDes': 'အကြောင်းကြားချက် ဆက်တင်များကို ပြောင်းရန်၊ ကျေးဇူးပြု၍ ဆက်တင်များသို့ သွားပါ',
      'openSettings': 'ဆက်တင်များ ဖွင့်ရန်',
      'testNotification': 'စမ်းသပ် အကြောင်းကြားချက် 🎉',
      'testNotificationDes': '၎င်းသည် Flow Finance မှ စမ်းသပ် အကြောင်းကြားချက် ဖြစ်ပါသည်!',
      'testNotificationMsg': 'စမ်းသပ် အကြောင်းကြားချက် ပေးပို့ပြီးပါပြီ! သင့်အကြောင်းကြားချက်များကို စစ်ဆေးပါ',
      'resetToDefaults': 'မူလသတ်မှတ်ချက်အတိုင်း ပြန်လည်ထားရှိမလား?',
      'enableAllNotificationTypes': '၎င်းသည် အကြောင်းကြားချက် အမျိုးအစားများ အားလုံးကို ဖွင့်ပေးမည်ဖြစ်သည် သေချာပါသလား?',
      'notificationPreferencesReset': 'အကြောင်းကြားချက် စိတ်ကြိုက်ရွေးချယ်မှုများကို မူလသတ်မှတ်ချက်အတိုင်း ပြန်လည်သတ်မှတ်ပြီးပါပြီ',
      'failedToResetPreferences': 'စိတ်ကြိုက်ရွေးချယ်မှုများကို ပြန်လည်သတ်မှတ်ရန် မအောင်မြင်ပါ',
      'reset': 'ပြန်လည်သတ်မှတ်ရန်',
      'resetToDefaultsWQ': 'မူလသတ်မှတ်ချက်အတိုင်း ပြန်လည်ထားရှိရန်',
      'pushNotifications': 'အကြောင်းကြားချက်များ',
      'receiveUpdatesAboutFinances': 'သင့်ငွေကြေးအကြောင်း အပ်ဒိတ်များကို လက်ခံရယူပါ',
      'sendTestNotification': 'စမ်းသပ် အကြောင်းကြားချက် ပေးပို့ရန်',
      'customizeNotificationsReceive': 'သင်လက်ခံလိုသော အကြောင်းကြားချက်များကို စိတ်ကြိုက်ပြုပြင်ပါ',
      'notificationTypes': 'အကြောင်းကြားချက် အမျိုးအစားများ',
      'progressUpdates': 'တိုးတက်မှု အပ်ဒိတ်များ',
      'notifiedMilestones': '၂၅%၊ ၅၀% နှင့် ၇၅% ရောက်ရှိချိန်များတွင် အသိပေးပါမည်',
      'milestoneReached': 'အောင်မြင်မှု တစ်ဆင့် ရရှိပါပြီ',
      'thousandSavedTowardsGoal': 'ရည်မှန်းချက်အတွက် ဒေါ်လာ ၁,၀၀၀ စုဆောင်းတိုင်း',
      'deadlineApproaching': 'နောက်ဆုံးရက် နီးလာသည်',
      'reminders': '၁၄၊ ၇၊ နှင့် ၃ ရက်အလိုတွင် သတိပေးချက်များ',
      'goalAchieved': 'ရည်မှန်းချက် အောင်မြင်ပြီ',
      'celebrate': 'သင်၏ ရည်မှန်းချက်ရောက်ရှိချိန်တွင် အတူတူ အောင်ပွဲခံလိုက်ပါ',
      'budgetStarted': 'ဘတ်ဂျက် စတင်ပြီ',
      'whenNewBudgetBegins': 'ဘတ်ဂျက်ကာလ အသစ် စတင်သည့်အခါ',
      'periodEndingSoon': 'ကာလ မကြာမီ ပြီးဆုံးတော့မည်',
      'reminderBudgets': 'ကာလ မကုန်ဆုံးမီ ၃ ရက်အလိုတွင် သတိပေးချက်',
      'budgetThreshold': 'ဘတ်ဂျက် ကန့်သတ်ချက်',
      'alertBudget': 'ဘတ်ဂျက်၏ ၈၀% သုံးစွဲသည့်အခါ အသိပေးပါ',
      'whenOverBudgetLimit': 'ဘတ်ဂျက် ကန့်သတ်ချက်ထက် ကျော်လွန်သွားသည့်အခါ',
      'autoCreatedBudget': 'အလိုအလျောက် ဖန်တီးထားသော ဘတ်ဂျက်',
      'budgetCreatedAutomatically': 'ဘတ်ဂျက်အသစ် အလိုအလျောက် ဖန်တီးပြီးပါပြီ',
      'budgetNowActive': 'ဘတ်ဂျက် စတင်အသက်ဝင်ပါပြီ',
      'whenBudgetBecomesActive': 'နောက်ထပ် ဘတ်ဂျက် စတင်အသက်ဝင်သည့်အခါ',
      'largeTransaction': 'ကြီးမားသော ငွေစာရင်းသွင်းမှု',
      'alertsLargeExpenses': 'ပုံမှန်မဟုတ်ဘဲ ကြီးမားသော အသုံးစရိတ်များအတွက် အကြောင်းကြားချက်များ',
      'unusualSpending': 'ပုံမှန်မဟုတ်သော သုံးစွဲမှု',
      'whenSpendingPatternsChange': 'သုံးစွဲမှု ပုံစံများ ပြောင်းလဲသည့်အခါ',
      'paymentReminders': 'ငွေပေးချေမှုအတွက် သတိပေးချက်များ',
      'upcomingPayments': 'လာမည့် ထပ်တလဲလဲ ပေးချေမှုများ',
      'recurringCreated': 'ထပ်တလဲလဲ ဖန်တီးပြီး',
      'recurringEnded': 'ထပ်တလဲလဲ ပြီးဆုံးပြီ',
      'whenRecurringEnds': 'ထပ်တလဲလဲ စီးရီး ပြီးဆုံးသည့်အခါ',
      'recurringDisabled': 'ထပ်တလဲလဲ ပိတ်ထားသည်',
      'whenRecurrenceDisabled': 'ထပ်တလဲလဲ ပြုလုပ်ခြင်း ပိတ်ထားသည့်အခါ',
      'whenRecurringTransactionsCreated': 'ထပ်တလဲလဲ ငွေစာရင်းသွင်းမှုများ ဖန်တီးသည့်အခါ',
      'weeklyInsights': 'အပတ်စဉ် ဘဏ္ဍာရေးသုံးသပ်ချက်များ',
      'whenWeeklyInsightsReady': 'တနင်္ဂနွေနေ့တိုင်း သင့်အပတ်စဉ် ဘဏ္ဍာရေးသုံးသပ်ချက်များ ထုတ်ပြီးသောအခါ အသိပေးချက်ရယူပါ',

      //edit profile screen
      'failedUpdateProfile': 'ပရိုဖိုင် ပြုပြင်ရန် မအောင်မြင်ပါ',
      'discardChanges': 'အပြောင်းအလဲများကို ပယ်ဖျက်မလား?',
      'discardChangesAlert': 'သင့်တွင် မသိမ်းဆည်းရသေးသော အပြောင်းအလဲများ ရှိသည် ၎င်းတို့ကို ပယ်ဖျက်ရန် သေချာပါသလား?',
      'keepEditing': 'ဆက်လက် ပြင်ဆင်ရန်',
      'discard': 'ပယ်ဖျက်ရန်',
      'tapIconChangeAvatar': 'ပရိုဖိုင်ပုံ ပြောင်းရန် အိုင်ကွန်ကို နှိပ်ပါ',
      'fullName': 'အမည် အပြည့်အစုံ',
      'enterFullName': 'သင့်အမည် အပြည့်အစုံကို ထည့်ပါ',
      'pleaseEnterName': 'ကျေးဇူးပြု၍ သင့်အမည်ကို ထည့်ပါ',
      'nameTwoCharacters': 'အမည်သည် အနည်းဆုံး စာလုံး ၂ လုံး ရှိရမည်',
      'emailAddress': 'အီးမေးလ် လိပ်စာ',
      'emailCannotChanged':  'အီးမေးလ်ကို ပြောင်းလဲ၍ မရပါ',
      'haveUnsavedChanges': 'သင့်တွင် မသိမ်းဆည်းရသေးသော အပြောင်းအလဲများ ရှိသည်',
      'dangerZone': 'အန္တရာယ်ရှိဇုန်',
      'dangerZoneDes': 'သင့်အကောင့်ကို ဖျက်လိုက်ပါက သင်၏ ငွေလွှဲမှတ်တမ်းများ၊ ရည်မှန်းချက်များ၊ ဘတ်ဂျက်များနှင့် သုံးသပ်ချက်များ အပါအဝင် ဒေတာအားလုံးကို အပြီးတိုင် ဖယ်ရှားသွားမည်ဖြစ်သည်။ ဤလုပ်ဆောင်ချက်ကို ပြန်လည်ပြင်ဆင်၍ မရနိုင်ပါ',
      'deleteAccount': 'အကောင့်ဖျက်ပါ',
      'deleteAccountQ': 'အကောင့်ကို ဖျက်မလား?',
      'willPermanentlyDelete': 'ဤလုပ်ဆောင်ချက်သည် အောက်ပါတို့ကို အပြီးတိုင် ဖျက်ပစ်မည်ဖြစ်သည်-',
      'allYourTransactions': 'သင်၏ ငွေလွှဲမှတ်တမ်းများ အားလုံး',
      'allYourFinancialGoals': 'သင်၏ ဘဏ္ဍာရေးဆိုင်ရာ ရည်မှန်းချက်များ အားလုံး',
      'allYourBudgets': 'သင်၏ ဘတ်ဂျက်များ အားလုံး',
      'allYourAiInsights': 'သင်၏ AI သုံးသပ်ချက်များ အားလုံး',
      'allYourChatHistory': 'သင်၏ Chat မှတ်တမ်းများ အားလုံး',
      'yourAccountInformation': 'သင်၏ အကောင့် အချက်အလက်များ',
      'actionCannotBeUndone': 'ဤလုပ်ဆောင်ချက်ကို ပြန်လည်ပြင်ဆင်၍ မရနိုင်ပါ',


      //currency settings screen
      'currencySettings': 'ငွေကြေး ဆက်တင်များ',
      'selectDefaultCurrency': 'မူရင်း ငွေကြေးအမျိုးအစားကို ရွေးချယ်ပါ',
      'preferredCurrency': 'သင်နှစ်သက်သော ငွေကြေးအမျိုးအစားကို ရွေးချယ်ပါ',
      'eachCurrencyOwnBalance': 'မည်သည့် ငွေကြေးအမျိုးအစားဖြင့်မဆို ငွေစာရင်းသွင်းမှုများ ထည့်နိုင်ပါသည် ငွေကြေးတစ်ခုစီတွင် ၎င်း၏ကိုယ်ပိုင် ငွေစာရင်း ရှိသည်',

      //change password screen
      'passwordSixCharacters': 'စကားဝှက်သည် အနည်းဆုံး စာလုံး ၆ လုံး ရှိရမည်',
      'currentPassword': 'လက်ရှိ စကားဝှက်',
      'enterCurrentPassword': 'သင့်လက်ရှိ စကားဝှက်ကို ထည့်ပါ',
      'pleaseEnterCurrentPassword': 'ကျေးဇူးပြု၍ သင့်လက်ရှိ စကားဝှက်ကို ထည့်ပါ',
      'newPassword': 'စကားဝှက် အသစ်',
      'enterNewPassword': 'သင့်စကားဝှက် အသစ်ကို ထည့်ပါ',
      'pleaseEnterNewPassword': 'ကျေးဇူးပြု၍ စကားဝှက် အသစ်ကို ထည့်ပါ',
      'newPasswordDifferentCurrentPassword': 'စကားဝှက် အသစ်သည် လက်ရှိ စကားဝှက်နှင့် မတူညီရ',
      'confirmNewPassword': 'စကားဝှက် အသစ်ကို အတည်ပြုရန်',
      'confirmYourNewPassword': 'သင့်စကားဝှက် အသစ်ကို အတည်ပြုပါ',
      'pleaseConfirmNewPassword': 'ကျေးဇူးပြု၍ စကားဝှက် အသစ်ကို အတည်ပြုပါ',
      'passwordsNotMatch': 'စကားဝှက်များ မတူညီပါ',

      //outflow analytics screen
      'yearly': 'နှစ်စဉ်',
      'totalSpending': 'စုစုပေါင်း သုံးစွဲမှု',
      'spendingByCategory': 'အမျိုးအစားအလိုက် သုံးစွဲမှု',
      'noDataAvailable': 'ဒေတာ မရရှိနိုင်ပါ',
      'addTransactionsSeeSpendingAnalytics': 'သင်၏ သုံးစွဲမှု ခွဲခြမ်းစိတ်ဖြာချက်ကို ကြည့်ရန် ငွေစာရင်းသွင်းမှုအချို့ကို ထည့်ပါ',
      'byDayOfWeek': 'ရက်သတ္တပတ်၏ နေ့အလိုက်',
      'byMonth': 'လအလိုက်',
      'byYear': 'နှစ်အလိုက်',
      'customPeriod': 'စိတ်ကြိုက်ကာလ',
      'spendingDayOfWeek': 'ရက်သတ္တပတ်၏ နေ့အလိုက် သုံးစွဲမှု',
      'spendingMonth': 'လအလိုက် သုံးစွဲမှု',
      'spendingYear': 'နှစ်အလိုက် သုံးစွဲမှု',
      'spendingOverTime': 'အချိန်ကြာလာသည်နှင့်အမျှ သုံးစွဲမှု',

      //inflow analytics screen
      'totalIncome': 'စုစုပေါင်း ဝင်ငွေ',
      'addIncomeSeeAnalytics': 'သင်၏ ခွဲခြမ်းစိတ်ဖြာချက်ကို ကြည့်ရန် ဝင်ငွေ ငွေစာရင်းသွင်းမှုအချို့ကို ထည့်ပါ',
      'incomeDayOfWeek': 'ရက်သတ္တပတ်၏ နေ့အလိုက် ဝင်ငွေ',
      'incomeByMonth': 'လအလိုက် ဝင်ငွေ',
      'incomeByYear': 'နှစ်အလိုက် ဝင်ငွေ',
      'incomeOverTime': 'အချိန်ကြာလာသည်နှင့်အမျှ ဝင်ငွေ',

      //subscription screen
      'welcomeToPremium': 'ပရီမီယံသို့ ကြိုဆိုပါသည်!',
      'accessAllPremiumFeatures': 'သင်သည် ယခု ပရီမီယံ ဝန်ဆောင်မှုများ အားလုံးကို အသုံးပြုနိုင်ပါပြီ',
      'getStarted': 'စတင်ရန်',
      'premiumStatus': 'ပရီမီယံ အခြေအနေ',
      'premiumActive': 'ပရီမီယံ အသက်ဝင်သည်',
      'premiumFeatures': 'ပရီမီယံ ဝန်ဆောင်မှုများ',
      'aiBudgetSuggestions': 'AI ဘတ်ဂျက် အကြံပြုချက်များ',
      'aiBudgetSuggestionsDes': 'သင့်သုံးစွဲမှု ပုံစံများအပေါ် အခြေခံ၍ စမတ်ကျသော ဘတ်ဂျက် အကြံပြုချက်များကို ရယူပါ',
      'voiceInputDes': 'အသံဖြင့် ပြောရုံဖြင့် ငွေစာရင်းသွင်းမှုများ ထည့်ပါ',
      'receiptScanning': 'ဘောင်ချာ စကန်ဖတ်ခြင်း',
      'receiptScanningDes': 'ဘောင်ချာများကို စကန်ဖတ်ပြီး ငွေစာရင်းအသေးစိတ်ကို အလိုအလျောက် ရယူပါ',
      'aiFinancialAssistant': 'AI ငွေကြေး အကူအညီပေးသူ',
      'aiFinancialAssistantDes': 'သင်နှင့်ကိုက်ညီမည့် ငွေကြေးဆိုင်ရာ အကြံပြုချက်များကို AI နှင့် ဆွေးနွေးတိုင်ပင်ပါ',
      'aiInsightsDes': 'သင်၏ သုံးစွဲမှုအလေ့အထများကို အသေးစိတ် ခွဲခြမ်းစိတ်ဖြာချက်များ ရယူပါ',
      'premiumPlan': 'ပရီမီယံ အစီအစဉ်',
      'tryCancelAnytime': 'ရက် ၃၀ စမ်းသပ်ပါ • အချိန်မရွေး ပယ်ဖျက်နိုင်သည်',
      'contactAdmin': 'အဆင့်မြှင့်ရန် Admin ကိုဆက်သွယ်ပါ',
      'contactSupport' : 'Premium activate လုပ်ရန် Admin Support ကို ဆက်သွယ်ပါ',


      // Feedback Screen
      'sendFeedback': 'အကြံပြုချက် ပေးပို့ရန်',
      'weValueYourInput': 'သင့်အကြံပြုချက်ကို တန်ဖိုးထားပါသည်',
      'feedbackHeaderSubtitle': 'Flow Finance ကို ပိုမိုကောင်းမွန်အောင် ပြုလုပ်ရန် သင့်အကြံဉာဏ်များ မျှဝေပါ သို့မဟုတ် ပြဿနာများကို တိုင်ကြားပါ',
      'whatIsThisRegarding': 'မည်သည့်အကြောင်းအရာနှင့် ပတ်သက်ပါသလဲ?',
      'howRateExperience': 'သင့်အတွေ့အကြုံကို မည်သို့ အဆင့်သတ်မှတ်လိုပါသလဲ?',
      'tellUsMore': 'ပိုမို ပြောပြပါ',
      'feedbackHint': 'သင့်ပြဿနာ သို့မဟုတ် အကြံဉာဏ်များကို ဖော်ပြပါ...',
      'submitFeedback': 'အကြံပြုချက် တင်သွင်းရန်',
      'pleaseSelectRating': 'ကျေးဇူးပြု၍ အဆင့်သတ်မှတ်ချက် ရွေးချယ်ပါ',
      'feedbackSubmittedSuccess': 'သင့်အကြံပြုချက်အတွက် ကျေးဇူးတင်ပါသည်!',
      'feedbackFailed': 'အကြံပြုချက် ပေးပို့ရန် မအောင်မြင်ပါ',
      'pleaseEnterMessage': 'ကျေးဇူးပြု၍ စာသား ရိုက်ထည့်ပါ',
      'feedbackMinLength': 'ကျေးဇူးပြု၍ အသေးစိတ် ပိုမိုဖြည့်သွင်းပါ (အနည်းဆုံး စာလုံး ၁၀ လုံး)',
      // Feedback Categories
      'feedbackCategoryGeneral': 'အထွေထွေ မေးမြန်းချက်',
      'feedbackCategoryBug': 'ချို့ယွင်းချက် တိုင်ကြားရန်',
      'feedbackCategoryFeature': 'လုပ်ဆောင်ချက် အသစ် တောင်းဆိုရန်',
      'feedbackCategoryUsability': 'အသုံးပြုမှုဆိုင်ရာ ပြဿနာ',
      'feedbackCategoryOther': 'အခြား',
      'feedbackDesc': 'ချို့ယွင်းချက်များတင်ပြရန် သို့မဟုတ် လုပ်ဆောင်ချက်အသစ်များတောင်းဆိုရန်',

      // Localization sweep — widgets/providers batch
      'badgeTryFree': 'အခမဲ့ စမ်းသုံးပါ',
      'badgeThreeNew': 'အသစ် ၃ ခု',
      'badgeFreeMonth': 'အခမဲ့ တစ်လ',
      'askAi': 'AI ကို မေးပါ',
      'chatWithAiAssistant': 'AI အကူအညီပေးသူနှင့် စကားပြောပါ',
      'noUpcomingOccurrences': 'လာမည့် အကြိမ်များ မရှိပါ',
      'repeatOn': 'ထပ်တလဲလဲ ပြုလုပ်မည့်နေ့',
      'dayLabel': 'ရက်',
      'weekdayMon': 'တနင်္လာ',
      'weekdayTue': 'အင်္ဂါ',
      'weekdayWed': 'ဗုဒ္ဓဟူး',
      'weekdayThu': 'ကြာသပတေး',
      'weekdayFri': 'သောကြာ',
      'weekdaySat': 'စနေ',
      'weekdaySun': 'တနင်္ဂနွေ',
      'monthJanuary': 'ဇန်နဝါရီ',
      'monthFebruary': 'ဖေဖော်ဝါရီ',
      'monthMarch': 'မတ်',
      'monthApril': 'ဧပြီ',
      'monthMay': 'မေ',
      'monthJune': 'ဇွန်',
      'monthJuly': 'ဇူလိုင်',
      'monthAugust': 'သြဂုတ်',
      'monthSeptember': 'စက်တင်ဘာ',
      'monthOctober': 'အောက်တိုဘာ',
      'monthNovember': 'နိုဝင်ဘာ',
      'monthDecember': 'ဒီဇင်ဘာ',
      'premiumFeatureDialogContent': 'ဤအင်္ဂါရပ်ကို အသုံးပြုရန် ပရီမီယံ စာရင်းသွင်းမှု လိုအပ်ပါသည်။ အင်္ဂါရပ်အားလုံးကို ဖွင့်ရန် ယခုပင် အဆင့်မြှင့်ပါ!',

      // Localization sweep — transactions batch
      'pickCategoryTitle': 'အမျိုးအစား ရွေးချယ်ပါ',
      'thenChooseSubCategoryHint': 'ထို့နောက် ၎င်း၏ အမျိုးအစားခွဲကို ရွေးချယ်ပါ',
      'chooseSubCategoryTitle': 'အမျိုးအစားခွဲ ရွေးချယ်ပါ',
      'noCategoriesLabel': 'အမျိုးအစားများ မရှိပါ',
      'subCategoriesCountLabel': 'အမျိုးအစားခွဲများ',
      'chooseCategoryFallback': 'အမျိုးအစားတစ်ခု ရွေးပါ',
      'categoryAndSubCategoryFallback': 'အမျိုးအစားနှင့် အမျိုးအစားခွဲ',
      'repeatLabel': 'ထပ်တလဲလဲ',
      'doneLabel': 'ပြီးပါပြီ',
      'offLabel': 'ပိတ်ထားသည်',
      'egExchangeRateHint': 'ဥပမာ၊ ၃၀၀၀',
      'speakItTooltip': 'အသံဖြင့် ပြောပါ',
      'keepItButton': 'ဆက်ထားမည်',
      'currencyConvertedMessage': 'ငွေကြေး ပြောင်းလဲပြီးပါပြီ! ပမာဏကို ပြောင်းလဲထားသည်',
      'addAReceiptTitle': 'ဘောက်ချာ ထည့်ရန်',
      'whatWeReadLabel': 'ကျွန်ုပ်တို့ ဖတ်ရှုရရှိသည်များ',
      'whatWeReadDescription': 'ဆိုင်အမည်၊ ရက်စွဲ၊ ပမာဏနှင့် အမျိုးအစား — သင်အတည်ပြုမှသာ မှတ်တမ်းတင်ပါမည်။',
      'useDifferentPhotoButton': 'အခြားဓာတ်ပုံကို သုံးရန်',
      'failedToSaveTransactionFallback': 'ငွေစာရင်းသွင်းမှု သိမ်းဆည်းရန် မအောင်မြင်ပါ',
      'successfullySavedPrefix': 'အောင်မြင်စွာ သိမ်းဆည်းပြီးပါပြီ',
      'transactionsSuffix': 'ငွေစာရင်း(များ)',
      'whatYouSaidLabel': 'သင်ပြောခဲ့သည်များ',
      'fromOneRecordingLabel': 'အသံဖမ်းယူမှု တစ်ခုမှ',
      'foundLabel': 'တွေ့ရှိသည်',
      'transactionSingularLabel': 'ငွေစာရင်းသွင်းမှု',
      'multipleSpendsWarning': 'သင့်ဝါကျတွင် သီးခြားသုံးစွဲမှုများစွာ ပါဝင်နေသဖြင့် သီးခြားစီ မှတ်တမ်းတင်ထားပါသည် — သင်ရည်ရွယ်မထားသည်များကို အမှန်ခြစ် ဖြုတ်ပါ။',
      'selectedTotalLabel': 'ရွေးချယ်ထားသော စုစုပေါင်း',
      'recordAgainButton': 'ထပ်မံ အသံဖမ်းယူရန်',
      'mixedCurrenciesLabel': 'ရောနှောငွေကြေးအမျိုးအစားများ',
      'oneTransactionLabel': '၁ ငွေစာရင်းသွင်းမှု',
      'transactionsCountSuffix': 'ငွေစာရင်းသွင်းမှုများ',

      // Localization sweep — auth screens batch
      'loginTagline': 'စောင့်ကြည့်လေ တိုးပွားလေ ဖြစ်သော ငွေကြေး',
      'emailLabel': 'အီးမေးလ်',
      'enterEmailError': 'ကျေးဇူးပြု၍ သင့်အီးမေးလ်ကို ထည့်ပါ',
      'enterValidEmailError': 'ကျေးဇူးပြု၍ မှန်ကန်သော အီးမေးလ်ကို ထည့်ပါ',
      'passwordLabel': 'စကားဝှက်',
      'enterPasswordError': 'ကျေးဇူးပြု၍ သင့်စကားဝှက်ကို ထည့်ပါ',
      'forgotPasswordQuestion': 'စကားဝှက် မေ့နေပါသလား?',
      'signIn': 'အကောင့်ဝင်ရန်',
      'newHerePrefix': 'ဒီနေရာမှာ အသစ်လား? ',
      'createAnAccount': 'အကောင့်တစ်ခု ဖန်တီးရန်',
      'registerTagline': 'အခုမိနစ်နှစ်မိနစ်လောက်ပဲ ကြာမယ်၊ အက်ပ်က သင့်ငွေကြေးရဲ့ လှုပ်ရှားမှုတွေကို စသင်ယူပါလိမ့်မယ်။',
      'fullNameLabel': 'အမည်အပြည့်အစုံ',
      'passwordMinLengthError': 'စကားဝှက်သည် အနည်းဆုံး စာလုံး ၆ လုံး ရှိရမည်',
      'confirmPasswordLabel': 'စကားဝှက်ကို အတည်ပြုပါ',
      'confirmPasswordError': 'ကျေးဇူးပြု၍ သင့်စကားဝှက်ကို အတည်ပြုပါ',
      'byContinuingAcceptPrefix': 'ဆက်လက်လုပ်ဆောင်ခြင်းဖြင့် သင်သည် ',
      'termsLinkText': 'စည်းမျဉ်းစည်းကမ်းများ',
      'andConnector': ' နှင့် ',
      'privacyPolicyLinkText': 'ကိုယ်ရေးအချက်အလက်မူဝါဒ',
      'neverSellDataSuffix': ' ကို လက်ခံပါသည်။ သင့်ဒေတာကို ကျွန်ုပ်တို့ ဘယ်သောအခါမျှ ရောင်းချမည် မဟုတ်ပါ။',
      'createAccountButton': 'အကောင့်ဖန်တီးရန်',
      'alreadyHaveAccountPrefix': 'အကောင့်ရှိပြီးသားလား? ',
      'oneTapLeft': 'နောက်တစ်ချက်ပဲ လိုပါတော့သည်',
      'verificationLinkSentPrefix': 'အတည်ပြုလင့်ခ်ကို ဤသို့ ပေးပို့လိုက်ပါပြီ\n',
      'whyExtraStepTitle': 'ဘာကြောင့် ဒီအဆင့်ထပ်လိုအပ်တာလဲ',
      'emailVerificationExplanation': 'သင့်အီးမေးလ်သည် စကားဝှက်မေ့သွားပါက အကောင့်ထဲသို့ ပြန်ဝင်ရန် တစ်ခုတည်းသောနည်းလမ်းဖြစ်သောကြောင့် သင်တကယ်ပိုင်ဆိုင်သည့်လိပ်စာဖြစ်ရပါမည်။ ငွေကြေးမည်သည့်အရာမျှ ကောက်ခံမည်မဟုတ်ပြီး အခြားအီးမေးလ်များလည်း ဆက်လက်ပေးပို့မည် မဟုတ်ပါ။',
      'verifiedSignInButton': 'အတည်ပြုပြီးပါပြီ — အကောင့်ဝင်ရန်',
      'nothingArrivedPrefix': 'ဘာမှမရောက်သေးဘူးလား? Spam ဖိုင်တွဲကို စစ်ဆေးပါ၊ သို့မဟုတ် ',
      'useDifferentAddressLink': 'အခြားလိပ်စာတစ်ခု သုံးပါ',
      'termsAndConditionsTitle': 'စည်းမျဉ်းများနှင့် သတ်မှတ်ချက်များ',
      'welcomeToToePwarTagline': 'တိုးပွား - ကိုယ်ပိုင်ငွေကြေး AI မှ ကြိုဆိုပါသည်',
      'termsAndConditionsBody': 'တိုးပွားကို အသုံးပြုခြင်းဖြင့် သင်သည် အောက်ပါတို့ကို သဘောတူပါသည်−\n\n၁။ အက်ပ်ကို ကိုယ်ပိုင်ငွေကြေးစီမံခန့်ခွဲမှုအတွက်သာ အသုံးပြုမည်\n\n၂။ ငွေစာရင်းသွင်းမှုများပြုလုပ်ရာတွင် မှန်ကန်သောအချက်အလက်များကို ပေးမည်\n\n၃။ သင့်အကောင့်အထောက်အထားများကို လုံခြုံစွာထိန်းသိမ်းမည်\n\n၄။ AI ဝန်ဆောင်မှုများကို အလွဲသုံးစားမပြုလုပ်ခြင်း သို့မဟုတ် စနစ်ကို လှည့်ဖြားရန် မကြိုးစားခြင်း\n\n၅။ ငွေကြေးဆိုင်ရာ သုံးသပ်ချက်များသည် အကြံပြုချက်များသာဖြစ်ပြီး ကျွမ်းကျင်သူအကြံဉာဏ်မဟုတ်ကြောင်း နားလည်ခြင်း\n\n၆။ ပရီမီယံအင်္ဂါရပ်များအတွက် စာရင်းသွင်းမှု တက်ကြွစွာရှိရန် လိုအပ်ကြောင်း လက်ခံခြင်း\n\n၇။ ကိုယ်ပိုင်ဆိုင်ရာသုံးသပ်ချက်များ ပေးရန် သင့်ငွေကြေးဒေတာကို ကျွန်ုပ်တို့ လုပ်ဆောင်ခွင့်ပြုခြင်း',
      'privacyPolicyTitle': 'ကိုယ်ရေးအချက်အလက်မူဝါဒ',
      'yourPrivacyMattersTitle': 'သင့်ကိုယ်ရေးကိုယ်တာ အရေးကြီးပါသည်',
      'privacyPolicyBody': 'ကျွန်ုပ်တို့သည် သင့်ဒေတာကို အောက်ပါရည်ရွယ်ချက်များအတွက် စုဆောင်းအသုံးပြုပါသည်−\n\n• ကိုယ်ပိုင်ငွေကြေးအသိအမြင်များ ပေးရန်\n• ကျွန်ုပ်တို့၏ AI အကြံပြုချက်များ တိုးတက်စေရန်\n• သင့်အကောင့်နှင့် ငွေစာရင်းများကို လုံခြုံစေရန်\n• သင့်ငွေကြေးဆိုင်ရာ အရေးကြီးသတိပေးချက်များ ပေးပို့ရန်\n\nကျွန်ုပ်တို့သည် သင့်ဒေတာကို အောက်ပါအတိုင်း ကာကွယ်ပါသည်−\n\n• အထိန်းအသိမ်းလိုအပ်သော အချက်အလက်အားလုံးကို ကုဒ်ဖြင့်ကာကွယ်ခြင်း\n• သဘောတူညီချက်မရှိဘဲ သင့်ဒေတာကို တတိယပါတီများနှင့် ဘယ်တော့မှ မမျှဝေခြင်း\n• သင့်ဒေတာကို အချိန်မရွေး ဖျက်ခွင့်ပြုခြင်း\n• စက်မှုလုပ်ငန်းစံနှုန်းနှင့်ညီသော လုံခြုံရေးအလေ့အကျင့်များကို လိုက်နာခြင်း\n\nသင့်ငွေကြေးဒေတာကို လုံခြုံစွာသိမ်းဆည်းထားပြီး တိုးပွားနှင့် သင့်အတွေ့အကြုံကို မြှင့်တင်ရန်အတွက်သာ အသုံးပြုပါသည်။',
      'resetPasswordTitle': 'သင့်စကားဝှက်ကို ပြန်လည်သတ်မှတ်ရန်',
      'resetPasswordSubtitle': 'အကောင့်ပေါ်ရှိ လိပ်စာသို့ ဂဏန်း ၆ လုံးပါ ကုဒ်ကို အီးမေးလ်ဖြင့် ပေးပို့ပါမည်။',
      'emailAddressLabel': 'အီးမေးလ်လိပ်စာ',
      'sendCodeButton': 'ကုဒ်ပို့ရန်',
      'enterAllSixDigitsError': 'ဂဏန်း ၆ လုံးလုံးကို ထည့်ပါ',
      'newCodeSentMessage': 'ကုဒ်အသစ်ကို သင့်အီးမေးလ်သို့ ပေးပို့ပြီးပါပြီ။',
      'enterTheCodeTitle': 'ကုဒ်ကို ထည့်ပါ',
      'sentCodeToPrefix': 'ပေးပို့ထားသည့်လိပ်စာ',
      'expiresInTenMinutes': '၎င်းသည် ဆယ်မိနစ်အတွင်း သက်တမ်းကုန်ဆုံးပါမည်။',
      'verifyCodeButton': 'ကုဒ်ကို အတည်ပြုရန်',
      'didntGetItPrefix': 'မရောက်သေးဘူးလား? ',
      'resendInPrefix': 'ပြန်ပို့ရန်',
      'sendNewCodeButton': 'ကုဒ်အသစ် ပေးပို့ရန်',
      'passwordResetTitle': 'စကားဝှက် ပြန်လည်သတ်မှတ်ပြီးပါပြီ!',
      'passwordResetSuccessMessage': 'သင့်စကားဝှက်ကို အောင်မြင်စွာ ပြောင်းလဲပြီးပါပြီ။ သင့်စကားဝှက်အသစ်ဖြင့် ယခု အကောင့်ဝင်နိုင်ပါပြီ။',
      'backToLogin': 'အကောင့်ဝင်ရန် ပြန်သွားမည်',
      'chooseNewPasswordTitle': 'စကားဝှက်အသစ်ကို ရွေးချယ်ပါ',
      'codeAcceptedSubtitle': 'ကုဒ်ကို လက်ခံပြီးပါပြီ။ အနည်းဆုံး စာလုံး ၆ လုံး ရှိရပါမည်။',
      'newPasswordLabel': 'စကားဝှက်အသစ်',
      'pleaseEnterAPasswordError': 'ကျေးဇူးပြု၍ စကားဝှက်တစ်ခု ထည့်ပါ',
      'minimumSixCharactersError': 'အနည်းဆုံး စာလုံး ၆ လုံး',
      'confirmItLabel': 'ထပ်မံအတည်ပြုပါ',
      'saveAndSignInButton': 'သိမ်းဆည်းပြီး အကောင့်ဝင်ရန်',

      // Localization sweep — legal text + force update batch
      'privacyPolicySubtitle': 'သင့်ကိုယ်ရေးအချက်အလက်များကို ကျွန်ုပ်တို့ တန်ဖိုးထားပါသည် · နောက်ဆုံးမွမ်းမံသည့်ရက် ဇန်နဝါရီ ၂၀၂၅',
      'privacyIntroTitle': '၁။ နိဒါန်း',
      'privacyIntroBody': 'Toe Pwar ("ကျွန်ုပ်တို့" သို့မဟုတ် "ကျွန်ုပ်တို့၏") သည် သင့်ကိုယ်ရေးအချက်အလက်များကို ကာကွယ်ရန် အလေးထား ဆောင်ရွက်ပါသည်။ ဤကိုယ်ရေးအချက်အလက်မူဝါဒတွင် ကျွန်ုပ်တို့၏ မိုဘိုင်းအက်ပလီကေးရှင်းကို အသုံးပြုစဉ် သင့်အချက်အလက်များကို ကျွန်ုပ်တို့ မည်သို့ စုဆောင်းသည်၊ အသုံးပြုသည်၊ ထုတ်ဖော်သည်၊ ကာကွယ်စောင့်ရှောက်သည် ဆိုသည်ကို ရှင်းလင်းဖော်ပြထားပါသည်။',
      'privacyInfoCollectTitle': '၂။ ကျွန်ုပ်တို့ စုဆောင်းသော အချက်အလက်များ',
      'privacyInfoCollectBody': 'ကျွန်ုပ်တို့သည် အချက်အလက်အမျိုးအစားများစွာကို စုဆောင်းပါသည်−\n\nကိုယ်ရေးကိုယ်တာ အချက်အလက်များ−\n• အမည်နှင့် အီးမေးလ်လိပ်စာ\n• အကောင့်ဝင်ရောက်ရန် အချက်အလက်များ\n• ပရိုဖိုင်းအချက်အလက်များ\n\nငွေကြေးဆိုင်ရာ အချက်အလက်များ−\n• ငွေလွှဲငွေပေးမှု အသေးစိတ် (ပမာဏ၊ အမျိုးအစား၊ ရက်စွဲ)\n• ဘတ်ဂျက်အချက်အလက်များ\n• ငွေကြေးဆိုင်ရာ ပန်းတိုင်များ\n• အကောင့်လက်ကျန်ငွေများ\n\nအသုံးပြုမှုဆိုင်ရာ အချက်အလက်များ−\n• အက်ပ်အသုံးပြုပုံစံများ\n• ဝန်ဆောင်မှုများ အသုံးပြုမှု\n• စက်ပစ္စည်းဆိုင်ရာ အချက်အလက်များ',
      'privacyUseInfoTitle': '၃။ သင့်အချက်အလက်များကို ကျွန်ုပ်တို့ မည်သို့အသုံးပြုသည်',
      'privacyUseInfoBody': 'ကျွန်ုပ်တို့သည် သင့်အချက်အလက်များကို အောက်ပါရည်ရွယ်ချက်များအတွက် အသုံးပြုပါသည်−\n\n• ကျွန်ုပ်တို့၏ ဝန်ဆောင်မှုများကို ပံ့ပိုးပေးရန်နှင့် ထိန်းသိမ်းရန်\n• AI ကို အသုံးပြု၍ သင့်အတွက် အထူးပြင်ဆင်ထားသော ငွေကြေးဆိုင်ရာ ထိုးထွင်းသိမြင်မှုများ ထုတ်ပေးရန်\n• ဘတ်ဂျက် အကြံပြုချက်များ ဖန်တီးရန်\n• သင့်ငွေကြေးအခြေအနေနှင့် ပတ်သက်၍ အကြောင်းကြားချက်များ ပေးပို့ရန်\n• ကျွန်ုပ်တို့၏ အက်ပ်နှင့် AI algorithm များကို ပိုမိုကောင်းမွန်အောင် ပြုလုပ်ရန်\n• လုံခြုံရေးကို သေချာစေပြီး လိမ်လည်မှုများကို ကာကွယ်ရန်\n• အပ်ဒိတ်များနှင့် ဝန်ဆောင်မှုအသစ်များအကြောင်း သင့်ထံ ဆက်သွယ်အသိပေးရန်',
      'privacyDataSecurityTitle': '၄။ ဒေတာလုံခြုံရေး',
      'privacyDataSecurityBody': 'ကျွန်ုပ်တို့သည် စက်မှုလုပ်ငန်း စံနှုန်းများနှင့်အညီ လုံခြုံရေးအစီအမံများကို အကောင်အထည်ဖော်ဆောင်ရွက်ပါသည်−\n\n• ပေးပို့နေစဉ်နှင့် သိမ်းဆည်းထားစဉ် အရေးကြီးသော ဒေတာများကို ကုဒ်ဝှက်ခြင်း\n• လုံခြုံသော အထောက်အထားစိစစ်မှု စနစ်များ\n• ပုံမှန်လုံခြုံရေး စစ်ဆေးမှုများ\n• ဝင်ရောက်ခွင့် ထိန်းချုပ်မှုနှင့် စောင့်ကြည့်မှု\n• လုံခြုံသော ဒေတာသိမ်းဆည်းမှု နည်းလမ်းများ\n\nသို့ရာတွင် အင်တာနက်မှတစ်ဆင့် ပေးပို့မှု မည်သည့်နည်းလမ်းမျှ ၁၀၀ ရာခိုင်နှုန်း လုံခြုံခြင်း မရှိပါ။ ကျွန်ုပ်တို့သည် လုံခြုံရေးကို အပြည့်အဝ အာမမခံနိုင်ပါ။',
      'privacyDataSharingTitle': '၅။ ဒေတာမျှဝေခြင်း',
      'privacyDataSharingBody': 'ကျွန်ုပ်တို့သည် သင့်ကိုယ်ရေးအချက်အလက်များကို ရောင်းချခြင်း မပြုပါ။ အောက်ပါ ကန့်သတ်အခြေအနေများတွင်သာ ဒေတာများကို မျှဝေနိုင်ပါသည်−\n\n• သင့်ထံမှ တိကျသော သဘောတူညီချက် ရရှိပါက\n• ဥပဒေရေးရာ တာဝန်များကို လိုက်နာရန်\n• ကျွန်ုပ်တို့၏ အခွင့်အရေးများကို ကာကွယ်ရန်နှင့် လိမ်လည်မှုများကို တားဆီးရန်\n• ကျွန်ုပ်တို့၏ လုပ်ငန်းဆောင်ရွက်မှုများကို ကူညီပံ့ပိုးသော ဝန်ဆောင်မှုပေးသူများနှင့် (တင်းကျပ်သော လျှို့ဝှက်ချက် စာချုပ်များအောက်တွင်)\n\nတတိယပါတီ ဝန်ဆောင်မှုပေးသူများသည် သင့်ဒေတာကို ကာကွယ်ရန် စာချုပ်အရ တာဝန်ရှိပါသည်။',
      'privacyAiProcessingTitle': '၆။ AI နှင့် ဒေတာလုပ်ဆောင်မှု',
      'privacyAiProcessingBody': 'ကျွန်ုပ်တို့၏ AI ဝန်ဆောင်မှုများသည် သင့်ငွေကြေးဆိုင်ရာ ဒေတာများကို အောက်ပါ ရည်ရွယ်ချက်များအတွက် အသုံးပြုပါသည်−\n\n• အသုံးစရိတ် ပုံစံများကို ခွဲခြမ်းစိတ်ဖြာရန်\n• သင့်အတွက် အထူးပြင်ဆင်ထားသော ထိုးထွင်းသိမြင်မှုများ ထုတ်ပေးရန်\n• ဘတ်ဂျက် အကြံပြုချက်များ ပေးရန်\n• အနာဂတ် လမ်းကြောင်းများကို ခန့်မှန်းရန်\n\nသင်က အကူအညီပေးစနစ်ကို မေးခွန်းမေးသောအခါ သို့မဟုတ် ဘတ်ဂျက်တစ်ခု ဖန်တီးသောအခါ၊ ထိုတောင်းဆိုမှုအတွက် သက်ဆိုင်သည့် မှတ်တမ်းများကိုသာ ပေးပို့ပါသည်။ AI လုပ်ဆောင်မှုအားလုံးကို သင့်ဒေတာ ကိုယ်ရေးအချက်အလက်ကို ဂရုစိုက်၍ ဆောင်ရွက်ပါသည် — ကျွန်ုပ်တို့၏ AI မော်ဒယ်များကို ပိုမိုကောင်းမွန်အောင် ပြုလုပ်ရန်အတွက် စုစည်းထားပြီး အမည်ဝှက်ထားသော ဒေတာများကိုသာ အသုံးပြုပြီး၊ သင့်မှတ်တမ်းများကို ထိုတောင်းဆိုမှုမှလွဲ၍ အခြားမည်သည့်နေရာတွင်မျှ လေ့ကျင့်ရန် အသုံးမပြုပါ။',
      'privacyYourRightsTitle': '၇။ သင့်အခွင့်အရေးများ',
      'privacyYourRightsBody': 'သင့်တွင် အောက်ပါအခွင့်အရေးများ ရှိပါသည်−\n\n• သင့်ကိုယ်ရေးအချက်အလက်များကို ကြည့်ရှုခွင့်\n• မမှန်ကန်သော ဒေတာများကို ပြင်ဆင်ခွင့်\n• သင့်အကောင့်နှင့် ဒေတာများကို ဖျက်ခွင့်\n• သင့်ဒေတာများကို ထုတ်ယူခွင့်\n• အချို့သောဒေတာ လုပ်ဆောင်မှုများမှ ပယ်ချခွင့်\n• သဘောတူညီချက်ကို အချိန်မရွေး ရုပ်သိမ်းခွင့်\n\nဤအခွင့်အရေးများကို အသုံးပြုရန် ကျွန်ုပ်တို့ထံ ဆက်သွယ်ပါ သို့မဟုတ် အက်ပ်ဆက်တင်များကို အသုံးပြုပါ။',
      'privacyDataRetentionTitle': '၈။ ဒေတာသိမ်းဆည်းမှု ကာလ',
      'privacyDataRetentionBody': 'ကျွန်ုပ်တို့သည် အောက်ပါကာလများအတွင်း သင့်အချက်အလက်များကို သိမ်းဆည်းထားပါသည်−\n\n• သင့်အကောင့် အသုံးပြုနေသေးသရွေ့\n• ဝန်ဆောင်မှုများ ပေးဆောင်ရန် လိုအပ်သရွေ့\n• ဥပဒေအရ လိုအပ်သရွေ့\n\nသင့်အကောင့်ကို ဖျက်လိုက်သောအခါ၊ ဥပဒေအရ ဆက်လက်သိမ်းဆည်းထားရန် လိုအပ်သည့်အခြေအနေများမှလွဲ၍ သင့်ဒေတာများကို ရက် ၃၀ အတွင်း အပြီးအပိုင် ဖျက်သိမ်းပေးမည် ဖြစ်ပါသည်။',
      'privacyChildrensTitle': '၉။ ကလေးများ၏ ကိုယ်ရေးအချက်အလက်',
      'privacyChildrensBody': 'Toe Pwar သည် အသက် ၁၈ နှစ်အောက် အသုံးပြုသူများအတွက် ရည်ရွယ်ထားခြင်း မဟုတ်ပါ။ ကျွန်ုပ်တို့သည် ကလေးများထံမှ အချက်အလက်များကို သိလျက်နှင့် စုဆောင်းခြင်း မပြုပါ။ ကလေးတစ်ဦးထံမှ အချက်အလက်များ စုဆောင်းမိသည်ဟု သင်ယုံကြည်ပါက ကျွန်ုပ်တို့ထံ ချက်ချင်း ဆက်သွယ်ပါ။',
      'privacyIntlTransfersTitle': '၁၀။ နိုင်ငံတကာ ဒေတာလွှဲပြောင်းမှု',
      'privacyIntlTransfersBody': 'သင့်အချက်အလက်များကို သင့်နိုင်ငံမှလွဲ၍ အခြားနိုင်ငံများသို့ လွှဲပြောင်းပြီး လုပ်ဆောင်နိုင်ပါသည်။ ဤကိုယ်ရေးအချက်အလက်မူဝါဒနှင့်အညီ သင့်ဒေတာကို ကာကွယ်ရန် သင့်လျော်သော ကာကွယ်မှုအစီအမံများ ထားရှိထားကြောင်း ကျွန်ုပ်တို့ သေချာစေပါသည်။',
      'privacyChangesTitle': '၁၁။ ကိုယ်ရေးအချက်အလက်မူဝါဒ ပြောင်းလဲမှုများ',
      'privacyChangesBody': 'ကျွန်ုပ်တို့သည် ဤကိုယ်ရေးအချက်အလက်မူဝါဒကို အချိန်အခါအလိုက် မွမ်းမံနိုင်ပါသည်။ သိသာထင်ရှားသော ပြောင်းလဲမှုများကို အက်ပ် သို့မဟုတ် အီးမေးလ်မှတစ်ဆင့် အသိပေးပါမည်။ ပြောင်းလဲမှုများပြီးနောက် ဆက်လက်အသုံးပြုခြင်းသည် မွမ်းမံထားသော မူဝါဒကို လက်ခံကြောင်း ဆိုလိုပါသည်။',
      'privacyContactTitle': '၁၂။ ဆက်သွယ်ရန်',
      'privacyContactBody': 'ဤကိုယ်ရေးအချက်အလက်မူဝါဒ သို့မဟုတ် ကျွန်ုပ်တို့၏ ဒေတာကိုင်တွယ်မှုများနှင့်ပတ်သက်၍ မေးခွန်းများရှိပါက−\n\nအီးမေးလ်− toepwarai@gmail.com\nဝက်ဘ်ဆိုက်− www.toepwar.com\n\nသင့်စုံစမ်းမေးမြန်းမှုကို ရက် ၃၀ အတွင်း ပြန်လည်ဖြေကြားပါမည်။',
      'privacySecurityNotice': 'သင့်ဒေတာကို ကုဒ်ဝှက်ထားပြီး စက်မှုလုပ်ငန်းစံနှုန်းနှင့်ညီသော လုံခြုံရေးအစီအမံများဖြင့် ကာကွယ်ထားပါသည်',
      'termsTitle': 'စည်းမျဉ်းစည်းကမ်းများနှင့် သတ်မှတ်ချက်များ',
      'termsSubtitle': 'နောက်ဆုံးမွမ်းမံသည့်ရက်− ဇန်နဝါရီ ၂၀၂၅',
      'termsAcceptanceTitle': '၁။ စည်းကမ်းချက်များကို လက်ခံခြင်း',
      'termsAcceptanceBody': 'Toe Pwar ("အက်ပ်") ကို ဝင်ရောက်အသုံးပြုခြင်းဖြင့် သင်သည် ဤစည်းမျဉ်းစည်းကမ်းများကို လက်ခံပြီး လိုက်နာရန် သဘောတူပါသည်။ ဤစည်းကမ်းများကို သင် သဘောမတူပါက ကျေးဇူးပြု၍ ဤအက်ပ်ကို အသုံးမပြုပါနှင့်။',
      'termsUseOfServiceTitle': '၂။ ဝန်ဆောင်မှု အသုံးပြုခြင်း',
      'termsUseOfServiceBody': 'Toe Pwar သည် အောက်ပါ ကိုယ်ရေးငွေကြေးစီမံခန့်ခွဲမှု ကိရိယာများကို ပံ့ပိုးပေးပါသည်−\n\n• ငွေလွှဲငွေပေးမှုများကို ခြေရာခံခြင်းနှင့် အမျိုးအစားခွဲခြင်း\n• AI ပါဝါဖြင့် ငွေကြေးဆိုင်ရာ ထိုးထွင်းသိမြင်မှုများနှင့် အကြံပြုချက်များ\n• ဘတ်ဂျက်စီမံခန့်ခွဲမှုနှင့် ပန်းတိုင်ခြေရာခံခြင်း\n• ငွေကြေးအစီရင်ခံစာများနှင့် ခွဲခြမ်းစိတ်ဖြာမှုများ\n\nသင်သည် ဤအက်ပ်ကို ကိုယ်ရေးငွေကြေးစီမံခန့်ခွဲမှု ရည်ရွယ်ချက်အတွက်သာ အသုံးပြုရန် သဘောတူပါသည်။',
      'termsAccountRegTitle': '၃။ အကောင့်ဖွင့်လှစ်ခြင်း',
      'termsAccountRegBody': 'အကောင့်တစ်ခု ဖွင့်လှစ်ရာတွင် တိကျပြီး ပြည့်စုံသော အချက်အလက်များကို ပေးဆောင်ရပါမည်။ သင်သည် အောက်ပါအရာများအတွက် တာဝန်ရှိပါသည်−\n\n• သင့်အကောင့် ဝင်ရောက်ရန်အချက်အလက်များကို လျှို့ဝှက်ထိန်းသိမ်းခြင်း\n• သင့်အကောင့်အောက်တွင် ဖြစ်ပေါ်သော လုပ်ဆောင်ချက်အားလုံး\n• ခွင့်ပြုချက်မရှိသော အသုံးပြုမှုများကို ကျွန်ုပ်တို့ထံ ချက်ချင်း အကြောင်းကြားခြင်း',
      'termsUserResponsibilitiesTitle': '၄။ အသုံးပြုသူ တာဝန်ဝတ္တရားများ',
      'termsUserResponsibilitiesBody': 'သင်သည် အောက်ပါအချက်များကို သဘောတူပါသည်−\n\n• တိကျသော ငွေကြေးအချက်အလက်များ ပေးဆောင်ရန်\n• AI ဝန်ဆောင်မှုများကို အလွဲသုံးစားမပြုရန် သို့မဟုတ် စနစ်ကို လှည့်စားရန် မကြိုးစားရန်\n• ဤအက်ပ်ကို တရားမဝင်ရည်ရွယ်ချက်များအတွက် အသုံးမပြုရန်\n• သင့်အကောင့်ကို အခြားသူများနှင့် မမျှဝေရန်\n• သက်ဆိုင်ရာ ဥပဒေများနှင့် စည်းမျဉ်းစည်းကမ်းများအားလုံးကို လိုက်နာရန်',
      'termsAiFeaturesTitle': '၅။ AI ပါဝါဝန်ဆောင်မှုများ',
      'termsAiFeaturesBody': 'ကျွန်ုပ်တို့၏ AI ဝန်ဆောင်မှုများသည် သင့်ငွေကြေးဒေတာအပေါ် အခြေခံ၍ အကြံပြုချက်များနှင့် ထိုးထွင်းသိမြင်မှုများ ပေးပါသည်။ ကျေးဇူးပြု၍ သတိပြုပါ−\n\n• AI ၏ ထိုးထွင်းသိမြင်မှုများသည် အကြံပြုချက်များသာဖြစ်ပြီး၊ ပညာရှင်ဆန်သော ငွေကြေးအကြံဉာဏ် မဟုတ်ပါ\n• မည်သည့်လုပ်ဆောင်ချက်မဆို မလုပ်ဆောင်မီ အကြံပြုချက်များအားလုံးကို စစ်ဆေးသင့်ပါသည်\n• AI ၏ အကြံပြုချက်များအပေါ် အခြေခံ၍ ချမှတ်သော ဆုံးဖြတ်ချက်များအတွက် ကျွန်ုပ်တို့ တာဝန်မယူပါ\n• ရလဒ်များသည် သင့်ငွေကြေးအခြေအနေပေါ် မူတည်၍ ကွဲပြားနိုင်ပါသည်',
      'termsPremiumSubTitle': '၆။ Premium စာရင်းသွင်းမှု',
      'termsPremiumSubBody': 'Premium ဝန်ဆောင်မှုများကို အသုံးပြုရန် တက်ကြွစွာ စာရင်းသွင်းမှု လိုအပ်ပါသည်−\n\n• စာရင်းသွင်းမှုများကို သင်ရွေးချယ်သော အစီအစဉ်အလိုက် ကျသင့်ငွေတောင်းခံပါမည်\n• နောက်ငွေတောင်းခံမည့် သံသရာမတိုင်မီ အချိန်မရွေး ပယ်ဖျက်နိုင်ပါသည်\n• ငွေပြန်အမ်းမှုများကို ကျွန်ုပ်တို့၏ ငွေပြန်အမ်းမူဝါဒအတိုင်း ဆောင်ရွက်ပေးပါမည်\n• Premium ဝန်ဆောင်မှုများ အသုံးပြုခွင့်သည် စာရင်းသွင်းမှု သက်တမ်းကုန်ဆုံးသောအခါ ပြီးဆုံးသွားပါမည်',
      'termsDataProcessingTitle': '၇။ ဒေတာလုပ်ဆောင်မှု',
      'termsDataProcessingBody': 'ကျွန်ုပ်တို့သည် သင့်ငွေကြေးဒေတာများကို အောက်ပါ ရည်ရွယ်ချက်များအတွက် လုပ်ဆောင်ပါသည်−\n\n• သင့်အတွက် အထူးပြင်ဆင်ထားသော ထိုးထွင်းသိမြင်မှုများနှင့် အကြံပြုချက်များ ပေးရန်\n• ကျွန်ုပ်တို့၏ ဝန်ဆောင်မှုများနှင့် AI algorithm များကို ပိုမိုကောင်းမွန်အောင် ပြုလုပ်ရန်\n• အစီရင်ခံစာများနှင့် ခွဲခြမ်းစိတ်ဖြာမှုများ ထုတ်ပေးရန်\n• လုံခြုံရေးကို သေချာစေပြီး လိမ်လည်မှုများကို ကာကွယ်ရန်\n\nဒေတာလုပ်ဆောင်မှုအားလုံးသည် ကျွန်ုပ်တို့၏ ကိုယ်ရေးအချက်အလက်မူဝါဒနှင့် ကိုက်ညီပါသည်။',
      'termsIntellectualPropertyTitle': '၈။ ဉာဏပစ္စည်းပိုင်ဆိုင်မှု',
      'termsIntellectualPropertyBody': 'အက်ပ်၏ အကြောင်းအရာ၊ ဝန်ဆောင်မှုများနှင့် လုပ်ဆောင်နိုင်စွမ်းအားလုံးသည် Toe Pwar ပိုင်ဆိုင်ပြီး မူပိုင်ခွင့်၊ ကုန်အမှတ်တံဆိပ်နှင့် အခြားဥပဒေများဖြင့် ကာကွယ်ထားပါသည်။ သင်သည် အောက်ပါအရာများကို မပြုလုပ်ရပါ−\n\n• ကျွန်ုပ်တို့၏ အကြောင်းအရာများကို ကူးယူခြင်း၊ ပြင်ဆင်ခြင်း သို့မဟုတ် ဖြန့်ဝေခြင်း\n• Reverse engineer ပြုလုပ်ခြင်း သို့မဟုတ် source code ကို ထုတ်ယူရန် ကြိုးစားခြင်း\n• ကျွန်ုပ်တို့၏ ကုန်အမှတ်တံဆိပ်များကို ခွင့်ပြုချက်မရှိဘဲ အသုံးပြုခြင်း',
      'termsLimitationLiabilityTitle': '၉။ တာဝန်ခံမှု ကန့်သတ်ချက်',
      'termsLimitationLiabilityBody': 'Toe Pwar ကို အာမခံချက်မရှိဘဲ "ရှိသည့်အတိုင်း" ပေးအပ်ထားပါသည်။ ကျွန်ုပ်တို့သည် အောက်ပါအရာများအတွက် တာဝန်မယူပါ−\n\n• ဤအက်ပ်ကို အသုံးပြု၍ ချမှတ်သော ငွေကြေးဆိုင်ရာ ဆုံးဖြတ်ချက်များ\n• ဒေတာဆုံးရှုံးမှု သို့မဟုတ် ဝန်ဆောင်မှု အနှောင့်အယှက်များ\n• သွယ်ဝိုက်သော သို့မဟုတ် ဆက်စပ်ဆုံးရှုံးမှုများ\n• တတိယပါတီ၏ လုပ်ဆောင်ချက်များ သို့မဟုတ် အကြောင်းအရာများ',
      'termsTerminationTitle': '၁၀။ ရပ်ဆိုင်းခြင်း',
      'termsTerminationBody': 'ကျွန်ုပ်တို့တွင် အောက်ပါအခွင့်အရေးများ ရှိပါသည်−\n\n• စည်းကမ်းချိုးဖောက်မှုများအတွက် သင့်အကောင့်ကို ခေတ္တရပ်ဆိုင်း သို့မဟုတ် ရပ်ဆိုင်းရန်\n• ဝန်ဆောင်မှုများကို အချိန်မရွေး ပြင်ဆင်ရန် သို့မဟုတ် ရပ်ဆိုင်းရန်\n• ဤစည်းကမ်းချက်များကို ချိုးဖောက်သော အကြောင်းအရာများကို ဖယ်ရှားရန်\n\nသင်သည် အက်ပ်ဆက်တင်များမှတစ်ဆင့် သင့်အကောင့်ကို အချိန်မရွေး ဖျက်နိုင်ပါသည်။',
      'termsChangesTitle': '၁၁။ စည်းကမ်းချက်များ ပြောင်းလဲမှု',
      'termsChangesBody': 'ကျွန်ုပ်တို့သည် ဤစည်းမျဉ်းစည်းကမ်းများကို အချိန်အခါအလိုက် မွမ်းမံနိုင်ပါသည်။ ပြောင်းလဲမှုများပြီးနောက် ဤအက်ပ်ကို ဆက်လက်အသုံးပြုခြင်းသည် စည်းကမ်းချက်အသစ်များကို လက်ခံကြောင်း ဆိုလိုပါသည်။ သိသာထင်ရှားသော ပြောင်းလဲမှုများကို အသုံးပြုသူများအား အသိပေးပါမည်။',
      'termsContactInfoTitle': '၁၂။ ဆက်သွယ်ရန် အချက်အလက်',
      'termsContactInfoBody': 'ဤစည်းမျဉ်းစည်းကမ်းများနှင့်ပတ်သက်၍ မေးခွန်းများရှိပါက ကျေးဇူးပြု၍ အောက်ပါလိပ်စာများမှတစ်ဆင့် ကျွန်ုပ်တို့ထံ ဆက်သွယ်ပါ−\n\nအီးမေးလ်− toepwarai@gmail.com\nဝက်ဘ်ဆိုက်− www.toepwar.com',
      'termsAcceptanceNotice': 'Toe Pwar ကို အသုံးပြုခြင်းဖြင့် သင်သည် ဤစည်းမျဉ်းစည်းကမ်းများကို လက်ခံသဘောတူပါသည်',
      'noBrowserFoundMessage': 'ဘရောင်ဇာ မတွေ့ပါ။ ကျေးဇူးပြု၍ ဤလိပ်စာကို ကိုယ်တိုင်သွားရောက်ကြည့်ရှုပါ−',
      'copyLabel': 'ကူးယူရန်',
      'forceUpdateTitle': 'အပ်ဒိတ်လုပ်ချိန် ရောက်ပါပြီ',
      'forceUpdateDefaultMessage': 'ဗားရှင်းအသစ် ရရှိနိုင်ပါပြီ။ ဤအက်ပ်ကို ဆက်လက်အသုံးပြုရန် ကျေးဇူးပြု၍ အပ်ဒိတ်လုပ်ပါ။',
      'whatsNewInVersion': 'အသစ်ပါဝင်လာသည်များ − ဗားရှင်း',
      'whatsNewLabel': 'အသစ်ပါဝင်လာသည်များ',
      'youHaveVersion': 'သင့်တွင်ရှိသည်',
      'updateNowButton': 'ယခုပင် အပ်ဒိတ်လုပ်ပါ',
      'updateSafetyNotice': 'သင့်မှတ်တမ်းများသည် စက်ပေါ်တွင်သာ ရှိနေပါမည် — အပ်ဒိတ်လုပ်ခြင်းကြောင့် မည်သည့်အရာမျှ မပျောက်ဆုံးပါ။',

      // Localization sweep — settings screens batch
      'passwordStrengthWeak': 'အားနည်း',
      'passwordStrengthFair': 'ပျမ်းမျှ',
      'passwordStrengthGood': 'ကောင်း',
      'passwordStrengthStrong': 'အားကောင်း',
      'failedToChangePassword': 'စကားဝှက် ပြောင်းလဲခြင်း မအောင်မြင်ပါ',
      'errorOccurred': 'အမှားအယွင်း ဖြစ်ပွားခဲ့သည်:',
      'passwordChangeSignOutNotice': 'သင့်စကားဝှက်ကို ပြောင်းလဲခြင်းသည် အခြားစက်ပစ္စည်းများမှ အကောင့်ထွက်စေပါမည်။ သင့်ငွေစာရင်းများနှင့် ဘတ်ဂျက်များကို မထိခိုက်ပါ။',
      'defaultCurrencyUpdatedTo': 'မူရင်းငွေကြေးအမျိုးအစားကို ပြောင်းလဲပြီးပါပြီ -',
      'failedToUpdateCurrency': 'ငွေကြေးအမျိုးအစား ပြောင်းလဲခြင်း မအောင်မြင်ပါ',
      'howCurrenciesWorkHere': 'ဤနေရာတွင် ငွေကြေးအမျိုးအစားများ အလုပ်လုပ်ပုံ',
      'accountDeletedSuccessfully': 'အကောင့်ကို အောင်မြင်စွာ ဖျက်ပြီးပါပြီ',
      'failedToDeleteAccount': 'အကောင့် ဖျက်ခြင်း မအောင်မြင်ပါ',
      'ratingHelper1': 'စိတ်မကောင်းပါဘူး — အောက်တွင် ဘာမှားယွင်းခဲ့လဲ ပြောပြပါ။',
      'ratingHelper2': 'ကျေးဇူးတင်ပါတယ် — ဘာတွေပိုကောင်းအောင် လုပ်နိုင်မလဲ?',
      'ratingHelper3': 'သိရတာ ဝမ်းသာပါတယ်။ ဘာတွေဖြည့်စွက်ရင် အကောင်းဆုံးဖြစ်မလဲ?',
      'ratingHelper4': 'နှစ်သက်တာ ဝမ်းသာပါတယ် — ပြင်ဆင်စရာ တစ်ခုခုရှိသေးလား?',
      'ratingHelper5': 'အံ့ဖွယ်ပါပဲ! နှစ်သက်မှုအတွက် ကျေးဇူးတင်ပါတယ်။',
      'ratingHelperDefault': 'သင့်အတွေ့အကြုံကို အဆင့်သတ်မှတ်ရန် ကြယ်ကို နှိပ်ပါ',
      'charCountMinimumSuffix': '/၁၀ အနည်းဆုံး',
      'languageChangedToEnglish': 'ဘာသာစကားကို အင်္ဂလိပ်သို့ ပြောင်းလဲပြီးပါပြီ',
      'languageChangedToBurmese': 'ဘာသာစကားကို မြန်မာသို့ပြောင်းလဲပြီးပါပြီ',
      'languageSettingsTitle': 'ဘာသာစကားဆက်တင်များ',
      'selectLanguageLabel': 'ဘာသာစကားရွေးချယ်ပါ',
      'languageRestartNotice': 'ဘာသာစကားအသစ်ကိုအသုံးပြုရန် အက်ပ်ကိုပြန်လည်စတင်ပါမည်',
      'failedToUpdatePreference': 'ဆက်တင် ပြောင်းလဲခြင်း မအောင်မြင်ပါ',
      'monthlyInsightsTitle': 'လစဉ် သုံးသပ်ချက်များ',
      'monthlyInsightsDesc': 'သင့်လစဉ်သုံးသပ်ချက်များ အသင့်ဖြစ်သောအခါ',
      'defaultUserName': 'အသုံးပြုသူ',
      'premiumMemberLabel': 'ပရီမီယံ အသင်းဝင်',
      'freePlanLabel': 'အခမဲ့ အစီအစဉ်',
      'currentLanguageName': 'မြန်မာ',
      'appVersion': 'ဗားရှင်း ၁.၀.၀',
      'viewOurPrivacyPolicy': 'ကျွန်ုပ်တို့၏ ကိုယ်ရေးအချက်အလက်မူဝါဒကို ကြည့်ရန်',
      'viewTermsAndConditions': 'စည်းကမ်းသတ်မှတ်ချက်များကို ကြည့်ရန်',
      'appDescription': 'တိုးပွားသည် AI နည်းပညာဖြင့် သုံးသပ်ချက်များနှင့် ဘတ်ဂျက်ခြေရာခံနိုင်သော သင့်ကိုယ်ပိုင် ငွေကြေးစီမံခန့်ခွဲမှု အက်ပ်လီကေးရှင်း ဖြစ်ပါသည်။',
      'copyrightNotice': '© ၂၀၂၅ တိုးပွား။ မူပိုင်ခွင့်အားလုံး ရယူထားသည်။',

      // Localization sweep — home/ai/insights/reports/charts/notifications/subscription batch
      'spendingPace': 'အသုံးစရိတ် အရှိန်',
      'insight': 'သုံးသပ်ချက်',
      'eachCurrencyOwnBalanceNote': 'တစ်ခုစီက သီးခြားလက်ကျန်ရှိပြီး၊ သင်မသိဘဲ ငွေကြေးပြောင်းလဲမှု မရှိပါ။',
      'errorLoadCurrencyBalances': 'ငွေကြေးလက်ကျန်များ ဖော်ပြရန် မအောင်မြင်ပါ:',
      'suggestionCurrentBalance': 'ကျွန်ုပ်၏ လက်ရှိလက်ကျန်ငွေ မည်မျှရှိပါသလဲ?',
      'suggestionSpendThisMonth': 'ဒီလ ကျွန်ုပ် မည်မျှ အသုံးစရိတ်သုံးခဲ့ပါသလဲ?',
      'suggestionTopSpendingCategories': 'ကျွန်ုပ်၏ အများဆုံးအသုံးစရိတ်သုံးသည့် အမျိုးအစားများက ဘာတွေလဲ?',
      'suggestionMoneySavingTips': 'ငွေကြေးချွေတာနည်းများ ပြောပြပါ',
      'suggestionIncomeVsExpenses': 'ကျွန်ုပ်၏ ဝင်ငွေနှင့် အသုံးစရိတ်ကို နှိုင်းယှဉ်ပြပါ',
      'suggestionSpendOnFood': 'အစားအသောက်အတွက် မည်မျှ အသုံးစရိတ်သုံးခဲ့ပါသလဲ?',
      'answers': 'အဖြေများ:',
      'clearThisConversation': 'ဤစကားဝိုင်းကို ရှင်းလင်းမလား?',
      'chatMessageSingular': 'စာတို',
      'chatMessagePlural': 'စာတိုများ',
      'clearChatConsequence': 'နှင့် အဖြေများ အပြီးတိုင် ပျောက်သွားပါမည်။ သင့်ငွေစာရင်းများ၊ ဘတ်ဂျက်များနှင့် ရည်မှန်းချက်များကို ထိခိုက်မှာ မဟုတ်ပါ — အကူအညီပေးသူက နောက်တစ်ကြိမ် အသစ်ပြန်ဖတ်ပါလိမ့်မည်။',
      'keepIt': 'ဆက်ထားမည်',
      'fallbackQuestionTighterMonth': 'ဘာကြောင့် ဒီလက ပိုတင်းကျပ်နေတာလဲ?',
      'assistantAnswersFromRecords': 'အကူအညီပေးသူသည် သင့်ကိုယ်ပိုင်မှတ်တမ်းများမှ အဖြေပေးပါသည်။',
      'spendingPaceCategoryComparisons': 'အသုံးစရိတ်အရှိန်၊ အမျိုးအစားနှိုင်းယှဉ်မှု၊ ဝယ်ယူမှုတစ်ခု သင့်တော်မသင့်တော်၊ ထပ်ခါထပ်ခါဖြစ်နေသည်များ — သင့်ကိုယ်ပိုင်ကိန်းဂဏန်းများနှင့်သာ၊ အထွေထွေအကြံပြုချက်မဟုတ်ပါ။',
      'tryOneMonthFree': 'တစ်လအခမဲ့ စမ်းသုံးကြည့်ပါ',
      'noCardRequiredCancelAnyTime': 'ကတ်မလိုအပ်ပါ · အချိန်မရွေး ပယ်ဖျက်နိုင်ပါသည်',
      'errorLoadingTransactions': 'ငွေစာရင်းများ ဖော်ပြရန် အမှားရှိပါသည်:',
      'moneyInLabel': 'ဝင်ငွေ ·',
      'moneyOutLabel': 'ထွက်ငွေ ·',
      'avgPerEntry': 'ပျမ်းမျှ / ခု',
      'spentLabel': 'သုံးစွဲပြီး',
      'biggestOutflowCategoryMiddle': 'သည် သင်၏ အကြီးဆုံး ထွက်ငွေအမျိုးအစား ဖြစ်ပါသည် —',
      'biggestOutflowCategorySuffix': 'ဤကာလအတွင်း အသုံးစရိတ်၏။',
      'biggestIncomeSourceMiddle': 'သည် သင်၏ အကြီးဆုံး ဝင်ငွေအရင်းအမြစ် ဖြစ်ပါသည် —',
      'biggestIncomeSourceSuffix': 'ဤကာလအတွင်း ဝင်ငွေ၏။',
      'regenerate': 'ပြန်လည်ထုတ်လုပ်ရန်',
      'threeInsightsWaiting': 'သုံးသပ်ချက် သုံးခု စောင့်နေပါသည်။ ပရီမီယံသည် သင့်ငွေစာရင်းများကို အပတ်စဉ် ဖတ်ပေးပါသည် — ကိုယ်တိုင်လုပ်ဆောင်စရာ မလိုပါ။',
      'swipeNotificationToDelete': 'အကြောင်းကြားစာကို ဖျက်ရန် ဘေးသို့ ပွတ်ဆွဲပါ',
      'justNow': 'အခုလေးတင်',
      'minutesAgoSuffix': ' မိနစ်က',
      'hoursAgoSuffix': ' နာရီက',
      'daysAgoSuffix': ' ရက်က',
      'errorDownloadReport': 'အစီရင်ခံစာ ဒေါင်းလုဒ်လုပ်ရန် မအောင်မြင်ပါ:',
      'exportThisReport': 'ဤအစီရင်ခံစာကို ထုတ်ယူရန်',
      'chartsCategoryTablesDailyAverages': 'ဇယားကားချပ်များ၊ အမျိုးအစား ဇယားများနှင့် နေ့စဉ်ပျမ်းမျှများ',
      'sendItOn': 'ပို့ဆက်ရန်',
      'samePdfToViberOrEmail': 'PDF အတူတူပါပဲ၊ Viber သို့မဟုတ် အီးမေးလ်သို့ တိုက်ရိုက်ပို့ရန်',
      'ofTotal': 'စုစုပေါင်း၏',
      'txnsAbbrev': 'စာရင်း',
      'welcomeToPremiumCelebration': '🎉 ပရီမီယံသို့ ကြိုဆိုပါတယ်!',
      'oneMonthFreePremiumAccess': 'သင့်တွင် ယခု ၁ လ အခမဲ့ ပရီမီယံအသုံးပြုခွင့် ရရှိပါပြီ။ လုပ်ဆောင်ချက်အားလုံးကို ခံစားလိုက်ပါ!',
      'letsGo': 'စလိုက်ကြရအောင်!',
      'couldNotClaimFreeTrial': 'အခမဲ့စမ်းသပ်ကာလကို ရယူ၍ မရပါ။',
      'oneMonthFreeCaps': 'တစ်လ အခမဲ့',
      'letAppReadYourMoney': 'အက်ပ်ကို သင့်ငွေကြေးအတွက် ဖတ်ခိုင်းလိုက်ပါ။',
      'weeklyInsightsReceiptScanningVoiceAiBudgets': 'အပတ်စဉ်သုံးသပ်ချက်များ၊ ဘောက်ချာစကင်ဖတ်ခြင်း၊ အသံဖြင့်ထည့်သွင်းခြင်းနှင့် AI ဘတ်ဂျက်များ — သင့်ကိုယ်ပိုင် ငွေစာရင်းများအပေါ်တွင်။',
      'claiming': 'ရယူနေသည်…',
      'claimOneMonthFree': '၁ လ အခမဲ့ ရယူရန်',
      'noCardRequiredThenContactUs': 'ကတ်မလိုအပ်ပါ · ဆက်လက်လုပ်ဆောင်ရန် ကျွန်ုပ်တို့ကို ဆက်သွယ်ပါ',

      // Localization sweep — budgets/goals batch
      'startsOnPrefix': 'စတင်မည်',
      'startsInDaysPrefix': 'စတင်ရန် ကျန်',
      'daysSuffix': 'ရက်',
      'endedDaysAgoPrefix': 'ပြီးဆုံးခဲ့သည်',
      'daysRemainingSuffix': 'ရက် ကျန်ရှိသည်',
      'budgetWillStartOnPrefix': 'ဤဘတ်ဂျက်သည်',
      'noSpendingTrackedYetSuffix': ' တွင် စတင်မည်ဖြစ်ပြီး ယခုအထိ သုံးစွဲမှု ခြေရာခံမထားသေးပါ။',
      'budgetEndedOnPrefix': 'ဤဘတ်ဂျက်သည် ပြီးဆုံးခဲ့သည်',
      'onlyTransactionsInPrefix': 'ငွေကြေး',
      'willAffectThisBudgetSuffix': 'ဖြင့်ပြုလုပ်သော ငွေစာရင်းသွင်းမှုများသာ ဤဘတ်ဂျက်ကို သက်ရောက်ပါမည်',
      'fixedForThisBudget': 'ဤဘတ်ဂျက်အတွက် သော့ခတ်ထားသည်',
      'periodCurrencyLockedNotice': 'ဘတ်ဂျက်တွင် သုံးစွဲမှု စတင်ရှိလာပြီးနောက် ကာလနှင့် ငွေကြေးအမျိုးအစားကို ပြောင်းလဲ၍ မရတော့ပါ — ဘတ်ဂျက်အသစ် ဖန်တီးပါ။',
      'capAlreadySpentTitle': 'ဤကန့်သတ်ပမာဏကို သုံးပြီးဖြစ်သည်',
      'alreadyHaveMoreSpent': 'ကန့်သတ်ပမာဏအသစ်ထက် ပိုသုံးထားပြီးဖြစ်သည်။',
      'alreadyHasMoreSpent': 'ကန့်သတ်ပမာဏအသစ်ထက် ပိုသုံးထားပြီးဖြစ်သည်။',
      'totalCapLabel': 'စုစုပေါင်း ကန့်သတ်ပမာဏ',
      'analyzingYourPrefix': 'သင့်',
      'spendingPatternsSuffix': 'သုံးစွဲမှု ပုံစံများကို ခွဲခြမ်းစိတ်ဖြာနေသည်...',
      'genericErrorOccurred': 'အမှားတစ်ခု ဖြစ်ပွားခဲ့သည်',
      'savedTowardsGoals': 'ရည်မှန်းချက်များအတွက် စုဆောင်းထားသည်',
      'failedToLoadBalances': 'လက်ကျန်ငွေများ ဖော်ပြရန် မအောင်မြင်ပါ:',
      'dueDatePrefix': 'သတ်မှတ်ရက်',
      'operationFailed': 'လုပ်ဆောင်မှု မအောင်မြင်ပါ',
      'moneyHeldNotSpendable': 'ဤရည်မှန်းချက်အတွက် ထားရှိသော ငွေကို အသုံးမပြုနိုင်ပါ',
      'heldFundsExplanation': '၎င်းသည် သင့်အသုံးပြုနိုင်သော လက်ကျန်ငွေမှ နုတ်ယူထားခြင်းဖြစ်သောကြောင့် အခြားနေရာတွင် ကတိပြုထားသော ငွေကို ဒက်ရှ်ဘုတ်က ဘယ်တော့မှ ထပ်ပြီး မပေးတော့ပါ။',
    }
  };

  String translate(String key) {
    return _localizedValues[locale.languageCode]?[key] ?? key;
  }

  String get toePwar => translate('toePwar');
  String get welcomeBack => translate('welcomeBack');
  String get totalBalance => translate('totalBalance');
  String get available => translate('available');
  String get allocatedToGoals => translate('allocatedToGoals');
  String get inflow => translate('inflow');
  String get outflow => translate('outflow');
  String get aiAssistant => translate('aiAssistant');
  String get getPersonalizedInsights => translate('getPersonalizedInsights');
  String get aiInsights => translate('aiInsights');
  String get viewComprehensiveAnalysis => translate('viewComprehensiveAnalysis');
  String get recentTransactions => translate('recentTransactions');
  String get seeMore => translate('seeMore');
  String get noTransactions => translate('noTransactions');
  String get tapToAddFirst => translate('tapToAddFirst');
  String get addTransaction => translate('addTransaction');
  String get manualEntry => translate('manualEntry');
  String get typeTransactionDetails => translate('typeTransactionDetails');
  String get voiceInput => translate('voiceInput');
  String get speakYourTransaction => translate('speakYourTransaction');
  String get scanReceipt => translate('scanReceipt');
  String get takeUploadPhoto => translate('takeUploadPhoto');
  String get premium => translate('premium');
  String get transactionAdded => translate('transactionAdded');
  String get transactionUpdated => translate('transactionUpdated');
  String get transactionDeleted => translate('transactionDeleted');
  String get dashboard => translate('dashboard');
  String get autoCreated => translate('autoCreated');
  String get viewAllCurrencies => translate('viewAllCurrencies');
  String get allCurrencyBalances => translate('allCurrencyBalances');
  String get defaultBalance => translate('default');



  // Drawer Navigation Getters
  String get drawerWelcome => translate('drawerWelcome');
  String get drawerLogout => translate('drawerLogout');
  String get dialogCancel => translate('dialogCancel');
  String get dialogLogoutConfirm => translate('dialogLogoutConfirm');
  String get transactions => translate('transactions');
  String get goals => translate('goals');
  String get budgets => translate('budgets');
  String get inflowAnalytics => translate('inflowAnalytics');
  String get outflowAnalytics => translate('outflowAnalytics');
  String get financialReports => translate('financialReports');
  String get settings => translate('settings');
  String get expiresOn => translate('expiresOn');

  // Add Transaction Screen Getters
  String get addTransactionTitle => translate('addTransactionTitle');
  String get amountLabel => translate('amountLabel');
  String get currency => translate('currency');
  String get convertCurrency => translate('convertCurrency');
  String get current => translate('current');
  String get selectTargetCurrency => translate('selectTargetCurrency');
  String get convertTo => translate('convertTo');
  String get exchangeRate => translate('exchangeRate');
  String get convert => translate('convert');
  String get dateLabel => translate('dateLabel');
  String get categoryLabel => translate('categoryLabel');
  String get selectMainCategoryHint => translate('selectMainCategoryHint');
  String get selectSubCategoryHint => translate('selectSubCategoryHint');
  String get descriptionLabel => translate('descriptionLabel');
  String get descriptionHint => translate('descriptionHint');
  String get addOutflowButton => translate('addOutflowButton');
  String get addInflowButton => translate('addInflowButton');
  String get validationAmountRequired => translate('validationAmountRequired');
  String get validationAmountInvalid => translate('validationAmountInvalid');
  String get validationAmountPositive => translate('validationAmountPositive');
  String get validationMainCategoryRequired => translate('validationMainCategoryRequired');
  String get validationSubCategoryRequired => translate('validationSubCategoryRequired');
  String get recurringTransaction => translate('recurringTransaction');
  String get recurringTransactionDes => translate('recurringTransactionDes');
  String get repeatFrequency => translate('repeatFrequency');
  String get dayOfMonth => translate('dayOfMonth');
  String get daily => translate('daily');
  String get weekly => translate('weekly');
  String get monthly => translate('monthly');
  String get annually => translate('annually');
  String get dailyDes => translate('dailyDes');
  String get weeklyDes => translate('weeklyDes');
  String get monthlyDes => translate('monthlyDes');
  String get annuallyDes => translate('annuallyDes');
  String get endDate => translate('endDate');
  String get next5Occurrences => translate('next5Occurrences');
  String get enterAmountBeforeConverting => translate('enterAmountBeforeConverting');
  String get preview => translate('preview');
  String get pleaseFillAllFields => translate('pleaseFillAllFields');
  String get pleaseEnterAmountFirst => translate('pleaseEnterAmountFirst');
  String get pleaseEnterValidExchangeRate => translate('pleaseEnterValidExchangeRate');
  String get pleaseEnterValidAmount => translate('pleaseEnterValidAmount');
  String get neverEnds => translate('neverEnds');





  // Edit Transaction Screen Getters
  String get editTransactionTitle => translate('editTransactionTitle');
  String get deleteTransactionTitle => translate('deleteTransactionTitle');
  String get deleteConfirmMessage => translate('deleteConfirmMessage');
  String get autoCreatedTransactionTitle => translate('autoCreatedTransactionTitle');
  String get autoCreatedDescriptionRecurring => translate('autoCreatedDescriptionRecurring');
  String get autoCreatedDescriptionDisabled => translate('autoCreatedDescriptionDisabled');
  String get stopFutureAutoCreation => translate('stopFutureAutoCreation');
  String get viewParentTransaction => translate('viewParentTransaction');
  String get stopRecurringDialogTitle => translate('stopRecurringDialogTitle');
  String get stopRecurringDialogContent => translate('stopRecurringDialogContent');
  String get stopRecurringDialogInfo => translate('stopRecurringDialogInfo');
  String get stopRecurringButton => translate('stopRecurringButton');
  String get stoppingRecurrence => translate('stoppingRecurrence');
  String get pleaseWait => translate('pleaseWait');
  String get successTitle => translate('successTitle');
  String get successAutoCreationStopped => translate('successAutoCreationStopped');
  String get errorTitle => translate('errorTitle');
  String get errorLoadParentFailed => translate('errorLoadParentFailed');
  String get updateTransactionButton => translate('updateTransactionButton');
  String get selectCurrencyT => translate('selectCurrencyT');
  String get recurringScheduleStopped => translate('recurringScheduleStopped');
  String get recurringSettingsStopDes => translate('recurringSettingsStopDes');
  String get dismiss => translate('dismiss');


  // Image Input Screen Getters
  String get imageInputTitle => translate('imageInputTitle');
  String get premiumFeatureTitle => translate('premiumFeatureTitle');
  String get premiumFeatureUpgradeDescImg => translate('premiumFeatureUpgradeDescImg');
  String get upgradeNowButton => translate('upgradeNowButton');
  String get tapToAddImagePlaceholder => translate('tapToAddImagePlaceholder');
  String get cameraOrGalleryPlaceholder => translate('cameraOrGalleryPlaceholder');
  String get chooseDifferentImageButton => translate('chooseDifferentImageButton');
  String get analyzingReceipt => translate('analyzingReceipt');
  String get extractedTransactionTitle => translate('extractedTransactionTitle');
  String get dataLabelType => translate('dataLabelType');
  String get dataLabelAmount => translate('dataLabelAmount');
  String get dataLabelCategory => translate('dataLabelCategory');
  String get dataLabelDate => translate('dataLabelDate');
  String get dataLabelDescription => translate('dataLabelDescription');
  String get aiReasoningLabel => translate('aiReasoningLabel');
  String get confidenceLabel => translate('confidenceLabel');
  String get saveTransactionButton => translate('saveTransactionButton');
  String get errorCaptureImage => translate('errorCaptureImage');
  String get errorPickImage => translate('errorPickImage');
  String get chooseImageSourceModalTitle => translate('chooseImageSourceModalTitle');
  String get cameraListTileTitle => translate('cameraListTileTitle');
  String get cameraListTileSubtitle => translate('cameraListTileSubtitle');
  String get galleryListTileTitle => translate('galleryListTileTitle');
  String get galleryListTileSubtitle => translate('galleryListTileSubtitle');

  // Voice Input Screen Getters
  String get voiceInputTitle => translate('voiceInputTitle'); // Used for the screen title
  String get premiumFeatureUpgradeDescVoice => translate('premiumFeatureUpgradeDescVoice');
  String get recordingStatus => translate('recordingStatus');
  String get tapToRecordStatus => translate('tapToRecordStatus');
  String get transcriptionTitle => translate('transcriptionTitle');
  String get errorStartRecording => translate('errorStartRecording');
  String get errorStopRecording => translate('errorStopRecording');
  String get analyzingTransactions => translate('analyzingTransactions');


  // Transactions List Screen Getters
  String get allTransactionsTitle => translate('allTransactionsTitle');
  String get filtersSectionTitle => translate('filtersSectionTitle');
  String get transactionTypeFilterLabel => translate('transactionTypeFilterLabel');
  String get filterChipAll => translate('filterChipAll');
  String get dateRangeFilterLabel => translate('dateRangeFilterLabel');
  String get selectDateRangeButton => translate('selectDateRangeButton');
  String get loadingMoreIndicator => translate('loadingMoreIndicator');
  String get emptyStateTitle => translate('emptyStateTitle');
  String get emptyStateSubtitle => translate('emptyStateSubtitle');
  String get clearAllFiltersButton => translate('clearAllFiltersButton');
  String get clearDateFilterTooltip => translate('clearDateFilterTooltip');
  String get addTransactionFabTooltip => translate('addTransactionFabTooltip');
  String get currencyFilter => translate('currencyFilter');


  //Goals screen getters
  String get financialGoals => translate('financialGoals');
  String get goalsSummary => translate('goalsSummary');
  String get active => translate('active');
  String get achieved => translate('achieved');
  String get total => translate('total');
  String get byCurrency => translate('byCurrency');
  String get availableBalance => translate('availableBalance');
  String get forGoals => translate('forGoals');
  String get availableForGoals => translate('availableForGoals');
  String get selected => translate('selected');
  String get goalCreatedSuccessfully => translate('goalCreatedSuccessfully');
  String get goalDeletedSuccessfully => translate('goalDeletedSuccessfully');
  String get noGoalsYet => translate('noGoalsYet');
  String get createGoalGetStarted => translate('createGoalGetStarted');




  //Add goal screen getters
  String get createNewGoal => translate('createNewGoal');
  String get goalName => translate('goalName');
  String get goalType => translate('goalType');
  String get targetAmount => translate('targetAmount');
  String get initialContribution => translate('initialContribution');
  String get targetDate => translate('targetDate');
  String get createGoal => translate('createGoal');
  String get failedToCreateGoal => translate('failedToCreateGoal');
  String get pleaseEnterAGoalName => translate('pleaseEnterAGoalName');
  String get pleaseEnterTargetAmount => translate('pleaseEnterTargetAmount');
  String get pleaseEnterAValidAmount => translate('pleaseEnterAValidAmount');
  String get insufficientBalance => translate('insufficientBalance');
  String get selectTargetDate => translate('selectTargetDate');
  String get egEmergencyFund => translate('egEmergencyFund');


  //Goal detail screen getters
  String get fundsAddedSuccessfully => translate('fundsAddedSuccessfully');
  String get fundsWithdrawnSuccessfully => translate('fundsWithdrawnSuccessfully');
  String get manageFunds => translate('manageFunds');
  String get currentProgress => translate('currentProgress');
  String get currentAmount => translate('currentAmount');
  String get remaining => translate('remaining');
  String get targetDateDetail => translate('targetDateDetail');
  String get created => translate('created');
  String get withdraw => translate('withdraw');
  String get add => translate('add');
  String get editGoal => translate('editGoal');
  String get enterAGoalName => translate('enterAGoalName');
  String get goalUpdatedSuccessfully => translate('goalUpdatedSuccessfully');
  String get failedToUpdateGoal => translate('failedToUpdateGoal');
  String get save => translate('save');
  String get deleteGoal => translate('deleteGoal');
  String get deleteGoalConfirmation => translate('deleteGoalConfirmation');
  String get delete => translate('delete');
  String get failedToDeleteGoal => translate('failedToDeleteGoal');
  String get goalDetails => translate('goalDetails');
  String get goalInformation => translate('goalInformation');


  //budgets screen getter
  String get budgetCreatedSuccessfully => translate('budgetCreatedSuccessfully');
  String get budgetDeletedSuccessfully => translate('budgetDeletedSuccessfully');
  String get budgetSummary => translate('budgetSummary');
  String get exceeded => translate('exceeded');
  String get allCurrencies => translate('allCurrencies');
  String get createNewBudget => translate('createNewBudget');
  String get upcoming => translate('upcoming');
  String get exceededCap => translate('exceededCap');
  String get completed => translate('completed');
  String get activeCap => translate('activeCap');
  String get auto => translate('auto');
  String get noBudgetsYet => translate('noBudgetsYet');
  String get createYourFirstBudget => translate('createYourFirstBudget');



  //create budget screen getters
  String get categoryAlreadyExists => translate('categoryAlreadyExists');
  String get selectEndDate => translate('selectEndDate');
  String get addOneCategoryBudget => translate('addOneCategoryBudget');
  String get failedToCreateBudget => translate('failedToCreateBudget');
  String get createBudget => translate('createBudget');
  String get selectCurrency => translate('selectCurrency');
  String get pleaseSelectCurrency => translate('pleaseSelectCurrency');
  String get aiFeatures => translate('aiFeatures');
  String get getAiPoweredBudgetSuggestions => translate('getAiPoweredBudgetSuggestions');
  String get tapToUseAiBudgetSuggestions => translate('tapToUseAiBudgetSuggestions');
  String get context => translate('context');
  String get addContext => translate('addContext');
  String get generateAiBudget => translate('generateAiBudget');
  String get aiWillAnalyzeAndSuggestBudgets => translate('aiWillAnalyzeAndSuggestBudgets');
  String get budgetName => translate('budgetName');
  String get enterBudgetName => translate('enterBudgetName');
  String get budgetPeriod => translate('budgetPeriod');
  String get week => translate('week');
  String get month => translate('month');
  String get year => translate('year');
  String get custom => translate('custom');
  String get startDate => translate('startDate');
  String get endDateNoOp => translate('endDateNoOp');
  String get autoCreateNextBudget => translate('autoCreateNextBudget');
  String get automaticallyCreateNewBudget => translate('automaticallyCreateNewBudget');
  String get enableAutoCreate => translate('enableAutoCreate');
  String get chooseHowToCreateNextBudget => translate('chooseHowToCreateNextBudget');
  String get useCurrentCategories => translate('useCurrentCategories');
  String get keepTheSameBudgetAmounts => translate('keepTheSameBudgetAmounts');
  String get aiOptimizedBudget => translate('aiOptimizedBudget');
  String get aiAnalyzesSpendingAndSuggestsAmounts => translate('aiAnalyzesSpendingAndSuggestsAmounts');
  String get categoryBudgets => translate('categoryBudgets');
  String get noCategoriesAddedYet => translate('noCategoriesAddedYet');
  String get totalBudget => translate('totalBudget');
  String get addCategoryBudget => translate('addCategoryBudget');
  String get editCategoryBudget => translate('editCategoryBudget');
  String get subCategory => translate('subCategory');
  String get allNoFilter => translate('allNoFilter');
  String get budgetAmount => translate('budgetAmount');
  String get enterAmount => translate('enterAmount');
  String get enterValidAmount => translate('enterValidAmount');
  String get notesThisBudget => translate('notesThisBudget');
  String get egMonthlyExpenses => translate('egMonthlyExpenses');
  String get egTravelingHolidaySeason => translate('egTravelingHolidaySeason');




  //edit budget screen getters
  String get budgetUpdatedSuccessfully => translate('budgetUpdatedSuccessfully');
  String get failedToUpdateBudget => translate('failedToUpdateBudget');
  String get editBudget => translate('editBudget');
  String get budgetPeriodC => translate('budgetPeriodC');
  String get period => translate('period');
  String get duration => translate('duration');
  String get currencyC => translate('currencyC');
  String get editingCategoriesRecalculateAlert => translate('editingCategoriesRecalculateAlert');
  String get newTotalBudget => translate('newTotalBudget');
  String get currentTotal => translate('currentTotal');
  String get saveChanges => translate('saveChanges');



  //budget detail screen getters
  String get deleteBudget => translate('deleteBudget');
  String get deleteBudgetAlert => translate('deleteBudgetAlert');
  String get deleted => translate('deleted');
  String get failedToDeleteBudget => translate('failedToDeleteBudget');
  String get startsIn => translate('startsIn');
  String get ended => translate('ended');
  String get daysRemaining => translate('daysRemaining');
  String get budgetDetails => translate('budgetDetails');
  String get budgetWasAutomaticallyCreatedAi => translate('budgetWasAutomaticallyCreatedAi');
  String get budgetWasAutomaticallyCreatedPrevious => translate('budgetWasAutomaticallyCreatedPrevious');
  String get autoCreateEnabled => translate('autoCreateEnabled');
  String get nextBudgetWillBeAiOptimized => translate('nextBudgetWillBeAiOptimized');
  String get nextBudgetWillUseSameAmounts => translate('nextBudgetWillUseSameAmounts');
  String get budgetExceeded => translate('budgetExceeded');
  String get budgetExceededAlert => translate('budgetExceededAlert');
  String get approachingBudgetLimit => translate('approachingBudgetLimit');
  String get used => translate('used');
  String get categories => translate('categories');
  String get deleting => translate('deleting');
  



  //ai budget suggestion screen getters
  String get analysisSummary => translate('analysisSummary');
  String get transactionsAnalyzed => translate('transactionsAnalyzed');
  String get analysisPeriod => translate('analysisPeriod');
  String get categoriesFound => translate('categoriesFound');
  String get avgMonthlyIncome => translate('avgMonthlyIncome');
  String get avgMonthlyExpenses => translate('avgMonthlyExpenses');
  String get activeGoals => translate('activeGoals');
  String get close => translate('close');
  String get aiBudgetSuggestion => translate('aiBudgetSuggestion');
  String get analysisDetails => translate('analysisDetails');
  String get failedToGenerateSuggestion => translate('failedToGenerateSuggestion');
  String get tryAgain => translate('tryAgain');
  String get dataConfidence => translate('dataConfidence');
  String get highConfidence => translate('highConfidence');
  String get moderateConfidence => translate('moderateConfidence');
  String get lowConfidence => translate('lowConfidence');
  String get yourContext => translate('yourContext');
  String get importantNotes => translate('importantNotes');
  String get suggestedBudgetPlan => translate('suggestedBudgetPlan');
  String get name => translate('name');
  String get aiAnalysis => translate('aiAnalysis');
  String get useThisBudget => translate('useThisBudget');



  //ai chat screen getters
  String get responseStyle => translate('responseStyle');
  String get chooseAiResponses => translate('chooseAiResponses');
  String get thinking => translate('thinking');
  String get financialAdvisor => translate('financialAdvisor');
  String get stopResponse => translate('stopResponse');
  String get changeResponseStyle => translate('changeResponseStyle');
  String get clearHistory => translate('clearHistory');
  String get loadingChatHistory => translate('loadingChatHistory');
  String get upgradeToPremium => translate('upgradeToPremium');
  String get unlockFullCapabilities => translate('unlockFullCapabilities');
  String get upgrade => translate('upgrade');
  String get helloAi => translate('helloAi');
  String get aiChatDes => translate('aiChatDes');
  String get tryAskingMeSomething => translate('tryAskingMeSomething');
  String get aiIsTyping => translate('aiIsTyping');
  String get upgradeToPremiumToChat => translate('upgradeToPremiumToChat');
  String get aiIsResponding => translate('aiIsResponding');
  String get askAboutFinances => translate('askAboutFinances');
  String get clearChatHistory => translate('clearChatHistory');
  String get clearChatHistoryAlert => translate('clearChatHistoryAlert');
  String get clear => translate('clear');
  String get generatingInsights => translate('generatingInsights');
  String get insightsRegeneratedSuccessfully => translate('insightsRegeneratedSuccessfully');
  String get failedToRegenerateInsights => translate('failedToRegenerateInsights');
  String get deepSpendingAnalysis => translate('deepSpendingAnalysis');
  String get personalizedRecommendations => translate('personalizedRecommendations');
  String get financialHealthScore => translate('financialHealthScore');
  String get savingsOpportunities => translate('savingsOpportunities');
  String get budgetOptimizationTips => translate('budgetOptimizationTips');
  String get analyzingYourFinancialData => translate('analyzingYourFinancialData');
  String get thisMayTakeFewSeconds => translate('thisMayTakeFewSeconds');
  String get failedToLoadInsights => translate('failedToLoadInsights');
  String get noInsightsAvailable => translate('noInsightsAvailable');
  String get addTransactionsGoalsToGenerateInsights => translate('addTransactionsGoalsToGenerateInsights');
  String get aiGeneratedInsights => translate('aiGeneratedInsights');
  String get normal => translate('normal');
  String get concise => translate('concise');
  String get detailed => translate('detailed');
  String get balancedResponses => translate('balancedResponses');
  String get briefDirect => translate('briefDirect');
  String get thoroughExplanations => translate('thoroughExplanations');


  //notification screen getters
  String get notifications => translate('notifications');
  String get markedAsRead => translate('markedAsRead');
  String get markAllRead => translate('markAllRead');
  String get notificationDeleted => translate('notificationDeleted');
  String get undo => translate('undo');
  String get noNotificationsYet => translate('noNotificationsYet');
  String get notifyGoalsProgress => translate('notifyGoalsProgress');


  //reports screen getters
  String get selectStartEndDates => translate('selectStartEndDates');
  String get reportDownloadedSuccessfully => translate('reportDownloadedSuccessfully');
  String get open => translate('open');
  String get downloadPDF => translate('downloadPDF');
  String get currencyR => translate('currencyR');
  String get generatingReport => translate('generatingReport');
  String get selectDatesToGenerateReport => translate('selectDatesToGenerateReport');
  String get select => translate('select');
  String get reportPeriod => translate('reportPeriod');
  String get netBalance => translate('netBalance');
  String get income => translate('income');
  String get expenses => translate('expenses');
  String get goalsAllocated => translate('goalsAllocated');
  String get dailyAverages => translate('dailyAverages');
  String get averageDailyIncome => translate('averageDailyIncome');
  String get averageDailyExpenses => translate('averageDailyExpenses');
  String get incomeByCategory => translate('incomeByCategory');
  String get expensesByCategory => translate('expensesByCategory');
  String get goalsProgress => translate('goalsProgress');
  String get multiCurrencyReport => translate('multiCurrencyReport');
  String get overview => translate('overview');
  String get totalTransactions => translate('totalTransactions');
  String get currencies => translate('currencies');
  String get allGoals => translate('allGoals');
  String get avgDailyIncome => translate('avgDailyIncome');
  String get avgDailyExpenses => translate('avgDailyExpenses');
  String get viewCategories => translate('viewCategories');
  String get topIncomeCategories => translate('topIncomeCategories');
  String get topExpenseCategories => translate('topExpenseCategories');
  String get account => translate('account');
  String get editProfile => translate('editProfile');
  String get updateYourName => translate('updateYourName');
  String get profileUpdatedSuccessfully => translate('profileUpdatedSuccessfully');
  String get changePassword => translate('changePassword');
  String get updateYourPassword => translate('updateYourPassword');
  String get passwordChangedSuccessfully => translate('passwordChangedSuccessfully');
  String get language => translate('language');
  String get changeAppLanguage => translate('changeAppLanguage');
  String get changeDefaultCurrency => translate('changeDefaultCurrency');
  String get appearance => translate('appearance');
  String get theme => translate('theme');
  String get themeSystem => translate('themeSystem');
  String get themeLight => translate('themeLight');
  String get themeDark => translate('themeDark');
  String get themeSystemDesc => translate('themeSystemDesc');
  String get themeLightDesc => translate('themeLightDesc');
  String get themeDarkDesc => translate('themeDarkDesc');
  String get notificationSettings => translate('notificationSettings');
  String get manageNotificationPreferences => translate('manageNotificationPreferences');
  String get subscription => translate('subscription');
  String get manageSubscription => translate('manageSubscription');
  String get viewManageSubscription => translate('viewManageSubscription');
  String get unlockPremiumFeatures => translate('unlockPremiumFeatures');
  String get about => translate('about');
  String get aboutToePwar => translate('aboutToePwar');



  //notification settings screen getters
  String get notificationsEnabled => translate('notificationsEnabled');
  String get changeNotificationSettingsDes => translate('changeNotificationSettingsDes');
  String get openSettings => translate('openSettings');
  String get testNotification => translate('testNotification');
  String get testNotificationDes => translate('testNotificationDes');
  String get testNotificationMsg => translate('testNotificationMsg');
  String get resetToDefaults => translate('resetToDefaults');
  String get enableAllNotificationTypes => translate('enableAllNotificationTypes');
  String get notificationPreferencesReset => translate('notificationPreferencesReset');
  String get failedToResetPreferences => translate('failedToResetPreferences');
  String get reset => translate('reset');
  String get resetToDefaultsWQ => translate('resetToDefaultsWQ');
  String get pushNotifications => translate('pushNotifications');
  String get receiveUpdatesAboutFinances => translate('receiveUpdatesAboutFinances');
  String get sendTestNotification => translate('sendTestNotification');
  String get customizeNotificationsReceive => translate('customizeNotificationsReceive');
  String get notificationTypes => translate('notificationTypes');
  String get progressUpdates => translate('progressUpdates');
  String get notifiedMilestones => translate('notifiedMilestones');
  String get milestoneReached => translate('milestoneReached');
  String get thousandSavedTowardsGoal => translate('thousandSavedTowardsGoal');
  String get deadlineApproaching => translate('deadlineApproaching');
  String get reminders => translate('reminders');
  String get goalAchieved => translate('goalAchieved');
  String get celebrate => translate('celebrate');
  String get budgetStarted => translate('budgetStarted');
  String get whenNewBudgetBegins => translate('whenNewBudgetBegins');
  String get periodEndingSoon => translate('periodEndingSoon');
  String get reminderBudgets => translate('reminderBudgets');
  String get budgetThreshold => translate('budgetThreshold');
  String get alertBudget => translate('alertBudget');
  String get whenOverBudgetLimit => translate('whenOverBudgetLimit');
  String get autoCreatedBudget => translate('autoCreatedBudget');
  String get budgetCreatedAutomatically => translate('budgetCreatedAutomatically');
  String get budgetNowActive => translate('budgetNowActive');
  String get whenBudgetBecomesActive => translate('whenBudgetBecomesActive');
  String get largeTransaction => translate('largeTransaction');
  String get alertsLargeExpenses => translate('alertsLargeExpenses');
  String get unusualSpending => translate('unusualSpending');
  String get whenSpendingPatternsChange => translate('whenSpendingPatternsChange');
  String get paymentReminders => translate('paymentReminders');
  String get upcomingPayments => translate('upcomingPayments');
  String get recurringCreated => translate('recurringCreated');
  String get recurringEnded => translate('recurringEnded');
  String get whenRecurringEnds => translate('whenRecurringEnds');
  String get recurringDisabled => translate('recurringDisabled');
  String get whenRecurrenceDisabled => translate('whenRecurrenceDisabled');
  String get whenRecurringTransactionsCreated => translate('whenRecurringTransactionsCreated');
  String get weeklyInsights => translate('weeklyInsights');
  String get whenWeeklyInsightsReady => translate('whenWeeklyInsightsReady');
  
  



  //edit profile screen getters
  String get failedUpdateProfile => translate('failedUpdateProfile');
  String get discardChanges => translate('discardChanges');
  String get discardChangesAlert => translate('discardChangesAlert');
  String get keepEditing => translate('keepEditing');
  String get discard => translate('discard');
  String get tapIconChangeAvatar => translate('tapIconChangeAvatar');
  String get fullName => translate('fullName');
  String get enterFullName => translate('enterFullName');
  String get pleaseEnterName => translate('pleaseEnterName');
  String get nameTwoCharacters => translate('nameTwoCharacters');
  String get emailAddress => translate('emailAddress');
  String get emailCannotChanged => translate('emailCannotChanged');
  String get haveUnsavedChanges => translate('haveUnsavedChanges');
  String get dangerZone => translate('dangerZone');
  String get dangerZoneDes => translate('dangerZoneDes');
  String get deleteAccount => translate('deleteAccount');
  String get deleteAccountQ => translate('deleteAccountQ');
  String get willPermanentlyDelete => translate('willPermanentlyDelete');
  String get allYourTransactions => translate('allYourTransactions');
  String get allYourFinancialGoals => translate('allYourFinancialGoals');
  String get allYourBudgets => translate('allYourBudgets');
  String get allYourAiInsights => translate('allYourAiInsights');
  String get allYourChatHistory => translate('allYourChatHistory');
  String get yourAccountInformation => translate('yourAccountInformation');
  String get actionCannotBeUndone => translate('actionCannotBeUndone');
  



  //currency settings screen getters
  String get currencySettings => translate('currencySettings');
  String get selectDefaultCurrency => translate('selectDefaultCurrency');
  String get preferredCurrency => translate('preferredCurrency');
  String get eachCurrencyOwnBalance => translate('eachCurrencyOwnBalance');



  //change password screen getters
  String get passwordSixCharacters => translate('passwordSixCharacters');
  String get currentPassword => translate('currentPassword');
  String get enterCurrentPassword => translate('enterCurrentPassword');
  String get pleaseEnterCurrentPassword => translate('pleaseEnterCurrentPassword');
  String get newPassword => translate('newPassword');
  String get enterNewPassword => translate('enterNewPassword');
  String get pleaseEnterNewPassword => translate('pleaseEnterNewPassword');
  String get newPasswordDifferentCurrentPassword => translate('newPasswordDifferentCurrentPassword');
  String get confirmNewPassword => translate('confirmNewPassword');
  String get confirmYourNewPassword => translate('confirmYourNewPassword');
  String get pleaseConfirmNewPassword => translate('pleaseConfirmNewPassword');
  String get passwordsNotMatch => translate('passwordsNotMatch');



  //outflow analytics screen getters
  String get yearly => translate('yearly');
  String get totalSpending => translate('totalSpending');
  String get spendingByCategory => translate('spendingByCategory');
  String get noDataAvailable => translate('noDataAvailable');
  String get addTransactionsSeeSpendingAnalytics => translate('addTransactionsSeeSpendingAnalytics');
  String get byDayOfWeek => translate('byDayOfWeek');
  String get byMonth => translate('byMonth');
  String get byYear => translate('byYear');
  String get customPeriod => translate('customPeriod');
  String get spendingDayOfWeek => translate('spendingDayOfWeek');
  String get spendingMonth => translate('spendingMonth');
  String get spendingYear => translate('spendingYear');
  String get spendingOverTime => translate('spendingOverTime');



  //inflow analytics screen getters
  String get totalIncome => translate('totalIncome');
  String get addIncomeSeeAnalytics => translate('addIncomeSeeAnalytics');
  String get incomeDayOfWeek => translate('incomeDayOfWeek');
  String get incomeByMonth => translate('incomeByMonth');
  String get incomeByYear => translate('incomeByYear');
  String get incomeOverTime => translate('incomeOverTim');



  //subscription screen getters
  String get welcomeToPremium => translate('welcomeToPremium');
  String get accessAllPremiumFeatures => translate('accessAllPremiumFeatures');
  String get getStarted => translate('getStarted');
  String get premiumStatus => translate('premiumStatus');
  String get premiumActive => translate('premiumActive');
  String get premiumFeatures => translate('premiumFeatures');
  String get aiBudgetSuggestions => translate('aiBudgetSuggestions');
  String get aiBudgetSuggestionsDes => translate('aiBudgetSuggestionsDes');
  String get voiceInputDes => translate('voiceInputDes');
  String get receiptScanning => translate('receiptScanning');
  String get receiptScanningDes => translate('receiptScanningDes');
  String get aiFinancialAssistant => translate('aiFinancialAssistant');
  String get aiFinancialAssistantDes => translate('aiFinancialAssistantDes');
  String get aiInsightsDes => translate('aiInsightsDes');
  String get premiumPlan => translate('premiumPlan');
  String get tryCancelAnytime => translate('tryCancelAnytime');
  String get contactAdmin => translate('contactAdmin');
  String get contactSupport => translate('contactSupport');




  // Feedback Screen Getters
  String get sendFeedback => translate('sendFeedback');
  String get weValueYourInput => translate('weValueYourInput');
  String get feedbackHeaderSubtitle => translate('feedbackHeaderSubtitle');
  String get whatIsThisRegarding => translate('whatIsThisRegarding');
  String get howRateExperience => translate('howRateExperience');
  String get tellUsMore => translate('tellUsMore');
  String get feedbackHint => translate('feedbackHint');
  String get submitFeedback => translate('submitFeedback');
  String get pleaseSelectRating => translate('pleaseSelectRating');
  String get feedbackSubmittedSuccess => translate('feedbackSubmittedSuccess');
  String get feedbackFailed => translate('feedbackFailed');
  String get pleaseEnterMessage => translate('pleaseEnterMessage');
  String get feedbackMinLength => translate('feedbackMinLength');
  String get feedbackCategoryGeneral => translate('feedbackCategoryGeneral');
  String get feedbackCategoryBug => translate('feedbackCategoryBug');
  String get feedbackCategoryFeature => translate('feedbackCategoryFeature');
  String get feedbackCategoryUsability => translate('feedbackCategoryUsability');
  String get feedbackCategoryOther => translate('feedbackCategoryOther');
  String get feedbackDesc => translate('feedbackDesc');

  // Localization sweep — widgets/providers batch
  String get badgeTryFree => translate('badgeTryFree');
  String get badgeThreeNew => translate('badgeThreeNew');
  String get badgeFreeMonth => translate('badgeFreeMonth');
  String get askAi => translate('askAi');
  String get chatWithAiAssistant => translate('chatWithAiAssistant');
  String get noUpcomingOccurrences => translate('noUpcomingOccurrences');
  String get repeatOn => translate('repeatOn');
  String get dayLabel => translate('dayLabel');
  String get weekdayMon => translate('weekdayMon');
  String get weekdayTue => translate('weekdayTue');
  String get weekdayWed => translate('weekdayWed');
  String get weekdayThu => translate('weekdayThu');
  String get weekdayFri => translate('weekdayFri');
  String get weekdaySat => translate('weekdaySat');
  String get weekdaySun => translate('weekdaySun');
  String get monthJanuary => translate('monthJanuary');
  String get monthFebruary => translate('monthFebruary');
  String get monthMarch => translate('monthMarch');
  String get monthApril => translate('monthApril');
  String get monthMay => translate('monthMay');
  String get monthJune => translate('monthJune');
  String get monthJuly => translate('monthJuly');
  String get monthAugust => translate('monthAugust');
  String get monthSeptember => translate('monthSeptember');
  String get monthOctober => translate('monthOctober');
  String get monthNovember => translate('monthNovember');
  String get monthDecember => translate('monthDecember');
  String get premiumFeatureDialogContent => translate('premiumFeatureDialogContent');

  // Localization sweep — transactions batch
  String get pickCategoryTitle => translate('pickCategoryTitle');
  String get thenChooseSubCategoryHint => translate('thenChooseSubCategoryHint');
  String get chooseSubCategoryTitle => translate('chooseSubCategoryTitle');
  String get noCategoriesLabel => translate('noCategoriesLabel');
  String get subCategoriesCountLabel => translate('subCategoriesCountLabel');
  String get chooseCategoryFallback => translate('chooseCategoryFallback');
  String get categoryAndSubCategoryFallback => translate('categoryAndSubCategoryFallback');
  String get repeatLabel => translate('repeatLabel');
  String get doneLabel => translate('doneLabel');
  String get offLabel => translate('offLabel');
  String get egExchangeRateHint => translate('egExchangeRateHint');
  String get speakItTooltip => translate('speakItTooltip');
  String get keepItButton => translate('keepItButton');
  String get currencyConvertedMessage => translate('currencyConvertedMessage');
  String get addAReceiptTitle => translate('addAReceiptTitle');
  String get whatWeReadLabel => translate('whatWeReadLabel');
  String get whatWeReadDescription => translate('whatWeReadDescription');
  String get useDifferentPhotoButton => translate('useDifferentPhotoButton');
  String get failedToSaveTransactionFallback => translate('failedToSaveTransactionFallback');
  String get successfullySavedPrefix => translate('successfullySavedPrefix');
  String get transactionsSuffix => translate('transactionsSuffix');
  String get whatYouSaidLabel => translate('whatYouSaidLabel');
  String get fromOneRecordingLabel => translate('fromOneRecordingLabel');
  String get foundLabel => translate('foundLabel');
  String get transactionSingularLabel => translate('transactionSingularLabel');
  String get multipleSpendsWarning => translate('multipleSpendsWarning');
  String get selectedTotalLabel => translate('selectedTotalLabel');
  String get recordAgainButton => translate('recordAgainButton');
  String get mixedCurrenciesLabel => translate('mixedCurrenciesLabel');
  String get oneTransactionLabel => translate('oneTransactionLabel');
  String get transactionsCountSuffix => translate('transactionsCountSuffix');

  // Localization sweep — auth screens batch
  String get loginTagline => translate('loginTagline');
  String get emailLabel => translate('emailLabel');
  String get enterEmailError => translate('enterEmailError');
  String get enterValidEmailError => translate('enterValidEmailError');
  String get passwordLabel => translate('passwordLabel');
  String get enterPasswordError => translate('enterPasswordError');
  String get forgotPasswordQuestion => translate('forgotPasswordQuestion');
  String get signIn => translate('signIn');
  String get newHerePrefix => translate('newHerePrefix');
  String get createAnAccount => translate('createAnAccount');
  String get registerTagline => translate('registerTagline');
  String get fullNameLabel => translate('fullNameLabel');
  String get passwordMinLengthError => translate('passwordMinLengthError');
  String get confirmPasswordLabel => translate('confirmPasswordLabel');
  String get confirmPasswordError => translate('confirmPasswordError');
  String get byContinuingAcceptPrefix => translate('byContinuingAcceptPrefix');
  String get termsLinkText => translate('termsLinkText');
  String get andConnector => translate('andConnector');
  String get privacyPolicyLinkText => translate('privacyPolicyLinkText');
  String get neverSellDataSuffix => translate('neverSellDataSuffix');
  String get createAccountButton => translate('createAccountButton');
  String get alreadyHaveAccountPrefix => translate('alreadyHaveAccountPrefix');
  String get oneTapLeft => translate('oneTapLeft');
  String get verificationLinkSentPrefix => translate('verificationLinkSentPrefix');
  String get whyExtraStepTitle => translate('whyExtraStepTitle');
  String get emailVerificationExplanation => translate('emailVerificationExplanation');
  String get verifiedSignInButton => translate('verifiedSignInButton');
  String get nothingArrivedPrefix => translate('nothingArrivedPrefix');
  String get useDifferentAddressLink => translate('useDifferentAddressLink');
  String get termsAndConditionsTitle => translate('termsAndConditionsTitle');
  String get welcomeToToePwarTagline => translate('welcomeToToePwarTagline');
  String get termsAndConditionsBody => translate('termsAndConditionsBody');
  String get privacyPolicyTitle => translate('privacyPolicyTitle');
  String get yourPrivacyMattersTitle => translate('yourPrivacyMattersTitle');
  String get privacyPolicyBody => translate('privacyPolicyBody');
  String get resetPasswordTitle => translate('resetPasswordTitle');
  String get resetPasswordSubtitle => translate('resetPasswordSubtitle');
  String get emailAddressLabel => translate('emailAddressLabel');
  String get sendCodeButton => translate('sendCodeButton');
  String get enterAllSixDigitsError => translate('enterAllSixDigitsError');
  String get newCodeSentMessage => translate('newCodeSentMessage');
  String get enterTheCodeTitle => translate('enterTheCodeTitle');
  String get sentCodeToPrefix => translate('sentCodeToPrefix');
  String get expiresInTenMinutes => translate('expiresInTenMinutes');
  String get verifyCodeButton => translate('verifyCodeButton');
  String get didntGetItPrefix => translate('didntGetItPrefix');
  String get resendInPrefix => translate('resendInPrefix');
  String get sendNewCodeButton => translate('sendNewCodeButton');
  String get passwordResetTitle => translate('passwordResetTitle');
  String get passwordResetSuccessMessage => translate('passwordResetSuccessMessage');
  String get backToLogin => translate('backToLogin');
  String get chooseNewPasswordTitle => translate('chooseNewPasswordTitle');
  String get codeAcceptedSubtitle => translate('codeAcceptedSubtitle');
  String get newPasswordLabel => translate('newPasswordLabel');
  String get pleaseEnterAPasswordError => translate('pleaseEnterAPasswordError');
  String get minimumSixCharactersError => translate('minimumSixCharactersError');
  String get confirmItLabel => translate('confirmItLabel');
  String get saveAndSignInButton => translate('saveAndSignInButton');

  // Localization sweep — legal text + force update batch
  String get privacyPolicySubtitle => translate('privacyPolicySubtitle');
  String get privacyIntroTitle => translate('privacyIntroTitle');
  String get privacyIntroBody => translate('privacyIntroBody');
  String get privacyInfoCollectTitle => translate('privacyInfoCollectTitle');
  String get privacyInfoCollectBody => translate('privacyInfoCollectBody');
  String get privacyUseInfoTitle => translate('privacyUseInfoTitle');
  String get privacyUseInfoBody => translate('privacyUseInfoBody');
  String get privacyDataSecurityTitle => translate('privacyDataSecurityTitle');
  String get privacyDataSecurityBody => translate('privacyDataSecurityBody');
  String get privacyDataSharingTitle => translate('privacyDataSharingTitle');
  String get privacyDataSharingBody => translate('privacyDataSharingBody');
  String get privacyAiProcessingTitle => translate('privacyAiProcessingTitle');
  String get privacyAiProcessingBody => translate('privacyAiProcessingBody');
  String get privacyYourRightsTitle => translate('privacyYourRightsTitle');
  String get privacyYourRightsBody => translate('privacyYourRightsBody');
  String get privacyDataRetentionTitle => translate('privacyDataRetentionTitle');
  String get privacyDataRetentionBody => translate('privacyDataRetentionBody');
  String get privacyChildrensTitle => translate('privacyChildrensTitle');
  String get privacyChildrensBody => translate('privacyChildrensBody');
  String get privacyIntlTransfersTitle => translate('privacyIntlTransfersTitle');
  String get privacyIntlTransfersBody => translate('privacyIntlTransfersBody');
  String get privacyChangesTitle => translate('privacyChangesTitle');
  String get privacyChangesBody => translate('privacyChangesBody');
  String get privacyContactTitle => translate('privacyContactTitle');
  String get privacyContactBody => translate('privacyContactBody');
  String get privacySecurityNotice => translate('privacySecurityNotice');
  String get termsTitle => translate('termsTitle');
  String get termsSubtitle => translate('termsSubtitle');
  String get termsAcceptanceTitle => translate('termsAcceptanceTitle');
  String get termsAcceptanceBody => translate('termsAcceptanceBody');
  String get termsUseOfServiceTitle => translate('termsUseOfServiceTitle');
  String get termsUseOfServiceBody => translate('termsUseOfServiceBody');
  String get termsAccountRegTitle => translate('termsAccountRegTitle');
  String get termsAccountRegBody => translate('termsAccountRegBody');
  String get termsUserResponsibilitiesTitle => translate('termsUserResponsibilitiesTitle');
  String get termsUserResponsibilitiesBody => translate('termsUserResponsibilitiesBody');
  String get termsAiFeaturesTitle => translate('termsAiFeaturesTitle');
  String get termsAiFeaturesBody => translate('termsAiFeaturesBody');
  String get termsPremiumSubTitle => translate('termsPremiumSubTitle');
  String get termsPremiumSubBody => translate('termsPremiumSubBody');
  String get termsDataProcessingTitle => translate('termsDataProcessingTitle');
  String get termsDataProcessingBody => translate('termsDataProcessingBody');
  String get termsIntellectualPropertyTitle => translate('termsIntellectualPropertyTitle');
  String get termsIntellectualPropertyBody => translate('termsIntellectualPropertyBody');
  String get termsLimitationLiabilityTitle => translate('termsLimitationLiabilityTitle');
  String get termsLimitationLiabilityBody => translate('termsLimitationLiabilityBody');
  String get termsTerminationTitle => translate('termsTerminationTitle');
  String get termsTerminationBody => translate('termsTerminationBody');
  String get termsChangesTitle => translate('termsChangesTitle');
  String get termsChangesBody => translate('termsChangesBody');
  String get termsContactInfoTitle => translate('termsContactInfoTitle');
  String get termsContactInfoBody => translate('termsContactInfoBody');
  String get termsAcceptanceNotice => translate('termsAcceptanceNotice');
  String get noBrowserFoundMessage => translate('noBrowserFoundMessage');
  String get copyLabel => translate('copyLabel');
  String get forceUpdateTitle => translate('forceUpdateTitle');
  String get forceUpdateDefaultMessage => translate('forceUpdateDefaultMessage');
  String get whatsNewInVersion => translate('whatsNewInVersion');
  String get whatsNewLabel => translate('whatsNewLabel');
  String get youHaveVersion => translate('youHaveVersion');
  String get updateNowButton => translate('updateNowButton');
  String get updateSafetyNotice => translate('updateSafetyNotice');

  // Localization sweep — settings screens batch
  String get passwordStrengthWeak => translate('passwordStrengthWeak');
  String get passwordStrengthFair => translate('passwordStrengthFair');
  String get passwordStrengthGood => translate('passwordStrengthGood');
  String get passwordStrengthStrong => translate('passwordStrengthStrong');
  String get failedToChangePassword => translate('failedToChangePassword');
  String get errorOccurred => translate('errorOccurred');
  String get passwordChangeSignOutNotice => translate('passwordChangeSignOutNotice');
  String get defaultCurrencyUpdatedTo => translate('defaultCurrencyUpdatedTo');
  String get failedToUpdateCurrency => translate('failedToUpdateCurrency');
  String get howCurrenciesWorkHere => translate('howCurrenciesWorkHere');
  String get accountDeletedSuccessfully => translate('accountDeletedSuccessfully');
  String get failedToDeleteAccount => translate('failedToDeleteAccount');
  String get ratingHelper1 => translate('ratingHelper1');
  String get ratingHelper2 => translate('ratingHelper2');
  String get ratingHelper3 => translate('ratingHelper3');
  String get ratingHelper4 => translate('ratingHelper4');
  String get ratingHelper5 => translate('ratingHelper5');
  String get ratingHelperDefault => translate('ratingHelperDefault');
  String get charCountMinimumSuffix => translate('charCountMinimumSuffix');
  String get languageChangedToEnglish => translate('languageChangedToEnglish');
  String get languageChangedToBurmese => translate('languageChangedToBurmese');
  String get languageSettingsTitle => translate('languageSettingsTitle');
  String get selectLanguageLabel => translate('selectLanguageLabel');
  String get languageRestartNotice => translate('languageRestartNotice');
  String get failedToUpdatePreference => translate('failedToUpdatePreference');
  String get monthlyInsightsTitle => translate('monthlyInsightsTitle');
  String get monthlyInsightsDesc => translate('monthlyInsightsDesc');
  String get defaultUserName => translate('defaultUserName');
  String get premiumMemberLabel => translate('premiumMemberLabel');
  String get freePlanLabel => translate('freePlanLabel');
  String get currentLanguageName => translate('currentLanguageName');
  String get appVersion => translate('appVersion');
  String get viewOurPrivacyPolicy => translate('viewOurPrivacyPolicy');
  String get viewTermsAndConditions => translate('viewTermsAndConditions');
  String get appDescription => translate('appDescription');
  String get copyrightNotice => translate('copyrightNotice');

  // Localization sweep — home/ai/insights/reports/charts/notifications/subscription batch
  String get spendingPace => translate('spendingPace');
  String get insight => translate('insight');
  String get eachCurrencyOwnBalanceNote => translate('eachCurrencyOwnBalanceNote');
  String get errorLoadCurrencyBalances => translate('errorLoadCurrencyBalances');
  String get suggestionCurrentBalance => translate('suggestionCurrentBalance');
  String get suggestionSpendThisMonth => translate('suggestionSpendThisMonth');
  String get suggestionTopSpendingCategories => translate('suggestionTopSpendingCategories');
  String get suggestionMoneySavingTips => translate('suggestionMoneySavingTips');
  String get suggestionIncomeVsExpenses => translate('suggestionIncomeVsExpenses');
  String get suggestionSpendOnFood => translate('suggestionSpendOnFood');
  String get answers => translate('answers');
  String get clearThisConversation => translate('clearThisConversation');
  String get chatMessageSingular => translate('chatMessageSingular');
  String get chatMessagePlural => translate('chatMessagePlural');
  String get clearChatConsequence => translate('clearChatConsequence');
  String get keepIt => translate('keepIt');
  String get fallbackQuestionTighterMonth => translate('fallbackQuestionTighterMonth');
  String get assistantAnswersFromRecords => translate('assistantAnswersFromRecords');
  String get spendingPaceCategoryComparisons => translate('spendingPaceCategoryComparisons');
  String get tryOneMonthFree => translate('tryOneMonthFree');
  String get noCardRequiredCancelAnyTime => translate('noCardRequiredCancelAnyTime');
  String get errorLoadingTransactions => translate('errorLoadingTransactions');
  String get moneyInLabel => translate('moneyInLabel');
  String get moneyOutLabel => translate('moneyOutLabel');
  String get avgPerEntry => translate('avgPerEntry');
  String get spentLabel => translate('spentLabel');
  String get biggestOutflowCategoryMiddle => translate('biggestOutflowCategoryMiddle');
  String get biggestOutflowCategorySuffix => translate('biggestOutflowCategorySuffix');
  String get biggestIncomeSourceMiddle => translate('biggestIncomeSourceMiddle');
  String get biggestIncomeSourceSuffix => translate('biggestIncomeSourceSuffix');
  String get regenerate => translate('regenerate');
  String get threeInsightsWaiting => translate('threeInsightsWaiting');
  String get swipeNotificationToDelete => translate('swipeNotificationToDelete');
  String get justNow => translate('justNow');
  String get minutesAgoSuffix => translate('minutesAgoSuffix');
  String get hoursAgoSuffix => translate('hoursAgoSuffix');
  String get daysAgoSuffix => translate('daysAgoSuffix');
  String get errorDownloadReport => translate('errorDownloadReport');
  String get exportThisReport => translate('exportThisReport');
  String get chartsCategoryTablesDailyAverages => translate('chartsCategoryTablesDailyAverages');
  String get sendItOn => translate('sendItOn');
  String get samePdfToViberOrEmail => translate('samePdfToViberOrEmail');
  String get ofTotal => translate('ofTotal');
  String get txnsAbbrev => translate('txnsAbbrev');
  String get welcomeToPremiumCelebration => translate('welcomeToPremiumCelebration');
  String get oneMonthFreePremiumAccess => translate('oneMonthFreePremiumAccess');
  String get letsGo => translate('letsGo');
  String get couldNotClaimFreeTrial => translate('couldNotClaimFreeTrial');
  String get oneMonthFreeCaps => translate('oneMonthFreeCaps');
  String get letAppReadYourMoney => translate('letAppReadYourMoney');
  String get weeklyInsightsReceiptScanningVoiceAiBudgets => translate('weeklyInsightsReceiptScanningVoiceAiBudgets');
  String get claiming => translate('claiming');
  String get claimOneMonthFree => translate('claimOneMonthFree');
  String get noCardRequiredThenContactUs => translate('noCardRequiredThenContactUs');

  // Localization sweep — budgets/goals batch
  String get startsOnPrefix => translate('startsOnPrefix');
  String get startsInDaysPrefix => translate('startsInDaysPrefix');
  String get daysSuffix => translate('daysSuffix');
  String get endedDaysAgoPrefix => translate('endedDaysAgoPrefix');
  String get daysRemainingSuffix => translate('daysRemainingSuffix');
  String get budgetWillStartOnPrefix => translate('budgetWillStartOnPrefix');
  String get noSpendingTrackedYetSuffix => translate('noSpendingTrackedYetSuffix');
  String get budgetEndedOnPrefix => translate('budgetEndedOnPrefix');
  String get onlyTransactionsInPrefix => translate('onlyTransactionsInPrefix');
  String get willAffectThisBudgetSuffix => translate('willAffectThisBudgetSuffix');
  String get fixedForThisBudget => translate('fixedForThisBudget');
  String get periodCurrencyLockedNotice => translate('periodCurrencyLockedNotice');
  String get capAlreadySpentTitle => translate('capAlreadySpentTitle');
  String get alreadyHaveMoreSpent => translate('alreadyHaveMoreSpent');
  String get alreadyHasMoreSpent => translate('alreadyHasMoreSpent');
  String get totalCapLabel => translate('totalCapLabel');
  String get analyzingYourPrefix => translate('analyzingYourPrefix');
  String get spendingPatternsSuffix => translate('spendingPatternsSuffix');
  String get genericErrorOccurred => translate('genericErrorOccurred');
  String get savedTowardsGoals => translate('savedTowardsGoals');
  String get failedToLoadBalances => translate('failedToLoadBalances');
  String get dueDatePrefix => translate('dueDatePrefix');
  String get operationFailed => translate('operationFailed');
  String get moneyHeldNotSpendable => translate('moneyHeldNotSpendable');
  String get heldFundsExplanation => translate('heldFundsExplanation');
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