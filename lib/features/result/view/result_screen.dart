import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/classification_result.dart';
import '../../../data/models/polymer_info.dart';
import '../../../data/services/location_service.dart';
import '../../../data/services/preferences_service.dart';
import '../../../data/services/transaction_repository.dart';
import '../cubit/minting_cubit.dart';

class ResultScreen extends StatelessWidget {
  final ClassificationResult result;
  const ResultScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MintingCubit(
        result: result,
        repo: sl<TransactionRepository>(),
        location: sl<LocationService>(),
        prefs: sl<PreferencesService>(),
      ),
      child: _ResultView(result: result),
    );
  }
}

class _ResultView extends StatelessWidget {
  final ClassificationResult result;
  const _ResultView({required this.result});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify & mint')),
      body: BlocListener<MintingCubit, MintingState>(
        listenWhen: (a, b) => a.status != b.status,
        listener: (context, state) {
          if (state.status == MintingStatus.mintedOnline ||
              state.status == MintingStatus.mintedOffline) {
            _showSuccess(context, state);
          } else if (state.status == MintingStatus.error &&
              state.error != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.error!)));
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ConfidenceCard(result: result),
            const SizedBox(height: 16),
            _CandidatePicker(result: result),
            const SizedBox(height: 16),
            const _SelectedPolymerCard(),
            const SizedBox(height: 16),
            const _WeightInput(),
            const SizedBox(height: 16),
            const _CreditPreview(),
            const SizedBox(height: 24),
            const _MintButton(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showSuccess(BuildContext context, MintingState state) {
    final online = state.status == MintingStatus.mintedOnline;
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: false,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle,
                  color: Color(0xFF16A34A), size: 44),
            ),
            const SizedBox(height: 16),
            Text('${Formatters.credits(state.creditsPreview)} credits minted',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              online
                  ? 'Verified and recorded to the exchange ledger.'
                  : 'Saved offline — it will sync automatically when you '
                      'reconnect.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // sheet
                  Navigator.pop(context); // result screen → back to scan
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

class _ConfidenceCard extends StatelessWidget {
  final ClassificationResult result;
  const _ConfidenceCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final confident = result.isConfident;
    final uncertain = result.isUncertain || result.isAmbiguous;
    final color = uncertain
        ? const Color(0xFFF59E0B)
        : confident
            ? const Color(0xFF16A34A)
            : scheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: color, size: 18),
                const SizedBox(width: 6),
                const Text('AI detection',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${result.inferenceTime.inMilliseconds} ms',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(result.polymer.shortName,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                Text(result.polymer.fullName,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: result.confidence.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 6),
            Text('${Formatters.percent(result.confidence)} confidence',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            if (uncertain) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: Color(0xFFF59E0B)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'The AI isn’t fully sure. Confirm the resin code below '
                        'or rescan with better lighting.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CandidatePicker extends StatelessWidget {
  final ClassificationResult result;
  const _CandidatePicker({required this.result});

  @override
  Widget build(BuildContext context) {
    final selected = context.select((MintingCubit c) => c.state.selectedPolymer);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Confirm material',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in result.predictions)
              ChoiceChip(
                selected: selected.code == p.polymer.code,
                onSelected: (_) =>
                    context.read<MintingCubit>().selectPolymer(p.polymer),
                avatar: CircleAvatar(
                  backgroundColor: p.polymer.color,
                  radius: 9,
                  child: Text('${p.polymer.resinNumber}',
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
                label: Text(
                    '${p.polymer.shortName} · ${Formatters.percent(p.confidence)}'),
              ),
            // Manual escape hatch to any resin.
            ActionChip(
              avatar: const Icon(Icons.more_horiz, size: 18),
              label: const Text('Other'),
              onPressed: () => _showAllPolymers(context),
            ),
          ],
        ),
      ],
    );
  }

  void _showAllPolymers(BuildContext context) {
    final cubit = context.read<MintingCubit>();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Select resin code',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final p in PolymerCatalog.all)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: p.color,
                  child: Text('${p.resinNumber}',
                      style: const TextStyle(color: Colors.white)),
                ),
                title: Text('${p.shortName} — ${p.fullName}'),
                subtitle: Text('${p.creditRate} credits/kg'),
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

class _SelectedPolymerCard extends StatelessWidget {
  const _SelectedPolymerCard();

  @override
  Widget build(BuildContext context) {
    final p = context.select((MintingCubit c) => c.state.selectedPolymer);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(p.fullName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: p.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(p.recyclabilityLabel,
                      style: TextStyle(
                          color: p.color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(p.description,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Text('Prep tips',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            for (final tip in p.tips)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check, size: 15, color: p.color),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(tip,
                            style: const TextStyle(fontSize: 12.5))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WeightInput extends StatelessWidget {
  const _WeightInput();

  @override
  Widget build(BuildContext context) {
    return TextField(
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
      ],
      onChanged: (v) => context.read<MintingCubit>().setWeight(v),
      decoration: const InputDecoration(
        labelText: 'Batch weight',
        hintText: 'e.g. 2.5',
        prefixIcon: Icon(Icons.scale),
        suffixText: 'kg',
      ),
    );
  }
}

class _CreditPreview extends StatelessWidget {
  const _CreditPreview();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MintingCubit>().state;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Credits to mint',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(Formatters.credits(state.creditsPreview),
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: scheme.primary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('CO₂ avoided',
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(Formatters.co2(state.co2Preview),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              Text('@ ${state.selectedPolymer.creditRate}/kg',
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant)),
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
    return ElevatedButton.icon(
      onPressed: state.canMint && !minting
          ? () => context.read<MintingCubit>().mint()
          : null,
      icon: minting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.verified),
      label: Text(minting ? 'Minting…' : 'Mint credits'),
    );
  }
}
