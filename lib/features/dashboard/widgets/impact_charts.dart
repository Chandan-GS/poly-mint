import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/impact_stats.dart';
import '../../../data/models/polymer_info.dart';

/// Donut chart of recovered weight split by resin type.
class PolymerBreakdownChart extends StatelessWidget {
  final ImpactStats stats;
  const PolymerBreakdownChart({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final entries = stats.weightByPolymer.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(child: Text('No material data yet')),
      );
    }
    final total = entries.fold<double>(0, (a, e) => a + e.value);

    return SizedBox(
      height: 170,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 38,
                sections: [
                  for (final e in entries)
                    PieChartSectionData(
                      value: e.value,
                      color: AppColors.forPolymer(e.key),
                      radius: 34,
                      showTitle: false,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in entries.take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppColors.forPolymer(e.key),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            PolymerCatalog.lookup(e.key).shortName,
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          '${(e.value / total * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 7-day bar chart of recovered weight per day.
class WeeklyTrendChart extends StatelessWidget {
  final ImpactStats stats;
  const WeeklyTrendChart({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(7, (i) {
      final d = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: 6 - i));
      return MapEntry(d, stats.weightByDay[d] ?? 0.0);
    });
    final maxY = days.fold<double>(0, (m, e) => e.value > m ? e.value : m);
    final scheme = Theme.of(context).colorScheme;
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return SizedBox(
      height: 150,
      child: BarChart(
        BarChartData(
          maxY: maxY == 0 ? 1 : maxY * 1.25,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final i = value.toInt();
                  final d = days[i.clamp(0, 6)].key;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(labels[d.weekday - 1],
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: days[i].value,
                  color: scheme.primary,
                  width: 16,
                  borderRadius: BorderRadius.circular(4),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}
