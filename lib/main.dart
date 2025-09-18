import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pages/home_page.dart';

void main() {
  runApp(const ProviderScope(child: GameLauncherApp()));
}

class GameLauncherApp extends StatelessWidget {
  const GameLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '游戏启动器',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
