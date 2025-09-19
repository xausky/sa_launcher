import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../models/save_backup.dart';
import 'app_data_service.dart';

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
      if (bytes != null) {
        final backupFile = File(backupFilePath);
        await backupFile.writeAsBytes(bytes);

        final backup = SaveBackup(
          id: backupId,
          gameId: gameId,
          name: backupName,
          filePath: backupFilePath,
          createdAt: createdAt,
          fileSize: bytes.length,
        );

        debugPrint('创建备份: $backupFilePath');

        return backup;
      }

      return null;
    } catch (e) {
      print('创建备份失败: $e');
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
      print('应用备份失败: $e');
      return false;
    }
  }

  // 获取游戏的所有备份
  static Future<List<SaveBackup>> getGameBackups(String gameId) async {
    return await AppDataService.getGameBackups(gameId);
  }

  // 获取所有备份
  static Future<List<SaveBackup>> getAllBackups() async {
    return await AppDataService.getAllBackups();
  }

  // 删除备份
  static Future<bool> deleteBackup(SaveBackup backup) async {
    try {
      // 删除备份文件
      final backupFile = File(backup.filePath);
      if (await backupFile.exists()) {
        await backupFile.delete();
      }

      return true;
    } catch (e) {
      print('删除备份失败: $e');
      return false;
    }
  }
}
