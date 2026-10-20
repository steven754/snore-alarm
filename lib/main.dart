import 'package:flutter/material.dart';

import 'home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SnoreAlarmApp());
}

class SnoreAlarmApp extends StatelessWidget {
  const SnoreAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '鼾声唤醒',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}
