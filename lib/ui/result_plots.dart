import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../reconstruction/layout.dart';

/// Candidate geometry only. Plotting geographic coordinates on a sphere is a
/// labelled model; it must never be confused with a fitted surface result.
class ResultPlots extends StatefulWidget {
  final List<StationPoint> stations;
  final VoidCallback onCheckAgain;
  final String? sessionId;
  final String? description;
  final ValueChanged<bool>? onWebView;
  const ResultPlots({super.key, required this.stations, required this.onCheckAgain,
    this.sessionId, this.description, this.onWebView});
  @override State<ResultPlots> createState() => _ResultPlotsState();
}

/// Fits the measured station centres in the viewport without changing their
/// positions relative to one another. Disc diameters remain legible on screen.
class ResultViewportFit {
  static ({double zoom, Offset pan}) calculate(List<Offset> points, Size viewport) {
    if (points.isEmpty || viewport.isEmpty) {
      return (zoom: 1, pan: Offset.zero);
    }
    var left = points.first.dx, right = left;
    var top = points.first.dy, bottom = top;
    for (final point in points.skip(1)) {
      left = math.min(left, point.dx);
      right = math.max(right, point.dx);
      top = math.min(top, point.dy);
      bottom = math.max(bottom, point.dy);
    }
    // Reserve space for the fixed-size station discs at both edges.
    final availableWidth = math.max(1.0, viewport.width * .8 - 36);
    final availableHeight = math.max(1.0, viewport.height * .8 - 36);
    final xZoom = right - left > 1e-9
        ? availableWidth / (right - left) : double.infinity;
    final yZoom = bottom - top > 1e-9
        ? availableHeight / (bottom - top) : double.infinity;
    final rawZoom = math.min(xZoom, yZoom);
    final zoom = (rawZoom.isFinite ? rawZoom : 1.0).clamp(.25, 16384.0);
    final centre = Offset(viewport.width / 2, viewport.height / 2);
    final stationCentre = Offset((left + right) / 2, (top + bottom) / 2);
    return (zoom: zoom, pan: (centre - stationCentre) * zoom);
  }
}

class _ResultPlotsState extends State<ResultPlots> {
  bool globe = false;
  bool allPairs = false;
  double flatYaw = .35, flatPitch = .38, globeYaw = 0;
  int selected = 0;
  double zoom = 1;
  Offset pan = Offset.zero;
  double gestureZoom = 1;
  double fittedZoom = 1;
  Offset fittedPan = Offset.zero;
  String? fittedKey;

  double get _zoomSliderValue =>
      ((math.log(zoom) / math.ln2 + 2) / 16).clamp(0.0, 1.0);

  void _setZoomFromSlider(double position) {
    final next = math.pow(2, -2 + 16 * position).toDouble();
    setState(() {
      pan *= next / zoom;
      zoom = next;
    });
  }

