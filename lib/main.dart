import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ui/launch_sequence.dart';
import 'ui/guided_home.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const RoundhoundApp());
}
class RoundhoundApp extends StatelessWidget {
  const RoundhoundApp({super.key});
  static final _launchAccent = _sampleAccent();

  static Color _sampleAccent() {
    const colors = [
      Color(0xff41e6d3), Color(0xffff4ebe), Color(0xff58e483),
      Color(0xffab70ff), Color(0xff56a7ff), Color(0xffffa450),
    ];
    final position = Random().nextDouble() * (colors.length - 1);
    final index = position.floor();
    return Color.lerp(colors[index], colors[index + 1], position - index)!;
  }

  @override Widget build(BuildContext context) => MaterialApp(
    title: 'Shape-ify',
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _launchAccent, brightness: Brightness.dark,
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity),
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xE8171B26)),
    ),
    builder: (context, child) => LaunchSequence(child: child),
    home: const GuidedHome());
}
