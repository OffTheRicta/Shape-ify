import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../astronomy/sky.dart';
import '../protocol/group_plan.dart';
import '../protocol/invite.dart';
import '../protocol/session.dart';
import '../protocol/session_repository.dart';

class SessionPage extends StatefulWidget {
  final double? latitude, longitude;
  final String? station;
  const SessionPage({super.key, this.latitude, this.longitude, this.station});

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  ExperimentSession? active;
  List<ExperimentSession> sessions = [];
  String? error;
  bool searching = false;
  Timer? countdownTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && active?.plan != null) setState(() {});
    });
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    super.dispose();
  }

  String _countdown(DateTime when) {
    final seconds = when.difference(DateTime.now().toUtc()).inSeconds;
    if (seconds <= 0) return 'The planned time has passed';
    return 'Next window in ${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
  }

  Future<void> _refresh() async {
    try {
      final current = await SessionRepository.active();
      final all = await SessionRepository.all();
      if (mounted) { setState(() {
        active = current;
        sessions = all;
        error = null;
      }); }
    } catch (e) {
      if (mounted) { setState(() => error = '$e'); }
    }
  }

  void _fail(Object e) {
    if (mounted) setState(() => error = '$e');
  }

  Future<String?> _paste(String title, String hint) async {
    return showDialog<String>(context: context,
        builder: (_) => PasteTextDialog(title: title, hint: hint));
  }

  Future<void> _create() async {
    var name = 'Star angle experiment';
    final title = await showDialog<String>(context: context, builder: (dialog) =>
      AlertDialog(title: const Text('Create a group'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Create the ID first. Everyone joins and sends an approximate location. Then choose stars visible to the whole group.'),
            TextField(onChanged: (value) => name = value,
              decoration: const InputDecoration(labelText: 'Group name',
                hintText: 'Star angle experiment')),
          ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, name),
              child: const Text('Create')),
        ]));
    if (title == null) return;
    try {
      await SessionRepository.create(InviteCode.create(), title);
      await _refresh();
    } catch (e) { _fail(e); }
  }

  Future<void> _join() async {
    final input = await _paste('Join with an ID', 'RH-XXXX-XXXX-XXXX');
    if (input == null) return;
    final id = InviteCode.parse(input);
    if (id == null) { _fail('Check the group ID from your invitation.'); return; }
    try {
      await SessionRepository.join(id);
      await _refresh();
    } catch (e) { _fail(e); }
  }

  Future<void> _sendSite() async {
    final s = active;
    final lat = widget.latitude, lon = widget.longitude;
    final station = widget.station;
    if (s == null || lat == null || lon == null || station == null) {
      _fail('Get a location fix on the main screen first.');
      return;
    }
    final site = ParticipantSite.rounded(station, lat, lon,
        DateTime.now().toUtc());
    final agreed = await showDialog<bool>(context: context, builder: (dialog) =>
      AlertDialog(title: const Text('Send location to organizer?'),
        content: Text('This shares an approximate position rounded to two decimal places: ${site.latitude}, ${site.longitude}. Your organizer can retain or forward it. No photo or sighting is included.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Share location')),
        ]));
    if (agreed != true || !mounted) return;
    try {
      await SessionRepository.save(s.withSite(site));
      await _refresh();
      await SharePlus.instance.share(ShareParams(
          text: GroupMessage.site(s.id, site),
          subject: 'Shape-ify location for ${s.id}'));
    } catch (e) { _fail(e); }
  }

  Future<void> _importSite() async {
    final source = await _paste('Paste a participant location',
        'Paste the location report sent to the organizer');
    if (source == null || active == null) return;
    try {
      final site = GroupMessage.readSite(source, active!.id);
      await SessionRepository.save(active!.withSite(site));
      await _refresh();
    } catch (e) { _fail(e); }
  }

  Future<void> _choosePlan() async {
    final s = active;
    if (s == null || s.sites.length < 2) {
      _fail('Import at least two participant locations, including yours.');
      return;
    }
    final now = DateTime.now().toUtc();
    if (s.sites.any((site) => site.reportedUtc.isBefore(
        now.subtract(const Duration(hours: 24))))) {
      _fail('A location report is over 24 hours old. Ask that participant to resend it.');
      return;
    }
    final confirmed = await showDialog<bool>(context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Is everyone included?'),
        content: Text('These ${s.sites.length} stations will be checked: ${s.sites.map((site) => site.station).join(', ')}. Include your own station and every participant before selecting stars.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Add another')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Check all sites')),
        ]));
    if (confirmed != true || !mounted) return;
    final ordered = [...s.sites]
      ..sort((a, b) => a.station.compareTo(b.station));
    final locations = [for (final site in ordered)
      SkyLocation(site.latitude, site.longitude)];
    try {
      setState(() => searching = true);
      final result = await compute(SkyGuide.searchGroup,
          GroupSkyRequest(locations, now));
      if (!mounted) return;
      var window = result.allSites;
      final excluded = <String>[];
      List<String> daylightStations(PartialSkyWindow partial) => [
        for (var i = 0; i < ordered.length; i++)
          if (!partial.includedIndexes.contains(i)) ordered[i].station,
      ];
      final earlierSubset = result.subset;
      if (window != null && earlierSubset != null &&
          earlierSubset.window.utc.isBefore(window.utc)) {
        final everyoneTime = window.utc;
        final daylight = daylightStations(earlierSubset);
        final choice = await showDialog<int>(context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Choose the group window'),
            content: Text('For everyone: ${_countdown(everyoneTime)}. Earlier, ${_countdown(earlierSubset.window.utc).toLowerCase()}, these stations are in daylight: ${daylight.join(', ')}. Their reports will stay saved if you plan without them.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel')),
              OutlinedButton(onPressed: () => Navigator.pop(dialog, 1),
                child: const Text('Wait for everyone')),
              FilledButton(onPressed: () => Navigator.pop(dialog, 2),
                child: const Text('Plan without them')),
            ]));
        if (choice == null || !mounted) return;
        if (choice == 2) {
          window = earlierSubset.window;
          excluded.addAll(daylight);
        }
      }
      if (window == null) {
        final partial = result.subset;
        if (partial == null) {
          _fail('No all-site window was found in the next year, and no smaller group with three common stars was found in the next 30 days. A countdown cannot be given for this group.');
          return;
        }
        excluded.addAll(daylightStations(partial));
        final approved = await showDialog<bool>(context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('No all-site window found'),
            content: Text('No common dark sky with three shared stars was found for everyone within the next year. A smaller group has a window in ${_countdown(partial.window.utc).replaceFirst('Next window in ', '')}. These stations are in daylight then: ${excluded.join(', ')}. Plan without them? Their reports stay saved, but they cannot capture under this plan.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Keep everyone')),
              FilledButton(onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Plan without them')),
            ]));
        if (approved != true || !mounted) return;
        window = partial.window;
      }
      final selectedWindow = window;
      final plan = SharedPlan([for (final star in selectedWindow.stars) star.name],
          selectedWindow.utc, DateTime.now().toUtc(), s.sites.length - excluded.length,
          excludedStations: excluded);
      await SessionRepository.save(s.withPlan(plan));
      await _refresh();
    } catch (e) { _fail(e); }
    finally { if (mounted) setState(() => searching = false); }
  }

  Future<void> _sendPlan() async {
    final s = active;
    if (s?.plan == null) return;
    await SharePlus.instance.share(ShareParams(
        text: GroupMessage.plan(s!.id, s.plan!),
        subject: 'Shape-ify shared stars and time'));
  }

  Future<void> _importPlan() async {
    final source = await _paste('Paste the shared sky plan',
        'Paste the organizer’s sky-plan message');
    if (source == null || active == null) return;
    try {
      final plan = GroupMessage.readPlan(source, active!.id);
      if (plan.stars.any((name) =>
          !SkyGuide.brightStars.any((star) => star.name == name))) {
        throw const FormatException('Sky plan contains an unknown star');
      }
      await SessionRepository.save(active!.withPlan(plan));
      await _refresh();
    } catch (e) { _fail(e); }
  }

  @override
  Widget build(BuildContext context) {
    final s = active;
    return Scaffold(appBar: AppBar(title: const Text('Groups')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        const Text('1. Everyone joins the group and sends an approximate location to the organizer. 2. The organizer imports the location reports and finds three stars visible to all at one UTC time. 3. Everyone imports that sky plan before measuring.'),
        if (error != null) Card(color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(padding: const EdgeInsets.all(12), child: Text(error!))),
        Wrap(spacing: 8, children: [
          FilledButton(onPressed: _create, child: const Text('Create group')),
          OutlinedButton(onPressed: _join, child: const Text('Join with ID')),
        ]),
        if (s != null) Card(child: Padding(padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.title, style: Theme.of(context).textTheme.titleMedium),
            SelectableText(s.id),
            Text('${s.observations.length} sightings · ${s.sites.length} locations on this phone'),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(icon: const Icon(Icons.copy),
                onPressed: () => Clipboard.setData(ClipboardData(text: s.id)),
                label: const Text('Copy ID')),
              FilledButton.icon(icon: const Icon(Icons.share),
                onPressed: () => SharePlus.instance.share(ShareParams(
                    text: 'Join my Shape-ify group. Open Groups → Join with ID and enter: ${s.id}\nThen send me your approximate location from the group screen.',
                    subject: 'Shape-ify group invitation')),
                label: const Text('Send invite')),
            ]),
          ]))),
        if (s != null) ...[
          const SizedBox(height: 8),
          const Text('Locations', style: TextStyle(fontWeight: FontWeight.bold)),
          Wrap(spacing: 8, children: [
            FilledButton(onPressed: _sendSite, child: const Text('Send my location')),
            OutlinedButton(onPressed: _importSite,
                child: const Text('Paste location report')),
          ]),
          for (final site in s.sites) Text('${site.station}: ${site.latitude}, ${site.longitude}'),
          const SizedBox(height: 8),
          FilledButton(onPressed: s.sites.length >= 2 && !searching
              ? _choosePlan : null,
              child: Text(searching ? 'Checking all sites…' : 'Find shared stars & time')),
          const SizedBox(height: 8),
          if (s.plan == null) const Text('Awaiting the shared sky plan. Capture stays locked until you import it.'),
          if (s.plan != null) ...[
            Text('${s.plan!.siteCount} planned sites: ${s.plan!.stars.join(', ')}'),
            Text(_countdown(s.plan!.targetUtc)),
            if (s.plan!.excludedStations.isNotEmpty)
              Text('Outside this plan (in daylight): ${s.plan!.excludedStations.join(', ')}. Their locations remain saved.'),
            Text('UTC: ${s.plan!.targetUtc.toIso8601String()}'),
            Text('Your local time: ${s.plan!.targetUtc.toLocal()}'),
            Wrap(spacing: 8, children: [
              FilledButton(onPressed: _sendPlan,
                  child: const Text('Send plan to everyone')),
            ]),
          ],
          OutlinedButton(onPressed: _importPlan,
              child: const Text('Paste group sky plan')),
        ],
        const Divider(),
        const Text('After measuring, send your sighting JSON to everyone from Results. Every phone merges records and calculates locally. An ID alone cannot fetch data from other phones.'),
        const Text('Only the organizer needs all planning locations. Sky plans sent to the group contain the star names and UTC time, not participant coordinates.'),
        const SizedBox(height: 10),
        const Text('Saved groups', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final group in sessions) ListTile(
          selected: s?.id == group.id,
          title: Text(group.title),
          subtitle: Text(group.id),
          trailing: s?.id == group.id ? const Icon(Icons.check) : null,
          onTap: () async {
            await SessionRepository.join(group.id);
            await _refresh();
          }),
      ]));
  }
}

