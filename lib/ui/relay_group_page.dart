import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../astronomy/sky.dart';
import '../protocol/relay_client.dart';
import 'scroll_cues.dart';

class RelayGroupPage extends StatefulWidget {
  final double? latitude, longitude;
  const RelayGroupPage({super.key, this.latitude, this.longitude});
  @override State<RelayGroupPage> createState() => _RelayGroupPageState();
}

class _RelayGroupPageState extends State<RelayGroupPage> {
  final url = TextEditingController(text: const String.fromEnvironment(
    'SHAPEIFY_RELAY_URL', defaultValue: 'https://relay.roundhound.info'));
  final code = TextEditingController();
  final tag = TextEditingController();
  RelayIdentity? identity;
  Map<String, dynamic>? state;
  Timer? polling;
  String? error;
  bool busy = false;
  bool finding = false;
  bool refreshing = false;
  double? currentLatitude, currentLongitude;
  DistributedSkyPlan? search;
  Object? searchRevision;
  DateTime? searchStartedUtc;
  Map<String, bool> blockedCanSeeOtherStars = {};
  static const demo = bool.fromEnvironment('SHAPEIFY_DEMO');
  String _removedNotice(Object error) =>
    error.toString().contains('No geometrically shared star set')
      ? 'No suitable shared three-star set can be seen from your location '
        'and the group majority. Find a group with observers nearer to you.'
      : error.toString().contains('No window for the shared stars')
        ? 'There was no observing window for this group’s shared stars '
          'within 48 hours. Try another group or a later start time.'
      : 'You are no longer in this group. You can join another group '
        'or create your own.';

