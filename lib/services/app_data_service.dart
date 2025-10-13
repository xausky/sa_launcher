import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../models/game.dart';
import 'cloud_sync_config_service.dart';
import 'logging_service.dart';
import 'restic_service.dart';

class AppDataService {
  static const String _appJsonFileName = 'app.json';

  // 获取应用数据目录
  static Future<Directory> getAppDataDirectory() async {
    final appSupportDir = await getApplicationSupportDirectory();
    if (!await appSupportDir.exists()) {
      await appSupportDir.create(recursive: true);
    }
    return appSupportDir;
  }

  // 获取app.json文件路径（新位置：main目录）
  static Future<File> _getAppJsonFile() async {
    final mainDir = await ResticService.getMainDataDirectory();
    return File(path.join(mainDir.path, _appJsonFileName));
  }

  // 获取游戏封面目录（新位置：main目录）
  static Future<Directory> getGameCoversDirectory() async {
    return await ResticService.getNewGameCoversDirectory();
  }

  // 读取app.json数据
  static Future<Map<String, dynamic>> readAppData() async {
    try {
      final appJsonFile = await _getAppJsonFile();
      if (await appJsonFile.exists()) {
        final jsonString = await appJsonFile.readAsString();
        return jsonDecode(jsonString) as Map<String, dynamic>;
      }
    } catch (e) {
      LoggingService.instance.info('读取app.json失败: $e');
    }
    return _getDefaultAppData();
  }

  // 写入app.json数据
  static Future<void> writeAppData(Map<String, dynamic> data) async {
    try {
      final appJsonFile = await _getAppJsonFile();
      final jsonString = const JsonEncoder.withIndent('  ').convert(data);
      await appJsonFile.writeAsString(jsonString);
    } catch (e) {
      LoggingService.instance.info('写入app.json失败: $e');
    }
  }

  // 获取默认app数据结构
  static Map<String, dynamic> _getDefaultAppData() {
    return {
      'version': '1.0.0',
      'games': <Map<String, dynamic>>[],
      'settings': <String, dynamic>{},
    };
  }

  // 获取所有游戏
  static Future<List<Game>> getAllGames() async {
    try {
      final appData = await readAppData();
      final gamesJson = appData['games'] as List<dynamic>? ?? [];

      // 获取本地路径数据
      final gamePaths = await CloudSyncConfigService.getGamePaths();

      return gamesJson.map((json) {
        final gameData = json as Map<String, dynamic>;
        // 如果JSON中没有路径信息，从本地路径数据中获取
        if (!gameData.containsKey('executablePath')) {
          return Game.fromCloudJsonWithLocalPaths(gameData, gamePaths);
        } else {
          // 如果JSON中有路径信息（旧格式），正常解析
          return Game.fromJson(gameData);
        }
      }).toList();
    } catch (e) {
      LoggingService.instance.info('获取游戏列表失败: $e');
      return [];
    }
  }

  // 保存游戏列表
  static Future<void> saveGames(List<Game> games) async {
    try {
      final appData = await readAppData();
      // 只保存云端数据（不包含路径）
      appData['games'] = games.map((game) => game.toJson()).toList();
      await writeAppData(appData);

      // 分别保存路径数据到本地
      final gamePaths = <String, Map<String, String>>{};
      for (final game in games) {
        final gamePathData = <String, String>{
          'executablePath': game.executablePath,
        };
        if (game.saveDataPath != null) {
          gamePathData['saveDataPath'] = game.saveDataPath!;
        }
        gamePaths[game.id] = gamePathData;
      }
      await CloudSyncConfigService.setGamePaths(gamePaths);
    } catch (e) {
      LoggingService.instance.info('保存游戏列表失败: $e');
    }
  }

  // 添加游戏
  static Future<void> addGame(Game game) async {
    final games = await getAllGames();
    games.add(game);
    await saveGames(games);
  }

  // 更新游戏
  static Future<void> updateGame(Game game) async {
    final games = await getAllGames();
    final index = games.indexWhere((g) => g.id == game.id);
    if (index != -1) {
      games[index] = game;
      await saveGames(games);
    }
  }

  // 删除游戏
  static Future<void> deleteGame(String gameId) async {
    final games = await getAllGames();
    games.removeWhere((game) => game.id == gameId);
    await saveGames(games);

    // 同时删除本地路径数据
    await CloudSyncConfigService.removeGamePaths(gameId);
  }

  // 获取设置
  static Future<Map<String, dynamic>> getSettings() async {
    final appData = await readAppData();
    return appData['settings'] as Map<String, dynamic>? ?? <String, dynamic>{};
  }

  // 更新设置
  static Future<void> updateSettings(Map<String, dynamic> newSettings) async {
    final appData = await readAppData();
    final currentSettings =
        appData['settings'] as Map<String, dynamic>? ?? <String, dynamic>{};
    currentSettings.addAll(newSettings);
    appData['settings'] = currentSettings;
    await writeAppData(appData);
  }

  // 获取特定设置值
  static Future<T?> getSetting<T>(String key, [T? defaultValue]) async {
    final settings = await getSettings();
    return settings[key] as T? ?? defaultValue;
  }

  // 根据文件名获取完整的封面路径
  static Future<String?> getGameCoverPath(String? coverFileName) async {
    if (coverFileName == null || coverFileName.isEmpty) {
      return null;
    }

    final coversDir = await getGameCoversDirectory();
    return path.join(coversDir.path, coverFileName);
  }
}