import 'dart:io';
import 'package:flutter/material.dart';
import '../models/game.dart';
import '../models/save_backup.dart';
import 'app_data_service.dart';
import 'save_backup_service.dart';

class AutoBackupService {
  static const String _autoBackupName = 'auto';

  // 检查游戏结束时是否需要创建自动备份
  static Future<void> checkAndCreateAutoBackup(Game game) async {
    try {
      // 检查是否启用了自动备份
      final autoBackupEnabled =
          await AppDataService.getSetting<bool>('autoBackupEnabled', false) ??
          false;
      if (!autoBackupEnabled) {
        return;
      }

      // 检查游戏是否配置了存档路径
      if (game.saveDataPath == null || game.saveDataPath!.isEmpty) {
        debugPrint('游戏 ${game.title} 未配置存档路径，跳过自动备份');
        return;
      }

      final saveDataDir = Directory(game.saveDataPath!);
      if (!await saveDataDir.exists()) {
        debugPrint('游戏 ${game.title} 存档路径不存在，跳过自动备份');
        return;
      }

      // 获取存档目录的最新文件修改时间
      final latestModifyTime = await _getLatestModifyTime(saveDataDir);
      if (latestModifyTime == null) {
        debugPrint('游戏 ${game.title} 存档目录为空，跳过自动备份');
        return;
      }

      // 获取当前的自动备份
      final currentAutoBackup = await _getCurrentAutoBackup(game.id);

      // 如果没有自动备份，或者存档有更新，则创建新的自动备份
      if (currentAutoBackup == null ||
          latestModifyTime.isAfter(currentAutoBackup.createdAt)) {
        debugPrint(
          'currentAutoBackup: ${currentAutoBackup?.createdAt} ${latestModifyTime}',
        );
        await _createAutoBackup(game, currentAutoBackup);
        debugPrint('为游戏 ${game.title} 创建了自动备份');
      } else {
        debugPrint('游戏 ${game.title} 存档未更新，跳过自动备份');
      }
    } catch (e) {
      debugPrint('检查自动备份失败: $e');
    }
  }

  // 获取存档目录中所有文件的最新修改时间
  static Future<DateTime?> _getLatestModifyTime(Directory directory) async {
    DateTime? latestTime;

    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          if (latestTime == null || stat.modified.isAfter(latestTime)) {
            latestTime = stat.modified;
          }
        }
      }
    } catch (e) {
      debugPrint('获取文件修改时间失败: $e');
    }

    return latestTime;
  }

  // 获取当前的自动备份
  static Future<SaveBackup?> _getCurrentAutoBackup(String gameId) async {
    try {
      final gameBackups = await AppDataService.getGameBackups(gameId);

      // 查找名为 "auto" 的备份
      for (final backup in gameBackups) {
        if (backup.name == _autoBackupName) {
          return backup;
        }
      }

      return null;
    } catch (e) {
      debugPrint('获取当前自动备份失败: $e');
      return null;
    }
  }

  // 创建自动备份
  static Future<void> _createAutoBackup(
    Game game,
    SaveBackup? oldAutoBackup,
  ) async {
    try {
      // 如果存在旧的自动备份，先删除它
      if (oldAutoBackup != null) {
        await SaveBackupService.deleteBackup(oldAutoBackup);
        debugPrint('删除旧的自动备份: ${oldAutoBackup.filePath}');
      }

      // 创建新的自动备份
      final backup = await SaveBackupService.createBackup(
        game.id,
        game.saveDataPath!,
        _autoBackupName,
      );

      if (backup != null) {
        debugPrint('自动备份创建成功: ${backup.filePath}');
      } else {
        debugPrint('自动备份创建失败');
      }
    } catch (e) {
      debugPrint('创建自动备份失败: $e');
    }
  }

  // 检查备份是否为自动备份
  static bool isAutoBackup(SaveBackup backup) {
    return backup.name == _autoBackupName;
  }

  // 获取排序后的备份列表（自动备份置顶）
  static List<SaveBackup> sortBackupsWithAutoFirst(List<SaveBackup> backups) {
    final autoBackups = <SaveBackup>[];
    final manualBackups = <SaveBackup>[];

    for (final backup in backups) {
      if (isAutoBackup(backup)) {
        autoBackups.add(backup);
      } else {
        manualBackups.add(backup);
      }
    }

    // 自动备份按时间倒序排列
    autoBackups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    // 手动备份按时间倒序排列
    manualBackups.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // 返回合并后的列表，自动备份在前
    return [...autoBackups, ...manualBackups];
  }

  // 删除游戏的自动备份
  static Future<void> deleteAutoBackup(String gameId) async {
    try {
      final autoBackup = await _getCurrentAutoBackup(gameId);
      if (autoBackup != null) {
        await SaveBackupService.deleteBackup(autoBackup);
        debugPrint('删除自动备份: ${autoBackup.filePath}');
      }
    } catch (e) {
      debugPrint('删除自动备份失败: $e');
    }
  }
}
