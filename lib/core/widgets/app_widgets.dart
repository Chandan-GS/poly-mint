import 'package:flutter/material.dart';

import '../../data/models/polymer_info.dart';
import '../theme/app_colors.dart';
import '../theme/app_type.dart';

/// Bordered surface block — the instrument "panel". Everything sits in one.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final Color? border;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.background,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? scheme.surface,
        border: Border.all(color: border ?? scheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
    );
  }
}

/// A hairline between rows inside a [Panel].
class RowDivider extends StatelessWidget {
  const RowDivider({super.key});
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant);
}

/// A small ALL-CAPS section label — the instrument "field name".
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: AppType.label.copyWith(color: muted)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Back-compat alias — same as [SectionLabel] with a `title` param.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) =>
      SectionLabel(title, trailing: trailing);
}

/// A labelled mono metric — the core instrument readout. Number in Plex Mono,
/// unit trailing, tiny caps label above.
class Metric extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final TextStyle? valueStyle;
  final Color? valueColor;
  final CrossAxisAlignment align;

  const Metric({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.valueStyle,
    this.valueColor,
    this.align = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final vStyle = (valueStyle ?? AppType.metricM)
        .copyWith(color: valueColor ?? scheme.onSurface);
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(),
            style: AppType.label.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        RichText(
          text: TextSpan(
            text: value,
            style: vStyle,
            children: unit == null
                ? null
                : [
                    TextSpan(
                      text: ' $unit',
                      style: AppType.monoSmall
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
          ),
        ),
      ],
    );
  }
}

/// Compact bordered metric cell used in grids. Keeps the legacy [StatCard] API.
class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? accent;
  final String? sublabel;

  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
    this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label.copyWith(color: scheme.onSurfaceVariant)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(value,
              style: AppType.metricM.copyWith(color: scheme.onSurface)),
          if (sublabel != null) ...[
            const SizedBox(height: 3),
            Text(sublabel!,
                style: AppType.monoSmall
                    .copyWith(color: accent ?? AppColors.accent)),
          ],
        ],
      ),
    );
  }
}

/// Neutral resin badge, e.g. `01·PET` — mono, hairline, no colour fill/emoji.
class PolymerBadge extends StatelessWidget {
  final PolymerInfo polymer;
  final double fontSize;
  const PolymerBadge({super.key, required this.polymer, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        '${polymer.resinNumber.toString().padLeft(2, '0')}·${polymer.shortName}',
        style: AppType.monoSmall
            .copyWith(color: scheme.onSurface, fontSize: fontSize),
      ),
    );
  }
}

/// PASS / REVIEW / REJECTED style status tag with a semantic dot.
class StatusTag extends StatelessWidget {
  final String label;
  final Color color;
  const StatusTag({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label.toUpperCase(),
            style: AppType.label.copyWith(color: color)),
      ],
    );
  }
}

/// Instrument segmented toggle — flat, hairline, ink-filled selection.
class SegmentedToggle<T> extends StatelessWidget {
  final List<(T value, String label)> options;
  final T selected;
  final ValueChanged<T> onChanged;
  const SegmentedToggle({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) Container(width: 1, color: scheme.outlineVariant),
            Expanded(
              child: InkWell(
                onTap: () => onChanged(options[i].$1),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  color: options[i].$1 == selected
                      ? scheme.onSurface
                      : Colors.transparent,
                  child: Text(
                    options[i].$2.toUpperCase(),
                    style: AppType.monoSmall.copyWith(
                      color: options[i].$1 == selected
                          ? scheme.surface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }
}

/// A hairline key/value row for settings-style panels.
class KeyValueRow extends StatelessWidget {
  final String label;
  final Widget value;
  final VoidCallback? onTap;
  const KeyValueRow(
      {super.key, required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: AppType.body.copyWith(color: scheme.onSurface))),
            value,
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  size: 18, color: scheme.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );
  }
}

/// Empty / error placeholder.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: AppType.heading.copyWith(color: scheme.onSurface)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(color: scheme.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
