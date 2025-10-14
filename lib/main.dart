import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sa_launcher/services/logging_service.dart';
import 'package:sa_launcher/views/home_page.dart';
import 'package:window_manager/window_manager.dart';
import 'services/app_data_service.dart';
import 'services/init_service.dart';
import 'controllers/controllers_binding.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化window_manager（仅在桌面平台）
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      title: 'SALauncher',
      size: Size(1280, 720),
      center: true,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  await LoggingService.instance.initialize();
  LoggingService.instance.info('AppDataDirectory ${await AppDataService.getAppDataDirectory()}');

  // 初始化应用
  await InitService.initializeApp();
  
  runApp(const GameLauncherApp());
}

class GameLauncherApp extends StatelessWidget {
  const GameLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: '游戏启动器',
      theme: ThemeData(
        fontFamily: 'Noto Sans SC',
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
      initialBinding: ControllersBinding(),
    );
  }
}