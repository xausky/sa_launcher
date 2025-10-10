import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/home_page.dart';
import 'services/app_data_service.dart';
import 'services/git_worktree_service.dart';
import 'services/logging_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化日志服务
  await LoggingService.instance.initialize();
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

  // 初始化应用数据目录
  final appDataDir = await AppDataService.getAppDataDirectory();
  LoggingService.instance.info('AppDataDirectory $appDataDir');

  // 初始化 Git 仓库
  try {
    final gitInitSuccess = await GitWorktreeService.initMainRepository();
    if (gitInitSuccess) {
      LoggingService.instance.info('Git 仓库初始化成功');
    } else {
      LoggingService.instance.warning('Git 仓库初始化失败');
    }
  } catch (e) {
    LoggingService.instance.logError('Git 仓库初始化异常', e);
  }

  runApp(const ProviderScope(child: GameLauncherApp()));
}

class GameLauncherApp extends StatelessWidget {
  const GameLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '游戏启动器',
      theme: ThemeData(
        fontFamily: 'Noto Sans SC',
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
