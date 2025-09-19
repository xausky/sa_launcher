import 'dart:io';
import 'package:flutter/material.dart';
import 'package:minio/minio.dart';
import 'package:minio/io.dart';
import 'package:path/path.dart' as path;
import 'cloud_sync_config_service.dart';
import 'app_data_service.dart';

enum CloudSyncResult {
  success,
  noConfig,
  connectionError,
  uploadError,
  downloadError,
  noChanges,
  fileNotFound,
}

class CloudBackupService {
  static const String _appJsonFileName = 'app.json';
  static const String _coversFolder = 'covers';
  static const String _backupsFolder = 'backups';
  static const String _lastModifiedFileName = 'lastModified';

  // 创建 Minio 客户端
  static Future<Minio?> _createMinioClient() async {
    final config = await CloudSyncConfigService.getCloudSyncConfig();
    if (config == null) {
      return null;
    }

    return Minio(
      endPoint: config.endPoint,
      accessKey: config.accessKey,
      secretKey: config.secretKey,
      useSSL:
          config.endPoint.contains('amazonaws.com') ||
          config.endPoint.contains('play.min.io') ||
          !config.endPoint.contains('localhost'),
    );
  }

  // 比较单个文件是否需要同步（使用 lastModified 文件时间和 listObjects 大小）
  static Future<bool> _shouldSyncFile(
    File localFile,
    DateTime? remoteLastModified,
    int? remoteSize,
  ) async {
    if (remoteLastModified == null || remoteSize == null) {
      // 远程文件不存在，需要上传
      return true;
    }

    if (!await localFile.exists()) {
      // 本地文件不存在，需要下载
      return true;
    }

    if (localFile.path.endsWith('/app.json')) {
      final localStat = await localFile.stat();
      final localModified = localStat.modified;
      final localSize = localStat.size;
      final timeDiff = localModified.difference(remoteLastModified).abs();
      return timeDiff.inMinutes > 1 || localSize != remoteSize;
    } else {
      final localStat = await localFile.stat();
      final localSize = localStat.size;
      return localSize != remoteSize;
    }
  }

  // 上传单个文件
  static Future<bool> _uploadSingleFile(
    Minio minio,
    String bucket,
    File localFile,
    String objectName,
    DateTime? remoteLastModified,
    Map<String, int> cloudFilesInfo,
  ) async {
    try {
      // 获取远程文件大小
      final remoteSize = cloudFilesInfo[objectName];

      // 检查是否需要上传
      final shouldSync = await _shouldSyncFile(
        localFile,
        remoteLastModified,
        remoteSize,
      );

      if (!shouldSync) {
        return false; // 不需要同步
      }
      // 上传文件
      await minio.fPutObject(bucket, objectName, localFile.path);
      print('上传文件: $objectName');
      return true;
    } catch (e) {
      print('上传文件失败 $objectName: $e');
      return false;
    }
  }

  // 下载单个文件
  static Future<bool> _downloadSingleFile(
    Minio minio,
    String bucket,
    String objectName,
    File localFile,
    DateTime? remoteLastModified,
    Map<String, int> cloudFilesInfo,
  ) async {
    try {
      // 获取远程文件大小
      final remoteSize = cloudFilesInfo[objectName];

      // 检查是否需要下载
      final shouldSync = await _shouldSyncFile(
        localFile,
        remoteLastModified,
        remoteSize,
      );

      if (!shouldSync) {
        return false; // 不需要同步
      }

      // 确保本地目录存在
      await localFile.parent.create(recursive: true);

      // 下载文件
      await minio.fGetObject(bucket, objectName, localFile.path);
      print('下载文件: $objectName');
      return true;
    } catch (e) {
      print('下载文件失败 $objectName: $e');
      return false;
    }
  }

  // 获取所有需要备份的本地文件
  static Future<List<Map<String, String>>> _getLocalFiles() async {
    final appDataDir = await AppDataService.getAppDataDirectory();
    final files = <Map<String, String>>[];

    // 添加 app.json
    final appJsonFile = File(path.join(appDataDir.path, _appJsonFileName));
    if (await appJsonFile.exists()) {
      files.add({
        'localPath': appJsonFile.path,
        'relativePath': _appJsonFileName,
      });
    }

    // 添加 covers 文件夹中的文件
    final coversDir = await AppDataService.getGameCoversDirectory();
    if (await coversDir.exists()) {
      await for (final file in coversDir.list(recursive: true)) {
        if (file is File) {
          final relativePath = path.join(
            _coversFolder,
            path.relative(file.path, from: coversDir.path),
          );
          files.add({'localPath': file.path, 'relativePath': relativePath});
        }
      }
    }

    // 添加 backups 文件夹中的文件
    final backupsDir = await AppDataService.getBackupsDirectory();
    if (await backupsDir.exists()) {
      await for (final file in backupsDir.list(recursive: true)) {
        if (file is File) {
          final relativePath = path.join(
            _backupsFolder,
            path.relative(file.path, from: backupsDir.path),
          );
          files.add({'localPath': file.path, 'relativePath': relativePath});
        }
      }
    }

    return files;
  }