/// Compact enough for the app's framed viewport when the keyboard opens.
/// The clipboard action imports directly and never needs the keyboard.
class PasteTextDialog extends StatefulWidget {
  final String title, hint;
  const PasteTextDialog({super.key, required this.title, required this.hint});

  @override
  State<PasteTextDialog> createState() => _PasteTextDialogState();
}

class _PasteTextDialogState extends State<PasteTextDialog> {
  String value = '';
  String? message;

  Future<void> _pasteClipboard() async {
    try {
      final clipboard = await Clipboard.getData('text/plain');
      if (!mounted) return;
      final source = clipboard?.text?.trim();
      if (source == null || source.isEmpty) {
        setState(() => message = 'Copy the report text first.');
      } else {
        Navigator.of(context).pop(source);
      }
    } catch (_) {
      if (mounted) setState(() => message = 'Could not read the clipboard. Try typing or long-press to paste.');
    }
  }

  void _import() {
    if (value.trim().isEmpty) {
      setState(() => message = 'Paste text before importing.');
    } else {
      Navigator.of(context).pop(value.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    title: Row(children: [
      Expanded(child: Text(widget.title,
          style: Theme.of(context).textTheme.titleMedium)),
      IconButton(tooltip: 'Paste from clipboard',
          icon: const Icon(Icons.content_paste), onPressed: _pasteClipboard),
    ]),
    content: TextField(
      minLines: 1,
      maxLines: 2,
      keyboardType: TextInputType.multiline,
      onChanged: (text) => setState(() { value = text; message = null; }),
      decoration: InputDecoration(hintText: widget.hint, errorText: message),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel')),
      FilledButton(onPressed: _import, child: const Text('Import')),
    ],
  );
}
