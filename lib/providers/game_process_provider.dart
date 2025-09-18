import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game_process.dart';
import '../services/game_process_manager.dart';

// 游戏进程状态管理
class GameProcessNotifier extends StateNotifier<Map<String, GameProcessInfo>> {
  GameProcessNotifier() : super({}) {
    _startPeriodicUpdate();
  }

  Timer? _updateTimer;
  final _processManager = GameProcessManager();

  // 启动游戏
  Future<bool> launchGame(String gameId, String executablePath) async {
    final success = await _processManager.launchGame(gameId, executablePath);
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

  @override
  void dispose() {
    _updateTimer?.cancel();
    _processManager.dispose();
    super.dispose();
  }
}

// 游戏进程状态Provider
final gameProcessProvider =
    StateNotifierProvider<GameProcessNotifier, Map<String, GameProcessInfo>>((
      ref,
    ) {
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

// 检查游戏是否正在运行
final isGameRunningProvider = Provider.family<bool, String>((ref, gameId) {
  final processInfo = ref.watch(gameProcessInfoProvider(gameId));
  return processInfo?.isRunning ?? false;
});

// 获取游戏进程PID
final gameProcessIdProvider = Provider.family<int?, String>((ref, gameId) {
  final processInfo = ref.watch(gameProcessInfoProvider(gameId));
  return processInfo?.processId;
});
