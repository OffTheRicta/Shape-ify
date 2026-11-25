import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import '../astronomy/sky.dart';
import '../measurement/device_orientation.dart';
import '../measurement/observation.dart';
import '../protocol/session.dart';
import '../protocol/session_repository.dart';
import '../protocol/relay_client.dart';
import 'home.dart';
import 'relay_group_page.dart';
import 'scroll_cues.dart';

class GuidedHome extends StatefulWidget {
  const GuidedHome({super.key});
  @override State<GuidedHome> createState() => _GuidedHomeState();
}

class _GuidedHomeState extends State<GuidedHome> with WidgetsBindingObserver {
  static const demo = bool.fromEnvironment('SHAPEIFY_DEMO');
  Position? position;
  ExperimentSession? session;
  String observer = '';
  RelayIdentity? relay;
  String? error;
  bool loading = true, locating = false, aiming = false, completed = false;
  bool initialGroupOpened = false;
  bool captureInProgress = false;
  int starIndex = 0;
  List<SkyTarget> stars = [];
  DateTime guideTime = DateTime.now().toUtc();
  CameraController? camera;
  StreamSubscription<AccelerometerEvent>? accelerometerSubscription;
  StreamSubscription<MagnetometerEvent>? magnetometerSubscription;
  Timer? refreshTimer, relayTimer;
  Axis3? gravity, magnetic;
  DeviceDirection? direction;

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      session = await SessionRepository.active();
      relay = await RelayStore.read();
      observer = prefs.getString('stationName') ?? 'Station ${const Uuid().v4().substring(0, 6)}';
      if (relay != null) observer = relay!.tag;
      await prefs.setString('stationName', observer);
      if (!mounted) return;
      // The first screen is group setup/status. Location can be obtained there
      // and must never block navigation behind a full-screen spinner.
      setState(() => loading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !initialGroupOpened) {
          initialGroupOpened = true;
          unawaited(_openSessions());
        }
      });
    } catch (e) {
      if (mounted) setState(() { error = 'Could not open local session: $e'; loading = false; });
    }
  }

  Future<void> _locate() async {
    if (locating) return;
    setState(() { locating = true; error = null; });
    try {
      final fix = await (() async {
        if (!await Geolocator.isLocationServiceEnabled()) {
          throw StateError('Turn on phone location services and try again.');
        }
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          throw StateError('Allow location while using the app to pick stars.');
        }
        return Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 25),
            ));
      })().timeout(const Duration(seconds: 35));
      if (!mounted) return;
      position = fix;
      _updateTargets();
      refreshTimer?.cancel();
      refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted && !aiming && !completed) setState(_updateTargets);
      });
      relayTimer?.cancel();
      relayTimer = Timer.periodic(const Duration(seconds: 12), (timer) {
        if (!mounted) { timer.cancel(); return; }
        if (!aiming) _syncRelay();
      });
      _syncRelay();
      setState(() {});
    } on TimeoutException {
      if (mounted) {
        setState(() => error =
            'Location is taking too long. You can create or join a group now, '
            'then retry location when the phone is ready.');
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  void _updateTargets() {
    final fix = position;
    if (fix == null) return;
    final plan = session?.plan;
    if (plan == null) { stars = []; return; }
    guideTime = DateTime.now().toUtc();
    stars = [for (final name in plan.stars)
      SkyGuide.horizontal(
        SkyGuide.brightStars.firstWhere((star) => star.name == name),
        fix.latitude, fix.longitude, guideTime)];
  }

  Future<void> _syncRelay() async {
    final current = relay;
    if (current == null) return;
    try {
      final client = RelayClient.forIdentity(current);
      var status = await client.status(current);
      final updated = await RelaySync.apply(current, status);
      await RelaySync.pushPending(current, status, updated);
      status = await client.status(current);
      if (!mounted || aiming) return;
      session = await RelaySync.apply(current, status);
      setState(_updateTargets);
    } catch (_) { // Retain the local readings; retry when the relay is reachable.
    }
  }

  bool get plannedWindowOpen {
    final plan = session?.plan;
    if (plan == null) { return false; }
    final now = DateTime.now().toUtc();
    if (plan.distributed) {
      return plan.windows.any((window) =>
        !now.isBefore(window.startUtc) && !now.isAfter(window.endUtc));
    }
    return now.difference(plan.targetUtc).inMinutes.abs() <= 45;
  }

  bool get includedInPlan => session?.plan != null &&
      !session!.plan!.excludedStations.contains(observer);

  bool get darkNow => demo || position != null &&
      SkyGuide.sunAltitude(position!.latitude, position!.longitude,
          DateTime.now().toUtc()) < -6;

  bool get sharedStarsVisibleNow {
    final fix = position;
    if (fix == null || stars.length != 3) return false;
    final now = DateTime.now().toUtc();
    return stars.every((target) {
      final altitude = SkyGuide.horizontal(target.star,
          fix.latitude, fix.longitude, now).altitudeDeg;
      return altitude >= 12 && altitude <= 85;
    });
  }

  Future<void> _start() async {
    if (!includedInPlan || !plannedWindowOpen ||
        !darkNow || !sharedStarsVisibleNow) { return; }
    final recorded = session?.observations.where((o) => o.observer == observer)
        .map((o) => o.starId).toSet() ?? <String>{};
    final next = stars.indexWhere((target) => !recorded.contains(target.star.name));
    if (next < 0) {
      if (mounted) setState(() => completed = true);
      return;
    }
    setState(() {
      loading = true;
      error = null;
      starIndex = next;
      completed = false;
    });
    if (demo) {
      await _demoCapture();
      return;
    }
    try {
      final cameras = await availableCameras();
      final backs = cameras.where((c) => c.lensDirection == CameraLensDirection.back);
      if (backs.isEmpty) throw StateError('No rear camera found');
      final controller = CameraController(backs.first, ResolutionPreset.medium,
          enableAudio: false);
      await controller.initialize();
      if (!mounted) { await controller.dispose(); return; }
      camera = controller;
      accelerometerSubscription = accelerometerEventStream().listen((event) {
        gravity = Axis3(event.x, event.y, event.z);
        _updateDirection();
      });
      magnetometerSubscription = magnetometerEventStream().listen((event) {
        magnetic = Axis3(event.x, event.y, event.z);
        _updateDirection();
      });
      setState(() { aiming = true; loading = false; });
    } catch (e) {
      if (mounted) setState(() { loading = false; error = 'Camera could not start: $e'; });
    }
  }

  Future<void> _demoCapture() async {
    final fix = position;
    if (fix == null || session == null) return;
    setState(() { aiming = true; loading = false; });
    for (var i = starIndex; i < stars.length; i++) {
      if (!mounted) return;
      setState(() => starIndex = i);
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted || !aiming) return;
      final now = DateTime.now().toUtc();
      final target = SkyGuide.horizontal(stars[i].star, fix.latitude,
        fix.longitude, now);
      final coarse = relay == null ? null : CoarseLocation.from(fix.latitude, fix.longitude);
      final reading = Observation(id: const Uuid().v4(), observer: observer,
        starId: stars[i].star.name, method: 'SIMULATED demo reading; no photo or sensor input',
        notes: 'Simulated pointing. Not a naked-eye observation.',
        observedUtc: now, latitude: coarse?['latitude'] ?? fix.latitude,
        longitude: coarse?['longitude'] ?? fix.longitude,
        elevationM: 0, instrumentHeightM: 1.5,
        altitudeDeg: target.altitudeDeg, azimuthDeg: target.azimuthDeg,
        angularUncertaintyDeg: 15, positionUncertaintyM: 2000,
        nakedEyeConfirmed: false, simulated: true, azimuthReference: 'true');
      session = session!.withObservation(reading);
      await SessionRepository.save(session!);
    }
    if (relay != null) await _syncRelay();
    if (mounted) setState(() { aiming = false; completed = true; });
  }

  void _updateDirection() {
    final reading = DeviceOrientation.rearCamera(gravity, magnetic);
    if (reading != null && mounted && aiming) setState(() => direction = reading);
  }

  Future<void> _stopCamera() async {
    await accelerometerSubscription?.cancel();
    await magnetometerSubscription?.cancel();
    accelerometerSubscription = null;
    magnetometerSubscription = null;
    final old = camera;
    camera = null;
    if (old != null) await old.dispose();
    direction = null;
    gravity = null;
    magnetic = null;
  }

  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive && camera != null) {
      _stopCamera();
      if (mounted) setState(() { aiming = false; error = 'Camera paused. Tap Start again.'; });
    }
  }

  Future<void> _capture() async {
    if (captureInProgress) return;
    setState(() => captureInProgress = true);
    try {
      await _recordCurrentStar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save this reading: $e')));
      }
    } finally {
      if (mounted) setState(() => captureInProgress = false);
    }
  }

  Future<void> _recordCurrentStar() async {
    final reading = direction;
    final fix = position;
    if (reading == null || fix == null) return;
    final target = SkyGuide.horizontal(stars[starIndex].star,
        fix.latitude, fix.longitude, DateTime.now().toUtc());
    if (!includedInPlan) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Your station is excluded from this shared sky plan. Ask the organizer for a later plan.')));
      }
      return;
    }
    if (!plannedWindowOpen) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Outside the shared observation time. Ask for a new plan.')));
      }
      return;
    }
    if (target.altitudeDeg < 12 || target.altitudeDeg > 85) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This shared star is not at a usable height here now. Try later.')));
      }
      return;
    }
    if (reading.altitudeDeg <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Point the rear camera above the horizon.')));
      return;
    }
    final azGap = SkyGuide.angularDelta(target.azimuthDeg,
        reading.magneticAzimuthDeg).abs();
    final altGap = (target.altitudeDeg - reading.altitudeDeg).abs();
    if (azGap > 35 || altGap > 35) {
      final proceed = await showDialog<bool>(context: context, builder: (context) =>
          AlertDialog(title: const Text('Guide and phone disagree'),
              content: const Text('Check the star name and nearby magnetic interference. Record only if you can see the named star with your own eyes at the center of the camera frame.'),
              actions: [TextButton(onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep aiming')),
                FilledButton(onPressed: () => Navigator.pop(context, true),
                    child: const Text('I can see it'))]));
      if (proceed != true || !mounted) return;
    }
    final observed = DateTime.now().toUtc();
    // The raw magnetic heading is intentionally retained. A catalog-predicted
    // position must never be substituted for this observation.
    final coarse = relay == null ? null : CoarseLocation.from(fix.latitude, fix.longitude);
    final observation = Observation(
        id: const Uuid().v4(), observer: observer,
        starId: target.star.name, method: 'Rear camera orientation: gravity and magnetic field; uncalibrated magnetic north',
        notes: 'Guide offset: azimuth ${azGap.toStringAsFixed(0)}°, elevation ${altGap.toStringAsFixed(0)}°. Human confirmed naked-eye sighting.',
        observedUtc: observed, latitude: coarse?['latitude'] ?? fix.latitude,
        longitude: coarse?['longitude'] ?? fix.longitude,
        elevationM: relay != null ? 0 : (fix.altitude.isFinite ? fix.altitude.clamp(-12000.0, 100000.0).toDouble() : 0.0),
        instrumentHeightM: 1.5,
        altitudeDeg: reading.altitudeDeg,
        azimuthDeg: reading.magneticAzimuthDeg,
        angularUncertaintyDeg: 15,
        positionUncertaintyM: relay != null ? math.max(2000.0, fix.accuracy.isFinite ? fix.accuracy : 2000.0) :
          math.max(5.0, fix.accuracy.isFinite ? fix.accuracy : 20.0),
        nakedEyeConfirmed: true,
        azimuthReference: 'magnetic');
    final problems = observation.validate();
    if (problems.isNotEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problems.join('; '))));
      return;
    }
    final updated = session!.withObservation(observation);
    await SessionRepository.save(updated);
    session = updated;
    if (relay != null) await _syncRelay();
    if (!mounted) return;
    final measured = session!.observations.where((o) => o.observer == observer)
        .map((o) => o.starId).toSet();
    final next = stars.indexWhere((star) => !measured.contains(star.star.name));
    if (next >= 0) {
      setState(() => starIndex = next);
    } else {
      await _stopCamera();
      if (mounted) setState(() { aiming = false; completed = true; });
    }
  }

  Future<void> _openRecords() async {
    if (aiming) {
      await _stopCamera();
      if (!mounted) return;
      setState(() => aiming = false);
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) =>
        HomePage(latitude: position?.latitude, longitude: position?.longitude,
          station: observer)));
    final current = await SessionRepository.active();
    if (mounted) setState(() { session = current; _updateTargets(); });
  }

  Future<void> _openWebResults() async {
    final code = relay?.code;
    if (code == null) return;
    final page = Uri.https('roundhound.info', '/shapeify/',
      {'group': code, 'view': 'flat'});
    try {
      if (await launchUrl(page, mode: LaunchMode.externalApplication)) return;
    } catch (_) { // Report a readable address below.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open web results. Visit $page')));
    }
  }

  Future<void> _openSessions() async {
    if (aiming) {
      await _stopCamera();
      if (!mounted) return;
      setState(() => aiming = false);
    }
    if (!mounted) return;
    final openCamera = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => RelayGroupPage(
          latitude: position?.latitude, longitude: position?.longitude)));
    final current = await SessionRepository.active();
    final newRelay = await RelayStore.read();
    if (mounted) {
      final station = newRelay?.tag ?? observer;
      final seen = current.observations.where((reading) =>
        reading.observer == station).map((reading) => reading.starId).toSet();
      final hasAll = current.plan?.stars.every(seen.contains) ?? false;
      setState(() { session = current; relay = newRelay;
        observer = station;
        completed = hasAll;
        _updateTargets(); });
    }
    if (openCamera == false && mounted) {
      await _openRecords();
    } else if (openCamera == true && mounted) {
      await _locate();
      if (!mounted || position == null) return;
      if (includedInPlan && plannedWindowOpen && darkNow && sharedStarsVisibleNow) {
        await _start();
      } else {
        setState(() => error = 'Camera guide opens at the shared time, after dark, when all three stars are visible.');
      }
    } else if (mounted && position == null) {
      unawaited(_locate());
    }
  }

  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    refreshTimer?.cancel();
    relayTimer?.cancel();
    accelerometerSubscription?.cancel();
    magnetometerSubscription?.cancel();
    camera?.dispose();
    super.dispose();
  }

  Widget _captureView(BuildContext context, SkyTarget? target,
      double? azTurn, double? upTurn) {
    final reading = direction;
    final guide = <String>[
      if (azTurn != null && azTurn.abs() >= 18)
        'Turn ${azTurn > 0 ? 'right' : 'left'} ${azTurn.abs().round()}°',
      if (upTurn != null && upTurn.abs() >= 18)
        'Aim ${upTurn > 0 ? 'higher' : 'lower'} ${upTurn.abs().round()}°',
    ];
    final theme = Theme.of(context);
    final controller = camera!;
    const edge = Color(0xFFFF292F);
    Widget cue(Alignment alignment, bool vertical) => Align(
      alignment: alignment,
      child: FractionallySizedBox(
        widthFactor: vertical ? null : .72,
        heightFactor: vertical ? .72 : null,
        child: Container(
          width: vertical ? 4 : null,
          height: vertical ? null : 4,
          decoration: BoxDecoration(
            color: edge,
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [BoxShadow(color: edge, blurRadius: 14, spreadRadius: 2)],
          ),
        ),
      ),
    );

    return ColoredBox(
      color: const Color(0xFF040711),
      child: Column(children: [
        Row(children: [
          IconButton(
            tooltip: 'Exit star capture',
            icon: const Icon(Icons.arrow_back),
            onPressed: captureInProgress ? null : () async {
              await _stopCamera();
              if (mounted) setState(() => aiming = false);
            },
          ),
          Expanded(child: Column(children: [
            Text('Observe Star ${starIndex + 1} of ${stars.length}'),
            Text(target?.star.name ?? stars[starIndex].star.name,
              style: theme.textTheme.titleLarge),
          ])),
          const SizedBox(width: 48),
        ]),
        const SizedBox(height: 8),
        Expanded(child: ClipRect(child: Stack(fit: StackFit.expand, children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.previewSize!.height,
              height: controller.value.previewSize!.width,
              child: CameraPreview(controller),
            ),
          ),
          IgnorePointer(child: Stack(fit: StackFit.expand, children: [
            if (azTurn != null && azTurn.abs() >= 18)
              cue(azTurn > 0 ? Alignment.centerRight : Alignment.centerLeft, true),
            if (upTurn != null && upTurn.abs() >= 18)
              cue(upTurn > 0 ? Alignment.topCenter : Alignment.bottomCenter, false),
            const Center(child: CustomPaint(
              size: Size.square(82), painter: _StarReticle())),
          ])),
        ]))),
        Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Column(children: [
            Text(reading == null ? 'Waiting for motion and compass sensors…'
                : guide.isEmpty ? 'Centre the star and hold steady' : guide.join(' · '),
              textAlign: TextAlign.center,
              style: TextStyle(color: reading != null && guide.isEmpty
                ? const Color(0xFFB2EE77) : Colors.white)),
            const SizedBox(height: 4),
            Text('Confirm the star by eye. The compass guide is approximate.',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(child: Text(
                  'Elevation\n${reading == null ? '—' : '${reading.altitudeDeg.toStringAsFixed(1)}°'}',
                  textAlign: TextAlign.center)),
                Expanded(child: Text(
                  'Azimuth (magnetic)\n${reading == null ? '—' : '${reading.magneticAzimuthDeg.toStringAsFixed(1)}°'}',
                  textAlign: TextAlign.center)),
              ]))),
            const SizedBox(height: 4),
            IconButton(
              tooltip: captureInProgress ? 'Recording reading' : 'Record centred star',
              onPressed: reading == null || captureInProgress ? null : _capture,
              iconSize: 48,
              color: Colors.white,
              icon: captureInProgress
                ? const SizedBox.square(dimension: 32, child: CircularProgressIndicator())
                : const Icon(Icons.radio_button_checked),
            ),
          ]),
        ),
      ]),
    );
  }

  @override Widget build(BuildContext context) {
    final p = position;
    final target = aiming && p != null && starIndex < stars.length
        ? SkyGuide.horizontal(stars[starIndex].star, p.latitude, p.longitude,
            DateTime.now().toUtc()) : null;
    final azTurn = target != null && direction != null
        ? SkyGuide.angularDelta(target.azimuthDeg,
            direction!.magneticAzimuthDeg) : null;
    final upTurn = target != null && direction != null
        ? target.altitudeDeg - direction!.altitudeDeg : null;
    final liveCapture = aiming && camera?.value.isInitialized == true;
    return Scaffold(appBar: liveCapture ? null : AppBar(title: const Text('Shape-ify'),
        actions: [IconButton(tooltip: 'Group sessions', icon: const Icon(Icons.group_outlined),
          onPressed: _openSessions),
          IconButton(tooltip: 'Results & sharing',
            onPressed: session == null ? null : _openRecords,
            icon: const Icon(Icons.insights_outlined))]),
      body: SafeArea(child: loading
          ? const Center(child: CircularProgressIndicator())
          : aiming && camera != null && camera!.value.isInitialized
              ? _captureView(context, target, azTurn, upTurn)
              : aiming && demo
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 18),
                      Text('Measuring star ${starIndex + 1} of ${stars.length}: '
                        '${stars[starIndex].star.name}'),
                      const Text('Moving to the next star…'),
                    ]))
                  : ActionFirstScroll(
                      actionId: session?.plan == null ? 'join-group' : p == null
                        ? 'locate' :
                        completed ? 'view-results' :
                          includedInPlan && plannedWindowOpen && darkNow &&
                          sharedStarsVisibleNow ? 'start-aiming' : null,
                      builder: (scrollController) => ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(20), children: [
                  Text(session?.plan == null
                      ? 'Join a group to choose stars together'
                      : 'The group will use these same 3 stars',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  if (error != null) Card(color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(padding: const EdgeInsets.all(12), child: Text(error!))),
                  if (session?.plan == null) FilledButton.icon(
                    onPressed: _openSessions,
                    icon: const Icon(Icons.group_outlined),
                    label: const Text('Create or join a group'))
                  else if (p == null) FilledButton(
                    onPressed: locating ? null : _locate,
                    child: const Text('Use my location'))
                  else if (completed) FilledButton.icon(
                    onPressed: _openRecords,
                    icon: const Icon(Icons.insights_outlined),
                    label: const Text('View results'))
                  else FilledButton.icon(
                    onPressed: includedInPlan && plannedWindowOpen &&
                      darkNow && sharedStarsVisibleNow ? _start : null,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Start star observations')),
                  if (completed && relay != null && session?.id == relay!.code)
                    OutlinedButton.icon(
                      onPressed: _openWebResults,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('View results on website')),
                  const SizedBox(height: 12),
                  if (p == null) ...[
                    if (locating) const LinearProgressIndicator(),
                    Text(locating ? 'Finding your location. Group setup is available now.'
                      : 'Location is needed before choosing stars.'),
                    TextButton(onPressed: locating ? null : _locate,
                      child: const Text('Retry location')),
                    const SizedBox(height: 8),
                  ],
                  if (p != null) ...[
                    Text('Location accuracy: about ${p.accuracy.round()} m · Station $observer'),
                    if (session?.plan == null)
                      const Text('Share an approximate location with the organizer, then import the group sky plan.'),
                    if (session?.plan != null && !includedInPlan)
                      const Text('Your station is outside this plan because it has no dark sky at the shared time. Your location report is still saved; ask the organizer for a later group plan.'),
                    const SizedBox(height: 8),
                    if (session?.plan != null && !plannedWindowOpen && !session!.plan!.distributed)
                      Text('Shared observing time: ${session!.plan!.targetUtc.toLocal()}. Capture opens within 45 minutes of that time.'),
                    if (session?.plan?.distributed == true && !plannedWindowOpen)
                      Text('Your scheduled sky window: ${session!.plan!.windows.first.startUtc.toLocal()}–${session!.plan!.windows.first.endUtc.toLocal()}. You remain in this group.'),
                    if (session?.plan != null && !darkNow)
                      const Text('Measurements open after dark at your location.'),
                    if (session?.plan != null && darkNow && !sharedStarsVisibleNow)
                      const Text('One or more group stars are outside the usable sky here now. Try at the planned time or ask for a revised plan.'),
                    if (session?.plan != null &&
                        stars.any((target) => target.altitudeDeg < 12 || target.altitudeDeg > 85))
                      const Text('At the planned time, a shared star is outside the usable sky from this location.'),
                    for (var i = 0; i < stars.length; i++)
                      Card(child: ListTile(leading: CircleAvatar(child: Text('${i + 1}')),
                          title: Text(stars[i].star.name),
                          subtitle: Text(stars[i].altitudeDeg < 0
                              ? 'Below the horizon here at the planned time'
                              : 'Approx. ${stars[i].altitudeDeg.round()}° high · ${stars[i].azimuthDeg.round()}° from true north'))),
                    const SizedBox(height: 10),
                    if (completed) const Card(child: Padding(padding: EdgeInsets.all(14),
                        child: Text('Three stars recorded. The group will publish the results to every phone.'))),
                    TextButton(onPressed: locating ? null : _locate,
                      child: Text(locating ? 'Refreshing location…' : 'Refresh location & stars')),
                  ],
                  const SizedBox(height: 12),
                  const Text('No photo or video is saved. Location, time and sensor direction stay on this phone until you choose to share. Confirm each star with your own eyes.'),
                ]))));
  }
}

class _StarReticle extends CustomPainter {
  const _StarReticle();

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.width * .36;
    final stroke = Paint()
      ..color = const Color(0xFFFF464B)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(centre, radius, stroke);
    for (final axis in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
      canvas.drawLine(centre + axis * (radius - 5),
        centre + axis * (radius + 8), stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _StarReticle oldDelegate) => false;
}
