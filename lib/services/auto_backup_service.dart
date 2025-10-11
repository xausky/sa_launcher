import 'dart:io';
import 'package:flutter/material.dart';
import '../models/game.dart';
import '../models/save_backup.dart';
import 'app_data_service.dart';
import 'save_backup_service.dart';
import 'cloud_backup_service.dart';
import 'git_worktree_service.dart';
import 'logging_service.dart';

// 备份检查结果
class BackupCheckResult {
  final bool shouldApply;
  final DateTime? autoBackupTime;
  final DateTime? saveDataTime;
  final String reason;
  final bool hasGitUpdates; // 存档目录是否有 git 更新
  final bool shouldPullSaveData; // 是否需要拉取存档目录的 git 更新

  BackupCheckResult({
    required this.shouldApply,
    this.autoBackupTime,
    this.saveDataTime,
    required this.reason,
    this.hasGitUpdates = false,
    this.shouldPullSaveData = false,
  });
}

class AutoBackupService {
  static const String _autoBackupName = 'auto';

  // 检查游戏结束时是否需要创建自动备份
  // 返回值：true 表示创建了备份，false 表示跳过了备份，null 表示出错或未启用
  static Future<bool?> checkAndCreateAutoBackup(Game game) async {
    try {
      // 检查游戏是否配置了存档路径
      if (game.saveDataPath == null || game.saveDataPath!.isEmpty) {
        LoggingService.instance.info('游戏 ${game.title} 未配置存档路径，跳过自动备份');
        return null;
      }

      final saveDataDir = Directory(game.saveDataPath!);
      if (!await saveDataDir.exists()) {
        LoggingService.instance.info('游戏 ${game.title} 存档路径不存在，跳过自动备份');
        return null;
      }

      // 如果没有自动备份，或者存档有更新，则创建新的自动备份
      final backup = await SaveBackupService.createBackup(
        game.id,
        game.saveDataPath!,
        _autoBackupName,
      );
      if(backup == null) {
        return null;
      }
      if('NO_CHANGES' == backup) {
        return false;
      }
      return true;
    } catch (e) {
      LoggingService.instance.logError('检查自动备份失败: $e', e);
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
      LoggingService.instance.logError('获取文件修改时间失败: $e', e);
    }

    return latestTime;
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

  // 详细检查游戏启动前是否需要应用自动备份
  static Future<BackupCheckResult> checkAutoBackupBeforeLaunch(
    Game game,
      bool? useRemote
  ) async {
    try {
      // 首先执行启动前的 git 同步检查
      if(game.saveDataPath == null) {
        return BackupCheckResult(shouldApply: false, reason: '未配置存档路径');
      }

      final remote = await GitWorktreeService.getRemoteUrl(game.saveDataPath!);

      if (remote == null) {
        return BackupCheckResult(shouldApply: false, reason: '未配置远程存档路径');
      }

      final pull = await GitWorktreeService.pull(game.saveDataPath!, game.id, useRemote);

      if (pull == OperateResultType.success) {
        return BackupCheckResult(
          shouldApply: false,
          reason: '无冲突',
        );
      }
      if (pull == OperateResultType.conflict) {
        return BackupCheckResult(
          shouldApply: true,
          reason: '存在冲突',
        );
      }
      return BackupCheckResult(
        shouldApply: false,
        reason: '出现错误',
      );
    } catch (e) {
      LoggingService.instance.logError('检查启动前备份应用失败: $e', e);
      return BackupCheckResult(
        shouldApply: false,
        reason: '检查失败: $e',
        hasGitUpdates: false,
        shouldPullSaveData: false,
      );
    }
  }
}
