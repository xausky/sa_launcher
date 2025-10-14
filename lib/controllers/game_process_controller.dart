import 'dart:async';
import 'package:get/get.dart';
import 'package:sa_launcher/controllers/game_controller.dart';
import '../models/game_process.dart';
import '../models/file_modification.dart';
import '../services/game_process_manager.dart';

// 游戏进程状态管理
class GameProcessController extends GetxController {
  // 游戏进程信息
  final _processManager = GameProcessManager();

  // 消息回调
  Function(String message, bool isSuccess)? _messageCallback;
  
  // 文件追踪回调
  Function(String gameId, FileTrackingSession session)? _fileTrackingCallback;

  @override
  void onInit() {
    super.onInit();
  }

  @override
  void onClose() {
    _processManager.dispose();
    super.onClose();
  }

  // 设置消息回调（用于显示 SnackBar）
  void setMessageCallback(Function(String message, bool isSuccess)? callback) {
    _messageCallback = callback;
    _processManager.setAutoBackupCallback(callback);
  }

  // 设置文件追踪回调
  void setFileTrackingCallback(
    Function(String gameId, FileTrackingSession session)? callback,
  ) {
    _fileTrackingCallback = callback;
    _processManager.setFileTrackingCallback(callback);
  }

  // 启动游戏
  Future<bool> launchGame(String gameId, String executablePath) async {
    return await _processManager.launchGame(gameId, executablePath);
  }

  // 启动游戏并追踪文件修改
  Future<bool> launchGameWithFileTracking(
    String gameId,
    String executablePath,
  ) async {
    return await _processManager.launchGameWithFileTracking(
      gameId,
      executablePath,
    );
  }

  // 终止游戏
  Future<bool> killGame(String gameId) async {
    return await _processManager.killGame(gameId);
  }

  RxMap<String, GameProcessInfo> get runningGames => _processManager.runningGames;
}