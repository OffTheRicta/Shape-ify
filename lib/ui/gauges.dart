import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The orange tip shows magnetic north relative to the direction the camera faces.
class HeadingGauge extends StatelessWidget {
  final double headingDeg;
  const HeadingGauge({super.key, required this.headingDeg});
  @override Widget build(BuildContext context) => Container(
    width: 96, padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 64, height: 64, child: Stack(alignment: Alignment.center, children: [
        Container(decoration: BoxDecoration(shape: BoxShape.circle,
            border: Border.all(color: Colors.white70, width: 2))),
        // Fixed upper triangle is the rear camera's horizontal bearing.
        const Positioned(top: 1, child: Icon(Icons.arrow_drop_up,
            color: Colors.white, size: 18)),
        Transform.rotate(angle: -headingDeg * math.pi / 180,
          child: const Align(alignment: Alignment.topCenter,
            child: Padding(padding: EdgeInsets.only(top: 8),
              child: Text('N', style: TextStyle(color: Colors.deepOrangeAccent,
                  fontWeight: FontWeight.bold, fontSize: 19))))),
        const Icon(Icons.circle, size: 7, color: Colors.white),
      ])),
      Text('${headingDeg.round()}° magnetic', textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 11)),
    ]),
  );
}

/// A point and angle label move from the bottom (0°) to the top (90°).
class ElevationGauge extends StatelessWidget {
  final double elevationDeg;
  const ElevationGauge({super.key, required this.elevationDeg});
  @override Widget build(BuildContext context) => Container(
    width: 124, height: 140,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      CustomPaint(size: const Size(116, 112),
          painter: _ElevationArcPainter(elevationDeg)),
      const Text('elevation', style: TextStyle(color: Colors.white70,
          fontSize: 11)),
    ]),
  );
}

class _ElevationArcPainter extends CustomPainter {
  final double elevationDeg;
  const _ElevationArcPainter(this.elevationDeg);
  @override void paint(Canvas canvas, Size size) {
    const center = Offset(17, 17);
    const radius = 82.0;
    final arc = Paint()..color = Colors.white70..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        0, math.pi / 2, false, arc);
    final t = elevationDeg.clamp(0.0, 90.0) * math.pi / 180;
    final dot = Offset(center.dx + radius * math.sin(t),
        center.dy + radius * math.cos(t));
    canvas.drawCircle(dot, 6, Paint()..color = Colors.amberAccent);
    final label = TextPainter(
      text: TextSpan(text: '${elevationDeg.round()}°',
          style: const TextStyle(color: Colors.amberAccent,
              fontSize: 15, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelX = dot.dx > 65 ? dot.dx - label.width - 9 : dot.dx + 9;
    final labelY = (dot.dy - 11).clamp(0.0, size.height - label.height);
    label.paint(canvas, Offset(labelX, labelY.toDouble()));
    final marks = Paint()..color = Colors.white54..strokeWidth = 1;
    canvas.drawLine(const Offset(14, 101), const Offset(14, 107), marks);
    canvas.drawLine(const Offset(99, 14), const Offset(106, 14), marks);
  }
  @override bool shouldRepaint(_ElevationArcPainter oldDelegate) =>
      oldDelegate.elevationDeg != elevationDeg;
}