  // 获取云端文件信息（包含文件名和大小）
  static Future<Map<String, int>> _getCloudFilesInfo(
    Minio minio,
    String bucket,
    String prefix,
  ) async {
    final filesInfo = <String, int>{};
    try {
      await for (final result in minio.listObjectsV2(
        bucket,
        prefix: prefix,
        recursive: true,
      )) {
        for (final obj in result.objects) {
          if (obj.key != null && obj.size != null) {
            filesInfo[obj.key!] = obj.size!;
          }
        }
      }
    } catch (e) {
      print('获取云端文件信息失败: $e');
    }
    return filesInfo;
  }

  // 删除云端文件
  static Future<bool> _deleteCloudFile(
    Minio minio,
    String bucket,
    String objectName,
  ) async {
    try {
      await minio.removeObject(bucket, objectName);
      print('删除云端文件: $objectName');
      return true;
    } catch (e) {
      print('删除云端文件失败 $objectName: $e');
      return false;
    }
  }

  // 创建 lastModified 文件
  static Future<File> _createLastModifiedFile(DateTime lastModified) async {
    final tempDir = Directory.systemTemp;
    final tempFile = File(path.join(tempDir.path, _lastModifiedFileName));

    final timeString = _formatDateTime(lastModified);
    await tempFile.writeAsString(timeString);

    return tempFile;
  }

  // 从云端读取 lastModified 文件内容
  static Future<DateTime?> _getCloudLastModifiedFromFile(
    Minio minio,
    String bucket,
    String objectPath,
  ) async {
    try {
      final objectName = objectPath.isEmpty
          ? _lastModifiedFileName
          : '$objectPath/$_lastModifiedFileName';

      final tempDir = Directory.systemTemp;
      final tempFile = File(
        path.join(tempDir.path, 'temp_$_lastModifiedFileName'),
      );

      // 下载 lastModified 文件
      await minio.fGetObject(bucket, objectName, tempFile.path);

      // 读取内容并解析时间
      final timeString = await tempFile.readAsString();
      final dateTime = _parseDateTime(timeString.trim());

      // 清理临时文件
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      return dateTime;
    } catch (e) {
      print('读取云端 lastModified 文件失败: $e');
      return null;
    }
  }

  // 设置本地文件的修改时间
  static Future<void> _setLocalFilesModifiedTime(DateTime modifiedTime) async {
    try {
      final localFiles = await _getLocalFiles();

      for (final fileInfo in localFiles) {
        final file = File(fileInfo['localPath']!);
        if (await file.exists()) {
          // 设置文件的最后修改时间
          await file.setLastModified(modifiedTime);
        }
      }

      print('已将本地文件时间设置为: ${_formatDateTime(modifiedTime)}');
    } catch (e) {
      print('设置本地文件时间失败: $e');
    }
  }

  // 获取本地和云端的最后修改时间用于状态显示
  static Future<Map<String, DateTime?>> _getLastModifiedTimes(
    Minio minio,
    String bucket,
    String objectPath,
  ) async {
    DateTime? localTime;
    DateTime? cloudTime;

    try {
      // 获取本地文件的最后修改时间
      final localFiles = await _getLocalFiles();
      for (final fileInfo in localFiles) {
        final file = File(fileInfo['localPath']!);
        if (await file.exists()) {
          final stat = await file.stat();
          if (localTime == null || stat.modified.isAfter(localTime)) {
            localTime = stat.modified;
          }
        }
      }

      // 从云端的 lastModified 文件获取时间
      cloudTime = await _getCloudLastModifiedFromFile(
        minio,
        bucket,
        objectPath,
      );
    } catch (e) {
      print('获取修改时间失败: $e');
    }

    return {'local': localTime, 'cloud': cloudTime};
  }

