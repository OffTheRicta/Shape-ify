import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The native launch screen is black; this timeline starts on Flutter's first
/// frame. Permission dialogs are deferred until after the intro.
class LaunchSequence extends StatefulWidget {
  final Widget? child;
  const LaunchSequence({super.key, this.child});

  @override
  State<LaunchSequence> createState() => _LaunchSequenceState();
}

class _LaunchSequenceState extends State<LaunchSequence>
    with SingleTickerProviderStateMixin {
  static const totalMs = 10700;
  late final AnimationController controller;
  bool finished = false;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this,
        duration: const Duration(milliseconds: totalMs));
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => finished = true);
      }
    });
    controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/family_crest.png'), context);
    precacheImage(const AssetImage('assets/logo.png'), context);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  // 0–3 s: crest zoom/fade; 3–4 s: hold; 4–6 s: fade out.
  static double crestScale(double ms) =>
      (0.72 + 0.28 * (ms / 3000).clamp(0.0, 1.0)).toDouble();

  static double crestOpacity(double ms) {
    if (ms < 3000) return (ms / 3000).clamp(0.0, 1.0).toDouble();
    if (ms < 4000) return 1;
    return ((6000 - ms) / 2000).clamp(0.0, 1.0).toDouble();
  }

  // Logo overlaps the last 0.3 s of the crest: in 5.7–7.7, hold 7.7–9.7,
  // out 9.7–10.7 seconds.
  static double logoOpacity(double ms) {
    if (ms < 5700) return 0;
    if (ms < 7700) return ((ms - 5700) / 2000).toDouble();
    if (ms < 9700) return 1;
    return ((10700 - ms) / 1000).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => LayoutBuilder(builder: (context, bounds) {
      final width = bounds.maxWidth;
      final height = bounds.maxHeight;
      final ms = controller.value * totalMs;
      final crestWidth = math.min(width * 0.96, height * 0.85 * 960 / 1097);
      return Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Color(0xFF080D14)),
        if (!finished) ...[
          Center(child: Opacity(key: const ValueKey('intro-crest'),
            opacity: crestOpacity(ms),
            child: Transform.scale(key: const ValueKey('crest-zoom'),
              scale: crestScale(ms),
              child: Image.asset('assets/family_crest.png',
                width: crestWidth, fit: BoxFit.contain)))),
          Center(child: Opacity(key: const ValueKey('intro-logo'),
            opacity: logoOpacity(ms),
            child: Image.asset('assets/logo.png',
              width: math.min(width * 0.96, height * 0.78),
              fit: BoxFit.contain))),
        ],
        if (finished) widget.child ?? const SizedBox.shrink(),
      ]);
    }),
  );
}
