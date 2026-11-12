import 'package:flutter/material.dart';
import 'package:frontend/utils/date_format.dart';
import 'package:frontend/models/plan_status.dart';
import 'package:frontend/models/user.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/plan_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/utils/contact_details.dart';
import 'package:frontend/widgets/accepted_payments.dart';
import 'package:frontend/widgets/owner_contact_block.dart';
import 'package:frontend/widgets/plan_badge.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../services/localization_service.dart';

/// The Upgrade screen: the user's current plan and a Free / Plus / Pro
/// comparison built from the limits the server reports (`GET /api/plan`), so
/// no number lives in the app, plus an "Upgrade to Plus / Pro" button for each
/// higher plan and a "Renew" button for a paid plan with an end date (upgrades
/// and renewals are manual: the owner sees the request in the admin panel) and
/// the owner's upgrade contact message and contact details (email, Viber,
/// Telegram, Facebook page, Messenger).
class SubscriptionScreen extends StatefulWidget {
  @override
  _SubscriptionScreenState createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isClaiming = false;

  @override
  void initState() {
    super.initState();
    // The owner may have changed the limits or the contact message since the
    // plan was last loaded.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Provider.of<PlanProvider>(context, listen: false).refresh();
    });
  }

  /// Asks for [plan]: a dialog for monthly or yearly (when the plan has a
  /// price), an optional note and an optional Viber number, then the request,
  /// then a "we'll contact you" thanks. A refused request (e.g. the user
  /// already has that plan) shows the server's message in a snackbar.
  Future<void> _requestUpgrade(Plan plan, String title) async {
    final planProvider = Provider.of<PlanProvider>(context, listen: false);
    final accountEmail = Provider.of<AuthProvider>(context, listen: false).user?.email;
    final localizations = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final input = await showDialog<UpgradeRequestInput>(
      context: context,
      builder: (_) => UpgradeRequestDialog(
        plan: plan,
        title: title,
        accountEmail: accountEmail,
        initialViber: planProvider.upgradeRequest?.viberNumber,
        ownerContact: planProvider.status?.ownerContact ?? OwnerContact.none,
        price: planProvider.status?.priceOf(plan) ?? PlanPrice.none,
      ),
    );
    if (input == null) return; // cancelled

    try {
      await planProvider.requestUpgrade(
        plan,
        note: input.note,
        viberNumber: input.viberNumber,
        billing: input.billing,
      );
      messenger.showSnackBar(SnackBar(content: Text(localizations.upgradeRequestThanks)));
    } catch (e) {
      // 422 is the server's validation: the Viber number or the note, which
      // the dialog checks first too, or the price the user picked, which the
      // owner changed since the screen loaded. The message names the field
      // ("viber_number: …", "billing: …"); say which in the app's language.
      final message = e is ApiException && e.statusCode == 422
          ? (e.message.contains('viber_number')
              ? localizations.upgradeRequestViberInvalid
              : e.message.contains('billing')
                  ? localizations.upgradeRequestPriceChanged
                  : localizations.upgradeRequestNoteTooLong)
          : e is ApiException && e.message.trim().isNotEmpty
              ? e.message
              : localizations.upgradeRequestFailed;
      messenger.showSnackBar(SnackBar(content: Text(message)));
      // The plan may have changed since the screen loaded: show what is true.
      planProvider.refresh();
    }
  }

  Future<void> _claimFreeTrial(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final planProvider = Provider.of<PlanProvider>(context, listen: false);
    final localizations = AppLocalizations.of(context);

    setState(() => _isClaiming = true);

    final success = await authProvider.claimFreeTrial();
    // The trial is a Plus plan with its own allowances: load them now.
    if (success) planProvider.refresh();

    if (!mounted) return;
    setState(() => _isClaiming = false);

    if (success) {
      final scheme = Theme.of(context).colorScheme;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.star_rounded, color: scheme.tertiary, size: 36),
              ),
              const SizedBox(height: 20),
              Text(
                localizations.welcomeToPlusCelebration,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                localizations.oneMonthFreePlusAccess,
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(backgroundColor: scheme.tertiary),
                  child: Text(localizations.letsGo),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authProvider.error ?? localizations.couldNotClaimFreeTrial)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Consumer2<AuthProvider, PlanProvider>(
          builder: (context, authProvider, planProvider, child) {
            final isPaid = authProvider.isPaid;
            final hasClaimedTrial = authProvider.hasClaimedFreeTrial;
            // A paid plan that ends on a date (not lifetime) can be renewed.
            final hasEndDate = isPaid && authProvider.subscriptionExpiresAt != null;
            final plans = requestablePlans(authProvider.plan,
                isTrial: authProvider.isTrial, hasEndDate: hasEndDate);

            return Column(
              children: [
                // ── Header ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          isPaid ? localizations.yourPlanTitle : localizations.upgradePlan,
                          style: theme.textTheme.titleLarge?.copyWith(color: scheme.onSurface),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: RefreshIndicator(
                    onRefresh: planProvider.refresh,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Current plan card ─────────────────────────
                          if (isPaid) ...[
                            _buildCurrentPlanCard(context, authProvider, scheme, localizations),
                            const SizedBox(height: 28),
                          ],

                          // ── Free-month offer (leads, per redesign) ──
                          if (!isPaid && !hasClaimedTrial) ...[
                            _buildOfferHero(context, scheme),
                            const SizedBox(height: 28),
                          ],

                          // ── Free / Plus / Pro, from the server's limits ──
                          Text(
                            localizations.comparePlans,
                            style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSurface),
                          ),
                          const SizedBox(height: 12),
                          _buildComparison(context, planProvider, authProvider.plan, localizations),

                          // ── Ask for a higher plan, or to renew this one ──
                          if (plans.isNotEmpty && planProvider.status != null) ...[
                            const SizedBox(height: 16),
                            _buildUpgradeRequests(
                              context,
                              planProvider,
                              plans,
                              authProvider.plan,
                              authProvider.isTrial,
                              hasEndDate,
                              localizations,
                            ),
                            // ── How to pay: KPay / WavePay (information only) ──
                            const SizedBox(height: 8),
                            const Center(child: AcceptedPayments(centered: true)),
                          ],

                          // ── Upgrade contact ──
                          if (plans.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            _buildContactBox(context, planProvider.status, localizations),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── The user's current paid plan ───────────────────────────────────────────
  Widget _buildCurrentPlanCard(
    BuildContext context,
    AuthProvider authProvider,
    ColorScheme scheme,
    AppLocalizations localizations,
  ) {
    final planName = localizations.planName(authProvider.plan);
    final isTrial = authProvider.isTrial;
    final expiresAt = authProvider.subscriptionExpiresAt;
    final endDate = authProvider.trialEndsAt ?? expiresAt;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(Icons.star_rounded, color: scheme.tertiary, size: 44),
          const SizedBox(height: 14),
          Text(
            isTrial ? localizations.planTrialActive(planName) : localizations.planActive(planName),
            key: const Key('current-plan-title'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: scheme.onTertiaryContainer,
            ),
          ),
          if (endDate != null) ...[
            const SizedBox(height: 6),
            Text(
              isTrial
                  ? localizations.planTrialEnds(AppDates.full(context, endDate))
                  : '${localizations.expiresOn}: ${AppDates.full(context, endDate)}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onTertiaryContainer),
            ),
          ],
        ],
      ),
    );
  }

  // ── "One month free" tonal hero ────────────────────────────────────────────
  Widget _buildOfferHero(BuildContext context, ColorScheme scheme) {
    final localizations = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localizations.oneMonthFreeCaps,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 8),
          Text(
            localizations.letAppReadYourMoney,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer, height: 1.25),
          ),
          const SizedBox(height: 8),
          Text(
            localizations.weeklyInsightsReceiptScanningVoiceAiBudgets,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onPrimaryContainer, height: 1.4),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isClaiming ? null : () => _claimFreeTrial(context),
              icon: _isClaiming
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Icon(Icons.card_giftcard_rounded, size: 20),
              label: Text(_isClaiming ? localizations.claiming : localizations.claimOneMonthFree),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              localizations.noCardRequiredThenContactUs,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  // ── Free / Plus / Pro comparison ───────────────────────────────────────────
  Widget _buildComparison(
    BuildContext context,
    PlanProvider planProvider,
    Plan currentPlan,
    AppLocalizations localizations,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final status = planProvider.status;
    if (status == null || status.catalog.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: planProvider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Text(
                    localizations.planDetailsUnavailable,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: planProvider.refresh,
                    child: Text(localizations.tryAgain),
                  ),
                ],
              ),
      );
    }
    return PlanComparisonTable(
      catalog: status.catalog,
      currentPlan: currentPlan,
      prices: status.prices,
    );
  }

  // ── "Upgrade to Plus" / "Upgrade to Pro" (or "Buy Plus" on the trial, ──────
  // "Renew Plus" for a paid plan with an end date). One card per plan in
  // [plans] (see requestablePlans), with the plan's price above the button
  // once the owner has set one. After a request, that plan's card says when it
  // was requested; asking for the other plan moves it there.
  Widget _buildUpgradeRequests(
    BuildContext context,
    PlanProvider planProvider,
    List<Plan> plans,
    Plan currentPlan,
    bool isTrial,
    bool hasEndDate,
    AppLocalizations localizations,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final pending = planProvider.upgradeRequest;
    final accountEmail = Provider.of<AuthProvider>(context, listen: false).user?.email;
    String label(Plan plan) =>
        upgradeButtonLabel(localizations, plan, current: currentPlan, isTrial: isTrial, hasEndDate: hasEndDate);
    return Column(
      children: [
        for (final plan in plans)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(16),
              ),
              child: pending?.plan == plan
                  ? Row(
                      children: [
                        Icon(Icons.check_circle_outline_rounded, color: scheme.primary, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            upgradeRequestedText(
                              localizations,
                              pending!,
                              accountEmail,
                            ),
                            key: Key('upgrade-requested-${plan.name}'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._priceLines(context, plan, planProvider.status!.priceOf(plan), localizations),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonal(
                            key: Key('request-${plan.name}'),
                            onPressed: planProvider.isRequestingUpgrade
                                ? null
                                : () => _requestUpgrade(plan, label(plan)),
                            child: Text(label(plan)),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
      ],
    );
  }

  /// "K15,000 / month" and, with a yearly price, "or K150,000 / year · save
  /// 17%", for above the upgrade button; nothing when [price] has no monthly price.
  List<Widget> _priceLines(BuildContext context, Plan plan, PlanPrice price, AppLocalizations l) {
    final monthly = price.monthlyMmk;
    if (monthly == null) return const [];
    final scheme = Theme.of(context).colorScheme;
    final yearly = upgradeYearlyText(l, price);
    return [
      Text(
        l.planPriceMonthly(formatPlanPrice(monthly)),
        key: Key('upgrade-price-${plan.name}'),
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: scheme.onSurface),
      ),
      if (yearly != null) ...[
        const SizedBox(height: 2),
        Text(
          yearly,
          key: Key('upgrade-price-yearly-${plan.name}'),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
        ),
      ],
      const SizedBox(height: 10),
    ];
  }

  // ── Upgrade contact info box ───────────────────────────────────────────────
  Widget _buildContactBox(BuildContext context, PlanStatus? status, AppLocalizations localizations) {
    final scheme = Theme.of(context).colorScheme;
    final message = status?.contactMessage(Localizations.localeOf(context).languageCode) ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: scheme.outlineVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.chat_bubble_outline_rounded, color: scheme.onSurfaceVariant, size: 26),
          const SizedBox(height: 8),
          Text(
            message.isNotEmpty ? localizations.planContactTitle : localizations.contactAdmin,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            message.isNotEmpty ? message : localizations.contactSupport,
            key: const Key('upgrade-contact-message'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.5),
          ),
          if (status != null && !status.ownerContact.isEmpty) ...[
            const SizedBox(height: 12),
            OwnerContactBlock(contact: status.ownerContact, centered: true),
          ],
        ],
      ),
    );
  }
}

