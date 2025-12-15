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
      'welcomeBack': 'ပြန်လည်ကြိုဆိုပါတယ်၊',
      'totalBalance': 'စုစုပေါင်းလက်ကျန်ငွေ',
      'available': 'အသုံးပြုနိုင်သော',
      'allocatedToGoals': 'ရည်မှန်းချက်များအတွက် ခွဲဝေထားသည်',
      'inflow': 'ဝင်ငွေ',
      'outflow': 'ထွက်ငွေ',
      'aiAssistant': 'AI လက်ထောက်',
      'getPersonalizedInsights': 'ကိုယ်ပိုင်ထိုးထွင်းသိမြင်မှုများရယူပါ',
      'aiInsights': 'AI ထိုးထွင်းသိမြင်မှု',
      'viewComprehensiveAnalysis': 'ဘဏ္ဍာရေးခွဲခြမ်းစိတ်ဖြာမှုကြည့်ရှုပါ',
      'recentTransactions': 'ငွေသွင်းထုတ်မှတ်တမ်းများ',
      'seeMore': 'ထပ်ကြည့်ရန်',
      'noTransactions': 'ငွေသွင်းထုတ်မှတ်တမ်းမရှိသေးပါ',
      'tapToAddFirst': 'သင့်ရဲ့ပထမဆုံးငွေသွင်းထုတ်မှတ်တမ်းထည့်ရန် + ခလုတ်ကိုနှိပ်ပါ',
      'addTransaction': 'ငွေသွင်းထုတ်မှတ်တမ်းထည့်ရန်',
      'manualEntry': 'လက်ဖြင့်ထည့်ခြင်း',
      'typeTransactionDetails': 'ငွေသွင်းထုတ်မှတ်တမ်းအသေးစိတ်ရိုက်ထည့်ပါ',
      'voiceInput': 'အသံဖြင့်ထည့်ခြင်း',
      'speakYourTransaction': 'သင့်ငွေသွင်းထုတ်မှတ်တမ်းကိုပြောပါ',
      'scanReceipt': 'စကန်ဖတ်ခြင်း',
      'takeUploadPhoto': 'ငွေလက်ခံဖြတ်ပိုင်းဓာတ်ပုံရိုက်ခြင်း သို့မဟုတ် တင်ခြင်း',
      'premium': 'ပရီမီယံ',
      'transactionAdded': 'ငွေသွင်းထုတ်မှတ်တမ်းအောင်မြင်စွာထည့်သွင်းပြီးပါပြီ!',
      'transactionUpdated': 'ငွေသွင်းထုတ်မှတ်တမ်းအောင်မြင်စွာပြင်ဆင်ပြီးပါပြီ!',
      'transactionDeleted': 'ငွေသွင်းထုတ်မှတ်တမ်းအောင်မြင်စွာဖျက်ပြီးပါပြီ!',
      'dashboard': 'ဒက်ရှ်ဘုတ်',
      'autoCreated': 'အလိုအလျောက်ဖန်တီးထားသည်',
      'viewAllCurrencies':'View All Currencies',
      'allCurrencyBalances':'All Currency Balances',
      'default':'Default',


      // Drawer Navigation
      'drawerWelcome': 'ကြိုဆိုပါသည်',
      'drawerLogout': 'ထွက်ရန်',
      'dialogCancel': 'ပယ်ဖျက်ပါ',
      'dialogLogoutConfirm': 'ထွက်ရန်သေချာပါသလား?',
      'transactions': 'ငွေသွင်းထုတ်မှတ်တမ်းများ',
      'goals': 'ရည်မှန်းချက်များ',
      'budgets': 'ဘတ်ဂျက်များ',
      'inflowAnalytics': 'ဝင်ငွေခွဲခြမ်းစိတ်ဖြာမှု',
      'outflowAnalytics': 'ထွက်ငွေခွဲခြမ်းစိတ်ဖြာမှု',
      'financialReports': 'ဘဏ္ဍာရေးအစီရင်ခံစာများ',
      'settings': 'ဆက်တင်များ',
      'expiresOn': 'ကုန်ဆုံးမည့်ရက်:',

      // Add Transaction Screen
      'addTransactionTitle': 'ငွေသွင်းထုတ်မှတ်တမ်းထည့်ရန်',
      'amountLabel': 'ပမာဏ',
      'currency': 'Currency',
      'convertCurrency': 'Convert Currency',
      'current': 'Current: ',
      'convertTo': 'Convert To: ',
      'exchangeRate': 'Exchange Rate:',
      'convert': 'Convert',
      'selectTargetCurrency': 'Select target currency',
      'dateLabel': 'ရက်စွဲ',
      'categoryLabel': 'အမျိုးအစား',
      'selectMainCategoryHint': 'အဓိကအမျိုးအစားရွေးပါ',
      'selectSubCategoryHint': 'အသေးစားအမျိုးအစားရွေးပါ',
      'descriptionLabel': 'ဖော်ပြချက် (optional)',
      'descriptionHint': 'ဤငွေလွှဲပြောင်းမှုအတွက် မှတ်ချက်ထည့်ပါ...',
      'addOutflowButton': 'ထွက်ငွေထည့်ပါ',
      'addInflowButton': 'ဝင်ငွေထည့်ပါ',
      'validationAmountRequired': 'ကျေးဇူးပြု၍ ပမာဏကို ထည့်ပါ',
      'validationAmountInvalid': 'ကျေးဇူးပြု၍ မှန်ကန်သော ပမာဏကို ထည့်ပါ',
      'validationAmountPositive': 'ပမာဏသည် 0 ထက်ပိုရမည်',
      'validationMainCategoryRequired': 'ကျေးဇူးပြု၍ အဓိကအမျိုးအစားကို ရွေးချယ်ပါ',
      'validationSubCategoryRequired': 'ကျေးဇူးပြု၍ အသေးစားအမျိုးအစားကို ရွေးချယ်ပါ',
      'recurringTransaction': 'Recurring Transaction',
      'recurringTransactionDes': 'Automatically create this transaction',
      'repeatFrequency': 'Repeat Frequency',
      'dayOfMonth': 'Day of Month',
      'daily': 'နေ့စဉ်',
      'weekly': 'အပတ်စဉ်',
      'monthly': 'လစဉ်',
      'annually': 'နှစ်စဉ်',
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

      // Edit Transaction Screen
      'editTransactionTitle': 'ငွေသွင်းထုတ်မှတ်တမ်းကို ပြင်ဆင်ပါ',
      'deleteTransactionTitle': 'ငွေသွင်းထုတ်မှတ်တမ်းကို ဖျက်ပါ',
      'deleteConfirmMessage': 'ဤငွေသွင်းထုတ်မှတ်တမ်းကို ဖျက်မှာ သေချာပါသလား? ဤလုပ်ဆောင်ချက်ကို ပြန်လည်ပြုပြင်၍မရပါ။',
      'autoCreatedTransactionTitle': 'အလိုအလျောက်ဖန်တီးထားသော ငွေသွင်းထုတ်မှတ်တမ်း',
      'autoCreatedDescriptionRecurring': 'ဤသည်မှာ ပုံမှန်ငွေသွင်းထုတ်မှုမှ အလိုအလျောက်ဖန်တီးထားခြင်းဖြစ်ပါသည်။',
      'autoCreatedDescriptionDisabled': 'ဤသည်မှာ ပုံမှန်ငွေသွင်းထုတ်မှုမှ အလိုအလျောက်ဖန်တီးထားခြင်းဖြစ်ပါသည်။ (ယခုပိတ်ထားပါသည်။)',
      'stopFutureAutoCreation': 'အလိုအလျောက်ဖန်တီးခြင်းကို ရပ်တန့်ပါ',
      'viewParentTransaction': 'မူရင်းငွေသွင်းထုတ်မှတ်တမ်းကို ကြည့်ပါ',
      'stopRecurringDialogTitle': 'ပုံမှန်ငွေသွင်းထုတ်မှုကို ရပ်တန့်မည်လား?',
      'stopRecurringDialogContent': 'ဤသည်မှာ အနာဂတ် ငွေသွင်းထုတ်မှုများကို အလိုအလျောက် ဖန်တီးခြင်းကို ရပ်တန့်ပါမည်။',
      'stopRecurringDialogInfo': 'ယခင်ငွေသွင်းထုတ်မှုများမှာ ထိခိုက်မည်မဟုတ်ပါ။',
      'stopRecurringButton': 'ပုံမှန်ရပ်တန့်ပါ',
      'stoppingRecurrence': 'ပုံမှန်ရပ်တန့်နေသည်',
      'pleaseWait': 'ကျေးဇူးပြု၍ စောင့်ဆိုင်းပါ...',
      'successTitle': 'အောင်မြင်ပါပြီ!',
      'successAutoCreationStopped': 'အလိုအလျောက်ဖန်တီးခြင်းကို ရပ်တန့်လိုက်ပါပြီ',
      'errorTitle': 'အမှား',
      'errorLoadParentFailed': 'မူရင်းငွေသွင်းထုတ်မှတ်တမ်းကို တင်ဆောင်ရန် ပျက်ကွက်သည်:',
      'updateTransactionButton': 'ငွေသွင်းထုတ်မှတ်တမ်းကို အပ်ဒိတ်လုပ်ပါ',
      'selectCurrencyT': 'Select currency',
      'recurringScheduleStopped': 'The recurring schedule for this transaction has been stopped.',
      'recurringSettingsStopDes': 'Recurring settings are managed by the parent transaction. Use the button above to stop future auto-creation.',
      'dismiss': 'DISMISS',

      // Image Input Screen
      'imageInputTitle': 'ပုံထည့်သွင်းခြင်း',
      'premiumFeatureTitle': 'ပရီမီယံ အင်္ဂါရပ်',
      'premiumFeatureUpgradeDescImg': 'ပုံမှ ငွေသွင်းထုတ်မှုများရယူရန် အဆင့်မြှင့်တင်ပါ',
      'upgradeNowButton': 'ယခု အဆင့်မြှင့်တင်ပါ',
      'tapToAddImagePlaceholder': 'လက်ခံပုံကိုထည့်ရန် တို့ပါ',
      'cameraOrGalleryPlaceholder': 'ကင်မရာ သို့မဟုတ် ပြခန်း',
      'chooseDifferentImageButton': 'အခြားပုံကို ရွေးပါ',
      'analyzingReceipt': 'လက်ခံကို ခွဲခြမ်းစိတ်ဖြာနေသည်...',
      'extractedTransactionTitle': 'ခွဲခြမ်းစိတ်ဖြာထားသော ငွေသွင်းထုတ်မှတ်တမ်း',
      'dataLabelType': 'အမျိုးအစား',
      'dataLabelAmount': 'ပမာဏ',
      'dataLabelCategory': 'အမျိုးအစား', // Note: 'Category' can be translated the same for both labels
      'dataLabelDate': 'ရက်စွဲ',
      'dataLabelDescription': 'ဖော်ပြချက်',
      'aiReasoningLabel': 'AI တွက်ချက်မှု:',
      'confidenceLabel': 'ယုံကြည်မှု:',
      'saveTransactionButton': 'ငွေသွင်းထုတ်မှတ်တမ်းကို သိမ်းဆည်းပါ',
      'errorCaptureImage': 'ပုံရိုက်ကူးရန် ပျက်ကွက်သည်:',
      'errorPickImage': 'ပုံရွေးချယ်ရန် ပျက်ကွက်သည်:',
      'chooseImageSourceModalTitle': 'ပုံရင်းမြစ်ကို ရွေးချယ်ပါ',
      'cameraListTileTitle': 'ကင်မရာ',
      'cameraListTileSubtitle': 'လက်ခံပုံ၏ ဓာတ်ပုံရိုက်ပါ',
      'galleryListTileTitle': 'ပြခန်း',
      'galleryListTileSubtitle': 'ပြခန်းမှ ရွေးချယ်ပါ',

      // Voice Input Screen
      'voiceInputTitle': 'အသံထည့်သွင်းခြင်း', // Adjusted from 'Voice Input' in the code snippet to match title
      'premiumFeatureUpgradeDescVoice': 'အသံမှ ငွေသွင်းထုတ်မှုများရယူရန် အဆင့်မြှင့်တင်ပါ',
      'recordingStatus': 'အသံဖမ်းနေသည်... ရပ်ရန် တို့ပါ',
      'tapToRecordStatus': 'အသံဖမ်းရန် တို့ပါ\nသင် ငွေသွင်းထုတ်မှုများစွာကို ဖော်ပြနိုင်သည်',
      'transcriptionTitle': 'အသံစာရင်း',
      'found_x_transactions': '%d ငွေသွင်းထုတ်မှတ်တမ်းများ တွေ့ရှိ', // Placeholder for count
      'transaction_x_card_title': 'ငွေသွင်းထုတ်မှတ်တမ်း %d', // Placeholder for index
      'save_x_transactions_button': '%d ငွေသွင်းထုတ်မှတ်တမ်းများ သိမ်းဆည်းပါ', // Placeholder for count
      'errorStartRecording': 'အသံဖမ်းရန် ပျက်ကွက်သည်:',
      'errorStopRecording': 'အသံဖမ်းရပ်တန့်ရန် ပျက်ကွက်သည်:',
      'analyzingTransactions': 'ငွေသွင်းထုတ်မှုများကို ခွဲခြမ်းစိတ်ဖြာနေသည်...',
      'success_save_transactions': '%d ငွေသွင်းထုတ်မှတ်တမ်း(များ)ကို အောင်မြင်စွာ သိမ်းဆည်းပြီးပါပြီ', // Placeholder for count

      // Transactions List Screen
      'allTransactionsTitle': 'အားလုံးသော ငွေသွင်းထုတ်မှတ်တမ်းများ',
      'filtersSectionTitle': 'စစ်ထုတ်မှုများ',
      'transactionTypeFilterLabel': 'ငွေသွင်းထုတ်မှတ်တမ်း အမျိုးအစား:',
      'filterChipAll': 'အားလုံး',
      'dateRangeFilterLabel': 'ရက်စွဲ ကန့်သတ်ချက်:',
      'selectDateRangeButton': 'ရက်စွဲ ကန့်သတ်ချက်ကို ရွေးပါ',
      'loadingMoreIndicator': 'နောက်ထပ် တင်နေသည်...',
      'emptyStateTitle': 'ငွေသွင်းထုတ်မှတ်တမ်း မတွေ့ရှိပါ',
      'emptyStateSubtitle': 'သင့်စစ်ထုတ်မှုများကို ချိန်ညှိပါ သို့မဟုတ် ငွေသွင်းထုတ်မှတ်တမ်းထည့်ပါ',
      'clearAllFiltersButton': 'စစ်ထုတ်မှုများအားလုံးကို ရှင်းလင်းပါ',
      'clearDateFilterTooltip': 'ရက်စွဲ စစ်ထုတ်မှုကို ရှင်းလင်းပါ',
      'addTransactionFabTooltip': 'ငွေသွင်းထုတ်မှတ်တမ်းအသစ်ထည့်ရန်',
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
      'selectTargetDate': 'Select target date',
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
      'upcoming':'UPCOMING',
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
  String get defaultBalance => translate('Default');



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
  String get selected => translate('Selected');
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
  String get aiChatDes => translate('AiChatDes');
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