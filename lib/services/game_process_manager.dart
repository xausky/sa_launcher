import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:event_tracing_windows/event_tracing_windows.dart';
import '../models/game_process.dart';
import '../models/game.dart';
import '../services/app_data_service.dart';
import '../services/auto_backup_service.dart';

class GameProcessManager {
  static final GameProcessManager _instance = GameProcessManager._internal();
  factory GameProcessManager() => _instance;
  GameProcessManager._internal();

  final Map<String, GameProcessInfo> _runningGames = {};
  final EventTracingWindows _etw = EventTracingWindows();
  StreamSubscription<ProcessEvent>? _processSubscription;
  bool _isMonitoring = false;

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
      await _startMonitoring();

      return true;
    } catch (e) {
      print('启动游戏失败: $e');
      return false;
    }
  }

  // 开始监控进程
  Future<void> _startMonitoring() async {
    // 如果已经在监控，就不重复启动
    if (_isMonitoring) return;

    try {
      // 启动 ETW 进程监控
      final success = await _etw.startProcessMonitoring();
      if (!success) {
        print('启动 ETW 进程监控失败，可能需要管理员权限');
        return;
      }

      _isMonitoring = true;

      // 监听进程事件
      _processSubscription = _etw.processEventStream.listen((event) {
        _handleProcessEvent(event);
      });
    } catch (e) {
      print('启动进程监控失败: $e');
    }
  }

  // 处理进程事件
  void _handleProcessEvent(ProcessEvent event) {
    final pid = event.processId;

    if (event.type == ProcessEventType.started) {
      // 进程启动事件 - 检查是否是游戏相关进程
      _onProcessStarted(pid, event.parentProcessId);
    } else if (event.type == ProcessEventType.terminated) {
      // 进程终止事件 - 检查是否是游戏进程
      _onProcessTerminated(pid);
    }
  }

  // 处理进程启动事件
  void _onProcessStarted(int pid, int parentProcessId) {
    // 如果 parentProcessId 在某个游戏的进程集合内，则认为是相关进程
    for (final entry in _runningGames.entries) {
      final gameId = entry.key;
      final gameInfo = entry.value;

      if (gameInfo.processIds.contains(parentProcessId)) {
        // 添加到游戏进程集合
        _runningGames[gameId] = gameInfo.addProcessId(pid);
        break;
      }
    }
  }

  // 处理进程终止事件
  void _onProcessTerminated(int pid) {
    final List<String> gamesToCheck = [];

    // 从所有游戏的进程集合中移除该进程ID
    for (final entry in _runningGames.entries) {
      final gameId = entry.key;
      final gameInfo = entry.value;

      if (gameInfo.processIds.contains(pid)) {
        _runningGames[gameId] = gameInfo.removeProcessId(pid);
        gamesToCheck.add(gameId);
      }
    }

    // 检查游戏是否完全结束
    for (final gameId in gamesToCheck) {
      final gameInfo = _runningGames[gameId];
      if (gameInfo != null && !gameInfo.isRunning) {
        // 游戏所有进程都已结束
        _onGameEnded(gameId, gameInfo);
        _runningGames.remove(gameId);
      }
    }

    // 如果没有游戏在运行，停止监控
    if (_runningGames.isEmpty) {
      _stopMonitoring();
    }
  }

  // 停止监控
  Future<void> _stopMonitoring() async {
    if (!_isMonitoring) return;

    try {
      await _processSubscription?.cancel();
      _processSubscription = null;

      await _etw.stopProcessMonitoring();
      _isMonitoring = false;
    } catch (e) {
      print('停止进程监控失败: $e');
    }
  }

  // 手动停止游戏进程
  Future<bool> killGame(String gameId) async {
    final gameInfo = _runningGames[gameId];
    if (gameInfo == null) return false;

    try {
      return Process.killPid(gameInfo.processId, ProcessSignal.sigkill);
    } catch (e) {
      print('终止游戏进程失败: $e');
      return false;
    }
  }

  // 游戏结束时的处理
  Future<void> _onGameEnded(String gameId, GameProcessInfo gameInfo) async {
    try {
      // 记录游戏时长统计
      await _recordPlaySession(gameId, gameInfo.startTime, DateTime.now());

      // 异步处理自动备份，不阻塞进程监控
      _handleAutoBackup(gameId);
    } catch (e) {
      print('处理游戏结束事件失败: $e');
      // 即使统计失败，也要继续处理自动备份
      _handleAutoBackup(gameId);
    }
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

  // 记录游戏会话
  Future<void> _recordPlaySession(
    String gameId,
    DateTime startTime,
    DateTime endTime,
  ) async {
    try {
      final sessionDuration = endTime.difference(startTime);

      // 如果游戏时长少于30秒，可能是启动失败或误操作，不记录
      if (sessionDuration.inSeconds < 30) {
        return;
      }

      // 获取当前游戏列表
      final games = await AppDataService.getAllGames();
      final gameIndex = games.indexWhere((g) => g.id == gameId);

      if (gameIndex != -1) {
        // 更新游戏统计
        final updatedGame = games[gameIndex].addPlaySession(sessionDuration);
        games[gameIndex] = updatedGame;

        // 保存更新后的游戏列表
        await AppDataService.saveGames(games);
      }
    } catch (e) {
      print('记录游戏会话失败: $e');
    }
  }

  // 清理资源
  Future<void> dispose() async {
    await _stopMonitoring();
    _runningGames.clear();
  }
}