/// What a request card says: when it was requested and how the owner will get
/// back to the user ("on Viber at {number}", else "by email at {email}" with the
/// account email). Without an account email (not loaded yet) it just says the
/// owner will be in touch.
String upgradeRequestedText(
  AppLocalizations l,
  UpgradeRequest request,
  String? accountEmail,
) {
  final date = l.formatPlanDate(request.createdAt);
  final viber = request.viberNumber;
  if (viber != null && viber.isNotEmpty) return l.upgradeRequestedViber(date, viber);
  if (accountEmail != null && accountEmail.isNotEmpty) {
    return l.upgradeRequestedEmail(date, accountEmail);
  }
  return l.upgradeRequestedOn(date);
}

/// The button (and dialog title) for asking for [plan]: "Buy Plus" for the
/// plan a trial user is trying, "Renew [plan]" for the paid plan a user has
/// until an end date ([hasEndDate]), otherwise "Upgrade to [plan]".
String upgradeButtonLabel(AppLocalizations l, Plan plan,
    {required Plan current, bool isTrial = false, bool hasEndDate = false}) {
  final name = l.planName(plan);
  if (plan == current && isTrial) return l.upgradeBuyButton(name);
  if (plan == current && hasEndDate) return l.upgradeRenewButton(name);
  return l.upgradeRequestButton(name);
}

