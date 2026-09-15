import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';

import '../../services/localization_service.dart';

class CurrencySettingsScreen extends StatefulWidget {
  @override
  _CurrencySettingsScreenState createState() => _CurrencySettingsScreenState();
}

class _CurrencySettingsScreenState extends State<CurrencySettingsScreen> {
  bool _isLoading = false;

  Future<void> _updateCurrency(Currency currency) async {
    setState(() {
      _isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.updateDefaultCurrency(currency: currency);

    setState(() {
      _isLoading = false;
    });

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Default currency updated to ${currency.displayName}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authProvider.error ?? 'Failed to update currency')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentCurrency = authProvider.defaultCurrency;
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(localizations.currencySettings)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              localizations.selectDefaultCurrency,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.primary),
            ),
          ),
          Card(
            child: Column(
              children: [
                for (final currency in Currency.values) ...[
                  if (currency != Currency.values.first) const Divider(),
                  _buildCurrencyOption(
                    currency: currency,
                    isSelected: currentCurrency == currency,
                    onTap: _isLoading ? null : () => _updateCurrency(currency),
                  ),
                ],
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HOW CURRENCIES WORK HERE',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(
                  localizations.eachCurrencyOwnBalance,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrencyOption({
    required Currency currency,
    required bool isSelected,
    required VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected ? scheme.primaryContainer : scheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                currency.symbol,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? scheme.onPrimaryContainer : scheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currency.displayName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    currency.symbol,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
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
