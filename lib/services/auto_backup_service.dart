import 'dart:io';
import 'package:flutter/material.dart';
import '../models/game.dart';
import '../models/save_backup.dart';
import 'app_data_service.dart';
import 'save_backup_service.dart';
import 'cloud_backup_service.dart';

// 备份检查结果
class BackupCheckResult {
  final bool shouldApply;
  final bool shouldSyncCloud;
  final DateTime? autoBackupTime;
  final DateTime? saveDataTime;
  final String reason;

  BackupCheckResult({
    required this.shouldApply,
    required this.shouldSyncCloud,
    this.autoBackupTime,
    this.saveDataTime,
    required this.reason,
  });
}

class AutoBackupService {
  static const String _autoBackupName = 'auto';

  // 检查游戏结束时是否需要创建自动备份
  // 返回值：true 表示创建了备份，false 表示跳过了备份，null 表示出错或未启用
  static Future<bool?> checkAndCreateAutoBackup(Game game) async {
    try {
      // 检查是否启用了自动备份
      final autoBackupEnabled =
          await AppDataService.getSetting<bool>('autoBackupEnabled', false) ??
          false;
      if (!autoBackupEnabled) {
        return null; // 未启用自动备份
      }

      // 检查游戏是否配置了存档路径
      if (game.saveDataPath == null || game.saveDataPath!.isEmpty) {
        debugPrint('游戏 ${game.title} 未配置存档路径，跳过自动备份');
        return null;
      }

      final saveDataDir = Directory(game.saveDataPath!);
      if (!await saveDataDir.exists()) {
        debugPrint('游戏 ${game.title} 存档路径不存在，跳过自动备份');
        return null;
      }

      // 获取存档目录的最新文件修改时间
      final latestModifyTime = await _getLatestModifyTime(saveDataDir);
      if (latestModifyTime == null) {
        debugPrint('游戏 ${game.title} 存档目录为空，跳过自动备份');
        return null;
      }

      // 获取最新的自动备份
      final latestAutoBackup = await _getLatestAutoBackup(game.id);

      // 如果没有自动备份，或者存档有更新，则创建新的自动备份
      if (latestAutoBackup == null ||
          latestModifyTime.isAfter(latestAutoBackup.createdAt)) {
        debugPrint(
          'latestAutoBackup: ${latestAutoBackup?.createdAt} $latestModifyTime',
        );
        await _createAutoBackup(game);
        debugPrint('为游戏 ${game.title} 创建了自动备份');
        return true; // 成功创建了备份
      } else {
        debugPrint('未检测到存档目录变更，跳过本次自动备份');
        return false; // 跳过了备份
      }
    } catch (e) {
      debugPrint('检查自动备份失败: $e');
      return null; // 出错了
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

  // 获取游戏的所有自动备份
  static Future<List<SaveBackup>> _getAutoBackups(String gameId) async {
    try {
      final gameBackups = await AppDataService.getGameBackups(gameId);

      // 查找所有自动备份（名称为 "auto" 的备份）
      return gameBackups
          .where((backup) => backup.name == _autoBackupName)
          .toList();
    } catch (e) {
      debugPrint('获取自动备份列表失败: $e');
      return [];
    }
  }

  // 获取最新的自动备份
  static Future<SaveBackup?> _getLatestAutoBackup(String gameId) async {
    try {
      final autoBackups = await _getAutoBackups(gameId);
      if (autoBackups.isEmpty) return null;

      // 按创建时间倒序排列，返回最新的
      autoBackups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return autoBackups.first;
    } catch (e) {
      debugPrint('获取最新自动备份失败: $e');
      return null;
    }
  }

  // 创建自动备份
  static Future<void> _createAutoBackup(Game game) async {
    try {
      // 获取配置的自动备份数量
      final maxBackupCount =
          await AppDataService.getSetting<int>('autoBackupCount', 3) ?? 3;

      // 创建新的自动备份
      final backup = await SaveBackupService.createBackup(
        game.id,
        game.saveDataPath!,
        _autoBackupName,
      );

      if (backup != null) {
        debugPrint('自动备份创建成功: ${backup.filePath}');

        // 检查是否需要删除旧备份
        await _cleanupOldAutoBackups(game.id, maxBackupCount);
      } else {
        debugPrint('自动备份创建失败');
      }
    } catch (e) {
      debugPrint('创建自动备份失败: $e');
    }
  }

  // 清理旧的自动备份，保持指定数量
  static Future<void> _cleanupOldAutoBackups(
    String gameId,
    int maxCount,
  ) async {
    try {
      final autoBackups = await _getAutoBackups(gameId);

      if (autoBackups.length <= maxCount) {
        return; // 数量未超出，无需清理
      }

      // 按创建时间倒序排列
      autoBackups.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // 删除超出数量的旧备份
      for (int i = maxCount; i < autoBackups.length; i++) {
        final oldBackup = autoBackups[i];
        await SaveBackupService.deleteBackup(oldBackup, autoUpload: false);
        debugPrint('删除旧的自动备份: ${oldBackup.filePath}');
      }

      debugPrint('清理完成，保留了 $maxCount 个最新的自动备份');
    } catch (e) {
      debugPrint('清理旧自动备份失败: $e');
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

  // 删除游戏的所有自动备份
  static Future<void> deleteAutoBackups(String gameId) async {
    try {
      final autoBackups = await _getAutoBackups(gameId);
      for (final backup in autoBackups) {
        await SaveBackupService.deleteBackup(backup);
        debugPrint('删除自动备份: ${backup.filePath}');
      }
    } catch (e) {
      debugPrint('删除自动备份失败: $e');
    }
  }

  // 详细检查游戏启动前是否需要应用自动备份
  static Future<BackupCheckResult> checkAutoBackupBeforeLaunch(
    Game game,
  ) async {
    try {
      // 检查云端是否有更新（在检查本地自动备份之前）
      final hasCloudUpdates = await CloudBackupService.hasCloudUpdates();

      // 检查游戏是否配置了存档路径
      if (game.saveDataPath == null || game.saveDataPath!.isEmpty) {
        return BackupCheckResult(
          shouldApply: false,
          shouldSyncCloud: hasCloudUpdates,
          reason: '未配置存档路径',
        );
      }

      // 获取最新的自动备份
      final autoBackup = await _getLatestAutoBackup(game.id);
      if (autoBackup == null) {
        return BackupCheckResult(
          shouldApply: false,
          shouldSyncCloud: hasCloudUpdates,
          reason: '没有可用的自动备份',
        );
      }

      final saveDataDir = Directory(game.saveDataPath!);

      // 如果存档目录不存在，说明需要应用自动备份
      if (!await saveDataDir.exists()) {
        debugPrint('存档目录不存在，建议应用自动备份: ${game.title}');
        return BackupCheckResult(
          shouldApply: true,
          autoBackupTime: autoBackup.createdAt,
          saveDataTime: null,
          shouldSyncCloud: hasCloudUpdates,
          reason: '存档目录不存在',
        );
      }

      // 获取存档目录的最新文件修改时间
      final latestModifyTime = await _getLatestModifyTime(saveDataDir);

      // 如果存档目录为空，建议应用自动备份
      if (latestModifyTime == null) {
        debugPrint('存档目录为空，建议应用自动备份: ${game.title}');
        return BackupCheckResult(
          shouldApply: true,
          autoBackupTime: autoBackup.createdAt,
          saveDataTime: null,
          shouldSyncCloud: hasCloudUpdates,
          reason: '存档目录为空',
        );
      }

      // 计算时间差（以分钟为单位）
      final timeDifference = autoBackup.createdAt.difference(latestModifyTime);
      final minutesDifference = timeDifference.inMinutes.abs();

      // 只有当自动备份比存档目录更新且相差超过1分钟时，才建议应用
      if (autoBackup.createdAt.isAfter(latestModifyTime) &&
          minutesDifference > 1) {
        debugPrint('自动备份比当前存档更新超过1分钟，建议应用: ${game.title}');
        debugPrint('自动备份时间: ${autoBackup.createdAt}');
        debugPrint('存档最新时间: $latestModifyTime');
        debugPrint('时间差: ${minutesDifference}分钟');

        return BackupCheckResult(
          shouldApply: true,
          autoBackupTime: autoBackup.createdAt,
          saveDataTime: latestModifyTime,
          shouldSyncCloud: hasCloudUpdates,
          reason: '自动备份更新（相差${minutesDifference}分钟）',
        );
      }

      return BackupCheckResult(
        shouldApply: false,
        autoBackupTime: autoBackup.createdAt,
        saveDataTime: latestModifyTime,
        shouldSyncCloud: hasCloudUpdates,
        reason: '当前存档已是最新',
      );
    } catch (e) {
      debugPrint('检查启动前备份应用失败: $e');
      return BackupCheckResult(
        shouldApply: false,
        shouldSyncCloud: false,
        reason: '检查失败: $e',
      );
    }
  }

  // 应用最新的自动备份
  static Future<bool> applyAutoBackup(Game game) async {
    try {
      final autoBackup = await _getLatestAutoBackup(game.id);
      if (autoBackup == null ||
          game.saveDataPath == null ||
          game.saveDataPath!.isEmpty) {
        return false;
      }

      final success = await SaveBackupService.applyBackup(
        autoBackup,
        game.saveDataPath!,
      );
      if (success) {
        debugPrint('自动备份应用成功: ${game.title}');
      } else {
        debugPrint('自动备份应用失败: ${game.title}');
      }
      return success;
    } catch (e) {
      debugPrint('应用自动备份失败: $e');
      return false;
    }
  }
}