/// A price in kyat as the app shows it: "K15,000" (no decimals; Western
/// digits in Myanmar too, like the amounts elsewhere in the app).
String formatPlanPrice(int mmk) => 'K${NumberFormat('#,##0', 'en').format(mmk)}';

/// " · save 17%" when the yearly price saves something, else "".
String _saveSuffix(AppLocalizations l, PlanPrice price) {
  final save = price.savePercent;
  return save != null && save > 0 ? ' · ${l.planPriceSave(save)}' : '';
}

/// "or K150,000 / year · save 17%" under the monthly price; null without a
/// yearly price.
String? upgradeYearlyText(AppLocalizations l, PlanPrice price) {
  final yearly = price.yearlyMmk;
  if (!price.hasYearly || yearly == null) return null;
  return '${l.planPriceYearlyOr(formatPlanPrice(yearly))}${_saveSuffix(l, price)}';
}

/// The paid plans a user on [current] can ask for: the ones above it (Pro
/// counts as Plus, so a lifetime Pro user has none). A free trial of Plus does
/// not count as having Plus, so a trial user may ask to keep it. A paid plan
/// with an end date ([hasEndDate], not a trial) can be renewed, so it is
/// offered too. The server applies the same rules.
List<Plan> requestablePlans(Plan current, {bool isTrial = false, bool hasEndDate = false}) {
  final held = isTrial && current == Plan.plus ? Plan.free : current;
  final renewable = !isTrial && hasEndDate && current != Plan.free;
  return [Plan.plus, Plan.pro]
      .where((p) => p.index > held.index || (renewable && p == current))
      .toList();
}