  // 上传文件到云端
  static Future<CloudSyncResult> uploadToCloud() async {
    try {
      final config = await CloudSyncConfigService.getCloudSyncConfig();
      if (config == null) {
        return CloudSyncResult.noConfig;
      }

      final minio = await _createMinioClient();
      if (minio == null) {
        return CloudSyncResult.noConfig;
      }

      // 检查存储桶是否存在，不存在则创建
      final bucketExists = await minio.bucketExists(config.bucket);
      if (!bucketExists) {
        await minio.makeBucket(config.bucket);
      }

      // 获取所有需要上传的本地文件
      final localFiles = await _getLocalFiles();
      if (localFiles.isEmpty) {
        return CloudSyncResult.fileNotFound;
      }

      // 获取云端文件信息和 lastModified 时间
      final cloudFilesInfo = await _getCloudFilesInfo(
        minio,
        config.bucket,
        config.objectPath,
      );

      final remoteLastModified = await _getCloudLastModifiedFromFile(
        minio,
        config.bucket,
        config.objectPath,
      );

      // 获取本地文件的最新修改时间
      DateTime? latestModified;
      for (final fileInfo in localFiles) {
        final file = File(fileInfo['localPath']!);
        if (await file.exists()) {
          final stat = await file.stat();
          if (latestModified == null || stat.modified.isAfter(latestModified)) {
            latestModified = stat.modified;
          }
        }
      }

      if (latestModified == null) {
        return CloudSyncResult.fileNotFound;
      }

      int uploadedCount = 0;
      int totalCount = localFiles.length;

      // 逐个上传文件
      for (final fileInfo in localFiles) {
        final localFile = File(fileInfo['localPath']!);
        final relativePath = fileInfo['relativePath']!;

        // 构建云端对象名称
        final objectName = config.objectPath.isEmpty
            ? relativePath
            : '${config.objectPath}/${relativePath.replaceAll('\\', '/')}';

        final uploaded = await _uploadSingleFile(
          minio,
          config.bucket,
          localFile,
          objectName,
          remoteLastModified,
          cloudFilesInfo,
        );

        if (uploaded) {
          uploadedCount++;
        }
      }

      // 删除云端存在但本地不存在的文件
      int deletedCount = 0;
      final localObjectNames = <String>{};

      // 收集所有本地文件对应的云端对象名称
      for (final fileInfo in localFiles) {
        final relativePath = fileInfo['relativePath']!;
        final objectName = config.objectPath.isEmpty
            ? relativePath
            : '${config.objectPath}/${relativePath.replaceAll('\\', '/')}';
        localObjectNames.add(objectName);
      }

      // 添加 lastModified 文件到本地文件集合
      final lastModifiedObjectName = config.objectPath.isEmpty
          ? _lastModifiedFileName
          : '${config.objectPath}/$_lastModifiedFileName';
      localObjectNames.add(lastModifiedObjectName);

      // 删除云端多余的文件
      for (final cloudObjectName in cloudFilesInfo.keys) {
        if (!localObjectNames.contains(cloudObjectName)) {
          final deleted = await _deleteCloudFile(
            minio,
            config.bucket,
            cloudObjectName,
          );
          if (deleted) {
            deletedCount++;
          }
        }
      }

      // 上传 lastModified 文件
      File? lastModifiedFile;
      try {
        lastModifiedFile = await _createLastModifiedFile(latestModified);

        await minio.fPutObject(
          config.bucket,
          lastModifiedObjectName,
          lastModifiedFile.path,
        );
        print('上传 lastModified 文件: ${_formatDateTime(latestModified)}');
      } catch (e) {
        print('上传 lastModified 文件失败: $e');
      } finally {
        // 清理临时文件
        if (lastModifiedFile != null && await lastModifiedFile.exists()) {
          await lastModifiedFile.delete();
        }
      }

      if (uploadedCount == 0 && deletedCount == 0) {
        return CloudSyncResult.noChanges;
      }

      print('成功上传 $uploadedCount/$totalCount 个文件，删除 $deletedCount 个多余文件');
      return CloudSyncResult.success;
    } catch (e) {
      print('上传到云端失败: $e');
      if (e.toString().contains('connection') ||
          e.toString().contains('network')) {
        return CloudSyncResult.connectionError;
      }
      return CloudSyncResult.uploadError;
    }
  }

