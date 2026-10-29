import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../data/models/classification_result.dart';
import '../../../data/models/polymer_info.dart';
import '../../../data/models/popp_proof.dart';
import '../../../data/models/waste_transaction.dart';
import '../../../data/services/location_service.dart';
import '../../../data/services/preferences_service.dart';
import '../../../data/services/transaction_repository.dart';
import '../cubit/minting_cubit.dart';

class ResultScreen extends StatelessWidget {
  final ClassificationResult result;

  /// Null when there is no scale and the operator types the weight.
  final PoppProof? proof;
  const ResultScreen({super.key, required this.result, required this.proof});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MintingCubit(
        result: result,
        repo: sl<TransactionRepository>(),
        location: sl<LocationService>(),
        prefs: sl<PreferencesService>(),
        weightKg: proof?.weightKg ?? 0,
        proof: proof,
      ),
      child: _ResultView(result: result, proof: proof),
    );
  }
}

class _ResultView extends StatelessWidget {
  final ClassificationResult result;
  final PoppProof? proof;
  const _ResultView({required this.result, required this.proof});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify & mint')),
      body: SafeArea(
        child: BlocListener<MintingCubit, MintingState>(
          listenWhen: (a, b) => a.status != b.status,
          listener: (context, state) {
            if (state.status == MintingStatus.mintedOnline ||
                state.status == MintingStatus.mintedOffline) {
              _showSuccess(context, state);
            } else if (state.status == MintingStatus.error &&
                state.error != null) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(state.error!)));
            }
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _ClassificationPanel(result: result),
              const SizedBox(height: 12),
              _CandidateChips(result: result),
              const SizedBox(height: 12),
              _VerificationNote(result: result),
              const SizedBox(height: 22),
              BlocBuilder<MintingCubit, MintingState>(
                buildWhen: (a, b) => a.weightSource != b.weightSource,
                builder: (context, state) {
                  final p = proof;
                  if (state.isManualWeight || p == null) {
                    return const Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [SectionLabel('Weight'), _WeightPanel()],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionLabel('Physical check'),
                      _ProofPanel(proof: p),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => context
                              .read<MintingCubit>()
                              .enterWeightManually(),
                          child: const Text('Enter the weight by hand instead'),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              const SectionLabel('Credit'),
              const _CreditPanel(),
              const SizedBox(height: 20),
              const _MintButton(),
            ],
          ),
        ),
      ),
    );
  }

  void _showSuccess(BuildContext context, MintingState state) {
    final online = state.status == MintingStatus.mintedOnline;
    final review =
        state.verificationFor(result) == VerificationMethod.manualReview;
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: scheme.surface,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusTag(
              label: review ? 'Minted · review' : 'Minted',
              color: review ? AppColors.review : AppColors.accent,
            ),
            const SizedBox(height: 14),
            Text.rich(
              TextSpan(
                text: Formatters.credits(state.creditsPreview),
                style: AppType.metricL.copyWith(color: scheme.onSurface),
                children: [
                  TextSpan(
                    text: '  credits',
                    style: AppType.body.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              [
                review
                    ? 'Flagged for manual review: the material was not confirmed '
                          'by the AI at the 85% gate.'
                    : 'AI-verified.',
                if (state.isManualWeight) 'Weight entered by hand.',
                online
                    ? 'Recorded to the exchange ledger.'
                    : 'Saved offline — syncs automatically when you reconnect.',
              ].join(' '),
              style: AppType.body.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // sheet
                  Navigator.pop(context); // back to scan
                },
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassificationPanel extends StatelessWidget {
  final ClassificationResult result;
  const _ClassificationPanel({required this.result});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final uncertain = result.isUncertain || result.isAmbiguous;
    final barColor = uncertain ? AppColors.review : AppColors.accent;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MATERIAL',
                      style: AppType.label.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      result.polymer.shortName,
                      style: AppType.screenTitle.copyWith(
                        fontSize: 26,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      result.polymer.fullName,
                      style: AppType.caption.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'SURE',
                    style: AppType.label.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    Formatters.percent(result.confidence),
                    style: AppType.metricM.copyWith(color: barColor),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: result.confidence.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: scheme.surfaceContainerHighest,
              color: barColor,
            ),
          ),
          if (uncertain) ...[
            const SizedBox(height: 12),
            Text(
              'Not fully sure — confirm the material below or rescan in better '
              'light.',
              style: AppType.caption.copyWith(color: AppColors.review),
            ),
          ],
        ],
      ),
    );
  }
}