/// The longest note the server accepts, counted in Unicode code points like
/// the server (Python `len`) and the database (`char_length`) count them. The
/// field's own `maxLength` counts grapheme clusters, which for Burmese is far
/// fewer than the code points, so it can't be used.
const int upgradeRequestNoteMaxLength = 500;

/// How many code points [text] has (what the server counts).
int noteLength(String text) => text.runes.length;

/// What the upgrade request dialog sends: the trimmed [note] and the
/// normalised [viberNumber] (`+` and digits), each empty when not given, and
/// the [billing] period picked ([PlanBilling]; null when the plan has no price).
class UpgradeRequestInput {
  const UpgradeRequestInput({required this.note, required this.viberNumber, this.billing});

  final String note;
  final String viberNumber;
  final String? billing;
}

/// Asks monthly or yearly (when the plan has a price), an optional note and
/// an optional Viber number, says how the owner will get back to the user,
/// and closes with an [UpgradeRequestInput]. Closes with null when cancelled;
/// the caller sends the request. Send is off while the note is over
/// [upgradeRequestNoteMaxLength] code points or the Viber number is not a
/// number (see [normalizeViberNumber]).
///
/// [accountEmail] is where the owner emails the user when they leave the
/// number empty. [initialViber] prefills the field (the number of the user's
/// pending request). [ownerContact] shows "Contact us directly" under the
/// fields, and "We accept" KPay / WavePay comes last. [price] is the plan's price: with a monthly price the user picks
/// Monthly (the default) or, when there is one, Yearly.
class UpgradeRequestDialog extends StatefulWidget {
  const UpgradeRequestDialog({
    super.key,
    required this.plan,
    this.title,
    this.accountEmail,
    this.initialViber,
    this.ownerContact = OwnerContact.none,
    this.price = PlanPrice.none,
  });

