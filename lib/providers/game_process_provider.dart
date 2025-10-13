import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game_process.dart';
import '../models/file_modification.dart';
import '../services/game_process_manager.dart';

// 游戏进程状态管理
class GameProcessNotifier extends Notifier<Map<String, GameProcessInfo>> {
  @override
  Map<String, GameProcessInfo> build() {
    _startPeriodicUpdate();
    return {};
  }

  Timer? _updateTimer;
  final _processManager = GameProcessManager();

  // 设置消息回调（用于显示 SnackBar）
  void setMessageCallback(Function(String message, bool isSuccess)? callback) {
    _processManager.setAutoBackupCallback(callback);
  }

  // 设置文件追踪回调
  void setFileTrackingCallback(
    Function(String gameId, FileTrackingSession session)? callback,
  ) {
    _processManager.setFileTrackingCallback(callback);
  }

  // 启动游戏
  Future<bool> launchGame(String gameId, String executablePath) async {
    final success = await _processManager.launchGame(ref, gameId, executablePath);
    if (success) {
      _updateState();
    }
    return success;
  }

  // 启动游戏并追踪文件修改
  Future<bool> launchGameWithFileTracking(
    String gameId,
    String executablePath,
  ) async {
    final success = await _processManager.launchGameWithFileTracking(
      gameId,
      executablePath,
    );
    if (success) {
      _updateState();
    }
    return success;
  }

  // 终止游戏
  Future<bool> killGame(String gameId) async {
    final success = await _processManager.killGame(gameId);
    if (success) {
      _updateState();
    }
    return success;
  }

  // 更新状态
  void _updateState() {
    state = Map.from(_processManager.runningGames);
  }

  // 开始定期更新状态
  void _startPeriodicUpdate() {
    _updateTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _updateState();
    });
  }

  void dispose() {
    _updateTimer?.cancel();
    _processManager.dispose();
  }
}

// 游戏进程状态Provider
final gameProcessProvider =
    NotifierProvider<GameProcessNotifier, Map<String, GameProcessInfo>>(() {
      return GameProcessNotifier();
    });

// 获取特定游戏的进程信息
final gameProcessInfoProvider = Provider.family<GameProcessInfo?, String>((
  ref,
  gameId,
) {
  final processMap = ref.watch(gameProcessProvider);
  return processMap[gameId];
});
