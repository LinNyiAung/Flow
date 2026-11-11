import 'package:flutter/material.dart';
import 'package:frontend/services/localization_service.dart';

/// A payment method the owner accepts: its logo (an asset) and its name, which is the same in every language.
class AcceptedPaymentMethod {
  const AcceptedPaymentMethod({required this.id, required this.name, required this.logoAsset});

  final String id;
  final String name;
  final String logoAsset;
}

/// The methods shown, in order. Users pay the owner with one of these and the owner then approves the upgrade in the
/// admin panel; the app only says which ones are accepted (no numbers, nothing to tap).
const acceptedPaymentMethods = [
  AcceptedPaymentMethod(id: 'kpay', name: 'KPay', logoAsset: 'assets/payments/kpay.png'),
  AcceptedPaymentMethod(id: 'wavepay', name: 'WavePay', logoAsset: 'assets/payments/wavepay.png'),
];

/// "We accept" with the KPay and WavePay logos and names: on the Upgrade screen under the upgrade buttons
/// ([centered]), and smaller in the upgrade request dialog ([compact]). Read by screen readers as one sentence.
class AcceptedPayments extends StatelessWidget {
  const AcceptedPayments({super.key, this.centered = false, this.compact = false});

  final bool centered;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final logoSize = compact ? 32.0 : 40.0;
    return Semantics(
      key: const Key('accepted-payments'),
      container: true,
      label: l.acceptedPaymentsSemantics,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Text(
              l.acceptedPaymentsTitle,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface),
            ),
            SizedBox(height: compact ? 8 : 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, method) in acceptedPaymentMethods.indexed) ...[
                  if (i > 0) SizedBox(width: compact ? 16 : 24),
                  Column(
                    key: Key('accepted-payment-${method.id}'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: logoSize,
                        height: logoSize,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(logoSize / 4),
                          image: DecorationImage(
                            image: AssetImage(method.logoAsset),
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        method.name,
                        style: TextStyle(
                          fontSize: compact ? 11 : 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
