import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/save_backup.dart';

class SaveBackupService {
  static const String _backupsKey = 'save_backups';

  // 获取应用程序文档目录下的备份文件夹
  static Future<Directory> _getBackupDirectory() async {
    final appDir = Directory.current;
    final backupDir = Directory(path.join(appDir.path, 'backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

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

      final backupDir = await _getBackupDirectory();
      final backupId = DateTime.now().millisecondsSinceEpoch.toString();
      final backupFileName = '${gameId}_${backupId}_$backupName.zip';
      final backupFilePath = path.join(backupDir.path, backupFileName);

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
          createdAt: DateTime.now(),
          fileSize: bytes.length,
        );

        await _saveBackupToStorage(backup);
        debugPrint('创建备份: ${backupFilePath}');

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
    final allBackups = await getAllBackups();
    return allBackups.where((backup) => backup.gameId == gameId).toList();
  }

  // 获取所有备份
  static Future<List<SaveBackup>> getAllBackups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backupsJson = prefs.getStringList(_backupsKey) ?? [];

      final backups = <SaveBackup>[];
      for (final jsonString in backupsJson) {
        try {
          final json = jsonDecode(jsonString);
          final backup = SaveBackup.fromJson(json);

          // 检查备份文件是否还存在
          if (await File(backup.filePath).exists()) {
            backups.add(backup);
          }
        } catch (e) {
          print('解析备份数据失败: $e');
        }
      }

      // 按创建时间倒序排列
      backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return backups;
    } catch (e) {
      print('加载备份列表失败: $e');
      return [];
    }
  }

  // 删除备份
  static Future<bool> deleteBackup(SaveBackup backup) async {
    try {
      // 删除备份文件
      final backupFile = File(backup.filePath);
      if (await backupFile.exists()) {
        await backupFile.delete();
      }

      // 从存储中移除记录
      final allBackups = await getAllBackups();
      allBackups.removeWhere((b) => b.id == backup.id);
      await _saveAllBackupsToStorage(allBackups);

      return true;
    } catch (e) {
      print('删除备份失败: $e');
      return false;
    }
  }

  // 保存单个备份到存储
  static Future<void> _saveBackupToStorage(SaveBackup backup) async {
    final allBackups = await getAllBackups();
    allBackups.add(backup);
    await _saveAllBackupsToStorage(allBackups);
  }

  // 保存所有备份到存储
  static Future<void> _saveAllBackupsToStorage(List<SaveBackup> backups) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backupsJson = backups
          .map((backup) => jsonEncode(backup.toJson()))
          .toList();
      await prefs.setStringList(_backupsKey, backupsJson);
    } catch (e) {
      print('保存备份列表失败: $e');
    }
  }

  // 清理无效的备份记录（文件不存在的）
  static Future<void> cleanupInvalidBackups() async {
    final allBackups = await getAllBackups();
    final validBackups = <SaveBackup>[];

    for (final backup in allBackups) {
      if (await File(backup.filePath).exists()) {
        validBackups.add(backup);
      }
    }

    if (validBackups.length != allBackups.length) {
      await _saveAllBackupsToStorage(validBackups);
    }
  }
}
