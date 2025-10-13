import 'cloud_sync_config_service.dart';
import 'logging_service.dart';
import 'restic_service.dart';

enum CloudSyncResult {
  success,
  noConfig,
  connectionError,
  uploadError,
  downloadError,
  noChanges,
  fileNotFound,
  needsConfirmation,
}

class CloudBackupService {

  // 检查同步操作是否需要用户确认（旧覆盖新的情况）
  static Future<bool> checkNeedsConfirmation({required bool isUpload}) async {
    return false;
  }

  // 上传文件到云端
  static Future<CloudSyncResult> uploadToCloud({
    bool skipConfirmation = false,
  }) async {
    final config = await CloudSyncConfigService.getCloudSyncConfig();
    if (config == null) {
      return CloudSyncResult.noConfig;
    }

    final success = await ResticService.uploadRepository(config);

    return success?CloudSyncResult.success: CloudSyncResult.uploadError;
  }

  // 从云端下载文件
  static Future<CloudSyncResult> downloadFromCloud({
    bool skipConfirmation = false,
  }) async {
    final config = await CloudSyncConfigService.getCloudSyncConfig();
    if (config == null) {
      return CloudSyncResult.noConfig;
    }

    var success = await ResticService.downloadRepository(config, delete: true);

    if(success) {
      final latestSnapshot = await ResticService.getLatestSnapshot(tag: 'game:main');
      final mainPath = await ResticService.getMainDataDirectory();
      if(latestSnapshot != null) {
        success = await ResticService.restoreBackup(snapshotId: latestSnapshot.id, targetPath: mainPath.path);
      }
    }

    return success?CloudSyncResult.success: CloudSyncResult.uploadError;
  }

  // 测试云连接
  static Future<bool> testCloudConnection() async {
    try {
      final config = await CloudSyncConfigService.getCloudSyncConfig();
      if (config == null) {
        return false;
      }
      final success = await ResticService.initRemoteRepository(cloudConfig: config);
      if (!success) {
        return false;
      }
      LoggingService.instance.info('连接成功');
      return true;
    } catch (e, stackTrace) {
      LoggingService.instance.info('测试云连接失败: $e, $stackTrace');
      return false;
    }
  }

  // 获取同步状态信息
  static Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final config = await CloudSyncConfigService.getCloudSyncConfig();
      if (config == null) {
        return {'configured': false, 'error': '未配置云同步'};
      }

      Map<String, dynamic> result = {'configured': true};




      final local = await ResticService.getLatestSnapshot();
      final remote = await ResticService.getLatestSnapshot(useRemote: true, cloudConfig: config);

      if (local != null) {
        result['localExists'] = true;
        result['localModified'] = _formatDateTime(local.time);
      } else {
        result['localExists'] = false;
      }

      if (remote != null) {
        result['remoteExists'] = true;
        result['remoteModified'] = _formatDateTime(remote.time);
      } else {
        result['remoteExists'] = false;
      }

      return result;
    } catch (e) {
      return {'configured': true, 'error': e.toString()};
    }
  }

  // 格式化日期时间
  static String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  // 获取同步结果的描述信息
  static String getSyncResultMessage(CloudSyncResult result) {
    switch (result) {
      case CloudSyncResult.success:
        return '同步成功';
      case CloudSyncResult.noConfig:
        return '未配置云同步';
      case CloudSyncResult.connectionError:
        return '网络连接错误';
      case CloudSyncResult.uploadError:
        return '上传失败';
      case CloudSyncResult.downloadError:
        return '下载失败';
      case CloudSyncResult.noChanges:
        return '文件已是最新，无需同步';
      case CloudSyncResult.fileNotFound:
        return '文件未找到';
      case CloudSyncResult.needsConfirmation:
        return '需要用户确认';
    }
  }

  // 自动上传到云端（静默模式，不显示确认对话框）
  static Future<void> autoUploadToCloud() async {
    try {
      // 检查是否启用了自动同步
      final autoSyncEnabled = await CloudSyncConfigService.getAutoSyncEnabled();
      if (!autoSyncEnabled) {
        return;
      }

      // 检查是否配置了云同步
      final isConfigured = await CloudSyncConfigService.isCloudSyncConfigured();
      if (!isConfigured) {
        return;
      }

      LoggingService.instance.info('开始自动上传到云端...');

      // 静默上传，跳过确认检查
      final result = await uploadToCloud(skipConfirmation: true);

      if (result == CloudSyncResult.success) {
        LoggingService.instance.info('自动上传成功');
      } else if (result != CloudSyncResult.noChanges) {
        LoggingService.instance.info('自动上传失败: ${getSyncResultMessage(result)}');
      }
    } catch (e) {
      LoggingService.instance.info('自动上传异常: $e');
    }
  }

  // 检查云端是否有更新（用于启动时检查）
  static Future<bool> hasCloudUpdates() async {
    try {
      // 检查是否配置了云同步
      final isConfigured = await CloudSyncConfigService.isCloudSyncConfigured();
      if (!isConfigured) {
        return false;
      }

      final config = await CloudSyncConfigService.getCloudSyncConfig();
      if (config == null) {
        return false;
      }


      final localTime = (await ResticService.getLatestSnapshot())?.time;
      final cloudTime = (await ResticService.getLatestSnapshot(useRemote: true, cloudConfig: config))?.time;

      // 如果云端时间比本地时间新，则有更新
      if(localTime == null && cloudTime != null) {
        return true;
      }
      if (localTime != null && cloudTime != null) {
        return cloudTime.isAfter(localTime);
      }

      return false;
    } catch (e) {
      LoggingService.instance.info('检查云端更新失败: $e');
      return false;
    }
  }
}