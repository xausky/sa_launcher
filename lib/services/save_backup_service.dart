import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../models/save_backup.dart';
import 'app_data_service.dart';
import 'cloud_backup_service.dart';
import 'git_worktree_service.dart';

class SaveBackupService {
  // 创建存档备份
  static Future<SaveBackup?> createBackup(
    String gameId,
    String saveDataPath,
    String backupName,
  ) async {
    try {
      final saveDir = Directory(saveDataPath);
      if (!await saveDir.exists()) {
        throw Exception('存档路径不存在: $saveDataPath');
      }

      // 首先确保存档目录被 git worktree 管理
      if (!await GitWorktreeService.isWorktreeManaged(saveDataPath)) {
        // 创建 worktree
        final success = await GitWorktreeService.createWorktreeForGame(
          gameId,
          saveDataPath,
        );
        if (!success) {
          debugPrint('无法为游戏创建 git worktree，回退到传统备份方式');
          return await _createTraditionalBackup(
            gameId,
            saveDataPath,
            backupName,
          );
        }
      }

      final createdAt = DateTime.now();

      // 使用 git commit 创建备份
      final commitMessage = backupName == 'auto' ? 'auto backup' : backupName;
      final commitHash = await GitWorktreeService.createBackup(
        saveDataPath,
        commitMessage,
      );

      if (commitHash != null) {
        final backup = SaveBackup.fromGitCommit(
          gameId: gameId,
          saveDataPath: saveDataPath,
          commitHash: commitHash,
          message: commitMessage,
          createdAt: createdAt,
          author: 'SA Launcher',
        );

        debugPrint('创建 Git 备份成功: $commitHash');

        // 触发自动上传到云端
        CloudBackupService.autoUploadToCloud();

        return backup;
      } else {
        debugPrint('Git 备份创建失败，回退到传统备份方式');
        return await _createTraditionalBackup(gameId, saveDataPath, backupName);
      }
    } catch (e) {
      debugPrint('创建备份失败: $e');
      // 回退到传统备份方式
      return await _createTraditionalBackup(gameId, saveDataPath, backupName);
    }
  }

  // 传统的 ZIP 备份方式（作为回退方案）
  static Future<SaveBackup?> _createTraditionalBackup(
    String gameId,
    String saveDataPath,
    String backupName,
  ) async {
    try {
      final saveDir = Directory(saveDataPath);
      if (!await saveDir.exists()) {
        throw Exception('存档路径不存在: $saveDataPath');
      }

      // 获取游戏信息以确定游戏标题
      final games = await AppDataService.getAllGames();
      final game = games.firstWhere((g) => g.id == gameId);

      // 获取游戏的备份目录
      final gameBackupDir = await AppDataService.getGameBackupDirectory(
        game.title,
      );

      final createdAt = DateTime.now();
      final backupId = createdAt.millisecondsSinceEpoch.toString();

      // 使用新的文件名格式，包含创建时间
      final backupFileName = AppDataService.generateBackupFileName(
        backupName,
        createdAt,
      );
      final backupFilePath = path.join(gameBackupDir.path, backupFileName);

      // 创建ZIP压缩包
      final archive = Archive();
      await _addDirectoryToArchive(archive, saveDir, '');

      final bytes = ZipEncoder().encode(archive);
      if (bytes.isNotEmpty) {
        final backupFile = File(backupFilePath);
        await backupFile.writeAsBytes(bytes);

        final backup = SaveBackup(
          id: backupId,
          gameId: gameId,
          name: backupName,
          filePath: backupFilePath,
          createdAt: createdAt,
          fileSize: bytes.length,
          isGitBackup: false,
        );

        debugPrint('创建传统备份: $backupFilePath');

        // 触发自动上传到云端
        CloudBackupService.autoUploadToCloud();

        return backup;
      }

      return null;
    } catch (e) {
      debugPrint('创建传统备份失败: $e');
      return null;
    }
  }

  // 递归添加目录到压缩包
  static Future<void> _addDirectoryToArchive(
    Archive archive,
    Directory dir,
    String relativePath,
  ) async {
    await for (final entity in dir.list()) {
      final entityPath = path.relative(entity.path, from: dir.path);
      final archivePath = relativePath.isEmpty
          ? entityPath
          : path.join(relativePath, entityPath);

      if (entity is File) {
        final bytes = await entity.readAsBytes();
        final file = ArchiveFile(archivePath, bytes.length, bytes);
        archive.addFile(file);
      } else if (entity is Directory) {
        await _addDirectoryToArchive(archive, entity, archivePath);
      }
    }
  }

  // 应用存档备份
  static Future<bool> applyBackup(
    SaveBackup backup,
    String saveDataPath,
  ) async {
    try {
      // 如果是 Git 备份，使用 Git 方式应用
      if (backup.isGitBackup && backup.commitHash != null) {
        return await GitWorktreeService.applyBackup(
          saveDataPath,
          backup.commitHash!,
        );
      }

      // 传统 ZIP 备份方式
      final backupFile = File(backup.filePath);
      if (!await backupFile.exists()) {
        throw Exception('备份文件不存在: ${backup.filePath}');
      }

      final saveDir = Directory(saveDataPath);

      // 清空目标目录
      if (await saveDir.exists()) {
        await saveDir.delete(recursive: true);
      }
      await saveDir.create(recursive: true);

      // 解压备份文件
      final bytes = await backupFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name;
        final filePath = path.join(saveDataPath, filename);

        if (file.isFile) {
          final outFile = File(filePath);
          final outDir = Directory(path.dirname(filePath));
          if (!await outDir.exists()) {
            await outDir.create(recursive: true);
          }
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          final outDir = Directory(filePath);
          if (!await outDir.exists()) {
            await outDir.create(recursive: true);
          }
        }
      }

      return true;
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

      // 同时获取传统的 ZIP 备份
      final traditionalBackups = await AppDataService.getGameBackups(gameId);
      backups.addAll(traditionalBackups);

      // 按创建时间倒序排列
      backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint('获取游戏备份失败: $e');
      // 回退到传统方式
      return await AppDataService.getGameBackups(gameId);
    }

    return backups;
  }

  // 获取所有备份
  static Future<List<SaveBackup>> getAllBackups() async {
    return await AppDataService.getAllBackups();
  }

  // 删除备份
  static Future<bool> deleteBackup(
    SaveBackup backup, {
    bool autoUpload = true,
  }) async {
    try {
      // Git 备份无法单独删除（因为会影响历史），只能删除传统备份
      if (backup.isGitBackup) {
        debugPrint('Git 备份无法删除，请使用 git 命令管理');
        return false;
      }

      // 删除传统备份文件
      final backupFile = File(backup.filePath);
      if (await backupFile.exists()) {
        await backupFile.delete();
      }

      // 触发自动上传到云端
      if (autoUpload) {
        CloudBackupService.autoUploadToCloud();
      }

      return true;
    } catch (e) {
      debugPrint('删除备份失败: $e');
      return false;
    }
  }
}
