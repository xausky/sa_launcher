import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;
import '../models/game_process.dart';
import '../models/game.dart';
import '../services/app_data_service.dart';
import '../services/auto_backup_service.dart';

class GameProcessManager {
  static final GameProcessManager _instance = GameProcessManager._internal();
  factory GameProcessManager() => _instance;
  GameProcessManager._internal();

  final Map<String, GameProcessInfo> _runningGames = {};
  Timer? _monitorTimer;

  // 获取正在运行的游戏信息
  GameProcessInfo? getGameProcessInfo(String gameId) {
    return _runningGames[gameId];
  }

  // 获取所有正在运行的游戏
  Map<String, GameProcessInfo> get runningGames =>
      Map.unmodifiable(_runningGames);

  // 启动游戏并开始监控
  Future<bool> launchGame(String gameId, String executablePath) async {
    try {
      final file = File(executablePath);
      if (!await file.exists()) {
        throw Exception('可执行文件不存在: $executablePath');
      }

      // 获取可执行文件的目录作为工作目录
      final workingDirectory = path.dirname(executablePath);
      final executableName = path.basenameWithoutExtension(executablePath);

      // 启动程序
      final process = await Process.start(
        executablePath,
        [],
        workingDirectory: workingDirectory,
        mode: ProcessStartMode.detached,
      );

      // 记录游戏进程信息
      _runningGames[gameId] = GameProcessInfo(
        gameId: gameId,
        executableName: executableName,
        processId: process.pid,
        startTime: DateTime.now(),
      );

      // 开始监控进程
      _startMonitoring();

      return true;
    } catch (e) {
      print('启动游戏失败: $e');
      return false;
    }
  }

  // 开始监控进程
  void _startMonitoring() {
    // 如果已经在监控，就不重复启动
    if (_monitorTimer?.isActive == true) return;

    _monitorTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _updateProcessStatus();
    });
  }

  // 更新进程状态
  Future<void> _updateProcessStatus() async {
    if (_runningGames.isEmpty) {
      _stopMonitoring();
      return;
    }

    final List<String> gamesToRemove = [];

    for (final entry in _runningGames.entries) {
      final gameId = entry.key;
      final gameInfo = entry.value;

      try {
        // 检查进程是否还在运行
        final isRunning = await _isProcessRunning(gameInfo.processId);

        if (!isRunning) {
          // 进程已结束，触发自动备份检查
          _onGameEnded(gameId);
          // 移除游戏
          gamesToRemove.add(gameId);
        }
      } catch (e) {
        print('监控进程失败: $e');
        gamesToRemove.add(gameId);
      }
    }

    // 移除已结束的游戏
    for (final gameId in gamesToRemove) {
      _runningGames.remove(gameId);
    }
  }

  // 检查指定PID的进程是否还在运行
  Future<bool> _isProcessRunning(int pid) async {
    try {
      if (Platform.isWindows) {
        // 使用tasklist命令检查指定PID的进程
        final result = await Process.run('tasklist', [
          '/FO',
          'CSV',
          '/NH',
          '/FI',
          'PID eq $pid',
        ]);

        if (result.exitCode == 0) {
          final output = result.stdout.toString();
          return output.trim().isNotEmpty && output.contains(pid.toString());
        }
      }

      return false;
    } catch (e) {
      print('检查进程状态失败: $e');
      return false;
    }
  }

  // 停止监控
  void _stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  // 手动停止游戏进程
  Future<bool> killGame(String gameId) async {
    final gameInfo = _runningGames[gameId];
    if (gameInfo == null) return false;

    try {
      if (Platform.isWindows) {
        // 使用taskkill命令终止进程
        await Process.run('taskkill', [
          '/PID',
          gameInfo.processId.toString(),
          '/F',
        ]);
      }

      _runningGames.remove(gameId);
      return true;
    } catch (e) {
      print('终止游戏进程失败: $e');
      return false;
    }
  }

  // 游戏结束时的处理
  void _onGameEnded(String gameId) {
    // 异步处理自动备份，不阻塞进程监控
    _handleAutoBackup(gameId);
  }

  // 自动备份消息回调
  Function(String message, bool isSuccess)? _autoBackupCallback;

  // 设置自动备份消息回调
  void setAutoBackupCallback(
    Function(String message, bool isSuccess)? callback,
  ) {
    _autoBackupCallback = callback;
  }

  // 处理自动备份
  Future<void> _handleAutoBackup(String gameId) async {
    try {
      // 获取游戏信息
      final games = await AppDataService.getAllGames();
      Game? game;
      try {
        game = games.firstWhere((g) => g.id == gameId);
      } catch (e) {
        game = null;
      }

      if (game != null) {
        // 检查并创建自动备份
        final result = await AutoBackupService.checkAndCreateAutoBackup(game);

        // 根据结果显示相应的消息
        if (_autoBackupCallback != null) {
          if (result == true) {
            _autoBackupCallback!('已为游戏 ${game.title} 创建自动备份', true);
          } else if (result == false) {
            _autoBackupCallback!('未检测到存档目录变更，跳过本次自动备份', false);
          }
          // result == null 时不显示消息（未启用或出错）
        }
      }
    } catch (e) {
      print('处理自动备份失败: $e');
      if (_autoBackupCallback != null) {
        _autoBackupCallback!('自动备份失败: $e', false);
      }
    }
  }

  // 清理资源
  void dispose() {
    _stopMonitoring();
    _runningGames.clear();
  }
}
