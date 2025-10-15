import 'dart:io';
import '../models/save_backup.dart';
import 'app_data_service.dart';
import 'cloud_backup_service.dart';
import 'logging_service.dart';
import 'restic_service.dart';
import 'cloud_sync_config_service.dart';

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
      // 创建标签
      final tags = <String>[
        'game:$gameId',
        'name:$backupName',
      ];

      // 创建本地备份
      final snapshot = await ResticService.createBackup(
        backupPath: saveDataPath,
        tags: tags,
      );

      if (snapshot == null) {
        throw Exception('创建本地备份失败');
      }

      final createdAt = DateTime.now();

      final backup = SaveBackup(
        id: snapshot.snapshotId,
        gameId: gameId,
        name: backupName,
        createdAt: createdAt,
        fileSize: snapshot.totalBytesProcessed
      );

      LoggingService.instance.info('创建备份成功: 本地快照ID=${snapshot.snapshotId}');

      // 触发自动上传到云端（对于其他数据）
      CloudBackupService.autoUploadToCloud();

      return backup;
    } catch (e) {
      LoggingService.instance.info('创建备份失败: $e');
      return null;
    }
  }

  // 应用存档备份
  static Future<bool> applyBackup(
    SaveBackup backup,
    String saveDataPath,
  ) async {
    try {
      final saveDir = Directory(saveDataPath);

      // 清空目标目录
      if (await saveDir.exists()) {
        await saveDir.delete(recursive: true);
      }
      await saveDir.create(recursive: true);

      // 恢复备份
      final success = await ResticService.restoreBackup(
        snapshotId: backup.id,
        targetPath: saveDataPath,
      );

      if (success) {
        LoggingService.instance.info('应用备份成功: 快照ID=${backup.id}');
      }

      return success;
    } catch (e) {
      LoggingService.instance.info('应用备份失败: $e');
      return false;
    }
  }

  // 获取游戏的所有备份
  static Future<List<SaveBackup>> getGameBackups(String gameId, {useRemote = false}) async {
    try {
      final cloudConfig = await CloudSyncConfigService.getCloudSyncConfig();

      final backups = <SaveBackup>[];

      // 获取快照
      final snapshots = await ResticService.listSnapshots(
        useRemote: useRemote,
        tag: 'game:$gameId',
        cloudConfig: cloudConfig
      );

      // 转换为 SaveBackup 对象
      for (final snapshot in snapshots) {
        try {
          // 从标签中提取备份名称
          final tags = snapshot.tags;
          String backupName = 'unknown';
          for (final tag in tags) {
            if (tag.startsWith('name:')) {
              backupName = tag.substring(5);
              break;
            }
          }

          final backup = SaveBackup(
            id: snapshot.id,
            gameId: gameId,
            name: backupName,
            createdAt: snapshot.time,
            fileSize: snapshot.summary.totalBytesProcessed,
          );

          backups.add(backup);
        } catch (e) {
          LoggingService.instance.info('解析快照失败: $e');
        }
      }

      // 按创建时间倒序排列
      backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return backups;
    } catch (e) {
      LoggingService.instance.info('获取游戏备份失败: $e');
      return [];
    }
  }

  // 删除备份
  static Future<bool> deleteBackup(
    SaveBackup backup, {
    bool autoUpload = true,
  }) async {
    try {
      final cloudConfig = await CloudSyncConfigService.getCloudSyncConfig();
      bool useRemote = cloudConfig != null;

      // 删除本地快照
      bool success = await ResticService.deleteSnapshot(
        snapshotId: backup.id,
        useRemote: false,
      );

      // 如果配置了远程同步且有远程快照，也删除远程快照
      if (useRemote) {
        deleteRemoteBackup(cloudConfig, backup);
      }

      return success;
    } catch (e) {
      LoggingService.instance.info('删除备份失败: $e');
      return false;
    }
  }

  static Future<void> deleteRemoteBackup(CloudSyncConfig cloudConfig, SaveBackup backup) async {
    final remoteSnapshots = await ResticService.listSnapshots(useRemote: true, cloudConfig: cloudConfig, tag: 'game:${backup.gameId}');
    final ids = remoteSnapshots.where((e) => e.time == backup.createdAt).map((e) => e.id).toList();
    if(ids.isEmpty) {
      return;
    }
    await ResticService.deleteSnapshots(
      ids: ids,
      useRemote: true,
      cloudConfig: cloudConfig,
    );
  }
}