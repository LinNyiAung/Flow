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
      'recentTransactions': 'Recent Transactions',
      'seeMore': 'See More',
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
      'expiresOn': 'Expires:',

      // Additions for Add Transaction Screen
      'addTransactionTitle': 'Add Transaction',
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
      'found_x_transactions': 'Found %d Transactions', // Placeholder for count
      'transaction_x_card_title': 'Transaction %d', // Placeholder for index
      'save_x_transactions_button': 'Save %d Transactions', // Placeholder for count
      'errorStartRecording': 'Failed to start recording:',
      'errorStopRecording': 'Failed to stop recording:',
      'analyzingTransactions': 'Analyzing transactions...',
      'success_save_transactions': 'Successfully saved %d transaction(s)', // Placeholder for count

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
      'notificationSettings': 'Notification Settings',
      'manageNotificationPreferences': 'Manage notification preferences',
      'subscription': 'Subscription',
      'manageSubscription': 'Manage Subscription',
      'viewManageSubscription': 'View and manage your subscription',
      'unlockPremiumFeatures': 'Unlock all premium features',
      'about': 'About',
      'aboutFlowFinance': 'About Flow Finance',


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
    },
    'my': {
      // Home Screen
      'welcomeBack': 'ပြန်လာတာ ကြိုဆိုပါတယ်၊',
      'totalBalance': 'စုစုပေါင်း လက်ကျန်ငွေ',
      'available': 'လက်ကျန်',
      'allocatedToGoals': 'ပန်းတိုင်များသို့ ခွဲဝေထားသော',
      'inflow': 'ဝင်ငွေ',
      'outflow': 'ထွက်ငွေ',
      'aiAssistant': 'AI အကူအညီပေးသူ',
      'getPersonalizedInsights': 'ပုဂ္ဂိုလ်ရေးဆိုင်ရာ ထိုးထွင်းသိမြင်မှုများ ရယူပါ',
      'aiInsights': 'AI ထိုးထွင်းသိမြင်မှုများ',
      'viewComprehensiveAnalysis': 'ပြည့်စုံသော ဘဏ္ဍာရေးဆိုင်ရာ ခွဲခြမ်းစိတ်ဖြာချက်ကို ကြည့်ပါ',
      'recentTransactions': 'လတ်တလောငွေစာရင်းသွင်းမှုများ',
      'seeMore': 'ကြည့်ရန်',
      'noTransactions': 'ငွေစာရင်းသွင်းမှု မရှိသေးပါ',
      'tapToAddFirst': 'ပထမဆုံး ငွေစာရင်းသွင်းမှုပြုလုပ်ရန် + ခလုတ်ကို နှိပ်ပါ',
      'addTransaction': 'ငွေစာရင်းသွင်းရန်',
      'manualEntry': 'ကိုယ်တိုင် ထည့်သွင်းခြင်း',
      'typeTransactionDetails': 'ငွေစာရင်းအသေးစိတ်ကို ရိုက်ထည့်ပါ',
      'voiceInput': 'အသံဖြင့် ထည့်သွင်းခြင်း',
      'speakYourTransaction': 'သင့်ငွေစာရင်းသွင်းမှုကို ပြောဆိုပါ',
      'scanReceipt': 'ဘောင်ချာ စကန်ဖတ်ခြင်း',
      'takeUploadPhoto': 'ဘောင်ချာ ဓာတ်ပုံရိုက်ပါ သို့မဟုတ် တင်ပါ',
      'premium': 'ပရီမီယံ',
      'transactionAdded': 'ငွေစာရင်းသွင်းမှု အောင်မြင်စွာ ထည့်သွင်းပြီးပါပြီ။',
      'transactionUpdated': 'ငွေစာရင်းသွင်းမှု အောင်မြင်စွာ ပြင်ဆင်ပြီးပါပြီ။',
      'transactionDeleted': 'ငွေစာရင်းသွင်းမှု အောင်မြင်စွာ ဖျက်ပြီးပါပြီ။',
      'dashboard': 'ဒက်ရှ်ဘုတ်',
      'autoCreated': 'အလိုအလျောက် ဖန်တီးထားသော',
      'viewAllCurrencies':'ငွေကြေးအားလုံးကို ကြည့်ရန်',
      'allCurrencyBalances':'ငွေကြေးအားလုံး၏ လက်ကျန်များ',
      'default':'မူရင်း',

      // Additions for Drawer Navigation
      'drawerWelcome': 'ကြိုဆိုပါသည်',
      'drawerLogout': 'အကောင့်ထွက်ရန်',
      'dialogCancel': 'ပယ်ဖျက်ရန်',
      'dialogLogoutConfirm': 'အကောင့်ထွက်ရန် သေချာပါသလား?',
      'transactions': 'ငွေစာရင်းသွင်းမှုများ',
      'goals': 'ပန်းတိုင်များ',
      'budgets': 'ဘတ်ဂျက်များ',
      'inflowAnalytics': 'ဝင်ငွေ ခွဲခြမ်းစိတ်ဖြာမှု',
      'outflowAnalytics': 'ထွက်ငွေ ခွဲခြမ်းစိတ်ဖြာမှု',
      'financialReports': 'ဘဏ္ဍာရေး အစီရင်ခံစာများ',
      'settings': 'ဆက်တင်များ',
      'expiresOn': 'သက်တမ်းကုန်ဆုံးမည့်ရက်:',

      // Additions for Add Transaction Screen
      'addTransactionTitle': 'ငွေစာရင်းသွင်းရန်',
      'currency': 'ငွေကြေး',
      'convertCurrency': 'ငွေကြေးလဲလှယ်ရန်',
      'current': 'လက်ရှိ: ',
      'convertTo': 'ပြောင်းလဲမည့် ငွေကြေး: ',
      'exchangeRate': 'ငွေလဲနှုန်း:',
      'convert': 'ပြောင်းလဲရန်',
      'selectTargetCurrency': 'ပြောင်းလဲလိုသည့်ငွေကြေးကိုရွေးပါ',
      'amountLabel': 'ပမာဏ',
      'dateLabel': 'ရက်စွဲ',
      'categoryLabel': 'အမျိုးအစား',
      'selectMainCategoryHint': 'အဓိက အမျိုးအစားကို ရွေးပါ',
      'selectSubCategoryHint': 'အမျိုးအစားခွဲကို ရွေးပါ',
      'descriptionLabel': 'ဖော်ပြချက် (စိတ်ကြိုက်)',
      'descriptionHint': 'ဤငွေစာရင်းသွင်းမှုအကြောင်း မှတ်စုထည့်ပါ...',
      'addOutflowButton': 'ထွက်ငွေ ထည့်ရန်',
      'addInflowButton': 'ဝင်ငွေ ထည့်ရန်',
      'validationAmountInvalid': 'မှန်ကန်သော ပမာဏကို ထည့်ပါ',
      'validationAmountPositive': 'ပမာဏသည် သုညထက် ကြီးရမည်',
      'validationMainCategoryRequired': 'အဓိက အမျိုးအစားကို ရွေးချယ်ပါ',
      'validationSubCategoryRequired': 'အမျိုးအစားခွဲကို ရွေးချယ်ပါ',
      'recurringTransaction': 'ထပ်တလဲလဲ ငွေစာရင်းသွင်းမှု',
      'recurringTransactionDes': 'ဤငွေစာရင်းသွင်းမှုကို အလိုအလျောက် ဖန်တီးပါ',
      'repeatFrequency': 'ထပ်တလဲလဲ ပြုလုပ်မည့် အကြိမ်ရေ',
      'dayOfMonth': 'လ၏ ရက်စွဲ',
      'daily': 'နေ့စဉ်',
      'weekly': 'အပတ်စဉ်',
      'monthly': 'လစဉ်',
      'annually': 'နှစ်စဉ်',
      'dailyDes':'နေ့တိုင်း ထပ်တလဲလဲ ပြုလုပ်မည်',
      'weeklyDes': 'ရွေးချယ်ထားသော ရက်သတ္တပတ်၏ နေ့တွင် ထပ်တလဲလဲ ပြုလုပ်မည်',
      'monthlyDes': 'ရွေးချယ်ထားသော လ၏ ရက်စွဲတွင် ထပ်တလဲလဲ ပြုလုပ်မည်',
      'annuallyDes': 'ရွေးချယ်ထားသော နှစ်၏ ရက်စွဲတွင် ထပ်တလဲလဲ ပြုလုပ်မည်',
      'endDate': 'ပြီးဆုံးမည့်ရက် (စိတ်ကြိုက်)',
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
      'deleteConfirmMessage': 'ဤငွေစာရင်းသွင်းမှုကို ဖျက်ရန် သေချာပါသလား? ဤလုပ်ဆောင်ချက်ကို ပြန်ဖျက်၍ မရပါ။',
      'autoCreatedTransactionTitle': 'အလိုအလျောက် ဖန်တီးထားသော ငွေစာရင်းသွင်းမှု',
      'autoCreatedDescriptionRecurring': '၎င်းသည် ထပ်တလဲလဲ ငွေစာရင်းသွင်းမှုမှ အလိုအလျောက် ဖန်တီးထားခြင်း ဖြစ်သည်။',
      'autoCreatedDescriptionDisabled': '၎င်းသည် ထပ်တလဲလဲ ငွေစာရင်းသွင်းမှုမှ အလိုအလျောက် ဖန်တီးထားခြင်း ဖြစ်သည် (ယခု ပိတ်ထားသည်။)',
      'stopFutureAutoCreation': 'နောင် အလိုအလျောက် ဖန်တီးခြင်းကို ရပ်ရန်',
      'viewParentTransaction': 'မိခင် ငွေစာရင်းသွင်းမှုကို ကြည့်ရန်',
      'stopRecurringDialogTitle': 'ထပ်တလဲလဲ ငွေစာရင်းသွင်းမှုကို ရပ်မလား?',
      'stopRecurringDialogContent': 'ဤအရာက နောင် ငွေစာရင်းသွင်းမှုများ အလိုအလျောက် ဖန်တီးခြင်းကို ရပ်တန့်စေမည်ဖြစ်သည်။',
      'stopRecurringDialogInfo': 'လက်ရှိ ငွေစာရင်းသွင်းမှုများကို သက်ရောက်မှုရှိမည် မဟုတ်ပါ။',
      'stopRecurringButton': 'ထပ်တလဲလဲ ပြုလုပ်ခြင်းကို ရပ်ရန်',
      'stoppingRecurrence': 'ထပ်တလဲလဲ ပြုလုပ်ခြင်း ရပ်ဆိုင်းနေသည်',
      'pleaseWait': 'ခဏ စောင့်ပါ...',
      'successTitle': 'အောင်မြင်သည်!',
      'successAutoCreationStopped': 'နောင် အလိုအလျောက် ဖန်တီးခြင်းကို ရပ်တန့်ပြီးပါပြီ',
      'errorTitle': 'အမှား',
      'errorLoadParentFailed': 'မိခင် ငွေစာရင်းသွင်းမှုကို တင်ရန် မအောင်မြင်ပါ:',
      'updateTransactionButton': 'ငွေစာရင်းသွင်းမှုကို အပ်ဒိတ်လုပ်ရန်',
      'selectCurrencyT': 'ငွေကြေးကို ရွေးပါ',
      'recurringScheduleStopped': 'ဤငွေစာရင်းသွင်းမှုအတွက် ထပ်တလဲလဲ အချိန်ဇယားကို ရပ်တန့်ပြီးပါပြီ။',
      'recurringSettingsStopDes': 'ထပ်တလဲလဲ ဆက်တင်များကို မိခင် ငွေစာရင်းသွင်းမှုမှ စီမံခန့်ခွဲသည်။ နောင် အလိုအလျောက် ဖန်တီးခြင်းကို ရပ်ရန် အထက်ပါ ခလုတ်ကို အသုံးပြုပါ။',
      'dismiss': 'ပယ်ဖျက်ရန်',

      // Additions for Image Input Screen
      'imageInputTitle': 'ပုံရိပ် ထည့်သွင်းခြင်း',
      'premiumFeatureTitle': 'ပရီမီယံ လုပ်ဆောင်ချက်',
      'premiumFeatureUpgradeDescImg': 'ငွေစာရင်းသွင်းမှုအတွက် ပုံရိပ် ထည့်သွင်းခြင်းကို အသုံးပြုရန် အဆင့်မြှင့်ပါ',
      'upgradeNowButton': 'ယခု အဆင့်မြှင့်ပါ',
      'tapToAddImagePlaceholder': 'ဘောင်ချာပုံ ထည့်ရန် နှိပ်ပါ',
      'cameraOrGalleryPlaceholder': 'ကင်မရာ သို့မဟုတ် ပြခန်း',
      'chooseDifferentImageButton': 'အခြားပုံကို ရွေးပါ',
      'analyzingReceipt': 'ဘောင်ချာကို ခွဲခြမ်းစိတ်ဖြာနေသည်...',
      'extractedTransactionTitle': 'ထုတ်ယူထားသော ငွေစာရင်းသွင်းမှု',
      'dataLabelType': 'အမျိုးအစား',
      'dataLabelAmount': 'ပမာဏ',
      'dataLabelCategory': 'အမျိုးအစား',
      'dataLabelDate': 'ရက်စွဲ',
      'dataLabelDescription': 'ဖော်ပြချက်',
      'aiReasoningLabel': 'AI ဆင်ခြင်တုံတရား:',
      'confidenceLabel': 'ယုံကြည်စိတ်ချရမှု:',
      'saveTransactionButton': 'ငွေစာရင်းသွင်းမှု သိမ်းဆည်းရန်',
      'errorCaptureImage': 'ပုံရိပ်ရိုက်ယူရန် မအောင်မြင်ပါ:',
      'errorPickImage': 'ပုံရိပ်ရွေးရန် မအောင်မြင်ပါ:',
      'chooseImageSourceModalTitle': 'ပုံရိပ်ရင်းမြစ်ကို ရွေးချယ်ပါ',
      'cameraListTileTitle': 'ကင်မရာ',
      'cameraListTileSubtitle': 'ဘောင်ချာ ဓာတ်ပုံရိုက်ပါ',
      'galleryListTileTitle': 'ပြခန်း',
      'galleryListTileSubtitle': 'ပြခန်းမှ ရွေးချယ်ပါ',

      // Additions for Voice Input Screen
      'voiceInputTitle': 'အသံဖြင့် ထည့်သွင်းခြင်း',
      'premiumFeatureUpgradeDescVoice': 'ငွေစာရင်းသွင်းမှုအတွက် အသံဖြင့် ထည့်သွင်းခြင်းကို အသုံးပြုရန် အဆင့်မြှင့်ပါ',
      'recordingStatus': 'အသံသွင်းနေသည်... ရပ်ရန် နှိပ်ပါ',
      'tapToRecordStatus': 'အသံသွင်းခြင်း စတင်ရန် နှိပ်ပါ\nငွေစာရင်းသွင်းမှုများစွာကို ဖော်ပြနိုင်သည်',
      'transcriptionTitle': 'ကူးယူဖော်ပြချက်',
      'found_x_transactions': 'ငွေစာရင်းသွင်းမှု %d ခု တွေ့ရှိသည်', // Placeholder for count
      'transaction_x_card_title': 'ငွေစာရင်းသွင်းမှု %d', // Placeholder for index
      'save_x_transactions_button': 'ငွေစာရင်းသွင်းမှု %d ခု သိမ်းဆည်းရန်', // Placeholder for count
      'errorStartRecording': 'အသံသွင်းခြင်း စတင်ရန် မအောင်မြင်ပါ:',
      'errorStopRecording': 'အသံသွင်းခြင်း ရပ်ရန် မအောင်မြင်ပါ:',
      'analyzingTransactions': 'ငွေစာရင်းသွင်းမှုများကို ခွဲခြမ်းစိတ်ဖြာနေသည်...',
      'success_save_transactions': 'ငွေစာရင်းသွင်းမှု %d ခု အောင်မြင်စွာ သိမ်းဆည်းပြီးပါပြီ', // Placeholder for count

      // Additions for Transactions List Screen
      'allTransactionsTitle': 'ငွေစာရင်းသွင်းမှုများ အားလုံး',
      'filtersSectionTitle': 'စစ်ထုတ်မှုများ',
      'transactionTypeFilterLabel': 'ငွေစာရင်းသွင်းမှု အမျိုးအစား:',
      'filterChipAll': 'အားလုံး',
      'dateRangeFilterLabel': 'ရက်စွဲ အပိုင်းအခြား:',
      'selectDateRangeButton': 'ရက်စွဲ အပိုင်းအခြားကို ရွေးပါ',
      'loadingMoreIndicator': 'ထပ်မံ တင်နေသည်...',
      'emptyStateTitle': 'ငွေစာရင်းသွင်းမှု မတွေ့ရှိပါ',
      'emptyStateSubtitle': 'သင်၏ စစ်ထုတ်မှုများကို ပြင်ဆင်ပါ သို့မဟုတ် ငွေစာရင်းသွင်းမှု ထည့်သွင်းကြည့်ပါ။',
      'clearAllFiltersButton': 'စစ်ထုတ်မှုများ အားလုံး ရှင်းလင်းရန်',
      'clearDateFilterTooltip': 'ရက်စွဲ စစ်ထုတ်မှုကို ရှင်းလင်းရန်',
      'addTransactionFabTooltip': 'ငွေစာရင်းသွင်းမှု အသစ် ထည့်ရန်',
      'currencyFilter': 'ငွေကြေး စစ်ထုတ်မှု',

      //Goals screen
      'financialGoals': 'ဘဏ္ဍာရေး ပန်းတိုင်များ',
      'goalsSummary': 'ပန်းတိုင်များ အကျဉ်းချုပ်',
      'active': 'ဆောင်ရွက်ဆဲ',
      'achieved': 'အောင်မြင်ပြီး',
      'total': 'စုစုပေါင်း',
      'byCurrency': 'ငွေကြေးအလိုက်',
      'availableBalance': 'ရရှိနိုင်သော လက်ကျန်ငွေ',
      'forGoals': 'ပန်းတိုင်များအတွက်',
      'availableForGoals': 'ပန်းတိုင်များအတွက် ရရှိနိုင်သော',
      'selected': 'ရွေးချယ်ပြီး',
      'goalCreatedSuccessfully': 'ပန်းတိုင် အောင်မြင်စွာ ဖန်တီးပြီးပါပြီ။',
      'goalDeletedSuccessfully': 'ပန်းတိုင် အောင်မြင်စွာ ဖျက်ပြီးပါပြီ။',
      'noGoalsYet': 'ပန်းတိုင် မရှိသေးပါ',
      'createGoalGetStarted': 'စတင်ရန် သင်၏ ပထမဆုံး ဘဏ္ဍာရေး ပန်းတိုင်ကို ဖန်တီးပါ!',

      //Add goal screen
      'createNewGoal': 'ပန်းတိုင် အသစ် ဖန်တီးရန်',
      'goalName': 'ပန်းတိုင် အမည်',
      'goalType': 'ပန်းတိုင် အမျိုးအစား',
      'targetAmount': 'ပန်းတိုင် ပမာဏ',
      'initialContribution': 'အစဦး ထည့်ဝင်ငွေ (စိတ်ကြိုက်)',
      'targetDate': 'ပန်းတိုင် ရက်စွဲ (စိတ်ကြိုက်)',
      'createGoal': 'ပန်းတိုင် ဖန်တီးရန်',
      'failedToCreateGoal': 'ပန်းတိုင် ဖန်တီးရန် မအောင်မြင်ပါ',
      'pleaseEnterAGoalName': 'ကျေးဇူးပြု၍ ပန်းတိုင် အမည်ကို ထည့်သွင်းပါ',
      'pleaseEnterTargetAmount': 'ကျေးဇူးပြု၍ ပန်းတိုင် ပမာဏကို ထည့်သွင်းပါ',
      'pleaseEnterAValidAmount': 'ကျေးဇူးပြု၍ မှန်ကန်သော ပမာဏကို ထည့်သွင်းပါ',
      'insufficientBalance': 'လက်ကျန်ငွေ မလုံလောက်ပါ',
      'selectTargetDate': 'ပန်းတိုင် ရက်စွဲကို ရွေးချယ်ပါ (စိတ်ကြိုက်)',
      'egEmergencyFund': 'ဥပမာ၊ အရေးပေါ် ရန်ပုံငွေ',

      // goal detail screen
      'goalInformation': 'ပန်းတိုင် အချက်အလက်',
      'fundsAddedSuccessfully': 'ရန်ပုံငွေများ အောင်မြင်စွာ ထည့်သွင်းပြီးပါပြီ။',
      'fundsWithdrawnSuccessfully': 'ရန်ပုံငွေများ အောင်မြင်စွာ ထုတ်ယူပြီးပါပြီ။',
      'manageFunds': 'ရန်ပုံငွေ စီမံခန့်ခွဲရန်',
      'currentProgress': 'လက်ရှိ တိုးတက်မှု',
      'currentAmount': 'လက်ရှိ ပမာဏ',
      'remaining': 'ကျန်ရှိသော',
      'targetDateDetail': 'ပန်းတိုင် ရက်စွဲ',
      'created': 'ဖန်တီးသည့်ရက်',
      'withdraw': 'ထုတ်ယူရန်',
      'add': 'ထည့်ရန်',
      'editGoal': 'ပန်းတိုင် ပြင်ဆင်ရန်',
      'enterAGoalName': 'ကျေးဇူးပြု၍ ပန်းတိုင် အမည်ကို ထည့်သွင်းပါ',
      'goalUpdatedSuccessfully': 'ပန်းတိုင် အောင်မြင်စွာ ပြင်ဆင်ပြီးပါပြီ။',
      'failedToUpdateGoal': 'ပန်းတိုင် ပြင်ဆင်ရန် မအောင်မြင်ပါ',
      'save': 'သိမ်းဆည်းရန်',
      'deleteGoal': 'ပန်းတိုင် ဖျက်ရန်',
      'deleteGoalConfirmation': 'ဤပန်းတိုင်ကို ဖျက်ရန် သေချာပါသလား? ခွဲဝေထားသော ရန်ပုံငွေများကို သင့်လက်ကျန်သို့ ပြန်လည်ရောက်ရှိမည်ဖြစ်သည်။',
      'delete': 'ဖျက်ရန်',
      'failedToDeleteGoal': 'ပန်းတိုင် ဖျက်ရန် မအောင်မြင်ပါ',
      'goalDetails': 'ပန်းတိုင် အသေးစိတ်',

      //budgets screen
      'budgetCreatedSuccessfully':'ဘတ်ဂျက် အောင်မြင်စွာ ဖန်တီးပြီးပါပြီ။',
      'budgetDeletedSuccessfully': 'ဘတ်ဂျက် အောင်မြင်စွာ ဖျက်ပြီးပါပြီ။',
      'budgetSummary': 'ဘတ်ဂျက် အကျဉ်းချုပ်',
      'exceeded': 'ကျော်လွန်သွားသော',
      'allCurrencies': 'ငွေကြေးအားလုံး',
      'createNewBudget': 'ဘတ်ဂျက် အသစ် ဖန်တီးရန်',
      'upcoming': 'လာမည့်',
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
      'selectCurrency': 'ဤဘတ်ဂျက်အတွက် ငွေကြေးကို ရွေးပါ',
      'pleaseSelectCurrency': 'ကျေးဇူးပြု၍ ငွေကြေးကို ရွေးချယ်ပါ',
      'aiFeatures': 'AI လုပ်ဆောင်ချက်များ',
      'getAiPoweredBudgetSuggestions': 'AI-မှ စွမ်းဆောင်သော ဘတ်ဂျက် အကြံပြုချက်များကို ရယူပါ',
      'tapToUseAiBudgetSuggestions': 'AI ဘတ်ဂျက် အကြံပြုချက်များကို အသုံးပြုရန် နှိပ်ပါ',
      'context': 'အကြောင်းအရာ (စိတ်ကြိုက်)',
      'addContext': 'AI မှ ပိုမိုကောင်းမွန်သော ဘတ်ဂျက်များ ဖန်တီးနိုင်ရန် အကြောင်းအရာ ထည့်ပါ',
      'generateAiBudget': 'AI ဘတ်ဂျက် ထုတ်လုပ်ရန်',
      'aiWillAnalyzeAndSuggestBudgets' : 'AI သည် သင့်သုံးစွဲမှုကို ခွဲခြမ်းစိတ်ဖြာပြီး အမျိုးအစား ဘတ်ဂျက်များကို အကြံပြုမည်',
      'budgetName': 'ဘတ်ဂျက် အမည်',
      'enterBudgetName': 'ကျေးဇူးပြု၍ ဘတ်ဂျက် အမည်ကို ထည့်သွင်းပါ',
      'budgetPeriod': 'ဘတ်ဂျက် ကာလ',
      'week': 'အပတ်',
      'month': 'လ',
      'year': 'နှစ်',
      'custom': 'စိတ်ကြိုက်',
      'startDate': 'စတင်မည့်ရက်',
      'endDateNoOp': 'ပြီးဆုံးမည့်ရက်',
      'autoCreateNextBudget':  'နောက် ဘတ်ဂျက်ကို အလိုအလျောက် ဖန်တီးရန်',
      'automaticallyCreateNewBudget': 'ဤဘတ်ဂျက် ပြီးဆုံးသည့်အခါ ဘတ်ဂျက်အသစ်ကို အလိုအလျောက် ဖန်တီးပါ',
      'enableAutoCreate': 'အလိုအလျောက် ဖန်တီးခြင်း ဖွင့်ရန်',
      'chooseHowToCreateNextBudget': 'နောက်ဘတ်ဂျက်ကို မည်သို့ ဖန်တီးမည်ကို ရွေးချယ်ပါ:',
      'useCurrentCategories': 'လက်ရှိ အမျိုးအစားများကို အသုံးပြုရန်',
      'keepTheSameBudgetAmounts': 'အမျိုးအစားအားလုံးအတွက် တူညီသော ဘတ်ဂျက် ပမာဏများကို ထားရှိရန်',
      'aiOptimizedBudget': 'AI-မှ အကောင်းဆုံးဖြစ်အောင် ပြုလုပ်ထားသော ဘတ်ဂျက်',
      'aiAnalyzesSpendingAndSuggestsAmounts': 'AI သည် သင့်သုံးစွဲမှုကို ခွဲခြမ်းစိတ်ဖြာပြီး အကောင်းဆုံး ပမာဏများကို အကြံပြုမည်',
      'categoryBudgets': 'အမျိုးအစား ဘတ်ဂျက်များ',
      'noCategoriesAddedYet': 'အမျိုးအစားများ မထည့်သွင်းရသေးပါ',
      'totalBudget': 'စုစုပေါင်း ဘတ်ဂျက်',
      'addCategoryBudget': 'အမျိုးအစား ဘတ်ဂျက် ထည့်ရန်',
      'editCategoryBudget': 'အမျိုးအစား ဘတ်ဂျက် ပြင်ဆင်ရန်',
      'subCategory': 'အမျိုးအစားခွဲ (စိတ်ကြိုက်)',
      'allNoFilter': 'အားလုံး (စစ်ထုတ်မှုမရှိ)',
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
      'currencyC': 'ငွေကြေး (ပြောင်းလဲ၍ မရပါ)',
      'editingCategoriesRecalculateAlert': 'အမျိုးအစားများကို ပြင်ဆင်ခြင်းသည် သုံးစွဲထားသော ပမာဏများကို ပြန်လည်သတ်မှတ်မည်ဖြစ်သည်။ လက်ရှိသုံးစွဲမှုကို ပြန်လည်တွက်ချက်မည်။',
      'newTotalBudget': 'စုစုပေါင်း ဘတ်ဂျက် အသစ်',
      'currentTotal': 'လက်ရှိ စုစုပေါင်း',
      'saveChanges': 'အပြောင်းအလဲများကို သိမ်းဆည်းရန်',

      //budget detail screen
      'deleteBudget': 'ဘတ်ဂျက် ဖျက်ရန်',
      'deleteBudgetAlert': 'ဤဘတ်ဂျက်ကို ဖျက်ရန် သေချာပါသလား? ဤလုပ်ဆောင်ချက်ကို ပြန်ဖျက်၍ မရပါ။',
      'deleted': 'ဖျက်လိုက်ပြီ',
      'failedToDeleteBudget': 'ဘတ်ဂျက် ဖျက်ရန် မအောင်မြင်ပါ',
      'startsIn': 'စတင်ရန် ကျန်ရှိသော',
      'ended': 'ပြီးဆုံးသွားပြီ',
      'daysRemaining': 'ကျန်ရှိသော ရက်များ',
      'budgetDetails': 'ဘတ်ဂျက် အသေးစိတ်',
      'budgetWasAutomaticallyCreatedAi': 'ဤဘတ်ဂျက်ကို AI အကောင်းဆုံးဖြစ်အောင် လုပ်ဆောင်မှုဖြင့် အလိုအလျောက် ဖန်တီးထားခြင်း ဖြစ်သည်',
      'budgetWasAutomaticallyCreatedPrevious': 'ဤဘတ်ဂျက်ကို အရင်ဘတ်ဂျက်မှ အလိုအလျောက် ဖန်တီးထားခြင်း ဖြစ်သည်',
      'autoCreateEnabled': 'အလိုအလျောက် ဖန်တီးခြင်း ဖွင့်ထားသည်',
      'nextBudgetWillBeAiOptimized': 'နောက်ဘတ်ဂျက်ကို သင့်သုံးစွဲမှုအပေါ် အခြေခံ၍ AI-မှ အကောင်းဆုံးဖြစ်အောင် ပြုလုပ်မည်',
      'nextBudgetWillUseSameAmounts': 'နောက်ဘတ်ဂျက်တွင် တူညီသော အမျိုးအစား ပမာဏများကို အသုံးပြုမည်',
      'budgetExceeded': 'ဘတ်ဂျက် ကျော်လွန်သွားသည်',
      'budgetExceededAlert': 'သင်သည် ခွဲဝေထားသော ဘတ်ဂျက်ထက် ပိုမို သုံးစွဲခဲ့သည်။ ကျော်လွန်သွားသော အမျိုးအစားများတွင် သုံးစွဲမှုကို လျှော့ချရန် စဉ်းစားပါ။',
      'approachingBudgetLimit': 'ဘတ်ဂျက် ကန့်သတ်ချက်သို့ နီးကပ်လာသည်',

      //ai budget suggestion screen
      'analysisSummary': 'ခွဲခြမ်းစိတ်ဖြာချက် အကျဉ်းချုပ်',
      'transactionsAnalyzed': 'ခွဲခြမ်းစိတ်ဖြာခဲ့သော ငွေစာရင်းသွင်းမှုများ',
      'analysisPeriod': 'ခွဲခြမ်းစိတ်ဖြာမှု ကာလ',
      'categoriesFound': 'တွေ့ရှိသော အမျိုးအစားများ',
      'avgMonthlyIncome': 'ပျမ်းမျှ လစဉ် ဝင်ငွေ',
      'avgMonthlyExpenses': 'ပျမ်းမျှ လစဉ် အသုံးစရိတ်များ',
      'activeGoals': 'ဆောင်ရွက်ဆဲ ပန်းတိုင်များ',
      'close': 'ပိတ်ရန်',
      'aiBudgetSuggestion': 'AI ဘတ်ဂျက် အကြံပြုချက်',
      'analysisDetails': 'ခွဲခြမ်းစိတ်ဖြာချက် အသေးစိတ်',
      'failedToGenerateSuggestion': 'အကြံပြုချက် ထုတ်လုပ်ရန် မအောင်မြင်ပါ',
      'tryAgain': 'ထပ်ကြိုးစားပါ',
      'dataConfidence': 'ဒေတာ ယုံကြည်စိတ်ချရမှု',
      'highConfidence': 'သင့်ဒေတာအပေါ် အခြေခံ၍ ယုံကြည်စိတ်ချရမှု မြင့်မားသည်',
      'moderateConfidence': 'ယုံကြည်စိတ်ချရမှု အသင့်အတင့် - ကန့်သတ်ထားသော ဒေတာ',
      'lowConfidence': 'ယုံကြည်စိတ်ချရမှု နည်းပါး - အလွန် ကန့်သတ်ထားသော ဒေတာ',
      'yourContext': 'သင့် အကြောင်းအရာ',
      'importantNotes': 'အရေးကြီး မှတ်စုများ',
      'suggestedBudgetPlan': 'အကြံပြုထားသော ဘတ်ဂျက် အစီအစဉ်',
      'name': 'အမည်',
      'aiAnalysis': 'AI ခွဲခြမ်းစိတ်ဖြာချက်',
      'useThisBudget': 'အသုံးပြုရန်',

      //ai chat screen
      'responseStyle': 'တုံ့ပြန်မှု ပုံစံ',
      'chooseAiResponses': 'AI တုံ့ပြန်မှုများ မည်မျှ အသေးစိတ်လိုသည်ကို ရွေးပါ',
      'thinking': 'စဉ်းစားနေသည်...',
      'financialAdvisor': 'ဘဏ္ဍာရေး အကြံပေး',
      'stopResponse': 'တုံ့ပြန်မှုကို ရပ်ရန်',
      'changeResponseStyle': 'တုံ့ပြန်မှု ပုံစံကို ပြောင်းရန်',
      'clearHistory': 'မှတ်တမ်း ရှင်းလင်းရန်',
      'loadingChatHistory': 'စကားပြော မှတ်တမ်း တင်နေသည်...',
      'upgradeToPremium': 'ပရီမီယံသို့ အဆင့်မြှင့်ပါ',
      'unlockFullCapabilities': 'AI စကားပြော လုပ်ဆောင်ချက် အပြည့်အစုံကို ဖွင့်ရန်',
      'upgrade': 'အဆင့်မြှင့်ရန်',
      'helloAi': 'မင်္ဂလာပါ! ကျွန်ုပ်သည် သင့်၏ AI ဘဏ္ဍာရေး အကူအညီပေးသူ ဖြစ်ပါသည်',
      'aiChatDes': 'သင့်သုံးစွဲမှုကို ခွဲခြမ်းစိတ်ဖြာခြင်း၊ ထိုးထွင်းသိမြင်မှုများ ပေးခြင်းနှင့် သင့်ဘဏ္ဍာရေးဆိုင်ရာ မေးခွန်းများကို ဖြေကြားခြင်းတို့ဖြင့် ကျွန်ုပ် ကူညီနိုင်ပါသည်။',
      'tryAskingMeSomething': 'ဤကဲ့သို့ မေးကြည့်ပါ:',
      'aiIsTyping': 'AI စာရိုက်နေသည်...',
      'upgradeToPremiumToChat': 'စကားပြောရန် ပရီမီယံသို့ အဆင့်မြှင့်ပါ',
      'aiIsResponding': 'AI တုံ့ပြန်နေသည်...',
      'askAboutFinances': 'သင့်ဘဏ္ဍာရေးအကြောင်း မေးပါ...',
      'clearChatHistory': 'စကားပြော မှတ်တမ်း ရှင်းလင်းရန်',
      'clearChatHistoryAlert': 'စကားပြော မှတ်တမ်း အားလုံးကို ရှင်းလင်းရန် သေချာပါသလား? ဤလုပ်ဆောင်ချက်ကို ပြန်ဖျက်၍ မရပါ။',
      'clear': 'ရှင်းလင်းရန်',
      'generatingInsights': 'ထိုးထွင်းသိမြင်မှုများ ထုတ်လုပ်နေသည်...',
      'insightsRegeneratedSuccessfully': 'ထိုးထွင်းသိမြင်မှုများ အောင်မြင်စွာ ပြန်လည်ထုတ်လုပ်ပြီးပါပြီ။',
      'failedToRegenerateInsights': 'ထိုးထွင်းသိမြင်မှုများ ပြန်လည်ထုတ်လုပ်ရန် မအောင်မြင်ပါ',
      'deepSpendingAnalysis': 'နက်ရှိုင်းသော သုံးစွဲမှု ခွဲခြမ်းစိတ်ဖြာချက်',
      'personalizedRecommendations': 'ပုဂ္ဂိုလ်ရေးဆိုင်ရာ အကြံပြုချက်များ',
      'financialHealthScore': 'ဘဏ္ဍာရေး ကျန်းမာရေး အမှတ်',
      'savingsOpportunities': 'စုဆောင်းနိုင်မည့် အခွင့်အလမ်းများ',
      'budgetOptimizationTips': 'ဘတ်ဂျက်ကို အကောင်းဆုံးဖြစ်အောင် လုပ်ဆောင်ရန် အကြံပြုချက်များ',
      'analyzingYourFinancialData': 'သင့်ဘဏ္ဍာရေး ဒေတာကို ခွဲခြမ်းစိတ်ဖြာနေသည်...',
      'thisMayTakeFewSeconds': '၎င်းသည် စက္ကန့်အနည်းငယ် ကြာနိုင်သည်',
      'failedToLoadInsights': 'ထိုးထွင်းသိမြင်မှုများ တင်ရန် မအောင်မြင်ပါ',
      'noInsightsAvailable': 'ထိုးထွင်းသိမြင်မှုများ မရရှိနိုင်ပါ',
      'addTransactionsGoalsToGenerateInsights': 'ထိုးထွင်းသိမြင်မှုများ ထုတ်လုပ်ရန် ငွေစာရင်းသွင်းမှုများနှင့် ပန်းတိုင်များကို ထည့်ပါ',
      'aiGeneratedInsights': 'AI-မှ ထုတ်လုပ်သော ထိုးထွင်းသိမြင်မှုများ',
      'normal': 'ပုံမှန်',
      'concise': 'ကျစ်လျစ်သော',
      'detailed': 'အသေးစိတ်',
      'balancedResponses': 'မျှတသော တုံ့ပြန်မှုများ',
      'briefDirect': 'အတိုချုပ်နှင့် တိုက်ရိုက်',
      'thoroughExplanations': 'ပြည့်စုံသော ရှင်းလင်းချက်များ',

      //notification screen
      'notifications': 'အသိပေးချက်များ',
      'markedAsRead': 'အသိပေးချက်များ အားလုံးကို ဖတ်ပြီးအဖြစ် အမှတ်အသားပြုပြီးပါပြီ',
      'markAllRead': 'အားလုံး ဖတ်ပြီးအဖြစ် အမှတ်အသားပြုရန်',
      'notificationDeleted': 'အသိပေးချက် ဖျက်လိုက်ပြီ',
      'undo': 'ပြန်ဖျက်ရန်',
      'noNotificationsYet': 'အသိပေးချက် မရှိသေးပါ',
      'notifyGoalsProgress': 'သင့်ဘဏ္ဍာရေး ပန်းတိုင်များ တိုးတက်မှုအကြောင်း ကျွန်ုပ်တို့ အသိပေးပါမည်',

      //reports screen
      'selectStartEndDates': 'ကျေးဇူးပြု၍ စတင်မည့်ရက်နှင့် ပြီးဆုံးမည့်ရက် နှစ်ခုလုံးကို ရွေးချယ်ပါ',
      'reportDownloadedSuccessfully': 'အစီရင်ခံစာ အောင်မြင်စွာ ဒေါင်းလုဒ်လုပ်ပြီးပါပြီ။',
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
      'goalsAllocated': 'ပန်းတိုင်များသို့ ခွဲဝေထားသော',
      'dailyAverages': 'နေ့စဉ် ပျမ်းမျှများ',
      'averageDailyIncome': 'ပျမ်းမျှ နေ့စဉ် ဝင်ငွေ',
      'averageDailyExpenses': 'ပျမ်းမျှ နေ့စဉ် အသုံးစရိတ်များ',
      'incomeByCategory': 'အမျိုးအစားအလိုက် ဝင်ငွေ',
      'expensesByCategory': 'အမျိုးအစားအလိုက် အသုံးစရိတ်များ',
      'goalsProgress': 'ပန်းတိုင်များ တိုးတက်မှု',
      'multiCurrencyReport': 'ငွေကြေးမျိုးစုံ အစီရင်ခံစာ',
      'overview': 'ခြုံငုံကြည့်ရှုမှု',
      'totalTransactions': 'စုစုပေါင်း ငွေစာရင်းသွင်းမှုများ',
      'currencies': 'ငွေကြေးများ',
      'allGoals': 'ပန်းတိုင်များ အားလုံး',
      'avgDailyIncome': 'ပျမ်းမျှ နေ့စဉ် ဝင်ငွေ',
      'avgDailyExpenses': 'ပျမ်းမျှ နေ့စဉ် အသုံးစရိတ်များ',
      'viewCategories': 'အမျိုးအစားများ ကြည့်ရန်',
      'topIncomeCategories': 'ထိပ်တန်း ဝင်ငွေ အမျိုးအစားများ',
      'topExpenseCategories': 'ထိပ်တန်း အသုံးစရိတ် အမျိုးအစားများ',
      'account': 'အကောင့်',
      'editProfile': 'ပရိုဖိုင် ပြင်ဆင်ရန်',
      'updateYourName': 'သင့်အမည်ကို အပ်ဒိတ်လုပ်ပါ',
      'profileUpdatedSuccessfully': 'ပရိုဖိုင် အောင်မြင်စွာ အပ်ဒိတ်လုပ်ပြီးပါပြီ။',
      'changePassword': 'စကားဝှက် ပြောင်းရန်',
      'updateYourPassword': 'သင့်စကားဝှက်ကို အပ်ဒိတ်လုပ်ပါ',
      'passwordChangedSuccessfully': 'စကားဝှက် အောင်မြင်စွာ ပြောင်းပြီးပါပြီ။',
      'language': 'ဘာသာစကား',
      'changeAppLanguage': 'အက်ပ် ဘာသာစကား ပြောင်းရန်',
      'changeDefaultCurrency': 'မူရင်း ငွေကြေး ပြောင်းရန်',
      'notificationSettings': 'အသိပေးချက် ဆက်တင်များ',
      'manageNotificationPreferences': 'အသိပေးချက် စိတ်ကြိုက်ရွေးချယ်မှုများကို စီမံခန့်ခွဲရန်',
      'subscription': 'စာရင်းသွင်းမှု',
      'manageSubscription': 'စာရင်းသွင်းမှုကို စီမံခန့်ခွဲရန်',
      'viewManageSubscription': 'သင့်စာရင်းသွင်းမှုကို ကြည့်ရှုပြီး စီမံခန့်ခွဲပါ',
      'unlockPremiumFeatures': 'ပရီမီယံ လုပ်ဆောင်ချက်များ အားလုံးကို ဖွင့်ရန်',
      'about': 'အကြောင်း',
      'aboutFlowFinance': 'Flow Finance အကြောင်း',

      //notification settings screen
      'notificationsEnabled': 'အသိပေးချက်များ ဖွင့်ထားသည်! 🔔',
      'changeNotificationSettingsDes': 'အသိပေးချက် ဆက်တင်များကို ပြောင်းရန်၊ ကျေးဇူးပြု၍ သင့်စက်၏ ဆက်တင်များသို့ သွားပါ။',
      'openSettings': 'ဆက်တင်များ ဖွင့်ရန်',
      'testNotification': 'စမ်းသပ် အသိပေးချက် 🎉',
      'testNotificationDes': '၎င်းသည် Flow Finance မှ စမ်းသပ် အသိပေးချက် ဖြစ်ပါသည်!',
      'testNotificationMsg': 'စမ်းသပ် အသိပေးချက် ပေးပို့ပြီးပါပြီ! သင့်အသိပေးချက် ဗန်းကို စစ်ဆေးပါ။',
      'resetToDefaults': 'မူရင်းသို့ ပြန်လည်သတ်မှတ်မလား?',
      'enableAllNotificationTypes': '၎င်းသည် အသိပေးချက် အမျိုးအစားများ အားလုံးကို ဖွင့်ပေးမည်ဖြစ်သည်။ သေချာပါသလား?',
      'notificationPreferencesReset': 'အသိပေးချက် စိတ်ကြိုက်ရွေးချယ်မှုများကို မူရင်းသို့ ပြန်လည်သတ်မှတ်ပြီးပါပြီ',
      'failedToResetPreferences': 'စိတ်ကြိုက်ရွေးချယ်မှုများကို ပြန်လည်သတ်မှတ်ရန် မအောင်မြင်ပါ',
      'reset': 'ပြန်လည်သတ်မှတ်ရန်',
      'resetToDefaultsWQ': 'မူရင်းသို့ ပြန်လည်သတ်မှတ်ရန်',
      'pushNotifications': 'တွန်းပို့ အသိပေးချက်များ',
      'receiveUpdatesAboutFinances': 'သင့်ဘဏ္ဍာရေးအကြောင်း အပ်ဒိတ်များကို လက်ခံရယူပါ',
      'sendTestNotification': 'စမ်းသပ် အသိပေးချက် ပေးပို့ရန်',
      'customizeNotificationsReceive': 'သင်လက်ခံလိုသော အသိပေးချက်များကို စိတ်ကြိုက်ပြုပြင်ပါ',
      'notificationTypes': 'အသိပေးချက် အမျိုးအစားများ',
      'progressUpdates': 'တိုးတက်မှု အပ်ဒိတ်များ',
      'notifiedMilestones': '၂၅%၊ ၅၀%၊ ၇၅% မှတ်တိုင်များတွင် အသိပေးမည်',
      'milestoneReached': 'မှတ်တိုင်သို့ ရောက်ရှိပြီ',
      'thousandSavedTowardsGoal': 'ပန်းတိုင်အတွက် ဒေါ်လာ ၁,၀၀၀ စုဆောင်းတိုင်း',
      'deadlineApproaching': 'နောက်ဆုံးရက် နီးလာသည်',
      'reminders': '၁၄၊ ၇၊ နှင့် ၃ ရက်အလိုတွင် သတိပေးချက်များ',
      'goalAchieved': 'ပန်းတိုင် အောင်မြင်ပြီ',
      'celebrate': 'သင်၏ ပန်းတိုင်သို့ ရောက်ရှိသည့်အခါ ဂုဏ်ပြုပါ!',
      'budgetStarted': 'ဘတ်ဂျက် စတင်ပြီ',
      'whenNewBudgetBegins': 'ဘတ်ဂျက်ကာလ အသစ် စတင်သည့်အခါ',
      'periodEndingSoon': 'ကာလ မကြာမီ ပြီးဆုံးတော့မည်',
      'reminderBudgets': 'ကာလ မကုန်ဆုံးမီ ၃ ရက်အလိုတွင် သတိပေးချက်',
      'budgetThreshold': 'ဘတ်ဂျက် ကန့်သတ်ချက်',
      'alertBudget': 'ဘတ်ဂျက်၏ ၈၀% သုံးစွဲသည့်အခါ အသိပေးပါ',
      'whenOverBudgetLimit': 'ဘတ်ဂျက် ကန့်သတ်ချက်ထက် ကျော်လွန်သွားသည့်အခါ',
      'autoCreatedBudget': 'အလိုအလျောက် ဖန်တီးထားသော ဘတ်ဂျက်',
      'budgetCreatedAutomatically': 'ဘတ်ဂျက်အသစ် အလိုအလျောက် ဖန်တီးပြီးပါပြီ',
      'budgetNowActive': 'ဘတ်ဂျက် ယခု ဆောင်ရွက်ဆဲ',
      'whenBudgetBecomesActive': 'လာမည့်ဘတ်ဂျက် ဆောင်ရွက်ဆဲ ဖြစ်လာသည့်အခါ',
      'largeTransaction': 'ကြီးမားသော ငွေစာရင်းသွင်းမှု',
      'alertsLargeExpenses': 'ပုံမှန်မဟုတ်သော ကြီးမားသော အသုံးစရိတ်များအတွက် အသိပေးချက်များ',
      'unusualSpending': 'ပုံမှန်မဟုတ်သော သုံးစွဲမှု',
      'whenSpendingPatternsChange': 'သုံးစွဲမှု ပုံစံများ ပြောင်းလဲသည့်အခါ',
      'paymentReminders': 'ပေးချေမှု သတိပေးချက်များ',
      'upcomingPayments': 'လာမည့် ထပ်တလဲလဲ ပေးချေမှုများ',
      'recurringCreated': 'ထပ်တလဲလဲ ဖန်တီးပြီး',
      'recurringEnded': 'ထပ်တလဲလဲ ပြီးဆုံးပြီ',
      'whenRecurringEnds': 'ထပ်တလဲလဲ စီးရီး ပြီးဆုံးသည့်အခါ',
      'recurringDisabled': 'ထပ်တလဲလဲ ပိတ်ထားသည်',
      'whenRecurrenceDisabled': 'ထပ်တလဲလဲ ပြုလုပ်ခြင်း ပိတ်ထားသည့်အခါ',
      'whenRecurringTransactionsCreated': 'ထပ်တလဲလဲ ငွေစာရင်းသွင်းမှုများ ဖန်တီးသည့်အခါ',

      //edit profile screen
      'failedUpdateProfile': 'ပရိုဖိုင် အပ်ဒိတ်လုပ်ရန် မအောင်မြင်ပါ',
      'discardChanges': 'အပြောင်းအလဲများကို ပယ်ဖျက်မလား?',
      'discardChangesAlert': 'သင့်တွင် မသိမ်းဆည်းရသေးသော အပြောင်းအလဲများ ရှိသည်။ ၎င်းတို့ကို ပယ်ဖျက်ရန် သေချာပါသလား?',
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

      //currency settings screen
      'currencySettings': 'ငွေကြေး ဆက်တင်များ',
      'selectDefaultCurrency': 'မူရင်း ငွေကြေးကို ရွေးချယ်ပါ',
      'preferredCurrency': 'သင်နှစ်သက်သော ငွေကြေးကို ရွေးချယ်ပါ',
      'eachCurrencyOwnBalance': 'မည်သည့် ငွေကြေးဖြင့်မဆို ငွေစာရင်းသွင်းမှုများ ထည့်နိုင်ပါသည်။ ငွေကြေးတစ်ခုစီတွင် ၎င်း၏ကိုယ်ပိုင် လက်ကျန်ငွေ ရှိသည်။',

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
      'accessAllPremiumFeatures': 'သင်သည် ယခု ပရီမီယံ လုပ်ဆောင်ချက်များ အားလုံးကို အသုံးပြုနိုင်ပါပြီ။',
      'getStarted': 'စတင်ရန်',
      'premiumStatus': 'ပရီမီယံ အခြေအနေ',
      'premiumActive': 'ပရီမီယံ အသက်ဝင်သည်',
      'premiumFeatures': 'ပရီမီယံ လုပ်ဆောင်ချက်များ',
      'aiBudgetSuggestions': 'AI ဘတ်ဂျက် အကြံပြုချက်များ',
      'aiBudgetSuggestionsDes': 'သင့်သုံးစွဲမှု ပုံစံများအပေါ် အခြေခံ၍ စမတ်ကျသော ဘတ်ဂျက် အကြံပြုချက်များကို ရယူပါ',
      'voiceInputDes': 'ရိုးရှင်းစွာ ပြောဆိုရုံဖြင့် ငွေစာရင်းသွင်းမှုများ ထည့်ပါ',
      'receiptScanning': 'ဘောင်ချာ စကန်ဖတ်ခြင်း',
      'receiptScanningDes': 'ဘောင်ချာများကို စကန်ဖတ်ပြီး ငွေစာရင်းသွင်းမှု အသေးစိတ်များကို အလိုအလျောက် ထုတ်ယူပါ',
      'aiFinancialAssistant': 'AI ဘဏ္ဍာရေး အကူအညီပေးသူ',
      'aiFinancialAssistantDes': 'ပုဂ္ဂိုလ်ရေးဆိုင်ရာ ဘဏ္ဍာရေး အကြံဉာဏ်များအတွက် AI နှင့် စကားပြောပါ',
      'aiInsightsDes': 'သင့်သုံးစွဲမှု အလေ့အကျင့်များအပေါ် နက်ရှိုင်းသော ထိုးထွင်းသိမြင်မှုများ ရယူပါ',
      'premiumPlan': 'ပရီမီယံ အစီအစဉ်',
      'tryCancelAnytime': 'ရက် ၃၀ စမ်းသပ်ပါ • အချိန်မရွေး ပယ်ဖျက်နိုင်သည်',
    }
  };

  String translate(String key) {
    return _localizedValues[locale.languageCode]?[key] ?? key;
  }

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
  String get keepTheSameBudgetAmounts => translate('useCurrentCategories');
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
  String get notificationSettings => translate('notificationSettings');
  String get manageNotificationPreferences => translate('manageNotificationPreferences');
  String get subscription => translate('subscription');
  String get manageSubscription => translate('manageSubscription');
  String get viewManageSubscription => translate('viewManageSubscription');
  String get unlockPremiumFeatures => translate('unlockPremiumFeatures');
  String get about => translate('about');
  String get aboutFlowFinance => translate('aboutFlowFinance');



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