  final Plan plan;

  /// The button's wording ("Upgrade to Pro" / "Buy Plus" / "Renew Plus");
  /// defaults to "Upgrade to [plan]".
  final String? title;
  final String? accountEmail;
  final String? initialViber;
  final OwnerContact ownerContact;
  final PlanPrice price;

  @override
  State<UpgradeRequestDialog> createState() => _UpgradeRequestDialogState();
}

class _UpgradeRequestDialogState extends State<UpgradeRequestDialog> {
  final TextEditingController _note = TextEditingController();
  late final TextEditingController _viber =
      TextEditingController(text: widget.initialViber ?? '');

  /// The period picked; null when the plan has no price (nothing to pick).
  late String? _billing = widget.price.hasMonthly ? PlanBilling.month : null;

  /// One choice of the billing period: a row with a radio mark and its text.
  Widget _billingOption(String value, String label, ColorScheme scheme) {
    final selected = _billing == value;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: InkWell(
        key: Key('upgrade-billing-$value'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _billing = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _note.dispose();
    _viber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final planName = l.planName(widget.plan);
    final length = noteLength(_note.text);
    final tooLong = length > upgradeRequestNoteMaxLength;
    final viber = normalizeViberNumber(_viber.text);
    final viberInvalid = viber == null;
    final email = widget.accountEmail;
    final monthly = widget.price.monthlyMmk;
    final yearly = widget.price.hasYearly ? widget.price.yearlyMmk : null;
    return AlertDialog(
      title: Text(widget.title ?? l.upgradeRequestButton(planName)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.upgradeRequestIntro(planName),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4),
            ),
            if (monthly != null) ...[
              const SizedBox(height: 16),
              Text(
                l.upgradeBillingLabel,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
              ),
              const SizedBox(height: 8),
              _billingOption(PlanBilling.month, l.upgradeBillingMonthly(formatPlanPrice(monthly)), scheme),
              if (yearly != null) ...[
                const SizedBox(height: 8),
                _billingOption(
                  PlanBilling.year,
                  '${l.upgradeBillingYearly(formatPlanPrice(yearly))}${_saveSuffix(l, widget.price)}',
                  scheme,
                ),
              ],
            ],
            const SizedBox(height: 16),
            TextField(
              key: const Key('upgrade-request-viber'),
              controller: _viber,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l.upgradeRequestViberLabel,
                hintText: l.upgradeRequestViberHint,
                errorText: viberInvalid ? l.upgradeRequestViberInvalid : null,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              email != null && email.isNotEmpty
                  ? l.upgradeRequestContactLine(email)
                  : l.upgradeRequestContactLineNoEmail,
              key: const Key('upgrade-request-contact-line'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('upgrade-request-note'),
              controller: _note,
              onChanged: (_) => setState(() {}),
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l.upgradeRequestNoteLabel,
                hintText: l.upgradeRequestNoteHint,
                alignLabelWithHint: true,
                errorText: tooLong ? l.upgradeRequestNoteTooLong : null,
                counter: Text(
                  '$length/$upgradeRequestNoteMaxLength',
                  key: const Key('upgrade-request-note-counter'),
                  style: TextStyle(color: tooLong ? scheme.error : scheme.onSurfaceVariant),
                ),
              ),
            ),
            if (!widget.ownerContact.isEmpty) ...[
              const SizedBox(height: 12),
              OwnerContactBlock(contact: widget.ownerContact),
            ],
            const SizedBox(height: 16),
            const AcceptedPayments(compact: true),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.dialogCancel),
        ),
        FilledButton(
          key: const Key('upgrade-request-send'),
          onPressed: tooLong || viberInvalid
              ? null
              : () => Navigator.pop(
                    context,
                    UpgradeRequestInput(note: _note.text.trim(), viberNumber: viber, billing: _billing),
                  ),
          child: Text(l.upgradeRequestSend),
        ),
      ],
    );
  }
}

