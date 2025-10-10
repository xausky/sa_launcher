import 'dart:io';
import 'package:flutter/material.dart';
import '../models/save_backup.dart';
import 'app_data_service.dart';
import 'cloud_backup_service.dart';
import 'git_worktree_service.dart';

class SaveBackupService {
  // 创建存档备份
  // 返回值：成功时返回 SaveBackup 对象，没有变更时返回 'NO_CHANGES'，失败时返回 null
  static Future<dynamic> createBackup(
    String gameId,
    String saveDataPath,
    String backupName,
  ) async {
    try {
      final saveDir = Directory(saveDataPath);
      if (!await saveDir.exists()) {
        throw Exception('存档路径不存在: $saveDataPath');
      }

      // 确保存档目录被 git worktree 管理
      if (!await GitWorktreeService.isWorktreeManaged(saveDataPath)) {
        // 创建 worktree
        final success = await GitWorktreeService.createWorktreeForGame(
          gameId,
          saveDataPath,
        );
        if (!success) {
          debugPrint('无法为游戏创建 git worktree');
          return null;
        }
      }

      final createdAt = DateTime.now();

      // 使用 git commit 创建备份
      final commitMessage = backupName == 'auto' ? 'auto-backup' : backupName;
      final commitHash = await GitWorktreeService.createBackup(
        saveDataPath,
        commitMessage,
      );

      if (commitHash == 'NO_CHANGES') {
        debugPrint('存档没有变更，无需创建备份');
        return 'NO_CHANGES';
      } else if (commitHash != null) {
        final backup = SaveBackup.fromGitCommit(
          gameId: gameId,
          saveDataPath: saveDataPath,
          commitHash: commitHash,
          message: commitMessage,
          createdAt: createdAt,
          author: 'SA Launcher',
        );

        debugPrint('创建 Git 备份成功: $commitHash');

        // 触发自动推送到 Git 远程仓库
        CloudBackupService.autoUploadToCloud();

        return backup;
      } else {
        debugPrint('Git 备份创建失败');
        return null;
      }
    } catch (e) {
      debugPrint('创建备份失败: $e');
      return null;
    }
  }

  // 应用存档备份
  static Future<bool> applyBackup(
    SaveBackup backup,
    String saveDataPath,
  ) async {
    try {
      // 应用 Git 备份
      return await GitWorktreeService.applyBackup(
        saveDataPath,
        backup.commitHash,
      );
    } catch (e) {
      debugPrint('应用备份失败: $e');
      return false;
    }
  }

  // 获取游戏的所有备份
  static Future<List<SaveBackup>> getGameBackups(String gameId) async {
    final backups = <SaveBackup>[];

    try {
      // 获取游戏信息
      final games = await AppDataService.getAllGames();
      final game = games.firstWhere((g) => g.id == gameId);

      // 如果游戏有存档路径且被 git worktree 管理，获取 git 备份
      if (game.saveDataPath != null &&
          await GitWorktreeService.isWorktreeManaged(game.saveDataPath!)) {
        final gitBackups = await GitWorktreeService.getBackupList(
          game.saveDataPath!,
        );

        for (final gitBackup in gitBackups) {
          final backup = SaveBackup.fromGitCommit(
            gameId: gameId,
            saveDataPath: game.saveDataPath!,
            commitHash: gitBackup['hash'],
            message: gitBackup['message'],
            createdAt: gitBackup['createdAt'],
            author: gitBackup['author'],
          );
          backups.add(backup);
        }
      }

      // 按创建时间倒序排列
      backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint('获取游戏备份失败: $e');
    }

    return backups;
  }

  // 获取所有备份
  static Future<List<SaveBackup>> getAllBackups() async {
    final allBackups = <SaveBackup>[];

    try {
      final games = await AppDataService.getAllGames();

      for (final game in games) {
        final gameBackups = await getGameBackups(game.id);
        allBackups.addAll(gameBackups);
      }

      // 按创建时间倒序排列
      allBackups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint('获取所有备份失败: $e');
    }

    return allBackups;
  }

  // 删除备份
  static Future<bool> deleteBackup(
    SaveBackup backup, {
    bool autoUpload = true,
  }) async {
    try {
      // Git 备份无法单独删除（因为会影响历史）
      debugPrint('Git 备份无法删除，请使用 git 命令管理历史记录');
      return false;
    } catch (e) {
      debugPrint('删除备份失败: $e');
      return false;
    }
  }
}