  Widget _compactSlider(BuildContext context, {required String title,
      required String value, required double position,
      required ValueChanged<double> onChanged, Key? key}) {
    return SizedBox(height: 38, child: Row(children: [
      SizedBox(width: 58, child: Text(title)),
      Expanded(child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        ),
        child: Slider(key: key, value: position, onChanged: onChanged),
      )),
      SizedBox(width: 48, child: Text(value, textAlign: TextAlign.right)),
    ]));
  }

  void _fitStations(List<StationPoint> stations, Size size) {
    final key = '$globe:${size.width}:${size.height}:'
      '${stations.map((s) => '${s.observation.id}:${s.observation.latitude}:'
        '${s.observation.longitude}').join('|')}';
    if (key == fittedKey) return;
    fittedKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || key != fittedKey) return;
      final painter = _CandidatePainter(stations, globe,
        flatYaw, flatPitch, globeYaw, selected, 1, Offset.zero, allPairs);
      final fit = ResultViewportFit.calculate(painter._centres(size), size);
      setState(() {
        fittedZoom = zoom = fit.zoom;
        fittedPan = pan = fit.pan;
      });
    });
  }

  void _showPlot(bool showGlobe) => setState(() {
    globe = showGlobe;
    zoom = 1;
    pan = Offset.zero;
  });

  @override Widget build(BuildContext context) {
    final records = widget.stations;
    if (records.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Waiting for measured stations.'),
        if (widget.onWebView != null) FilledButton.tonalIcon(
          key: const Key('view-results-via-web'),
          onPressed: () => widget.onWebView!(globe),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('View results on website')),
      ]);
    }
    final chosen = records[math.min(selected, records.length - 1)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Every phone builds the same picture',
        style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      SizedBox(height: 340, child: Card(clipBehavior: Clip.hardEdge,
        child: Stack(children: [
          LayoutBuilder(builder: (context, bounds) {
          _fitStations(records, Size(bounds.maxWidth, bounds.maxHeight));
          return GestureDetector(
          key: const Key('result-viewport'),
          behavior: HitTestBehavior.opaque,
          onDoubleTap: () => setState(() {
            zoom = fittedZoom;
            pan = fittedPan;
          }),
          onScaleStart: (_) => gestureZoom = zoom,
          onScaleUpdate: (details) => setState(() {
            if (details.pointerCount > 1) {
              final next = (gestureZoom * details.scale).clamp(.25, 16384.0);
              final focal = details.localFocalPoint -
                Offset(bounds.maxWidth / 2, bounds.maxHeight / 2);
              // Anchor the content beneath the previous finger position,
              // then move it with the fingers while changing the scale.
              pan = focal - (focal - details.focalPointDelta - pan) *
                (next / zoom);
              zoom = next;
            } else {
              pan += details.focalPointDelta;
            }
          }),
          onTapDown: (details) {
            final painter = _CandidatePainter(records, globe,
              flatYaw, flatPitch, globeYaw, selected, zoom, pan, allPairs);
            final hit = painter.hitTestStation(details.localPosition,
              Size(bounds.maxWidth, bounds.maxHeight));
            if (hit != null) setState(() => selected = hit);
          },
          child: CustomPaint(painter: _CandidatePainter(records, globe,
            flatYaw, flatPitch, globeYaw, selected, zoom, pan, allPairs),
            child: const SizedBox.expand()),
        );
          }),
          Positioned(left: 10, right: 10, bottom: 8,
            child: IgnorePointer(child: Text(globe
              ? 'Gold: selected  ·  Cyan: stations  ·  3 rays each'
              : 'Gold: selected  ·  Cyan: stations  ·  3 rays each',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Colors.white,
                shadows: [Shadow(color: Colors.black, blurRadius: 5)])))),
        ]))),
      _compactSlider(context, title: 'Zoom', value: '${zoom.toStringAsFixed(1)}×',
        position: _zoomSliderValue, key: const Key('zoom-slider'),
        onChanged: _setZoomFromSlider),
      if (globe)
        _compactSlider(context, title: 'Rotate',
          value: '${(globeYaw * 180 / math.pi).round()}°',
          position: (globeYaw + math.pi) / (2 * math.pi),
          onChanged: (value) => setState(() => globeYaw =
            value * 2 * math.pi - math.pi))
      else ...[
        _compactSlider(context, title: 'Turn',
          value: '${(flatYaw * 180 / math.pi).round()}°',
          position: (flatYaw + math.pi) / (2 * math.pi),
          onChanged: (value) => setState(() => flatYaw =
            value * 2 * math.pi - math.pi)),
        _compactSlider(context, title: 'Tilt',
          value: '${(flatPitch * 180 / math.pi).round()}°',
          position: (flatPitch + 1.35) / 2.7,
          onChanged: (value) => setState(() => flatPitch =
            value * 2.7 - 1.35)),
        const Text('The centre axes mark east, north and up.'),
      ],
      if (globe) SwitchListTile(
        key: const Key('all-pairs-toggle'),
        title: const Text('Straight lines between every station'),
        subtitle: Text('${records.length * (records.length - 1) ~/ 2} unique pairs'),
        value: allPairs,
        onChanged: (v) => setState(() => allPairs = v)),
      const Text('Double-tap the plot to refit stations.'),
      Text('Station ${selected + 1}: ${chosen.observation.observer} · '
        '${chosen.observations.length} star readings'),
      const SizedBox(height: 8),
      if (!globe) ...[
        FilledButton(onPressed: () => _showPlot(true),
          child: const Text('Continue to 3D workspace')),
        TextButton(onPressed: widget.onCheckAgain,
          child: const Text('Check measurements again')),
      ] else FilledButton(onPressed: () => _showPlot(false),
        child: const Text('Back to flat observations')),
      if (widget.onWebView != null)
        Align(alignment: Alignment.centerLeft, child: FilledButton.tonalIcon(
          key: const Key('view-results-via-web'),
          onPressed: () => widget.onWebView!(globe),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('View results on website'))),
      if (widget.sessionId != null)
        Text('Session ID: ${widget.sessionId}',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      Text(globe ? 'Second view · 3D workspace (fit pending)' : 'First view · flat observations',
        style: Theme.of(context).textTheme.titleLarge),
      const Text('Original star readings · no inferred surface'),
      const Text('Drag to move · pinch with two fingers to zoom'),
      for (var i = 0; i < records.length; i++)
        TextButton(onPressed: () => setState(() => selected = i),
          child: Text('${i + 1} · ${records[i].observation.observer}')),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(globe
        ? 'No globe is drawn. Reference positions only; the measured 3D station fit is not yet implemented.'
        : 'Flat reference projection of stations and original star rays; no measured ground surface is implied.'))),
      if (widget.description != null) ...[
        const SizedBox(height: 8),
        Text(widget.description!, style: Theme.of(context).textTheme.bodySmall),
      ],
    ]);
  }
}