/// Says, before minting, whether the record will be AI-verified or sent for
/// manual review, and why.
class _VerificationNote extends StatelessWidget {
  final ClassificationResult result;
  const _VerificationNote({required this.result});

  @override
  Widget build(BuildContext context) {
    final selected = context.select(
      (MintingCubit c) => c.state.selectedPolymer,
    );
    final review =
        verificationOf(result, selected) == VerificationMethod.manualReview;
    final overridden = selected.code != result.polymer.code;
    final color = review ? AppColors.review : AppColors.accent;
    final reason = !review
        ? 'Material confirmed by the AI at '
              '${Formatters.percent(result.confidence)}.'
        : overridden
        ? 'You changed the material from the AI pick '
              '(${result.polymer.shortName}).'
        : 'AI confidence is below the 85% gate.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusTag(
          label: review ? 'Manual review' : 'AI-verified',
          color: color,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            reason,
            style: AppType.caption.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _CandidateChips extends StatelessWidget {
  final ClassificationResult result;
  const _CandidateChips({required this.result});

  @override
  Widget build(BuildContext context) {
    final selected = context.select(
      (MintingCubit c) => c.state.selectedPolymer,
    );
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in result.predictions)
          _Chip(
            label:
                '${p.polymer.shortName} · ${Formatters.percent(p.confidence)}',
            selected: selected.code == p.polymer.code,
            onTap: () => context.read<MintingCubit>().selectPolymer(p.polymer),
          ),
        InkWell(
          onTap: () => _showAll(context),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Other…',
              style: AppType.monoSmall.copyWith(color: scheme.onSurface),
            ),
          ),
        ),
      ],
    );
  }

  void _showAll(BuildContext context) {
    final cubit = context.read<MintingCubit>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final p in PolymerCatalog.all)
              ListTile(
                dense: true,
                leading: Text(
                  p.resinNumber.toString().padLeft(2, '0'),
                  style: AppType.monoBody,
                ),
                title: Text(
                  '${p.shortName} · ${p.fullName}',
                  style: AppType.body,
                ),
                onTap: () {
                  cubit.selectPolymer(p);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? scheme.onSurface : scheme.surface,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: AppType.monoSmall.copyWith(
            color: selected ? scheme.surface : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// The Proof-of-Physical-Presence readout — plain words, mono values.
class _ProofPanel extends StatelessWidget {
  final PoppProof proof;
  const _ProofPanel({required this.proof});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: AppType.body.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Text(v, style: AppType.monoBody.copyWith(color: scheme.onSurface)),
        ],
      ),
    );
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  proof.simulated
                      ? 'Weight and photo matched (simulated)'
                      : 'Weight and photo matched',
                  style: AppType.bodyStrong.copyWith(color: scheme.onSurface),
                ),
              ),
              const StatusTag(label: 'Verified', color: AppColors.accent),
            ],
          ),
          const SizedBox(height: 12),
          const RowDivider(),
          const SizedBox(height: 4),
          row('Weight on scale', '${proof.weightKg.toStringAsFixed(3)} kg'),
          row(
            'Held steady for',
            '${(proof.stableWindowMs / 1000).toStringAsFixed(1)} s',
          ),
          row(
            'Tamper check',
            proof.sampleHashChain.isEmpty
                ? '—'
                : '${proof.sampleHashChain.substring(0, 8)}…',
          ),
        ],
      ),
    );
  }
}

/// Weight typed by the operator, with a suggestion from the detected
/// material: item count × the typical weight of one item.
class _WeightPanel extends StatefulWidget {
  const _WeightPanel();

  @override
  State<_WeightPanel> createState() => _WeightPanelState();
}

class _WeightPanelState extends State<_WeightPanel> {
  late final TextEditingController _weight;
  late final TextEditingController _count;

