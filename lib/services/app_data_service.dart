import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../models/game.dart';
import '../models/save_backup.dart';
import 'cloud_sync_config_service.dart';

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
      print('获取游戏列表失败: $e');
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
      final gamePaths = <String, String>{};
      for (final game in games) {
        gamePaths['${game.id}_executablePath'] = game.executablePath;
        if (game.saveDataPath != null) {
          gamePaths['${game.id}_saveDataPath'] = game.saveDataPath!;
        }
      }
      await CloudSyncConfigService.setGamePaths(gamePaths);
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

    // 同时删除本地路径数据
    await CloudSyncConfigService.removeGamePaths(gameId);
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
                final fileName = path.basename(backupFile.path);
                final stat = await backupFile.stat();

                // 解码文件名获取备份名称和创建时间
                final decodedInfo = decodeBackupFileName(fileName);
                final backupName = decodedInfo['name'] as String;
                final createdAt =
                    (decodedInfo['createdAt'] as DateTime?) ?? stat.modified;

                // 生成备份ID（使用创建时间的毫秒数）
                final backupId = createdAt.millisecondsSinceEpoch.toString();

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
                    createdAt: createdAt,
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

  // 生成备份文件名（格式：<备份名base64Url去除=>-<备份创建时间>.zip）
  static String generateBackupFileName(String backupName, DateTime createdAt) {
    if (backupName == 'auto') {
      // 自动备份格式：auto-<备份创建时间>.zip
      final timeString = _formatBackupTime(createdAt);
      return 'auto-$timeString.zip';
    } else {
      // 普通备份格式：<备份名base64Url去除=>-<备份创建时间>.zip
      final encodedName = base64UrlEncode(
        utf8.encode(backupName),
      ).replaceAll('=', '');
      final timeString = _formatBackupTime(createdAt);
      return '$encodedName-$timeString.zip';
    }
  }

  // 格式化备份时间为文件名格式（yyyyMMddHHmmss）
  static String _formatBackupTime(DateTime dateTime) {
    return '${dateTime.year}'
        '${dateTime.month.toString().padLeft(2, '0')}'
        '${dateTime.day.toString().padLeft(2, '0')}'
        '${dateTime.hour.toString().padLeft(2, '0')}'
        '${dateTime.minute.toString().padLeft(2, '0')}'
        '${dateTime.second.toString().padLeft(2, '0')}';
  }

  // 从备份文件名解码备份名称和创建时间
  static Map<String, dynamic> decodeBackupFileName(String fileName) {
    try {
      // 移除 .zip 扩展名
      final nameWithoutExt = fileName.replaceAll('.zip', '');

      if (nameWithoutExt.startsWith('auto-')) {
        // 自动备份格式：auto-<时间>
        final timeString = nameWithoutExt.substring(5); // 移除 'auto-'
        final createdAt = _parseBackupTime(timeString);
        return {'name': 'auto', 'createdAt': createdAt};
      } else {
        // 普通备份格式：<base64名称>-<时间>
        final lastDashIndex = nameWithoutExt.lastIndexOf('-');
        if (lastDashIndex == -1 || lastDashIndex == nameWithoutExt.length - 1) {
          // 如果没有找到分隔符，可能是旧格式，尝试直接解码
          final bytes = base64Decode(base64.normalize(nameWithoutExt));
          return {
            'name': utf8.decode(bytes),
            'createdAt': null, // 旧格式没有时间信息
          };
        }

        final encodedName = nameWithoutExt.substring(0, lastDashIndex);
        final timeString = nameWithoutExt.substring(lastDashIndex + 1);

        final bytes = base64Decode(base64.normalize(encodedName));
        final backupName = utf8.decode(bytes);
        final createdAt = _parseBackupTime(timeString);

        return {'name': backupName, 'createdAt': createdAt};
      }
    } catch (e) {
      print('解码备份文件名失败: $e');
      return {'name': fileName, 'createdAt': null};
    }
  }

  // 解析备份时间字符串（yyyyMMddHHmmss）
  static DateTime? _parseBackupTime(String timeString) {
    try {
      if (timeString.length != 14) return null;

      final year = int.parse(timeString.substring(0, 4));
      final month = int.parse(timeString.substring(4, 6));
      final day = int.parse(timeString.substring(6, 8));
      final hour = int.parse(timeString.substring(8, 10));
      final minute = int.parse(timeString.substring(10, 12));
      final second = int.parse(timeString.substring(12, 14));

      return DateTime(year, month, day, hour, minute, second);
    } catch (e) {
      print('解析备份时间失败: $e');
      return null;
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
