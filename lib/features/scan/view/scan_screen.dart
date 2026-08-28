import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../data/services/ml_service.dart';
import '../../../data/services/popp_engine.dart';
import '../../../data/services/weight_sensor.dart';
import '../../../main.dart';
import '../../result/view/result_screen.dart';
import '../cubit/scan_cubit.dart';

const _accent = Color(0xFF2FCB8B);

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ScanCubit(sl<MlService>(), sl<WeightSensor>()),
      child: const _ScanView(),
    );
  }
}

class _ScanView extends StatefulWidget {
  const _ScanView();
  @override
  State<_ScanView> createState() => _ScanViewState();
}

class _ScanViewState extends State<_ScanView> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (availableCameraList.isEmpty) {
      setState(() => _initFailed = true);
      return;
    }
    try {
      final controller = CameraController(
        availableCameraList.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (_) {
      setState(() => _initFailed = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _capture(BuildContext context) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final scanCubit = context.read<ScanCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final frames = <Uint8List>[];
    try {
      final file = await c.takePicture();
      frames.add(await File(file.path).readAsBytes());
    } catch (_) {
      messenger
          .showSnackBar(const SnackBar(content: Text('Could not capture image.')));
      return;
    }
    if (!mounted) return;
    scanCubit.capture(frames);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ScanCubit, ScanState>(
      listenWhen: (a, b) => a.phase != b.phase,
      listener: (context, state) async {
        if (state.phase == ScanPhase.success &&
            state.result != null &&
            state.proof != null) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ResultScreen(
                  result: state.result!, proof: state.proof!),
            ),
          );
          if (context.mounted) context.read<ScanCubit>().reset();
        } else if (state.phase == ScanPhase.error && state.error != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.error!)));
          context.read<ScanCubit>().reset();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _initFailed
            ? _CameraUnavailable()
            : _controller == null || !_controller!.value.isInitialized
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _buildCamera(context),
      ),
    );
  }

  Widget _buildCamera(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.previewSize!.height,
            height: _controller!.value.previewSize!.width,
            child: CameraPreview(_controller!),
          ),
        ),
        const _Viewfinder(),
        // top bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                BlocBuilder<ScanCubit, ScanState>(
                  buildWhen: (a, b) => a.simulated != b.simulated,
                  builder: (context, s) => s.simulated
                      ? _tag('◦ SIMULATED SENSOR')
                      : _tag('◦ SENSOR'),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        // bottom HUD + capture
        BlocBuilder<ScanCubit, ScanState>(
          builder: (context, state) {
            if (state.phase == ScanPhase.rejected) {
              return _RejectionOverlay(
                reason: state.rejectReason ?? 'No physical presence.',
                onRetry: () => context.read<ScanCubit>().reset(),
              );
            }
            return _CaptureDock(
              state: state,
              onCapture: () => _capture(context),
              onSimulate: () => context.read<ScanCubit>().simulatePlacement(),
            );
          },
        ),
      ],
    );
  }

  Widget _tag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(text,
            style: AppType.monoSmall.copyWith(color: Colors.white70)),
      );
}

/// Live weight HUD + arm state + capture button (gated until armed).
class _CaptureDock extends StatelessWidget {
  final ScanState state;
  final VoidCallback onCapture;
  final VoidCallback onSimulate;
  const _CaptureDock(
      {required this.state, required this.onCapture, required this.onSimulate});

  @override
  Widget build(BuildContext context) {
    final busy = state.phase == ScanPhase.classifying;
    final armed = state.isArmed;
    final (String armText, Color armColor) = switch (state.armState) {
      PoppArmState.armed => ('Armed', _accent),
      PoppArmState.settling => ('Settling…', Colors.white),
      PoppArmState.waitingForMass => ('Place a batch on the scale', Colors.white70),
      PoppArmState.idle => ('Connecting sensor…', Colors.white70),
    };

    return Positioned(
      left: 16,
      right: 16,
      bottom: 0,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // HUD panel
            Container(
              padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.82),
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('LIVE WEIGHT',
                                style: AppType.label
                                    .copyWith(color: Colors.white54)),
                            const SizedBox(height: 4),
                            Text.rich(TextSpan(
                              text: state.liveKg.toStringAsFixed(3),
                              style: AppType.metricL.copyWith(color: Colors.white),
                              children: [
                                TextSpan(
                                    text: '  kg',
                                    style: AppType.monoSmall
                                        .copyWith(color: Colors.white54)),
                              ],
                            )),
                          ],
                        ),
                      ),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                            width: 7,
                            height: 7,
                            decoration:
                                BoxDecoration(color: armColor, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(armText,
                            style: AppType.label.copyWith(color: armColor)),
                      ]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: armed ? 1 : (state.armState == PoppArmState.settling ? 0.5 : 0.06),
                      minHeight: 4,
                      backgroundColor: Colors.white24,
                      color: _accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // capture button — enabled only when armed
            GestureDetector(
              onTap: (armed && !busy) ? onCapture : null,
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: armed ? _accent : Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(armed ? 'CAPTURE  ▸' : 'WAITING FOR STABLE WEIGHT',
                        style: AppType.monoSmall.copyWith(
                            color: Colors.white,
                            fontSize: 12,
                            letterSpacing: 1)),
              ),
            ),
            if (state.simulated) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSimulate,
                child: Text('↻ simulate a new batch',
                    style: AppType.monoSmall.copyWith(color: Colors.white70)),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// The pitch moment: photo/replay with no mass → rejected.
class _RejectionOverlay extends StatelessWidget {
  final String reason;
  final VoidCallback onRetry;
  const _RejectionOverlay({required this.reason, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF17110F).withValues(alpha: 0.96),
            border: Border.all(color: const Color(0xFFB23A2E)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                        color: Color(0xFFE8756A), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('REJECTED',
                    style: AppType.label.copyWith(color: const Color(0xFFE8756A))),
              ]),
              const SizedBox(height: 12),
              Text('No weight on the scale',
                  style: AppType.heading.copyWith(color: Colors.white)),
              const SizedBox(height: 8),
              Text(
                'A photo or a video off a screen has no weight, so nothing can '
                'be minted. Put the real plastic on the scale and try again.',
                style: AppType.body.copyWith(color: const Color(0xFFD7C9C7)),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                  ),
                  child: const Text('Try again'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 250,
        height: 250,
        child: CustomPaint(painter: _CornerPainter()),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white70
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const l = 26.0;
    // corners
    canvas.drawPath(Path()..moveTo(0, l)..lineTo(0, 0)..lineTo(l, 0), p);
    canvas.drawPath(
        Path()..moveTo(size.width - l, 0)..lineTo(size.width, 0)..lineTo(size.width, l), p);
    canvas.drawPath(
        Path()..moveTo(0, size.height - l)..lineTo(0, size.height)..lineTo(l, size.height), p);
    canvas.drawPath(Path()
      ..moveTo(size.width - l, size.height)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width, size.height - l), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CameraUnavailable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: EmptyState(
        icon: Icons.no_photography_outlined,
        title: 'Camera unavailable',
        message: 'PolyMint needs the camera to identify plastic. Enable the '
            'camera permission in settings and try again.',
      ),
    );
  }
}
