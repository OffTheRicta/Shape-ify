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
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'Shape-ify',
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF5AD8ED), brightness: Brightness.dark),
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xE8171B26)),
    ),
    builder: (context, child) => LaunchSequence(child: child),
    home: const GuidedHome());
}