/// The Free / Plus / Pro comparison: one row per feature, one column per plan
/// (a number and its period, a tick for "included", a dash for "not
/// included"), with the user's current plan's column highlighted. Everything
/// comes from [catalog], the limits the server reports. Once the owner has set
/// a monthly price for Plus or Pro, a Price row comes first (the monthly
/// price, "Free" for Free, a dash for a paid plan without one).
class PlanComparisonTable extends StatelessWidget {
  const PlanComparisonTable({
    super.key,
    required this.catalog,
    required this.currentPlan,
    this.prices = const {},
  });

  final Map<Plan, Map<String, CatalogLimit>> catalog;
  final Plan currentPlan;
  final Map<Plan, PlanPrice> prices;

  static const List<Plan> _plans = [Plan.free, Plan.plus, Plan.pro];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final features = PlanFeature.all
        .where((f) => _plans.any((p) => catalog[p]?.containsKey(f) ?? false))
        .toList();
    final highlight = scheme.primaryContainer.withValues(alpha: 0.55);

    Widget cell(Widget child, Plan? plan, {Alignment alignment = Alignment.center}) {
      return Container(
        color: plan == currentPlan ? highlight : null,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        alignment: alignment,
        child: child,
      );
    }

    Widget rowLabel(String text) => cell(
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          null,
          alignment: Alignment.centerLeft,
        );

    final showPrices = _plans.any((p) => p != Plan.free && (prices[p]?.hasMonthly ?? false));

    final rows = <TableRow>[
      TableRow(
        children: [
          cell(const SizedBox.shrink(), null),
          for (final plan in _plans)
            cell(
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.planName(plan),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (plan == currentPlan) ...[
                    const SizedBox(height: 2),
                    Text(
                      l.planCurrent,
                      key: const Key('current-plan-marker'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
              plan,
            ),
        ],
      ),
      if (showPrices)
        TableRow(
          children: [
            rowLabel(l.planPriceRow),
            for (final plan in _plans) cell(_priceCell(l, scheme, plan), plan),
          ],
        ),
      for (final feature in features)
        TableRow(
          children: [
            rowLabel(l.planFeatureName(feature)),
            for (final plan in _plans)
              cell(_limitCell(context, l, scheme, catalog[plan]?[feature]), plan),
          ],
        ),
    ];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Theme.of(context).cardTheme.shadowColor ?? Colors.black12, blurRadius: 3, offset: const Offset(0, 1)),
        ],
      ),
      child: Table(
        key: const Key('plan-comparison-table'),
        // Every cell is as tall as the row's tallest, so the current plan's
        // highlight fills the whole column.
        defaultVerticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
        columnWidths: const {
          0: FlexColumnWidth(2.1),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1),
          3: FlexColumnWidth(1),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: scheme.outlineVariant),
        ),
        children: rows,
      ),
    );
  }

  /// The monthly price ("K15,000" over "per month"), shrunk to fit a narrow
  /// column; "Free" for Free; the dash for a paid plan without a price.
  Widget _priceCell(AppLocalizations l, ColorScheme scheme, Plan plan) {
    final valueStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: scheme.onSurface);
    if (plan == Plan.free) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(l.planPriceFree, key: const Key('plan-price-free'), maxLines: 1, style: valueStyle),
      );
    }
    final monthly = prices[plan]?.monthlyMmk;
    if (monthly == null) return _dash(l, scheme);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            formatPlanPrice(monthly),
            key: Key('plan-price-${plan.name}'),
            maxLines: 1,
            style: valueStyle,
          ),
        ),
        Text(
          l.planPerMonth,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _dash(AppLocalizations l, ColorScheme scheme) => Semantics(
        label: l.planNotIncluded,
        child: Icon(Icons.remove_rounded, size: 20, color: scheme.outline),
      );

  Widget _limitCell(
    BuildContext context,
    AppLocalizations l,
    ColorScheme scheme,
    CatalogLimit? limit,
  ) {
    if (limit == null || limit.isLocked) return _dash(l, scheme);
    if (limit.isIncluded || limit.quota == null) {
      return Semantics(
        label: l.planIncluded,
        child: Icon(Icons.check_rounded, size: 20, color: scheme.primary),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${limit.quota}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
        Text(
          limit.period == 'week' ? l.planPerWeek : l.planPerMonth,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