  @override
  void initState() {
    super.initState();
    final s = context.read<MintingCubit>().state;
    _weight = TextEditingController(text: _fmt(s.weightKg));
    _count = TextEditingController(text: '${s.itemCount}');
  }

  @override
  void dispose() {
    _weight.dispose();
    _count.dispose();
    super.dispose();
  }

  static String _fmt(double kg) => kg <= 0 ? '' : kg.toStringAsFixed(3);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cubit = context.read<MintingCubit>();
    return BlocConsumer<MintingCubit, MintingState>(
      listenWhen: (a, b) =>
          a.weightKg != b.weightKg || a.itemCount != b.itemCount,
      listener: (context, s) {
        // Keep the fields in step with the suggestion until the operator types.
        if (!s.weightEdited) _weight.text = _fmt(s.weightKg);
        if (_count.text != '${s.itemCount}') _count.text = '${s.itemCount}';
      },
      buildWhen: (a, b) =>
          a.selectedPolymer.code != b.selectedPolymer.code ||
          a.itemCount != b.itemCount ||
          a.weightEdited != b.weightEdited,
      builder: (context, s) {
        final est = s.estimate;
        final unitG = (est.unitKg * 1000).round();
        return Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Batch weight',
                style: AppType.bodyStrong.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('weightField'),
                controller: _weight,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                style: AppType.metricM.copyWith(color: scheme.onSurface),
                decoration: const InputDecoration(
                  suffixText: 'kg',
                  hintText: '0.000',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: cubit.setWeight,
              ),
              const SizedBox(height: 16),
              const RowDivider(),
              const SizedBox(height: 12),
              Text(
                'SUGGESTED FROM THE PHOTO',
                style: AppType.label.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'A typical ${s.selectedPolymer.shortName} ${est.itemNoun} '
                      'weighs about $unitG g.',
                      style: AppType.body.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('Items', style: AppType.body),
                  const Spacer(),
                  IconButton(
                    key: const Key('itemMinus'),
                    onPressed: s.itemCount > 1
                        ? () => cubit.setItemCount(s.itemCount - 1)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      key: const Key('itemCount'),
                      controller: _count,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: AppType.monoBody,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        final n = int.tryParse(v);
                        if (n != null && n > 0) cubit.setItemCount(n);
                      },
                    ),
                  ),
                  IconButton(
                    key: const Key('itemPlus'),
                    onPressed: () => cubit.setItemCount(s.itemCount + 1),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${s.itemCount} × $unitG g ≈ '
                      '${est.kg.toStringAsFixed(3)} kg',
                      style: AppType.monoBody.copyWith(color: scheme.onSurface),
                    ),
                  ),
                  if (s.weightEdited)
                    TextButton(
                      onPressed: cubit.useEstimate,
                      child: const Text('Use suggestion'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Weigh the batch and type the real weight if you can. The '
                'suggestion uses typical item weights.',
                style: AppType.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CreditPanel extends StatelessWidget {
  const _CreditPanel();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MintingCubit>().state;
    final scheme = Theme.of(context).colorScheme;
    return Panel(
      background: AppColors.accentWash,
      border: const Color(0xFFCFE3D9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CREDIT VALUE',
                  style: AppType.label.copyWith(color: const Color(0xFF3A7A5F)),
                ),
                const SizedBox(height: 6),
                Text(
                  '${state.weightKg.toStringAsFixed(2)} kg × '
                  '${state.selectedPolymer.creditRate}',
                  style: AppType.monoSmall.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Formatters.credits(state.creditsPreview),
                style: AppType.metricL.copyWith(color: AppColors.accent),
              ),
              Text(
                '${Formatters.co2(state.co2Preview)} CO₂e',
                style: AppType.monoSmall.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MintButton extends StatelessWidget {
  const _MintButton();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MintingCubit>().state;
    final minting = state.status == MintingStatus.minting;
    return FilledButton(
      onPressed: state.canMint && !minting
          ? () => context.read<MintingCubit>().mint()
          : null,
      child: minting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text('Confirm & mint'),
    );
  }
}
