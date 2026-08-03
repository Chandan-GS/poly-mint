import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/polymer_info.dart';
import '../../../data/models/waste_transaction.dart';

/// Row summarising a single minted (or pending) transaction.
class TransactionTile extends StatelessWidget {
  final WasteTransaction txn;
  const TransactionTile({super.key, required this.txn});

  @override
  Widget build(BuildContext context) {
    final polymer = PolymerCatalog.lookup(txn.polymerCode);
    final scheme = Theme.of(context).colorScheme;
    final pending = txn.status == TransactionStatus.pendingSync;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: polymer.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text('${polymer.resinNumber}',
                  style: TextStyle(
                      color: polymer.color,
                      fontWeight: FontWeight.w800,
                      fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(polymer.shortName,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Text(Formatters.weight(txn.weightKg),
                          style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        pending ? Icons.cloud_upload_outlined : Icons.verified,
                        size: 13,
                        color: pending ? const Color(0xFFF59E0B) : scheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        pending ? 'Pending sync' : Formatters.relative(txn.timestamp),
                        style: TextStyle(
                            fontSize: 11.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('+${Formatters.credits(txn.creditsMinted)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: scheme.primary)),
                Text('credits',
                    style: TextStyle(
                        fontSize: 10.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
