import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import '../measurement/observation.dart';
import '../protocol/session.dart';
import '../protocol/session_repository.dart';
import '../protocol/relay_client.dart';
import 'relay_group_page.dart';
import '../solver/comparison.dart';
import '../reconstruction/layout.dart';
import '../astronomy/visibility.dart' as star;
import 'station_diagram.dart';
import 'result_plots.dart';
import 'scroll_cues.dart';

class HomePage extends StatefulWidget {
  final double? latitude, longitude;
  final String? station;
  const HomePage({super.key, this.latitude, this.longitude, this.station});
  @override State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  ExperimentSession? session;
  RelayIdentity? relay;
  bool arrows = true, exportConsent = false;
  int selected = 0;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final current = await SessionRepository.active();
      final activeRelay = await RelayStore.read();
      if (mounted) setState(() { session = current; relay = activeRelay; });
    } catch (_) {
      if (mounted) setState(() => session = ExperimentSession(const Uuid().v4(), 'Star angle experiment', []));
    }
  }
  Future<void> _save() => SessionRepository.save(session!);
  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _openWebResults(String groupCode, bool globe) async {
    final page = Uri.https('roundhound.info', '/shapeify/',
      {'group': groupCode, 'view': globe ? 'globe' : 'flat'});
    try {
      if (!await launchUrl(page, mode: LaunchMode.externalApplication) && mounted) {
        _message('Could not open web results. Visit $page');
      }
    } catch (_) {
      if (mounted) _message('Could not open web results. Visit $page');
    }
  }

  Future<void> _add() async {
    final fields = List.generate(10, (_) => TextEditingController());
    final labels = ['Observer', 'Star name / ID', 'Latitude °', 'Longitude °', 'Elevation m', 'Instrument height m', 'Star altitude °', 'True azimuth °', 'Angular uncertainty °', 'Position uncertainty m'];
    fields[5].text='1.5'; fields[8].text='1'; fields[9].text='10';
    final method = TextEditingController(text: 'Manual sighting, leveled horizon, true north');
    final notes = TextEditingController();
    DateTime time = DateTime.now().toUtc(); bool naked = false;
    final result = await showDialog<Observation>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, update) => AlertDialog(
      title: const Text('Record a naked-eye sighting'),
      content: SizedBox(width: math.min(460, MediaQuery.sizeOf(context).width * 0.52), child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Enter measured angles. Azimuth must be corrected to true north. UTC is captured now; adjust it if your sighting was earlier.'),
        for (var i=0;i<fields.length;i++) TextField(controller: fields[i], keyboardType: i<2 ? TextInputType.text : const TextInputType.numberWithOptions(decimal:true,signed:true), decoration: InputDecoration(labelText: labels[i])),
        TextField(controller: method, decoration: const InputDecoration(labelText: 'Measurement method')),
        TextField(controller: notes, decoration: const InputDecoration(labelText: 'Conditions / notes')),
        ListTile(title: const Text('Observation time (UTC)'), subtitle: Text(time.toIso8601String()), trailing: const Icon(Icons.schedule), onTap: () async {
          final d = await showDatePicker(context: context, initialDate: time, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 1)));
          if (d == null || !context.mounted) return;
          final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(time));
          if (t != null) update(() => time = DateTime.utc(d.year,d.month,d.day,t.hour,t.minute));
        }),
        CheckboxListTile(value: naked, onChanged: (v) => update(() => naked=v??false), title: const Text('I saw this star directly with my unaided eyes')),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () {
        try {
          double number(int i) => double.parse(fields[i].text.trim());
          final o = Observation(id: const Uuid().v4(), observer: fields[0].text.trim(), starId: fields[1].text.trim(),
            latitude: number(2), longitude: number(3), elevationM: number(4), instrumentHeightM: number(5),
            altitudeDeg: number(6), azimuthDeg: number(7), angularUncertaintyDeg: number(8),
            positionUncertaintyM: number(9), method: method.text.trim(), notes: notes.text.trim(),
            observedUtc: time, nakedEyeConfirmed: naked);
          final errors=o.validate();
          if (errors.isNotEmpty) { _message(errors.join('; ')); return; }
          Navigator.pop(context, o);
        } catch (_) { _message('Enter valid numbers in all numeric fields'); }
      }, child: const Text('Add'))],
    )));
    for (final c in [...fields,method,notes]) { c.dispose(); }
    if (result == null || !mounted) return;
    setState(() {
      session = session!.withObservation(result);
      selected = StationLayout.arrange(session!.observations).indexWhere((station) =>
          station.observation.observer.trim().toLowerCase() ==
          result.observer.trim().toLowerCase());
    });
    await _save();
  }

  Future<void> _import() async {
    final c=TextEditingController();
    final pasted=await showDialog<String>(context:context,builder:(context)=>AlertDialog(title:const Text('Import from another phone'),
      content:SizedBox(width:math.min(480, MediaQuery.sizeOf(context).width * 0.52),child:Column(mainAxisSize:MainAxisSize.min,children:[const Text('Only import records from people you trust. Their locations and notes will be saved on this phone.'),TextField(controller:c,maxLines:8,decoration:const InputDecoration(hintText:'Paste session JSON'))])),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,c.text),child:const Text('Import'))]));
    if (pasted==null || !mounted) return;
    try {
      final incoming=ExperimentSession.decode(pasted);
      if (incoming.id != session!.id) {
        throw const FormatException('Different session ID. Join that group first.');
      }
      final before = session!.observations.length;
      setState(() => session = session!.merge(incoming));
      await _save();
      if (mounted) _message('Added ${session!.observations.length - before} new sighting(s)');
    } catch(e) { _message('Import failed: $e'); }
  }
  Future<void> _export() async {
    if (!exportConsent) { _message('Review and tick the sharing consent box first'); return; }
    await SharePlus.instance.share(ShareParams(
      text: session!.encode(includeSites: false),
      subject: 'Shape-ify ${session!.title}'));
  }

  @override Widget build(BuildContext context) {
    final s=session;
    if (s==null) return const Scaffold(body:Center(child:CircularProgressIndicator()));
    final online = relay != null && relay!.code == s.id;
    final pairs=ComparisonSolver.all(s.observations);
    final stations = StationLayout.arrange(s.observations);
    final assembled = AssemblyLayout.ready(stations, s.plan?.stars,
        s.plan?.siteCount, s.plan?.excludedStations ?? const []);
    return Scaffold(appBar:AppBar(title:const Text('Results'),
      actions: [IconButton(tooltip: 'Group sessions',
        icon: const Icon(Icons.group_outlined), onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => RelayGroupPage(
                  latitude: widget.latitude, longitude: widget.longitude)));
          final current = await SessionRepository.active();
          final activeRelay = await RelayStore.read();
          if (mounted) setState(() { session = current; relay = activeRelay; selected = 0; });
        })]),
      floatingActionButton:online ? null : FloatingActionButton.extended(onPressed:_add,label:const Text('Add sighting'),icon:const Icon(Icons.add)),
      body:ActionFirstScroll(actionId: online ? 'results-${s.id}' : null,
        builder: (scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 36), children:[
        if (online) ...[
          ResultPlots(stations: stations,
            sessionId: s.id,
            description: 'Each phone updates its plots as readings arrive. Reserved stations join the final result within 48 hours. Candidate views are illustrative.',
            onWebView: RegExp(r'^[A-Z]{5}$').hasMatch(s.id)
              ? (globe) => _openWebResults(s.id, globe) : null,
            onCheckAgain: () => Navigator.pop(context)),
        ] else ...[
          const Text('Every phone builds the same picture',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
          Text('Session ID: ${s.id}',style:Theme.of(context).textTheme.bodySmall),
          const SizedBox(height:8),
          const Text('Each station appears as its sightings arrive. The arrangement is illustrative, not a recovered ground shape.'),
          SwitchListTile(title:const Text('Show ground-anchored direction arrows'),value:arrows,onChanged:(v)=>setState(()=>arrows=v)),
          SizedBox(height:340,child:Card(clipBehavior:Clip.hardEdge,
            child:StationDiagram(key:ValueKey(s.id),points:stations,
              arrows:arrows,assemble:assembled,star:s.plan?.stars.first,
              selected:selected,onSelect:(i)=>setState(()=>selected=i)))),
          const Text('Arrow direction: reported azimuth from local north. Arrow length: reported star altitude in degrees, not physical height.'),
        ],
        if(stations.isEmpty) Text(online ? 'Waiting for your group to complete its readings.' : 'Add a sighting to start.'),
        if(stations.isNotEmpty) ...[
          const SizedBox(height:12), const Text('Stations',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
          for(var i=0;i<stations.length;i++) ListTile(selected:i==selected,onTap:()=>setState(()=>selected=i),
            title:Text(stations[i].observation.observer),
            subtitle:Text('${stations[i].observations.length} sighting(s) · ${stations[i].observations.map((o) => o.starId).toSet().join(', ')}')),
          Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Selected: ${stations[math.min(selected,stations.length-1)].observation.observer}'),
            for (final o in stations[math.min(selected,stations.length-1)].observations)
              Padding(padding: const EdgeInsets.only(top: 8), child:Text('${o.starId} · ${o.altitudeDeg.toStringAsFixed(1)}° high · ${o.azimuthDeg.toStringAsFixed(1)}° ${o.azimuthReference} azimuth\n'
                '${o.observedUtc.toIso8601String()} · ${o.latitude}, ${o.longitude}\n'
                '${o.simulated ? '' : '${star.Visibility.status(o)} · ${o.method}\n${o.notes}'}')),
          ]))),
        ],
        const SizedBox(height:12),const Text('Comparable sightings',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        if(pairs.isEmpty) const Text('Waiting for the same star to be measured at two locations. Measurements can be made on different nights.'),
        for(final p in pairs) Card(child:ListTile(title:Text('${p.a.observer} ↔ ${p.b.observer} · ${p.a.starId}'),
          subtitle:Text('Raw local-ray angle: ${p.raySeparationDeg.toStringAsFixed(2)}° (different observation times are not directly comparable)${p.magneticReference ? ' (magnetic headings; uncorrected)' : ''}\n'
            'Catalog/time-model residual difference: ${p.modelDependentResidualDifferenceDeg == null ? 'unavailable for these readings' : '${p.modelDependentResidualDifferenceDeg!.toStringAsFixed(2)}°'}\n'
            'Approximate GPS reference separation: ${(p.baselineM/1000).toStringAsFixed(2)} km${p.baselineApproximate ? ' (short-range approximation only)' : ''}\n'
            'The catalog residual uses an Earth-rotation/geodetic reference model; it is not independent proof of ground shape.'))),
        const Divider(),
        if (!online) CheckboxListTile(value:exportConsent,onChanged:(v)=>setState(()=>exportConsent=v??false),
          title:const Text('I agree to share precise locations, times and notes with the group'),
          subtitle:const Text('The recipient can retain and forward this information. Review records above first.')),
        if (!online) Wrap(spacing:12,children:[OutlinedButton.icon(onPressed:_import,icon:const Icon(Icons.file_download),label:const Text('Paste group JSON')),
          FilledButton.icon(onPressed:_export,icon:const Icon(Icons.share),label:const Text('Send JSON to everyone'))]),
        const SizedBox(height:90),
      ])));
  }
}
