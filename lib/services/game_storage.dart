import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/game.dart';
import 'app_data_service.dart';

class GameStorage {
  static Future<List<Game>> getGames() async {
    return await AppDataService.getAllGames();
  }

  static Future<void> saveGames(List<Game> games) async {
    await AppDataService.saveGames(games);
  }

  static Future<void> addGame(Game game) async {
    await AppDataService.addGame(game);
  }

  static Future<void> updateGame(Game updatedGame) async {
    await AppDataService.updateGame(updatedGame);
  }

  static Future<void> deleteGame(String gameId) async {
    await AppDataService.deleteGame(gameId);
  }

  static Future<String> saveGameCover(String imagePath, String gameId) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw Exception('图片文件不存在');
    }

    // 获取游戏封面目录
    final coversDir = await AppDataService.getGameCoversDirectory();

    final extension = path.extension(imagePath);
    final fileName = '${DateTime.now().millisecondsSinceEpoch}$extension';
    final newPath = path.join(coversDir.path, fileName);

    await file.copy(newPath);
    return fileName; // 只返回文件名，不返回完整路径
  }

  static Future<void> deleteGameCover(String? coverFileName) async {
    try {
      if (coverFileName == null || coverFileName.isEmpty) {
        return;
      }

      final coversDir = await AppDataService.getGameCoversDirectory();
      final coverPath = path.join(coversDir.path, coverFileName);
      final file = File(coverPath);

      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // 忽略删除错误
      print('删除封面文件失败: $e');
    }
  }
}
