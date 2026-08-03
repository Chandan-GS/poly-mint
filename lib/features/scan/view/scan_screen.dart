import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../data/services/ml_service.dart';
import '../../../main.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../result/view/result_screen.dart';
import '../cubit/scan_cubit.dart';

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ScanCubit(sl<MlService>()),
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
  bool _torchOn = false;
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

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null) return;
    try {
      _torchOn = !_torchOn;
      await c.setFlashMode(_torchOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (_) {}
  }

  Future<void> _capture(BuildContext context) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    // Capture the dependencies we need up front so we don't touch `context`
    // across the await boundary.
    final scanCubit = context.read<ScanCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final highAccuracy = context.read<SettingsCubit>().state.highAccuracyMode;

    final frames = <Uint8List>[];
    try {
      final shots = highAccuracy ? 3 : 1;
      for (var i = 0; i < shots; i++) {
        final file = await c.takePicture();
        frames.add(await File(file.path).readAsBytes());
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not capture image.')),
      );
      return;
    }
    if (!mounted) return;
    scanCubit.classify(frames);
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
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, state) async {
        if (state.status == ScanStatus.success && state.result != null) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ResultScreen(result: state.result!),
            ),
          );
          if (context.mounted) context.read<ScanCubit>().reset();
        } else if (state.status == ScanStatus.error && state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.error!)),
          );
          context.read<ScanCubit>().reset();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _initFailed
            ? _CameraUnavailable()
            : _controller == null || !_controller!.value.isInitialized
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : _buildCamera(context),
      ),
    );
  }

  Widget _buildCamera(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Fullscreen preview.
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.previewSize!.height,
            height: _controller!.value.previewSize!.width,
            child: CameraPreview(_controller!),
          ),
        ),
        // Darken outside the framing window.
        _ReticleOverlay(),
        // Top bar.
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const Spacer(),
                BlocBuilder<SettingsCubit, SettingsState>(
                  buildWhen: (a, b) =>
                      a.highAccuracyMode != b.highAccuracyMode,
                  builder: (context, s) => _Pill(
                    icon: s.highAccuracyMode
                        ? Icons.hdr_strong
                        : Icons.hdr_weak,
                    label: s.highAccuracyMode ? 'High accuracy' : 'Fast',
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _toggleTorch,
                  icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off,
                      color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        // Guidance + capture button.
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _ScanTips(),
                const SizedBox(height: 16),
                BlocBuilder<ScanCubit, ScanState>(
                  builder: (context, state) {
                    final busy = state.status == ScanStatus.classifying ||
                        state.status == ScanStatus.loadingModel;
                    return GestureDetector(
                      onTap: busy ? null : () => _capture(context),
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                              color: const Color(0xFF34D399), width: 4),
                        ),
                        child: busy
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: Color(0xFF1B8A5A)),
                              )
                            : const Icon(Icons.camera,
                                color: Color(0xFF1B8A5A), size: 36),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                const Text('Tap to identify the polymer',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReticleOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 260,
        height: 260,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF34D399), width: 3),
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }
}

class _ScanTips extends StatelessWidget {
  const _ScanTips();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tips_and_updates, color: Color(0xFF34D399), size: 16),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'Fill the frame · good light · plain background',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF34D399), size: 15),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: EmptyState(
        icon: Icons.no_photography,
        title: 'Camera unavailable',
        message:
            'PolyMint needs camera access to identify polymers. Enable the '
            'camera permission in your device settings and try again.',
      ),
    );
  }
}