  @override void initState() {
    super.initState();
    currentLatitude = widget.latitude;
    currentLongitude = widget.longitude;
    code.addListener(() { if (mounted) setState(() {}); });
    _restore();
    polling = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }
  Future<void> _restore() async {
    try {
      final saved = await RelayStore.read();
      if (saved != null && mounted) {
        setState(() { identity = saved; url.text = saved.url; });
        if (currentLatitude == null || currentLongitude == null) {
          await _updateReportedLocation();
        }
        await _refresh();
      }
    } catch (e) { _showError(e); }
  }
  void _showError(Object e) {
    if (mounted) setState(() => error = e.toString().replaceFirst('Bad state: ', ''));
  }
  Future<void> _perform(Future<Map<String, dynamic>> Function() task) async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      final result = await task();
      if (!mounted) return;
      final current = identity;
      if (current != null) await RelaySync.apply(current, result);
      if (mounted) setState(() { state = result; search = null;
        blockedCanSeeOtherStars = {}; });
    } catch (e) {
      if (e.toString().contains('HTTP 410')) {
        await RelayStore.clear();
        if (mounted) setState(() { identity = null; state = null; search = null;
          error = _removedNotice(e); });
      } else { _showError(e); }
    }
    finally { if (mounted) { setState(() => busy = false); } }
  }
  Future<void> _refresh() async {
    final current = identity;
    if (current == null || busy || finding || refreshing) return;
    refreshing = true;
    try {
      final client = RelayClient.forIdentity(current);
      var result = await client.status(current);
      final self = (result['members'] as List).cast<Map>().firstWhere(
        (m) => m['id'] == current.memberId);
      if (result['phase'] == 'lobby' && self['hasSite'] != true &&
          currentLatitude != null && currentLongitude != null) {
        result = await client.site(current, currentLatitude!, currentLongitude!);
      }
      final local = await RelaySync.apply(current, result);
      await RelaySync.pushPending(current, result, local);
      result = await client.status(current);
      if (mounted) setState(() {
        state = result;
        if (currentLatitude != null && currentLongitude != null) error = null;
      });
    } catch (e) {
      if (e.toString().contains('HTTP 410')) {
        await RelayStore.clear();
        if (mounted) setState(() { identity = null; state = null; search = null;
          error = _removedNotice(e); });
      } else { _showError(e); }
    } finally { refreshing = false; }
  }
  Future<void> _enter({required bool master}) async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      final joined = await RelayClient.enter(url.text, tag.text,
        code: master ? null : code.text.trim());
      if (!mounted) return;
      setState(() => identity = joined);
      if (currentLatitude != null && currentLongitude != null) {
        await RelayClient.forIdentity(joined).site(joined,
          currentLatitude!, currentLongitude!);
      }
    } catch (e) { _showError(e); }
    finally {
      if (mounted) setState(() => busy = false);
      if (identity != null) {
        if (currentLatitude == null || currentLongitude == null) {
          await _updateReportedLocation();
        }
        await _refresh();
      }
    }
  }
  Future<void> _updateReportedLocation() async {
    final current = identity;
    if (current == null || busy) return;
    setState(() { busy = true; error = null; });
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
          throw StateError('Allow location while using the app to share your station.');
        }
        return Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 25)));
      })().timeout(const Duration(seconds: 35));
      final result = await RelayClient.forIdentity(current).site(
        current, fix.latitude, fix.longitude);
      await RelaySync.apply(current, result);
      if (mounted) {
        setState(() { currentLatitude = fix.latitude;
          currentLongitude = fix.longitude; state = result; search = null; });
      }
    } on TimeoutException {
      _showError(StateError('Location timed out. Try again when the phone has a clear GPS fix.'));
    } catch (e) { _showError(e); }
    finally { if (mounted) { setState(() => busy = false); } }
  }
  Future<void> _find() async {
    if (finding || state == null) return;
    final sites = (state!['sites'] as List).cast<Map>();
    final revision = state!['revision'];
    setState(() { finding = true; error = null; });
    try {
      final request = GroupSkyRequest([for (final s in sites)
        SkyLocation((s['latitude'] as num).toDouble(),
          (s['longitude'] as num).toDouble())], DateTime.now().toUtc(), demo: demo);
      final full = await compute(SkyGuide.planGroup, request);
      if (!mounted) return;
      if (full == null) {
        final compatible = await compute(SkyGuide.geometricallyCompatible,
          request);
        if (!mounted) return;
        if (!compatible.first) {
          _showError(StateError('Your location cannot share a usable '
            'three-star set with this group majority. Start a group with '
            'observers nearer to you.'));
          return;
        }
        final impossible = <int>[
          for (var i = 1; i < sites.length; i++)
            if (!compatible[i]) i,
        ];
        final current = identity!;
        final client = RelayClient.forIdentity(current);
        final latest = await client.status(current);
        if (latest['revision'] != revision) {
          if (mounted) setState(() { state = latest; search = null;
            error = 'Group locations changed. Search again.'; });
          return;
        }
        if (impossible.isNotEmpty) {
          for (final index in impossible) {
            await client.remove(current, sites[index]['memberId'] as String,
              reason: 'no-shared-sky');
          }
          final updated = await client.status(current);
          await RelaySync.apply(current, updated);
          if (mounted) setState(() {
            state = updated; search = null; blockedCanSeeOtherStars = {};
            error = '${impossible.map((i) => sites[i]['station']).join(', ')} '
              'cannot ever share a usable three-star set with this group '
              'majority and were removed. Their phones will explain how '
              'to find a nearer group when they next connect. Search again '
              'with the remaining members.';
          });
          return;
        }
      }
      final found = full ?? await compute(SkyGuide.planWithBlocked, request);
      final current = identity!;
      final latest = await RelayClient.forIdentity(current).status(current);
      if (latest['revision'] != revision) {
        if (mounted) setState(() { state = latest; search = null;
          error = 'Group locations changed. Search again.'; });
        return;
      }
      final otherStars = <String, bool>{};
      if (found != null) {
        for (var i = 0; i < sites.length; i++) {
          if (found.windows[i].isEmpty) {
            otherStars[sites[i]['memberId'] as String] =
              SkyGuide.hasIndependentThreeSoon(request.sites[i],
                request.startUtc, demo: demo);
          }
        }
      }
      if (mounted) {
        if (found == null) {
          _showError(StateError('No shared catalogue stars give at least 60% '
            'of this group (minimum three people) a window in the next '
            '30 minutes. Try again when more observers have dark skies.'));
        } else {
          setState(() { search = found; searchRevision = revision;
            searchStartedUtc = request.startUtc;
            blockedCanSeeOtherStars = otherStars; });
        }
      }
    } catch (e) { _showError(e); }
    finally { if (mounted) setState(() => finding = false); }
  }
  Future<void> _sendPlan(DistributedSkyPlan chosen) async {
    if (!chosen.openingReady ||
        chosen.windows.any((windows) => windows.isEmpty)) {
      _showError(StateError('A Go plan requires at least 60% within '
        '30 minutes and a later window for every remaining participant. '
        'Recheck the skies or remove those without a viable window.'));
      return;
    }
    final current = identity!;
    final sites = (state!['sites'] as List).cast<Map>();
    final now = DateTime.now().toUtc();
    if (searchStartedUtc == null ||
        now.difference(searchStartedUtc!) > const Duration(minutes: 5)) {
      setState(() { search = null; error = 'The sky search is over five '
        'minutes old. Recheck the stars before sending the plan.'; });
      return;
    }
    try {
      final latest = await RelayClient.forIdentity(current).status(current);
      if (latest['revision'] != searchRevision) {
        if (mounted) setState(() { state = latest; search = null;
          error = 'Group locations changed. Search again.'; });
        return;
      }
    } catch (e) { _showError(e); return; }
    final windows = <String, List<Map<String, String>>>{};
    final reserved = <String>[];
    for (var i = 0; i < sites.length; i++) {
      final memberId = sites[i]['memberId'] as String;
      windows[memberId] = chosen.windows[i].map((w) => w.toJson()).toList();
      if (!chosen.windows[i].any((w) =>
          !now.isBefore(w.startUtc) && !now.isAfter(w.endUtc))) {
        reserved.add(memberId);
      }
    }
    await _perform(() => RelayClient.forIdentity(current).action(current, 'plan', {
      'distributed': true,
      'stars': chosen.stars.map((star) => star.name).toList(),
      'targetUtc': now.add(const Duration(minutes: 1)).toIso8601String(),
      'windows': windows, 'reservedMemberIds': reserved,
    }));
  }
  Future<void> _removeMember(Map site, {bool noWindow = false}) async {
    final memberId = site['memberId'] as String;
    final station = site['station'] as String;
    final approved = await showDialog<bool>(context: context, builder: (context) =>
      AlertDialog(title: Text('Remove $station?'),
        content: Text(noWindow
          ? '$station has no window for these shared stars within 48 hours. '
            'Removing them ends their participation in this group.'
          : 'Removing $station ends their participation in this group. '
            'The remaining members stay together.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep participant')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove')),
        ]));
    if (approved != true || !mounted || identity == null) return;
    final current = identity!;
    await _perform(() => RelayClient.forIdentity(current).remove(current,
      memberId, reason: noWindow ? 'no-window' : 'manual'));
  }
  Future<void> _leaveGroup(RelayIdentity current, String phase,
      bool ownReadings) async {
    if (!current.master &&
        ['lobby', 'planning', 'observing'].contains(phase) && !ownReadings) {
      if (busy) return;
      setState(() => busy = true);
      try {
        await RelayClient.forIdentity(current).remove(current,
          current.memberId);
      } catch (e) { _showError(e); return; }
      finally { if (mounted) setState(() => busy = false); }
    }
    await RelayStore.clear();
    if (mounted) setState(() { identity = null; state = null; search = null;
      blockedCanSeeOtherStars = {}; });
  }
  Future<void> _openWebResults(String groupCode) async {
    final page = Uri.https('roundhound.info', '/shapeify/',
      {'group': groupCode, 'view': 'flat'});
    try {
      if (await launchUrl(page, mode: LaunchMode.externalApplication)) return;
    } catch (_) { // The website link remains available for a later retry.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open web results. Visit $page')));
    }
  }
  @override void dispose() {
    polling?.cancel(); url.dispose(); code.dispose(); tag.dispose(); super.dispose();
  }
  @override Widget build(BuildContext context) {
    final current = identity;
    final data = state;
    final members = (data?['members'] as List? ?? []).cast<Map>();
    final phase = data?['phase'] as String? ?? 'connecting';
    final received = (data?['pendingObservations'] as List? ?? []).length;
    final canReplan = phase == 'observing' && received == 0 &&
      members.every((m) => (m['received'] as List).isEmpty);
    final plan = data?['plan'] as Map?;
    final allReady = members.length >= 3 && members.every((m) => m['hasSite'] == true);
    final searchResult = search;

    final sitesData = (data?['sites'] as List? ?? []).cast<Map>();
    final blockedSites = searchResult == null ? <Map>[] : <Map>[
      for (var i = 0; i < sitesData.length; i++)
        if (i < searchResult.windows.length && searchResult.windows[i].isEmpty)
          sitesData[i],
    ];
    final ownSite = data?['self'] is Map ? (data!['self'] as Map)['site'] as Map? : null;
    final now = DateTime.now().toUtc();
    final ownWindows = (plan?['window'] as List? ?? const []).cast<Map>();
    final duringWindow = plan != null && (plan['distributed'] == true
      ? ownWindows.any((w) => !now.isBefore(DateTime.parse(w['startUtc'] as String)) &&
        !now.isAfter(DateTime.parse(w['endUtc'] as String)))
      : now.difference(DateTime.parse(plan['targetUtc'] as String)).inMinutes.abs() <= 45);
    final siteAvailable = currentLatitude != null && currentLongitude != null;
    final darkEnough = demo || siteAvailable &&
      SkyGuide.sunAltitude(currentLatitude!, currentLongitude!, now) < -6;
    final starsReady = siteAvailable && plan != null && (plan['stars'] as List)
      .every((name) {
        final guideStar = SkyGuide.brightStars.where((star) => star.name == name);
        if (guideStar.isEmpty) return false;
        final altitude = SkyGuide.horizontal(guideStar.first, currentLatitude!,
          currentLongitude!, now).altitudeDeg;
        return altitude >= 12 && altitude <= 85;
      });
    final ownMembers = members.where((member) => member['id'] == current?.memberId);
    final allThreeReceived = ownMembers.isNotEmpty &&
      (ownMembers.first['received'] as List).length == 3;
    final cameraReady = phase == 'observing' && duringWindow && darkEnough &&
      starsReady && !allThreeReceived &&
      !(plan['excludedStations'] as List).contains(current?.tag);
    final pendingAck = current != null && current.master && phase == 'observing'
      ? members.where((m) => m['excluded'] != true &&
          (m['received'] as List).length == 3 && m['acknowledged'] != true).toList()
      : <Map>[];
    final publishReady = current != null && current.master &&
      phase == 'observing' && plan?['distributed'] != true &&
      members.every((m) => m['excluded'] == true ||
        ((m['received'] as List).length == 3 && m['acknowledged'] == true));
    final actionId = current == null ? 'create-group' :
      cameraReady ? 'camera' :
      phase == 'lobby' && current.master ? 'begin' :
      (phase == 'planning' || canReplan) && current.master ?
        (searchResult == null ? 'find' :
          blockedSites.isNotEmpty || !searchResult.openingReady ?
            'resolve-plan' : 'send-plan') :
      pendingAck.isNotEmpty ? 'ack-${pendingAck.first['id']}' :
      publishReady ? 'publish' :
      data?['published'] != null ? 'results' : null;
    return Scaffold(appBar: AppBar(title: const Text('Group')),
      body: SafeArea(child: ActionFirstScroll(actionId: actionId,
        builder: (scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 36), children: [
        if (current == null) ...[
          const Text('Create a group or enter the five-letter code from your organizer.'),
          if (!demo) const Text('Real observations are retained for the public Shape-ify collection. Locations are used for calculations; the public display deliberately shifts station positions.'),
          TextField(controller: tag, maxLength: 20, decoration:
            const InputDecoration(labelText: 'Your tag (optional)')),
          TextField(controller: code, maxLength: 5, textCapitalization:
            TextCapitalization.characters, decoration:
            const InputDecoration(labelText: 'Five-letter group code')),
          Wrap(spacing: 10, runSpacing: 8, children: [
            FilledButton(onPressed: busy ? null : () => _enter(master: true),
              child: const Text('Create group')),
            OutlinedButton(onPressed: busy || code.text.trim().length != 5
              ? null : () => _enter(master: false), child: const Text('Join group')),
          ]),
          ExpansionTile(title: const Text('Connection settings'), children: [
          TextField(controller: url, decoration: const InputDecoration(
            labelText: 'Relay address', hintText: 'https://relay.example.org'),
            keyboardType: TextInputType.url),
          ]),
        ] else ...[
          SelectableText('Group ${current.code}', style: Theme.of(context)
            .textTheme.headlineMedium),
          Text('Your tag: ${current.tag} • ${current.master ? 'Organizer' : 'Participant'}'),
          Text('Status: $phase'),
          const SizedBox(height: 8),
          if (cameraReady) FilledButton.icon(
            onPressed: busy ? null : () => Navigator.pop(context, true),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Start star observations'))
          else if (phase == 'lobby' && current.master) FilledButton(
            onPressed: busy || !allReady ? null :
              () => _perform(() => RelayClient.forIdentity(current).action(current, 'begin')),
            child: const Text('Begin and find shared stars'))
          else if ((phase == 'planning' || canReplan) && current.master) ...[
            if (searchResult == null) FilledButton(
              onPressed: finding ? null : _find,
              child: Text(finding ? 'Checking each participant’s sky…' :
                'Find stars and individual windows'))
            else if (blockedSites.isNotEmpty || !searchResult.openingReady) ...[
              if (!searchResult.openingReady) Text('Not ready to go: fewer '
                'than 60% of this group (minimum three) can use these stars '
                'in the next 30 minutes.'),
              if (searchResult.nextOpeningUtc != null)
                Text('Possible group opening to recheck: '
                  '${searchResult.nextOpeningUtc!.toLocal()}'),
              if (blockedSites.isNotEmpty)
                Text('${blockedSites.length} participant(s) have no window '
                  'for these stars within 48 hours. You may remove them '
                  'and search again, or wait for a different star set.'),
              for (final site in blockedSites) FilledButton.icon(
                onPressed: busy || finding ? null : () => _removeMember(site,
                  noWindow: true),
                icon: const Icon(Icons.person_remove_outlined),
                label: Text('Remove ${site['station']} (no window)')),
              OutlinedButton(onPressed: busy || finding ? null : _find,
                child: const Text('Recheck sky windows')),
            ] else FilledButton(
              onPressed: busy ? null : () => _sendPlan(searchResult),
              child: Text(searchResult.reservedAt(now).isEmpty
                ? 'Send three-star plan to everyone'
                : 'Reserve later observers and send the plan')),
          ] else if (pendingAck.isNotEmpty) FilledButton(
            onPressed: busy ? null : () => _perform(() =>
              RelayClient.forIdentity(current).action(current, 'ack',
                {'memberId': pendingAck.first['id']})),
            child: Text('Acknowledge ${pendingAck.first['tag']}'))
          else if (publishReady) FilledButton(
            onPressed: busy ? null : () => _perform(() =>
              RelayClient.forIdentity(current).action(current, 'publish')),
            child: const Text('Send completed results to everyone'))
          else if (data?['published'] != null) FilledButton.icon(
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.insights_outlined),
            label: const Text('View results'))
          else if (phase == 'lobby' && !current.master)
            const Text('Waiting for the organizer to begin.'),
          if (data?['published'] != null)
            OutlinedButton.icon(
              onPressed: () => _openWebResults(current.code),
              icon: const Icon(Icons.open_in_new),
              label: const Text('View results on website')),
          if (!demo && current.master && data?['archive'] == 'pending')
            OutlinedButton.icon(
              onPressed: busy ? null : () => _perform(() =>
                RelayClient.forIdentity(current).action(current, 'archive')),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Retry website upload')),
          const SizedBox(height: 12),
          if (ownSite != null)
            Text('Your reported GPS: ${(ownSite['latitude'] as num).toStringAsFixed(3)}°, '
              '${(ownSite['longitude'] as num).toStringAsFixed(3)}°'),
          if (['lobby', 'planning', 'observing'].contains(phase) && received == 0 &&
              members.every((m) => (m['received'] as List).isEmpty))
            TextButton.icon(onPressed: busy ? null : _updateReportedLocation,
              icon: const Icon(Icons.my_location_outlined),
              label: const Text('Refresh this phone’s reported GPS')),
          if (current.master && sitesData.isNotEmpty) ...[
            const Text('Reported station locations (rounded to about 2 km):'),
            for (final site in sitesData) Text(
              '${site['station']}: ${(site['latitude'] as num).toStringAsFixed(3)}°, '
              '${(site['longitude'] as num).toStringAsFixed(3)}° · '
              '${SkyGuide.sunAltitude((site['latitude'] as num).toDouble(),
                (site['longitude'] as num).toDouble(), now) < -8 ? 'dark now' : 'not dark now'}'),
          ],
          if (phase == 'observing' && plan != null) ...[
            if (allThreeReceived) const Text(
              'All three readings received. Results update as the group submits.')
            else if (!cameraReady) const Text(
              'Observations open during your scheduled sky window.'),
          ],
          if (phase == 'lobby') ...[
            const Text('Share the five-letter code. Each participant sends an approximate location automatically.'),
            if (current.master) Text('${members.length}/12 joined • ${members.where((m) => m['hasSite'] == true).length} locations ready'),
          ],
          if ((phase == 'planning' || canReplan) && current.master) ...[
            const Text('Check everyone now, then every five minutes. If no full-group opening is available in 30 minutes, try 90%, 80%, 70%, then 60% (at least three). Others keep later chances with the same stars.'),
            if (searchResult != null) ...[
              Text('Shared stars: ${searchResult.stars.map((s) => s.name).join(' • ')}'),
              const Text('Named catalogue stars, visual magnitude +2.5 or brighter. Confirm them by eye before recording.'),
              for (var i = 0; i < sitesData.length; i++) ...[
                if (searchResult.windows[i].isEmpty) ...[
                  Text('${sitesData[i]['station']}: no window for these '
                    'shared stars within 48 hours.'),
                  Text(blockedCanSeeOtherStars[sitesData[i]['memberId']] == true
                    ? 'Other suitable stars are visible there soon.'
                    : 'No suitable three-star set there in the next 30 minutes.'),
                ] else Text('${sitesData[i]['station']}: '
                  '${searchResult.windows[i].first.startUtc.toLocal()} – '
                  '${searchResult.windows[i].first.endUtc.toLocal()}'
                  '${searchResult.windows[i].first.startUtc.difference(now) > const Duration(hours: 12) ? ' · later chance' : ''}'),
              ],
              if (searchResult.openingReady && blockedSites.isEmpty)
                Text(searchResult.reservedAt(now).isEmpty
                  ? 'Everyone has a usable window now.'
                  : '${searchResult.reservedAt(now).length} participant(s) are waiting for their scheduled windows.'),
            ] else if (!finding && searchResult == null)
              const Text('Find today’s group opening, then later chances for members who miss it.'),
          ],
          if (phase == 'planning' && !current.master)
            const Text('Organizer is selecting the three shared stars. This screen will update automatically.'),
          if (plan != null) ...[
            Text('Shared stars: ${(plan['stars'] as List).join(' • ')}'),
            if (plan['distributed'] == true) ...[
              Text('Submit within 48 hours: deadline ${DateTime.parse(plan['deadlineUtc'] as String).toLocal()}'),
              for (final window in ownWindows)
                Text('Your sky window: ${DateTime.parse(window['startUtc'] as String).toLocal()} – '
                  '${DateTime.parse(window['endUtc'] as String).toLocal()}'),
              if (ownMembers.isNotEmpty && ownMembers.first['reserved'] == true)
                const Text('Reserved • You are still in the group and your three measurements are required. Your observing window has not opened yet. Return in the window above. You will receive the interim result; you may also leave and start a new group.'),
              if (ownMembers.isNotEmpty && ownMembers.first['reserved'] != true)
                const Text('Some members are outside the current dark window. Their measurements will be added as they arrive. You and reserved members receive an interim result when three stations finish. Everyone receives the final result within 48 hours.'),
            ] else Text('Observation window: ${(DateTime.parse(plan['targetUtc'] as String)).toLocal()} (±45 minutes)'),
            if ((plan['excludedStations'] as List).contains(current.tag))
              const Text('Your location is outside this dark-sky window.'),
          ],
          if (phase == 'observing') ...[
            if (current.master) Text('$received readings received. Confirm each station after all three arrive.'),
            if (current.master && plan?['distributed'] == true)
              const Text('Results update as observations arrive. Later observers remain in the group until the 48-hour deadline.'),
          ],
          if (data?['published'] != null) const Text(
            'Group readings are on this phone. Open Results; the group will update as more participants submit.'),
          for (final member in members) ListTile(
            dense: true, title: Text('${member['tag']}'),
            titleTextStyle: member['reserved'] == true ?
              TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)) : null,
            subtitle: Text(member['hasSite'] == true ?
              '${member['reserved'] == true ? 'Reserved · waiting for sky window · ' : ''}'
              '${(member['received'] as List).length}/3 stars received${member['acknowledged'] == true ? ' • acknowledged' : ''}' :
              'Waiting for approximate location'),
            trailing: current.master &&
                ['lobby', 'planning', 'observing'].contains(phase) &&
                (member['received'] as List).isEmpty &&
                member['id'] != current.memberId
              ? IconButton(tooltip: 'Remove member', icon: const Icon(Icons.person_remove_outlined),
                  onPressed: busy || finding ? null : () => _removeMember({
                    'memberId': member['id'], 'station': member['tag']})) : null),
          TextButton(onPressed: busy ? null : _refresh, child: const Text('Refresh')),
          TextButton(onPressed: busy || finding ? null : () => _leaveGroup(current, phase,
            ownMembers.isNotEmpty &&
              (ownMembers.first['received'] as List).isNotEmpty),
            child: Text(current.master ||
              (ownMembers.isNotEmpty &&
                (ownMembers.first['received'] as List).isNotEmpty)
                ? 'Disconnect this phone from the group'
                : 'Leave this group')),
        ],
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]))));
  }
}