class _P3 {
  final double x, y, z;
  const _P3(this.x, this.y, this.z);
  _P3 operator +(_P3 b) => _P3(x + b.x, y + b.y, z + b.z);
  _P3 scale(double n) => _P3(x * n, y * n, z * n);
}

class _CandidatePainter extends CustomPainter {
  final List<StationPoint> stations;
  final bool globe;
  final double yaw, pitch, spin;
  final int selected;
  final double zoom;
  final Offset pan;
  final bool allPairs;
  const _CandidatePainter(this.stations, this.globe, this.yaw,
    this.pitch, this.spin, this.selected, this.zoom, this.pan, this.allPairs);
  Offset _flat(_P3 p, Size size) {
    final x = p.x * math.cos(yaw) + p.z * math.sin(yaw);
    final z = -p.x * math.sin(yaw) + p.z * math.cos(yaw);
    final y = p.y * math.cos(pitch) - z * math.sin(pitch);
    return Offset(size.width / 2 + pan.dx + x * size.width * .21 * zoom,
      size.height / 2 + pan.dy - y * size.height * .23 * zoom);
  }
  Offset _globe(_P3 p, Size size) {
    final radius = math.min(size.width, size.height) * .38 * zoom;
    return Offset(size.width / 2 + pan.dx + p.x * radius,
      size.height / 2 + pan.dy - p.y * radius);
  }
  void _line(Canvas canvas, Offset a, Offset b, Color color,
      {double stroke = 2}) => canvas.drawLine(a, b,
    Paint()..color = color..strokeWidth = stroke);
  void _label(Canvas canvas, String text, Offset p, Color color) {
    final span = TextSpan(text: text, style: TextStyle(color: color, fontSize: 11));
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, p);
  }
  void _disc(Canvas canvas, Offset Function(_P3) project, _P3 centre,
      _P3 east, _P3 north, Color color, double opacity) {
    final path = Path();
    for (var j = 0; j <= 32; j++) {
      final t = j * math.pi / 16;
      final p = project(centre + east.scale(.15 / zoom * math.cos(t)) +
        north.scale(.15 / zoom * math.sin(t)));
      if (j == 0) { path.moveTo(p.dx, p.dy); } else { path.lineTo(p.dx, p.dy); }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: .38 * opacity));
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }
  (StationPoint, double, double, double) _stationEntry(
      StationPoint station, double firstLon) {
    final lat = station.observation.latitude * math.pi / 180;
    final lon = (station.observation.longitude - firstLon) * math.pi / 180 - spin;
    return (station, lat, lon, math.cos(lat) * math.cos(lon));
  }
  List<Offset> _centres(Size size) {
    if (stations.isEmpty) return [];
    final lon = stations.first.observation.longitude;
    final lat = stations.first.observation.latitude;
    return [for (final station in stations)
      _flat(_P3(
        ((station.observation.longitude - lon + 540) % 360 - 180) / 70,
        (station.observation.latitude - lat) / 55, 0), size)];
  }
  int? hitTestStation(Offset local, Size size) {
    final anchors = _centres(size);
    for (var i = 0; i < anchors.length; i++) {
      if ((anchors[i] - local).distance < 19) return i;
    }
    return null;
  }
  @override void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xff0c201a));
    final grid = Paint()..color = const Color(0x3646a276)..strokeWidth = 1;
    for (var i = 0; i < 8; i++) {
      final p = i * size.width / 8;
      canvas.drawLine(Offset(p, 0), Offset(p, size.height), grid);
      canvas.drawLine(Offset(0, i * size.height / 8),
        Offset(size.width, i * size.height / 8), grid);
    }
    if (stations.isEmpty) return;
    final firstLon = stations.first.observation.longitude;
    final firstLat = stations.first.observation.latitude;
    if (!globe) {
      Offset project(_P3 p) => _flat(p, size);
      final coords = [for (final s in stations) _P3(
        ((s.observation.longitude - firstLon + 540) % 360 - 180) / 70,
        (s.observation.latitude - firstLat) / 55, 0)];
      for (var i = 0; i < coords.length - 1; i++) {
        _line(canvas, project(coords[i]), project(coords[i + 1]),
          const Color(0xff718979), stroke: 1);
      }
      final origin = project(const _P3(0, 0, 0));
      for (final axis in [
        (const _P3(.45, 0, 0), 'E', const Color(0xffff9b9b)),
        (const _P3(0, .45, 0), 'N', const Color(0xffa8d3ff)),
        (const _P3(0, 0, .45), 'UP', const Color(0xfff6d995)),
      ]) {
        final end = project(axis.$1);
        _line(canvas, origin, end, axis.$3);
        _label(canvas, axis.$2, end, axis.$3);
      }
      for (var i = 0; i < stations.length; i++) {
        final centre = coords[i];
        final c = i == selected ? const Color(0xfff9e8a1) : const Color(0xff91eeb0);
        _disc(canvas, project, centre, const _P3(1, 0, 0),
          const _P3(0, 1, 0), c, 1);
        for (var j = 0; j < stations[i].observations.length && j < 3; j++) {
          final o = stations[i].observations[j];
          final a = o.azimuthDeg * math.pi / 180;
          final h = o.altitudeDeg * math.pi / 180;
          final target = centre + _P3(math.sin(a) * math.cos(h),
            math.cos(a) * math.cos(h), math.sin(h)).scale(.37 / zoom);
          final colors = [const Color(0xffffdc69),
            const Color(0xffff8f79), const Color(0xffbb9bff)];
          _line(canvas, project(centre), project(target), colors[j], stroke: 2);
        }
        _label(canvas, '${i + 1}', project(centre) + const Offset(4, 8), c);
      }
    } else {
      // Reference-only workspace; NO Earth sphere or inferred surface.
      // Until a measured station solver exists, discs remain on a flat
      // reference projection. Do not present this as a 3D reconstruction.
      final coords = [for (final station in stations) _P3(
        ((station.observation.longitude - firstLon + 540) % 360 - 180) / 70,
        (station.observation.latitude - firstLat) / 55, 0)];
      Offset project(_P3 point) => _flat(point, size);
      if (allPairs) {
        for (var i = 0; i < coords.length; i++) {
          for (var j = i + 1; j < coords.length; j++) {
            _line(canvas, project(coords[i]), project(coords[j]),
              const Color(0x668d75c8), stroke: .7);
          }
        }
      }
      for (var i = 0; i < stations.length; i++) {
        final centre = coords[i];
        final c = i == selected ? const Color(0xffffe79c)
          : const Color(0xff6be0e9);
        _disc(canvas, project, centre, const _P3(1, 0, 0),
          const _P3(0, 1, 0), c, 1);
        for (var j = 0; j < stations[i].observations.length && j < 3; j++) {
          final o = stations[i].observations[j];
          final a = o.azimuthDeg * math.pi / 180;
          final h = o.altitudeDeg * math.pi / 180;
          final target = centre + _P3(math.sin(a) * math.cos(h),
            math.cos(a) * math.cos(h), math.sin(h)).scale(.37 / zoom);
          final colors = [const Color(0xffffdc69),
            const Color(0xffff8f79), const Color(0xffbb9bff)];
          _line(canvas, project(centre), project(target), colors[j], stroke: 2);
        }
        _label(canvas, (i + 1).toString(),
          project(centre) + const Offset(4, 8), c);
      }
    }
  }
  @override bool shouldRepaint(covariant _CandidatePainter old) =>
    old.globe != globe || old.yaw != yaw || old.pitch != pitch ||
    old.spin != spin || old.selected != selected || old.stations != stations ||
    old.zoom != zoom || old.pan != pan || old.allPairs != allPairs;
}
