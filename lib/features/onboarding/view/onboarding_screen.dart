import 'package:flutter/material.dart';

import '../../../core/di/injector.dart';
import '../../../data/services/preferences_service.dart';
import '../../home/view/home_shell.dart';

class _Slide {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _Slide(this.icon, this.color, this.title, this.body);
}

/// First-launch walkthrough explaining the scan → weigh → mint flow.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _slides = [
    _Slide(
      Icons.recycling,
      Color(0xFF1B8A5A),
      'Turn plastic into impact',
      'PolyMint verifies recovered plastic with on-device AI and mints '
          'circular-economy credits for every kilogram you recycle.',
    ),
    _Slide(
      Icons.center_focus_strong,
      Color(0xFF2563EB),
      'Scan the resin',
      'Point your camera at the item inside the frame. The AI identifies the '
          'polymer type (PET, HDPE, PP…) right on your phone — no internet '
          'needed for detection.',
    ),
    _Slide(
      Icons.scale,
      Color(0xFFF59E0B),
      'Weigh & confirm',
      'Enter the weight of the batch. PolyMint calculates credits and the CO₂ '
          'you helped avoid using real recycling factors. Not sure of the '
          'resin? Pick from the AI’s top suggestions.',
    ),
    _Slide(
      Icons.workspace_premium,
      Color(0xFF7C3AED),
      'Mint & track impact',
      'Your verified batch is minted to the exchange ledger. Track credits, '
          'climb the leaderboard, and watch your environmental impact grow.',
    ),
  ];

  bool get _isLast => _index == _slides.length - 1;

  Future<void> _finish() async {
    await sl<PreferencesService>().setOnboarded();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeShell()),
    );
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
          duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: Text(_isLast ? '' : 'Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: _slides.length,
                itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _index ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _index
                        ? _slides[_index].color
                        : Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _slides[_index].color),
                onPressed: _next,
                child: Text(_isLast ? 'Get started' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: slide.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(slide.icon, size: 64, color: slide.color),
          ),
          const SizedBox(height: 40),
          Text(slide.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Text(slide.body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15.5,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
        ],
      ),
    );
  }
}
