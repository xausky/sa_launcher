import 'dart:io';
import 'package:path/path.dart' as path;

import 'logging_service.dart';

class GameLauncher {
  static Future<bool> launchGame(String executablePath) async {
    try {
      final file = File(executablePath);
      if (!await file.exists()) {
        throw Exception('可执行文件不存在: $executablePath');
      }

      // 获取可执行文件的目录作为工作目录
      final workingDirectory = path.dirname(executablePath);

      // 在 Windows 上启动程序
      if (Platform.isWindows) {
        await Process.start(
          executablePath,
          [],
          workingDirectory: workingDirectory,
          mode: ProcessStartMode.detached,
        );
      } else {
        // 其他平台的处理
        await Process.start(
          executablePath,
          [],
          workingDirectory: workingDirectory,
          mode: ProcessStartMode.detached,
        );
      }

      return true;
    } catch (e) {
      LoggingService.instance.info('启动游戏失败: $e');
      return false;
    }
  }

  static bool isExecutable(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    return extension == '.exe' || extension == '.msi';
  }
}
