import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../models/game.dart';
import '../models/save_backup.dart';

class AppDataService {
  static const String _appJsonFileName = 'app.json';
  static const String _backupsDirName = 'backups';
  static const String _gameCoversDir = 'covers';

  // 获取应用数据目录
  static Future<Directory> getAppDataDirectory() async {
    final appSupportDir = await getApplicationSupportDirectory();
    if (!await appSupportDir.exists()) {
      await appSupportDir.create(recursive: true);
    }
    return appSupportDir;
  }

  // 获取app.json文件路径
  static Future<File> _getAppJsonFile() async {
    final appDataDir = await getAppDataDirectory();
    return File(path.join(appDataDir.path, _appJsonFileName));
  }

  // 获取备份目录
  static Future<Directory> getBackupsDirectory() async {
    final appDataDir = await getAppDataDirectory();
    final backupsDir = Directory(path.join(appDataDir.path, _backupsDirName));
    if (!await backupsDir.exists()) {
      await backupsDir.create(recursive: true);
    }
    return backupsDir;
  }

  // 获取游戏封面目录
  static Future<Directory> getGameCoversDirectory() async {
    final appDataDir = await getAppDataDirectory();
    final coversDir = Directory(path.join(appDataDir.path, _gameCoversDir));
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }
    return coversDir;
  }

  // 获取游戏的备份目录
  static Future<Directory> getGameBackupDirectory(String gameTitle) async {
    final backupsDir = await getBackupsDirectory();
    final gameBackupDir = Directory(path.join(backupsDir.path, gameTitle));
    if (!await gameBackupDir.exists()) {
      await gameBackupDir.create(recursive: true);
    }
    return gameBackupDir;
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
      print('读取app.json失败: $e');
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
      print('写入app.json失败: $e');
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

      return gamesJson
          .map((json) => Game.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('获取游戏列表失败: $e');
      return [];
    }
  }

  // 保存游戏列表
  static Future<void> saveGames(List<Game> games) async {
    try {
      final appData = await readAppData();
      appData['games'] = games.map((game) => game.toJson()).toList();
      await writeAppData(appData);
    } catch (e) {
      print('保存游戏列表失败: $e');
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
  }

  // 从文件系统扫描获取所有备份
  static Future<List<SaveBackup>> getAllBackups() async {
    try {
      final backupsDir = await getBackupsDirectory();
      final backups = <SaveBackup>[];

      // 遍历所有游戏目录
      await for (final gameDir in backupsDir.list()) {
        if (gameDir is Directory) {
          final gameTitle = path.basename(gameDir.path);

          // 遍历游戏目录下的所有zip文件
          await for (final backupFile in gameDir.list()) {
            if (backupFile is File && backupFile.path.endsWith('.zip')) {
              try {
                final fileName = path.basenameWithoutExtension(backupFile.path);

                // 对于 auto.zip 文件，直接使用 'auto' 作为备份名称
                final backupName = fileName == 'auto'
                    ? 'auto'
                    : decodeBackupFileName(fileName);
                final stat = await backupFile.stat();

                // 从文件名生成备份ID（使用文件修改时间的毫秒数）
                final backupId = stat.modified.millisecondsSinceEpoch
                    .toString();

                // 需要根据游戏标题找到对应的游戏ID
                final games = await getAllGames();
                Game? game;
                try {
                  game = games.firstWhere((g) => g.title == gameTitle);
                } catch (e) {
                  game = null;
                }

                if (game != null) {
                  final backup = SaveBackup(
                    id: backupId,
                    gameId: game.id,
                    name: backupName,
                    filePath: backupFile.path,
                    createdAt: stat.modified,
                    fileSize: stat.size,
                  );
                  backups.add(backup);
                }
              } catch (e) {
                print('解析备份文件失败: ${backupFile.path}, $e');
              }
            }
          }
        }
      }

      // 按创建时间倒序排列
      backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return backups;
    } catch (e) {
      print('扫描备份目录失败: $e');
      return [];
    }
  }

  // 获取游戏的所有备份
  static Future<List<SaveBackup>> getGameBackups(String gameId) async {
    final allBackups = await getAllBackups();
    return allBackups.where((backup) => backup.gameId == gameId).toList();
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

  // 生成备份文件名（使用base64编码的备份名称）
  static String generateBackupFileName(String backupName) {
    return base64UrlEncode(utf8.encode(backupName));
  }

  // 从备份文件名解码备份名称
  static String decodeBackupFileName(String fileName) {
    try {
      final bytes = base64Decode(fileName.replaceAll('.zip', ''));
      return utf8.decode(bytes);
    } catch (e) {
      print('解码备份文件名失败: $e');
      return fileName;
    }
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
