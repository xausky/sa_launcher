import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import '../models/game.dart';

class GameStorage {
  static const String _gamesKey = 'games';
  static const String _coversDir = 'game_covers';

  static Future<List<Game>> getGames() async {
    final prefs = await SharedPreferences.getInstance();
    final gamesJson = prefs.getString(_gamesKey);

    if (gamesJson == null) {
      return [];
    }

    final gamesList = jsonDecode(gamesJson) as List;
    return gamesList.map((json) => Game.fromJson(json)).toList();
  }

  static Future<void> saveGames(List<Game> games) async {
    final prefs = await SharedPreferences.getInstance();
    final gamesJson = jsonEncode(games.map((game) => game.toJson()).toList());
    await prefs.setString(_gamesKey, gamesJson);
  }

  static Future<void> addGame(Game game) async {
    final games = await getGames();
    games.add(game);
    await saveGames(games);
  }

  static Future<void> updateGame(Game updatedGame) async {
    final games = await getGames();
    final index = games.indexWhere((game) => game.id == updatedGame.id);
    if (index != -1) {
      games[index] = updatedGame;
      await saveGames(games);
    }
  }

  static Future<void> deleteGame(String gameId) async {
    final games = await getGames();
    games.removeWhere((game) => game.id == gameId);
    await saveGames(games);
  }

  static Future<String> saveGameCover(String imagePath, String gameId) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw Exception('图片文件不存在');
    }

    // 获取应用文档目录
    final directory = Directory.systemTemp; // 临时使用系统临时目录
    final coversDir = Directory(path.join(directory.path, _coversDir));

    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }

    final extension = path.extension(imagePath);
    final newPath = path.join(coversDir.path, '$gameId$extension');

    await file.copy(newPath);
    return newPath;
  }

  static Future<void> deleteGameCover(String coverPath) async {
    try {
      final file = File(coverPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // 忽略删除错误
    }
  }
}
