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
        seedColor: const Color(0xFFB16AFF), brightness: Brightness.dark),
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF080D1A)),
      cardTheme: const CardThemeData(color: Color(0xFF111B2D)),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ),
    builder: (context, child) => LaunchSequence(child: child),
    home: const GuidedHome());
}
