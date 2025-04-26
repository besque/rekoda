import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'homescreen.dart';

void main() async {
  // Ensure Flutter is initialized before accessing plugins
  WidgetsFlutterBinding.ensureInitialized();
  
  // Request permissions at app start
  await Permission.microphone.request();
  await Permission.storage.request();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Recorder',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const RecorderPage(),
    );
  }
}