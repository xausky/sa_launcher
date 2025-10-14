import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sa_launcher/services/auto_backup_service.dart';
import 'package:sa_launcher/services/restic_service.dart';
import 'package:sa_launcher/services/save_backup_service.dart';
import '../models/game.dart';
import '../services/game_storage.dart';
import '../services/cloud_backup_service.dart';
import '../services/logging_service.dart';

// 游戏列表状态管理
class GameController extends GetxController {
  // 游戏列表
  var games = <String, Game>{}.obs;
  var isLoading = false.obs;
  var errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    loadGames();
  }

  // 加载游戏列表
  Future<void> loadGames() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final games = await GameStorage.getGames();
      for(final game in games) {
        this.games[game.id] = game;
      }
    } catch (error) {
      errorMessage.value = error.toString();
      Get.snackbar(
        '错误',
        '加载游戏列表失败: $error',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      isLoading.value = false;
    }
  }

  // 添加游戏
  Future<void> addGame(Game game) async {
    try {
      await GameStorage.addGame(game);
      await loadGames(); // 重新加载列表

      // 触发自动上传到云端
      backupMainAndUpload();
      Get.snackbar(
        '成功',
        '游戏添加成功',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (error) {
      Get.snackbar(
        '错误',
        '添加游戏失败: $error',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> backupMainAndUpload() async {
    await AutoBackupService.checkAndCreateAutoBackup(Game(id: 'main', title: '启动器数据', executablePath: '', createdAt: DateTime.now(), saveDataPath: (await ResticService.getMainDataDirectory()).path));
  }

  // 更新游戏
  Future<void> updateGame(Game updatedGame) async {
    try {
      LoggingService.instance.info('updateGame: ${updatedGame.toJson()}');
      this.games[updatedGame.id] = updatedGame;
      await GameStorage.updateGame(updatedGame);

      // 触发自动上传到云端
      backupMainAndUpload();
      Get.snackbar(
        '成功',
        '游戏更新成功',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (error) {
      Get.snackbar(
        '错误',
        '更新游戏失败: $error',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  // 删除游戏
  Future<void> deleteGame(String gameId) async {
    try {
      // 先找到游戏以获取封面路径
      final game = games.remove(gameId);

      if(game == null) {
        return;
      }

      // 删除封面图片
      if (game.coverImageFileName != null) {
        await GameStorage.deleteGameCover(game.coverImageFileName!);
      }

      await GameStorage.deleteGame(gameId);
      await loadGames(); // 重新加载列表

      // 触发自动上传到云端
      backupMainAndUpload();
      Get.snackbar(
        '成功',
        '游戏删除成功',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (error) {
      Get.snackbar(
        '错误',
        '删除游戏失败: $error',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  // 刷新游戏列表
  Future<void> refresh() async {
    await loadGames();
  }

  // 获取特定游戏
  Game? getGameById(String gameId) {
    try {
      return games[gameId];
    } catch (e) {
      return null;
    }
  }
}