  // 从云端下载文件
  static Future<CloudSyncResult> downloadFromCloud() async {
    try {
      final config = await CloudSyncConfigService.getCloudSyncConfig();
      if (config == null) {
        return CloudSyncResult.noConfig;
      }

      final minio = await _createMinioClient();
      if (minio == null) {
        return CloudSyncResult.noConfig;
      }

      // 获取云端文件信息和 lastModified 时间
      final cloudFilesInfo = await _getCloudFilesInfo(
        minio,
        config.bucket,
        config.objectPath,
      );

      final remoteLastModified = await _getCloudLastModifiedFromFile(
        minio,
        config.bucket,
        config.objectPath,
      );

      if (cloudFilesInfo.isEmpty) {
        return CloudSyncResult.fileNotFound;
      }

      final appDataDir = await AppDataService.getAppDataDirectory();
      int downloadedCount = 0;
      int totalCount = cloudFilesInfo.length;

      // 逐个下载文件
      for (final objectName in cloudFilesInfo.keys) {
        try {
          // 跳过 lastModified 文件
          if (objectName.endsWith(_lastModifiedFileName)) {
            continue;
          }

          // 计算本地文件路径
          String relativePath = objectName;
          if (config.objectPath.isNotEmpty &&
              objectName.startsWith('${config.objectPath}/')) {
            relativePath = objectName.substring(config.objectPath.length + 1);
          }

          // 确定本地文件路径
          File localFile;
          if (relativePath == _appJsonFileName) {
            localFile = File(path.join(appDataDir.path, _appJsonFileName));
          } else if (relativePath.startsWith('$_coversFolder/')) {
            final coversDir = await AppDataService.getGameCoversDirectory();
            final fileName = relativePath.substring(_coversFolder.length + 1);
            localFile = File(path.join(coversDir.path, fileName));
          } else if (relativePath.startsWith('$_backupsFolder/')) {
            final backupsDir = await AppDataService.getBackupsDirectory();
            final fileName = relativePath.substring(_backupsFolder.length + 1);
            localFile = File(path.join(backupsDir.path, fileName));
          } else {
            debugPrint('跳过不认识的文件: $relativePath');
            continue; // 跳过不认识的文件
          }

          final downloaded = await _downloadSingleFile(
            minio,
            config.bucket,
            objectName,
            localFile,
            remoteLastModified,
            cloudFilesInfo,
          );

          if (downloaded) {
            downloadedCount++;
          }
        } catch (e) {
          print('下载单个文件失败 $objectName: $e');
          continue;
        }
      }

      // 读取云端的 lastModified 文件并设置本地文件时间
      try {
        final cloudLastModified = await _getCloudLastModifiedFromFile(
          minio,
          config.bucket,
          config.objectPath,
        );

        if (cloudLastModified != null) {
          await _setLocalFilesModifiedTime(cloudLastModified);
        }
      } catch (e) {
        print('设置本地文件时间失败: $e');
      }

      if (downloadedCount == 0) {
        return CloudSyncResult.noChanges;
      }

      print('成功从云端下载 $downloadedCount/$totalCount 个文件');
      return CloudSyncResult.success;
    } catch (e) {
      print('从云端下载失败: $e');
      if (e.toString().contains('connection') ||
          e.toString().contains('network')) {
        return CloudSyncResult.connectionError;
      }
      return CloudSyncResult.downloadError;
    }
  }

  // 测试云连接
  static Future<bool> testCloudConnection() async {
    try {
      final config = await CloudSyncConfigService.getCloudSyncConfig();
      if (config == null) {
        return false;
      }

      final minio = await _createMinioClient();
      if (minio == null) {
        return false;
      }
      // 测试连接，尝试获取存储桶区域
      final region = await minio.getBucketRegion(config.bucket);
      print('连接成功，region: $region');
      return true;
    } catch (e, stackTrace) {
      print('测试云连接失败: $e, $stackTrace');
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

      final minio = await _createMinioClient();
      if (minio == null) {
        return {'configured': true, 'error': '无法创建连接'};
      }

      // 获取本地和云端的最后修改时间
      final times = await _getLastModifiedTimes(
        minio,
        config.bucket,
        config.objectPath,
      );

      Map<String, dynamic> result = {'configured': true};

      final localTime = times['local'];
      final cloudTime = times['cloud'];

      if (localTime != null) {
        result['localExists'] = true;
        result['localModified'] = _formatDateTime(localTime);
      } else {
        result['localExists'] = false;
      }

      if (cloudTime != null) {
        result['remoteExists'] = true;
        result['remoteModified'] = _formatDateTime(cloudTime);
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

  // 解析日期时间字符串
  static DateTime? _parseDateTime(String dateTimeString) {
    try {
      // 解析格式: "2024-01-01 12:00:00"
      final parts = dateTimeString.split(' ');
      if (parts.length != 2) return null;

      final dateParts = parts[0].split('-');
      final timeParts = parts[1].split(':');

      if (dateParts.length != 3 || timeParts.length != 3) return null;

      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final second = int.parse(timeParts[2]);

      return DateTime(year, month, day, hour, minute, second);
    } catch (e) {
      print('解析时间字符串失败: $e');
      return null;
    }
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
    }
  }
}
