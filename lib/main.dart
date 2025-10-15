import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sa_launcher/services/cloud_sync_config_service.dart';
import 'package:sa_launcher/services/logging_service.dart';
import 'package:sa_launcher/services/restic_service.dart';
import 'package:sa_launcher/views/dialogs/dialogs.dart';
import 'package:sa_launcher/views/home_page.dart';
import 'package:sa_launcher/views/init_page.dart';
import 'package:window_manager/window_manager.dart';
import 'services/app_data_service.dart';
import 'controllers/bindings/main_binding.dart';

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
    windowManager.addListener(MyWindowListener());
    await windowManager.setPreventClose(true);
  }
  await LoggingService.instance.initialize();
  LoggingService.instance.info('AppDataDirectory ${await AppDataService.getAppDataDirectory()}');

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
      home: const InitPage(),
      initialBinding: MainBinding(),
    );
  }
}

class MyWindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    await windowManager.hide();
    Dialogs.showProgressDialog('正在清理遗留数据', () async {
      try {
        LoggingService.instance.info("程序即将退出，清理 restic 锁");
        final cloudSyncConfig = await CloudSyncConfigService.getCloudSyncConfig();
        await ResticService.pruneRepository();
        await ResticService.unlockRepository();
        if(cloudSyncConfig != null) {
          await ResticService.pruneRepository(useRemote: true, cloudConfig: cloudSyncConfig);
          await ResticService.unlockRepository(useRemote: true, cloudConfig: cloudSyncConfig);
        }
        LoggingService.instance.info("清理 restic 锁结束");
      } finally {
        exit(0);
      }
    });
  }
}