import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../reconstruction/layout.dart';

/// Incoming pieces line up first. Once every planned station supplies the
/// three named stars, the pieces move into a compact schematic arrangement.
/// Their positions and disc tilt are presentation only, never a surface fit.
class StationDiagram extends StatefulWidget {
  final List<StationPoint> points;
  final bool arrows;
  final bool assemble;
  final String? star;
  final int selected;
  final ValueChanged<int> onSelect;

  const StationDiagram({super.key, required this.points, required this.arrows,
    required this.assemble, required this.star, required this.selected,
    required this.onSelect});

  @override
  State<StationDiagram> createState() => _StationDiagramState();
}

class _StationDiagramState extends State<StationDiagram>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 2100));
    if (widget.assemble) controller.forward();
  }

  @override
  void didUpdateWidget(covariant StationDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.assemble && widget.assemble) controller.forward(from: 0);
    if (oldWidget.assemble && !widget.assemble) controller.reset();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  double _movement(int index) {
    final count = widget.points.length;
    final start = count <= 1 ? 0.0 : (index / count) * 0.35;
    return Curves.easeInOutCubic.transform(
        ((controller.value - start) / (1 - start)).clamp(0.0, 1.0).toDouble());
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) {
    final width = math.max(bounds.maxWidth, 320.0);
    final height = math.max(bounds.maxHeight,
        ((widget.points.length / 3).ceil() * 128 + 62).toDouble());
    return InteractiveViewer(minScale: 0.55, maxScale: 5,
      constrained: false,
      child: SizedBox(width: width, height: height,
        child: AnimatedBuilder(animation: controller, builder: (context, _) {
          final centers = <Offset>[
            for (var i = 0; i < widget.points.length; i++)
              Offset.lerp(
                _offset(AssemblyLayout.staging(i, width)),
                _offset(AssemblyLayout.assembled(i,
                    widget.points.length, width, height)),
                _movement(i))!,
          ];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              if (centers.isEmpty) return;
              var nearest = 0;
              for (var i = 1; i < centers.length; i++) {
                if ((centers[i] - details.localPosition).distance <
                    (centers[nearest] - details.localPosition).distance) {
                  nearest = i;
                }
              }
              if ((centers[nearest] - details.localPosition).distance < 59) {
                widget.onSelect(nearest);
              }
            },
            child: CustomPaint(painter: _PiecePainter(widget.points, centers,
              widget.star, widget.selected, widget.arrows,
              controller.value, widget.assemble)),
          );
        }),
      ),
    );
  });

  static Offset _offset(LayoutPosition p) => Offset(p.x, p.y);
}

class _PiecePainter extends CustomPainter {
  final List<StationPoint> points;
  final List<Offset> centers;
  final String? star;
  final int selected;
  final bool arrows;
  final double progress;
  final bool assemble;

  const _PiecePainter(this.points, this.centers, this.star, this.selected,
      this.arrows, this.progress, this.assemble);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0x4441D6A5)..strokeWidth = 0.65;
    for (var x = 0.0; x < size.width; x += 20) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 20) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (points.isEmpty) {
      _label(canvas, 'Sightings appear here', Offset(size.width / 2,
          size.height / 2), size.width - 24, 14, Colors.white70);
      return;
    }

    for (var i = 0; i < points.length; i++) {
      final center = centers[i];
      final reading = points[i].observations.where((o) => o.starId == star)
          .firstOrNull ?? points[i].observation;
      final selectedPiece = selected == i;
      final tint = selectedPiece
          ? const Color(0xB87BCBCD) : const Color(0x936FA8B4);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      // The tilt is purely visual. It carries no inferred terrain information.
      canvas.rotate(-0.12 * progress * (assemble ? 1 : 0));
      canvas.scale(1, 1 - 0.20 * progress * (assemble ? 1 : 0));
      canvas.drawCircle(Offset.zero, 42, Paint()..color = tint);
      canvas.drawCircle(Offset.zero, 42, Paint()
        ..color = selectedPiece ? const Color(0xFFB7FEE3) : const Color(0xFFB9DBE2)
        ..style = PaintingStyle.stroke ..strokeWidth = 1.5);
      if (arrows) {
        // Clockwise from local north; magnitude encodes the reported altitude
        // in degrees. It does not represent the star's physical height.
        final radians = reading.azimuthDeg * math.pi / 180;
        final length = 11.0 +
            reading.altitudeDeg.clamp(0.0, 90.0).toDouble() * 0.65;
        final tip = Offset(math.sin(radians) * length,
            -math.cos(radians) * length);
        final direction = Offset(math.sin(radians), -math.cos(radians));
        final side = Offset(-direction.dy, direction.dx);
        final paint = Paint()..color = const Color(0xFF19ED83)
          ..strokeWidth = 4 ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset.zero, tip, paint);
        canvas.drawPath(Path()..moveTo(tip.dx, tip.dy)
          ..lineTo(tip.dx - direction.dx * 12 + side.dx * 6,
              tip.dy - direction.dy * 12 + side.dy * 6)
          ..lineTo(tip.dx - direction.dx * 12 - side.dx * 6,
              tip.dy - direction.dy * 12 - side.dy * 6)
          ..close(), paint);
        canvas.drawCircle(Offset.zero, 3, Paint()..color = Colors.white);
      }
      canvas.restore();
      _label(canvas, points[i].observation.observer,
          center + const Offset(0, 50), 100, 13, Colors.white);
      _label(canvas, '${reading.starId}  ${reading.altitudeDeg.toStringAsFixed(0)}°',
          center + const Offset(0, 67), 100, 11, Colors.white70);
    }
  }

  void _label(Canvas canvas, String text, Offset center, double width,
      double fontSize, Color color) {
    final painter = TextPainter(text: TextSpan(text: text,
      style: TextStyle(color: color, fontSize: fontSize)),
      textDirection: TextDirection.ltr, textAlign: TextAlign.center,
      maxLines: 1, ellipsis: '…')..layout(maxWidth: width);
    painter.paint(canvas, center - Offset(painter.width / 2, 0));
  }

  @override
  bool shouldRepaint(covariant _PiecePainter previous) =>
      previous.points != points || previous.centers != centers ||
      previous.selected != selected || previous.arrows != arrows ||
      previous.star != star || previous.progress != progress ||
      previous.assemble != assemble;
}
