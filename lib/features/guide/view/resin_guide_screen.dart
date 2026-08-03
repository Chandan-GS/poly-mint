import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/polymer_info.dart';

/// Educational reference for all resin codes — how to identify, prep and what
/// each is worth. Reachable from Settings and the empty states.
class ResinGuideScreen extends StatelessWidget {
  const ResinGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recycling guide')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Plastics are marked with a resin code (1–7) inside the recycling '
            'triangle ♲. PolyMint recognises each and rewards them by market '
            'value and recyclability.',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4),
          ),
          const SizedBox(height: 16),
          for (final p in PolymerCatalog.all) _ResinCard(polymer: p),
        ],
      ),
    );
  }
}

class _ResinCard extends StatelessWidget {
  final PolymerInfo polymer;
  const _ResinCard({required this.polymer});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          leading: CircleAvatar(
            backgroundColor: polymer.color,
            child: Text('${polymer.resinNumber}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          title: Text('${polymer.shortName} — ${polymer.fullName}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: Text(
              '${polymer.creditRate} credits/kg · ${polymer.recyclabilityLabel}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(polymer.description,
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
            ),
            const SizedBox(height: 12),
            _row(context, Icons.inventory_2, 'Common items',
                polymer.commonItems.join(', ')),
            const SizedBox(height: 8),
            _row(context, Icons.co2, 'CO₂ saved',
                '${Formatters.co2(polymer.co2SavedPerKg)} per kg recycled'),
            const SizedBox(height: 12),
            for (final tip in polymer.tips)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 16, color: polymer.color),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(tip, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style.copyWith(fontSize: 13),
              children: [
                TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
