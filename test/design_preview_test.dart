import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poly_mint/core/theme/app_colors.dart';
import 'package:poly_mint/core/theme/app_theme.dart';
import 'package:poly_mint/core/theme/app_type.dart';
import 'package:poly_mint/core/widgets/app_widgets.dart';

/// Renders the redesigned dashboard with the real theme + IBM Plex fonts and
/// writes a PNG (run with `flutter test --update-goldens`). Not a real test —
/// a design-preview harness so the instrument look can be eyeballed.
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(rootBundle.load(p));
    }
    await loader.load();
  }

  await load('IBM Plex Sans', ['assets/fonts/IBMPlexSans-Variable.ttf']);
  await load('IBM Plex Mono', [
    'assets/fonts/IBMPlexMono-Regular.ttf',
    'assets/fonts/IBMPlexMono-Medium.ttf',
  ]);
}

Widget _panel(BuildContext c, Widget child,
        {EdgeInsets p = const EdgeInsets.all(16)}) =>
    Container(
      width: double.infinity,
      padding: p,
      decoration: BoxDecoration(
        color: Theme.of(c).colorScheme.surface,
        border: Border.all(color: Theme.of(c).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
    );

void main() {
  setUpAll(_loadFonts);

  testWidgets('dashboard preview', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Builder(builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        Widget vdiv() =>
            Container(width: 1, height: 34, color: scheme.outlineVariant);
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                // header
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('POLYMINT',
                            style: AppType.label.copyWith(
                                color: scheme.onSurface, letterSpacing: 2.5)),
                        const SizedBox(height: 4),
                        Text('Good evening, Ramesh',
                            style: AppType.caption
                                .copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: AppColors.accent, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('LIVE',
                      style: AppType.monoSmall
                          .copyWith(color: scheme.onSurfaceVariant)),
                ]),
                const SizedBox(height: 20),
                // hero readout
                _panel(
                  context,
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('VERIFIED MASS',
                        style: AppType.label
                            .copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    RichText(
                      text: TextSpan(
                        text: '12.40',
                        style: AppType.metricXL.copyWith(color: scheme.onSurface),
                        children: [
                          TextSpan(
                              text: '  kg',
                              style: AppType.metricM
                                  .copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Divider(height: 1, color: scheme.outlineVariant),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                          child: Metric(
                              label: 'Credits minted',
                              value: '342.80',
                              valueStyle: AppType.metricM,
                              valueColor: AppColors.accent)),
                      Expanded(
                          child: Metric(
                              label: 'CO₂e avoided',
                              value: '8.1',
                              unit: 'kg',
                              valueStyle: AppType.metricM)),
                    ]),
                  ]),
                  p: const EdgeInsets.all(18),
                ),
                const SizedBox(height: 12),
                // triple stat
                _panel(
                  context,
                  Row(children: [
                    Expanded(
                        child: Center(
                            child: Metric(
                                label: 'Batches',
                                value: '27',
                                align: CrossAxisAlignment.center))),
                    vdiv(),
                    Expanded(
                        child: Center(
                            child: Metric(
                                label: 'Verified',
                                value: '25',
                                align: CrossAxisAlignment.center))),
                    vdiv(),
                    Expanded(
                        child: Center(
                            child: Metric(
                                label: 'Top resin',
                                value: 'PET',
                                align: CrossAxisAlignment.center))),
                  ]),
                  p: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                ),
                const SizedBox(height: 26),
                const SectionLabel('Recent activity',
                    trailing: null),
                _panel(
                  context,
                  Column(children: [
                    _row(context, 'PET', '1.20', 'verified', AppColors.verified),
                    Divider(height: 1, color: scheme.outlineVariant),
                    _row(context, 'HDPE', '0.90', 'verified', AppColors.verified),
                    Divider(height: 1, color: scheme.outlineVariant),
                    _row(context, 'PP', '0.30', 'review', AppColors.review),
                  ]),
                  p: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        );
      }),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dashboard.png'),
    );
  });
}

Widget _row(BuildContext c, String resin, String kg, String status, Color col) {
  final scheme = Theme.of(c).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    child: Row(children: [
      SizedBox(
          width: 54,
          child: Text(resin,
              style: AppType.bodyStrong.copyWith(color: scheme.onSurface))),
      Text('$kg kg', style: AppType.monoBody.copyWith(color: scheme.onSurface)),
      const Spacer(),
      StatusTag(label: status, color: col),
    ]),
  );
}
