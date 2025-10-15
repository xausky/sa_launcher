import 'dart:async';
import 'package:get/get.dart';
import 'package:sa_launcher/models/game_process.dart';
import 'package:sa_launcher/models/file_modification.dart';
import 'package:sa_launcher/services/game_process_manager.dart';
import 'package:sa_launcher/views/dialogs/dialogs.dart';

// 游戏进程状态管理
class GameProcessController extends GetxController {
  // 游戏进程信息
  final _processManager = GameProcessManager();

  @override
  void onInit() {
    super.onInit();
    _processManager.setFileTrackingCallback((id, session) async {
      Dialogs.showFileTrackingResultsDialog(session);
    });

  }


  @override
  void onClose() {
    _processManager.dispose();
    super.onClose();
  }

  // 设置消息回调（用于显示 SnackBar）
  void setMessageCallback(Function(String message, bool isSuccess)? callback) {
    _processManager.setAutoBackupCallback(callback);
  }

  // 设置文件追踪回调
  void setFileTrackingCallback(
    Function(String gameId, FileTrackingSession session)? callback,
  ) {

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