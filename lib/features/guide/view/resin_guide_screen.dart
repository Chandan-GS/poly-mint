import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../data/models/polymer_info.dart';

/// Reference for the seven resin codes. Plain rows; tap for the details.
class ResinGuideScreen extends StatelessWidget {
  const ResinGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = PolymerCatalog.all;
    return Scaffold(
      appBar: AppBar(title: const Text('Resin guide')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text('The seven codes PolyMint reads. Tap any for how to spot and '
                'prep it.',
                style:
                    AppType.body.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < all.length; i++) ...[
                    if (i > 0) const RowDivider(),
                    _ResinRow(polymer: all[i]),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _recyclabilityColor(String label) {
  final l = label.toLowerCase();
  if (l.contains('high')) return AppColors.accent;
  if (l.contains('low')) return AppColors.rejected;
  if (l.contains('mix') || l.contains('other')) return AppColors.muted;
  return AppColors.review;
}

class _ResinRow extends StatelessWidget {
  final PolymerInfo polymer;
  const _ResinRow({required this.polymer});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _showDetails(context, polymer),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(polymer.resinNumber.toString().padLeft(2, '0'),
                  style: AppType.monoBody
                      .copyWith(color: scheme.onSurfaceVariant)),
            ),
            SizedBox(
                width: 58,
                child: Text(polymer.shortName,
                    style: AppType.bodyStrong
                        .copyWith(color: scheme.onSurface))),
            Expanded(
              child: Text(polymer.commonItems.take(2).join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption
                      .copyWith(color: scheme.onSurfaceVariant)),
            ),
            Text(polymer.recyclabilityLabel,
                style: AppType.label
                    .copyWith(color: _recyclabilityColor(polymer.recyclabilityLabel))),
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context, PolymerInfo p) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(p.resinNumber.toString().padLeft(2, '0'),
                  style:
                      AppType.metricM.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(width: 10),
              Text('${p.shortName} · ${p.fullName}',
                  style: AppType.heading.copyWith(color: scheme.onSurface)),
            ]),
            const SizedBox(height: 12),
            Text(p.description,
                style: AppType.body.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Text('COMMON ITEMS',
                style:
                    AppType.label.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text(p.commonItems.join(', '), style: AppType.body),
            const SizedBox(height: 16),
            Text('HOW TO PREP',
                style:
                    AppType.label.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            for (final tip in p.tips)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('— $tip', style: AppType.body),
              ),
          ],
        ),
      ),
    );
  }
}
