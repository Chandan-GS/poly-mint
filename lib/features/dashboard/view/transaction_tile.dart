import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../data/models/polymer_info.dart';
import '../../../data/models/waste_transaction.dart';

/// One batch as a plain hairline row (lives inside a [Panel] that draws the
/// border + dividers). Plain words: Verified / Pending / Review.
class TransactionTile extends StatelessWidget {
  final WasteTransaction txn;
  const TransactionTile({super.key, required this.txn});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final polymer = PolymerCatalog.lookup(txn.polymerCode);

    final (String statusText, Color statusColor) = switch (txn.status) {
      TransactionStatus.pendingSync => ('Pending', AppColors.review),
      TransactionStatus.flagged => ('Review', AppColors.review),
      TransactionStatus.verified => ('Verified', AppColors.accent),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(TextSpan(
                  style: AppType.bodyStrong.copyWith(color: scheme.onSurface),
                  children: [
                    TextSpan(text: polymer.shortName),
                    TextSpan(
                        text:
                            '  ${txn.weightKg.toStringAsFixed(2)} kg',
                        style: AppType.monoBody
                            .copyWith(color: scheme.onSurface)),
                  ],
                )),
                const SizedBox(height: 3),
                Text(
                  '+${txn.creditsMinted.toStringAsFixed(2)} cr',
                  style: AppType.monoSmall
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          StatusTag(label: statusText, color: statusColor),
        ],
      ),
    );
  }
}
